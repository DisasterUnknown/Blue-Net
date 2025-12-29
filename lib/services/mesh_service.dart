// Stub MeshService for UI compatibility
// The actual mesh functionality is handled by GossipService and MeshIncidentSyncService
import 'dart:async';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/gossip_service.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';
import 'package:flutter/material.dart';

class MeshStats {
  final int currentConnectedDevices;
  final int totalMessagesSent;
  final int totalMessagesReceived;
  final int totalMessagesDeliveredToMe;
  final int avgDeliveryMillis;
  final int successfulDeliveries;
  final DateTime? nextCleanupTime;
  final int lastCleanupRemovedCount;

  MeshStats({
    this.currentConnectedDevices = 0,
    this.totalMessagesSent = 0,
    this.totalMessagesReceived = 0,
    this.totalMessagesDeliveredToMe = 0,
    this.avgDeliveryMillis = 0,
    this.successfulDeliveries = 0,
    this.nextCleanupTime,
    this.lastCleanupRemovedCount = 0,
  });
}

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal();

  static MeshService get instance => _instance;

  final ValueNotifier<MeshStats> stats = ValueNotifier<MeshStats>(MeshStats());
  
  // Stream subscription for connected peers updates
  StreamSubscription<List<Peer>>? _peersSubscription;
  bool _isInitialized = false;

  void _initializeLiveUpdates() {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // Listen to connected peers stream and update stats
    try {
      final gossipService = GossipService();
      _peersSubscription = gossipService.meshPeersStream.listen((peers) {
        stats.value = MeshStats(
          currentConnectedDevices: peers.length,
          totalMessagesSent: stats.value.totalMessagesSent,
          totalMessagesReceived: stats.value.totalMessagesReceived,
          totalMessagesDeliveredToMe: stats.value.totalMessagesDeliveredToMe,
          avgDeliveryMillis: stats.value.avgDeliveryMillis,
          successfulDeliveries: stats.value.successfulDeliveries,
          nextCleanupTime: stats.value.nextCleanupTime,
          lastCleanupRemovedCount: stats.value.lastCleanupRemovedCount,
        );
      });
    } catch (e) {
      // GossipService might not be initialized yet
      _isInitialized = false;
    }
  }

  void dispose() {
    _peersSubscription?.cancel();
    _isInitialized = false;
  }

  Future<void> sendNewMessage({
    required String myUserCode,
    required String targetUserCode,
    required String plainText,
  }) async {
    // Initialize live updates if not already done
    if (!_isInitialized) {
      _initializeLiveUpdates();
    }
    // Store message in database for routing
    final db = DBHelper();
    final msgId = '${myUserCode}-${DateTime.now().millisecondsSinceEpoch}';
    
    await db.insertChatMsg(
      targetUserCode,
      {
        'msgId': msgId,
        'msg': plainText,
        'sendDate': DateTime.now().toIso8601String(),
        'receiveDate': null,
        'isReceived': 0,
      },
      encrypt: true,
      receiverUserCode: targetUserCode,
      myUserCode: myUserCode,
    );

    // Store as non-user message for mesh forwarding
    await db.insertNonUserMsg({
      'msgId': msgId,
      'msg': plainText,
      'sendDate': DateTime.now().toIso8601String(),
      'receiveDate': null,
      'senderUserCode': myUserCode,
      'receiverUserCode': targetUserCode,
      'isReceived': 0,
      'hops': 0,
    });

    // Update stats
    stats.value = MeshStats(
      totalMessagesSent: stats.value.totalMessagesSent + 1,
    );
  }
}

