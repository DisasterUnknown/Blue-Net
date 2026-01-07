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
import 'package:bluetooth_chat_app/core/shared_prefs/shared_pref_service.dart';
import 'dart:convert';
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

  Map<String, dynamic> toJson() {
    return {
      'currentConnectedDevices': currentConnectedDevices,
      'totalMessagesSent': totalMessagesSent,
      'totalMessagesReceived': totalMessagesReceived,
      'totalMessagesDeliveredToMe': totalMessagesDeliveredToMe,
      'avgDeliveryMillis': avgDeliveryMillis,
      'successfulDeliveries': successfulDeliveries,
      'nextCleanupTime': nextCleanupTime?.toIso8601String(),
      'lastCleanupRemovedCount': lastCleanupRemovedCount,
    };
  }

  factory MeshStats.fromJson(Map<String, dynamic> json) {
    return MeshStats(
      currentConnectedDevices: json['currentConnectedDevices'] as int? ?? 0,
      totalMessagesSent: json['totalMessagesSent'] as int? ?? 0,
      totalMessagesReceived: json['totalMessagesReceived'] as int? ?? 0,
      totalMessagesDeliveredToMe:
          json['totalMessagesDeliveredToMe'] as int? ?? 0,
      avgDeliveryMillis: json['avgDeliveryMillis'] as int? ?? 0,
      successfulDeliveries: json['successfulDeliveries'] as int? ?? 0,
      nextCleanupTime: json['nextCleanupTime'] != null
          ? DateTime.tryParse(json['nextCleanupTime'] as String)
          : null,
      lastCleanupRemovedCount:
          json['lastCleanupRemovedCount'] as int? ?? 0,
    );
  }
}

class MeshService {
  static final MeshService _instance = MeshService._internal();
  factory MeshService() => _instance;
  MeshService._internal() {
    _loadPersistedStats();
  }

  static MeshService get instance => _instance;

  final ValueNotifier<MeshStats> stats = ValueNotifier<MeshStats>(MeshStats());
  static const String _statsPrefsKey = 'mesh_stats_v1';
  
  // Stream subscription for connected peers updates
  StreamSubscription<List<Peer>>? _peersSubscription;
  bool _isInitialized = false;

  Future<void> _loadPersistedStats() async {
    try {
      final raw =
          await LocalSharedPreferences.getString(_statsPrefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final loaded = MeshStats.fromJson(decoded);
      stats.value = loaded;
      LogService.log(
        LogTypes.info,
        'Loaded persisted mesh stats: ${loaded.toJson()}',
      );
    } catch (e) {
      LogService.log(
        LogTypes.info,
        'Failed to load persisted mesh stats: $e',
      );
    }
  }

  Future<void> _persistStats() async {
    try {
      final jsonString = jsonEncode(stats.value.toJson());
      await LocalSharedPreferences.setString(
        _statsPrefsKey,
        jsonString,
      );
    } catch (e) {
      LogService.log(
        LogTypes.info,
        'Failed to persist mesh stats: $e',
      );
    }
  }

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
          totalMessagesDeliveredToMe:
              stats.value.totalMessagesDeliveredToMe,
          avgDeliveryMillis: stats.value.avgDeliveryMillis,
          successfulDeliveries: stats.value.successfulDeliveries,
          nextCleanupTime: stats.value.nextCleanupTime,
          lastCleanupRemovedCount:
              stats.value.lastCleanupRemovedCount,
        );
        _persistStats();
      });
    } catch (e) {
      // GossipService might not be initialized yet
      _isInitialized = false;
    }
  }

  /// Helper to immutably update stats without losing existing values.
  void _updateStats({
    int? currentConnectedDevices,
    int? totalMessagesSent,
    int? totalMessagesReceived,
    int? totalMessagesDeliveredToMe,
    int? avgDeliveryMillis,
    int? successfulDeliveries,
    DateTime? nextCleanupTime,
    int? lastCleanupRemovedCount,
  }) {
    final current = stats.value;
    stats.value = MeshStats(
      currentConnectedDevices:
          currentConnectedDevices ?? current.currentConnectedDevices,
      totalMessagesSent: totalMessagesSent ?? current.totalMessagesSent,
      totalMessagesReceived:
          totalMessagesReceived ?? current.totalMessagesReceived,
      totalMessagesDeliveredToMe:
          totalMessagesDeliveredToMe ?? current.totalMessagesDeliveredToMe,
      avgDeliveryMillis: avgDeliveryMillis ?? current.avgDeliveryMillis,
      successfulDeliveries:
          successfulDeliveries ?? current.successfulDeliveries,
      nextCleanupTime: nextCleanupTime ?? current.nextCleanupTime,
      lastCleanupRemovedCount:
          lastCleanupRemovedCount ?? current.lastCleanupRemovedCount,
    );
    _persistStats();
  }

  void recordMessageSent() {
    _updateStats(totalMessagesSent: stats.value.totalMessagesSent + 1);
  }

  void recordMessageSeen({
    required bool deliveredToMe,
    int? deliveryMillis,
  }) {
    final previous = stats.value;
    final newSuccessfulDeliveries = deliveredToMe
        ? previous.successfulDeliveries + 1
        : previous.successfulDeliveries;

    int newAvg = previous.avgDeliveryMillis;
    if (deliveredToMe && deliveryMillis != null) {
      final totalMillis =
          (previous.avgDeliveryMillis * previous.successfulDeliveries) +
              deliveryMillis;
      newAvg = (totalMillis ~/ newSuccessfulDeliveries);
    }

    _updateStats(
      totalMessagesReceived: previous.totalMessagesReceived + 1,
      totalMessagesDeliveredToMe: deliveredToMe
          ? previous.totalMessagesDeliveredToMe + 1
          : previous.totalMessagesDeliveredToMe,
      successfulDeliveries: newSuccessfulDeliveries,
      avgDeliveryMillis: newAvg,
    );
  }

  void recordCleanup({
    required int removedCount,
    DateTime? nextCleanup,
  }) {
    _updateStats(
      lastCleanupRemovedCount: removedCount,
      nextCleanupTime: nextCleanup ?? stats.value.nextCleanupTime,
    );
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
    recordMessageSent();
  }

  String _generateDeviceId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }
}

