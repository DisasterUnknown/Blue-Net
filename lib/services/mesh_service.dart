// Stub MeshService for UI compatibility
// The actual mesh functionality is handled by GossipService and MeshIncidentSyncService
import 'dart:async';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/gossip_service.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_message.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_payload.dart';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
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
    final msgId = '$myUserCode-${DateTime.now().millisecondsSinceEpoch}';
    final sendDate = DateTime.now().toIso8601String();
    
    await db.insertChatMsg(
      targetUserCode,
      {
        'msgId': msgId,
        'msg': plainText,
        'sendDate': sendDate,
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
      'sendDate': sendDate,
      'receiveDate': null,
      'senderUserCode': myUserCode,
      'receiverUserCode': targetUserCode,
      'isReceived': 0,
      'hops': 0,
    });

    // Broadcast message via gossip protocol
    try {
      final gossipService = GossipService();
      final payload = GossipPayload.chatMessage(
        msgId: msgId,
        msg: plainText,
        senderUserCode: myUserCode,
        receiverUserCode: targetUserCode,
        sendDate: sendDate,
        hops: 0,
      );
      
      final message = GossipMessage(
        id: msgId,
        originId: _generateDeviceId(),
        payload: payload,
        hops: 0,
        ttl: 24, // 24 hours TTL
        timestamp: DateTime.now(),
      );

      LogService.log(
        LogTypes.gossipService,
        'Broadcasting chat message $msgId from $myUserCode to $targetUserCode via mesh',
      );
      
      await gossipService.gossip.broadcastMessage(message);
      
      LogService.log(
        LogTypes.gossipService,
        'Chat message $msgId broadcast successfully',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.gossipService,
        'Failed to broadcast chat message $msgId: $e, $stack',
      );
    }

    // Update stats
    stats.value = MeshStats(
      totalMessagesSent: stats.value.totalMessagesSent + 1,
    );
  }

  String _generateDeviceId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }
}

