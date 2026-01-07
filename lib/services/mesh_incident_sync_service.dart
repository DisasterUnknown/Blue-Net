import 'dart:async';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_message.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_payload.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';
import 'package:bluetooth_chat_app/core/connection-logic/transport/gossip_transport.dart';
import 'package:bluetooth_chat_app/core/connection-logic/transport/transport_manager.dart';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:bluetooth_chat_app/services/gossip_service.dart';

/// Mesh Incident Sync Service
///
/// Handles:
/// 1. Periodic data exchange every 10 seconds between all connected devices
/// 2. Duplicate detection and prevention
/// 3. Stop broadcasting when message is received by owner
/// 4. Update incident status across devices when received
class MeshIncidentSyncService {
  static final MeshIncidentSyncService _instance =
      MeshIncidentSyncService._internal();
  factory MeshIncidentSyncService() => _instance;
  MeshIncidentSyncService._internal();

  TransportManager? _transportManager;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _peerSubscription;
  StreamSubscription? _peerDisconnectedSubscription;
  Timer? _periodicSyncTimer;
  bool _isInitialized = false;

  // Track which incidents have been sent to which peers
  // Map<peerId, Set<incidentId>> - tracks what each peer already has
  final Map<String, Set<String>> _sentToPeers = {};

  // Track which incidents have been received by owner (stop broadcasting these)
  final Set<String> _receivedByOwner = {};

  /// Initialize the service
  Future<void> initialize(TransportManager transportManager) async {
    if (_isInitialized) return;

    _transportManager = transportManager;

    // Listen to incoming messages from peers
    _messageSubscription = transportManager.onMessageReceived.listen(
      _handleIncomingMessage,
    );

    // Listen to peer discovery to sync data when new peer connects
    _peerSubscription = transportManager.onPeerDiscovered.listen(
      _handlePeerDiscovered,
    );

    // Listen to peer disconnections to clean up tracking
    _peerDisconnectedSubscription = transportManager.onPeerDisconnected.listen(
      _handlePeerDisconnected,
    );

    // Start periodic mesh sync every 10 seconds
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncToAllPeers(),
    );

    // Start periodic cleanup of non-owned data
    _startPeriodicCleanup();

    // Initial sync
    _syncToAllPeers();

    _isInitialized = true;
    LogService.log(LogTypes.meshIncidentSync, 'Service initialized');
  }

  /// Handle incoming messages from peers
  Future<void> _handleIncomingMessage(ReceivedMessage received) async {
    try {
      final message = received.message;
      final peer = received.peer;

      // Check if this is a chat message
      if (message.payload.type == PayloadType.chatMessage) {
        await _processIncomingChatMessage(message.payload.data, peer);
      }
      // Chat delivery receipt
      else if (message.payload.type == PayloadType.chatReceipt) {
        await _processIncomingChatReceipt(message.payload.data, peer);
      }
      // Check if this is an incident data message (formSubmission is used by gossip protocol)
      else if (message.payload.type == PayloadType.formSubmission ||
          message.payload.type == PayloadType.incidentData) {
        // Process as incident data
        await _processIncomingIncident(message.payload.data, peer);
      }
      // Check if this is a received confirmation (stop broadcasting)
      else if (message.payload.type == PayloadType.confirmation) {
        await _processReceivedConfirmation(message.payload.data, peer);
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error handling incoming message: $e, $stack',
      );
    }
  }

  /// Process incoming incident data from peer
  /// IMPORTANT: We NEVER set userId/uniqueId here - we only preserve the original reporter's data
  Future<void> _processIncomingIncident(
    Map<String, dynamic> incidentData,
    Peer peer,
  ) async {
    try {
      // Extract incident ID (use localId or generate from data)
      final incidentId =
          incidentData['localId'] ??
          incidentData['id'] ??
          _generateIncidentId(incidentData);

      // Check if already received by owner (stop broadcasting)
      if (_receivedByOwner.contains(incidentId)) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Incident $incidentId already received by owner, ignoring',
        );
        return;
      }

      // Check in database for duplicates using efficient query
      final db = DBHelper();
      final database = await db.db;

      // Check in incoming incidents
      final existingIncoming = await database.query(
        'incident_reports_incoming',
        where: 'remoteId = ?',
        whereArgs: [incidentId],
        limit: 1,
      );

      // Check in outgoing incidents (if this is our own incident)
      final existingOutgoing = await database.query(
        'incident_reports_outgoing',
        where: 'localId = ?',
        whereArgs: [incidentId],
        limit: 1,
      );

      if (existingIncoming.isNotEmpty || existingOutgoing.isNotEmpty) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Duplicate incident $incidentId received from ${peer.id}, ignoring',
        );
        return;
      }

      // CRITICAL: Preserve the ORIGINAL reporter's userId and uniqueId
      // We NEVER set our own userId/uniqueId when receiving from peers
      final originalUserId = incidentData['userId'];
      final originalUniqueId = incidentData['uniqueId'];

      if (originalUserId == null) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Warning: Received incident $incidentId without userId from ${peer.id}',
        );
      }

      // Store as incoming incident (preserve original reporter's userId and uniqueId)
      await db.insertIncomingIncident({
        'remoteId': incidentId,
        'type': incidentData['type'],
        'riskLevel': incidentData['riskLevel'] ?? 3,
        'latitude': incidentData['latitude'],
        'longitude': incidentData['longitude'],
        'reportedAt':
            incidentData['reportedAt'] ?? DateTime.now().toIso8601String(),
        'photoPath': incidentData['photoPath'],
        'description': incidentData['description'],
        'userId':
            originalUserId, // CRITICAL: Original reporter's userId (not ours!)
        'uniqueId':
            originalUniqueId ??
            incidentId, // CRITICAL: Original reporter's uniqueId
      });

      LogService.log(
        LogTypes.meshIncidentSync,
        'Stored incident $incidentId from peer ${peer.id} '
        '(Original reporter: userId=$originalUserId, uniqueId=$originalUniqueId)',
      );

      // Check if this incident belongs to this device (userId matches)
      final myUserId = await _getMyUserId();
      if (originalUserId != null && originalUserId == myUserId) {
        // This is our incident - mark as received and stop broadcasting
        _receivedByOwner.add(incidentId);

        // Update database to mark as received in both tables
        await db.markIncidentAsReceived(incidentId);

        // Broadcast received confirmation to stop other devices from broadcasting
        await _broadcastReceivedConfirmation(incidentId);

        LogService.log(
          LogTypes.meshIncidentSync,
          'Incident $incidentId received by owner (userId=$myUserId), stopping broadcasts',
        );
      } else {
        // Re-broadcast to other peers (gossip protocol) - preserve original data
        // Only if not already received by owner
        if (!_receivedByOwner.contains(incidentId)) {
          await _broadcastIncident(incidentData, excludePeerId: peer.id);
        }
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error processing incoming incident from ${peer.id}: $e, $stack',
      );
    }
  }

  /// Process incoming chat message from peer
  Future<void> _processIncomingChatMessage(
    Map<String, dynamic> chatData,
    Peer peer,
  ) async {
    try {
      final msgId = chatData['msgId'] as String?;
      final msg = chatData['msg'] as String?;
      final senderUserCode = chatData['senderUserCode'] as String?;
      final receiverUserCode = chatData['receiverUserCode'] as String?;
      final sendDate = chatData['sendDate'] as String?;
      final hops = (chatData['hops'] as int?) ?? 0;

      if (msgId == null ||
          msg == null ||
          senderUserCode == null ||
          receiverUserCode == null) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Invalid chat message received from ${peer.id} - missing required fields',
        );
        return;
      }

      final db = DBHelper();
      final database = await db.db;

      // Check if message already exists (duplicate detection)
      final existing = await database.query(
        'nonUserMsgs',
        where: 'msgId = ?',
        whereArgs: [msgId],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Duplicate chat message $msgId received from ${peer.id}, ignoring',
        );
        return;
      }

      // Get our user code
      final myUserCode = await AppIdentifier.getId();
      final isForMe = receiverUserCode == myUserCode;
      final mesh = MeshService.instance;

      if (isForMe) {
        // This message is for us - store in chat messages table
        LogService.log(
          LogTypes.meshIncidentSync,
          'Received chat message $msgId from $senderUserCode (for me) via ${peer.id}',
        );

        await db.insertChatMsg(
          senderUserCode,
          {
            'msgId': msgId,
            'msg': msg,
            'sendDate': sendDate ?? DateTime.now().toIso8601String(),
            'receiveDate': DateTime.now().toIso8601String(),
            'isReceived': 1, // Mark as received
          },
          encrypt: true,
          receiverUserCode: receiverUserCode,
          myUserCode: myUserCode,
        );

        // Mark as received in nonUserMsgs if it exists there
        await db.insertNonUserMsg({
          'msgId': msgId,
          'msg': msg,
          'sendDate': sendDate ?? DateTime.now().toIso8601String(),
          'receiveDate': DateTime.now().toIso8601String(),
          'senderUserCode': senderUserCode,
          'receiverUserCode': receiverUserCode,
          'isReceived': 1, // Mark as received
          'hops': hops,
        });

        await db.insertUser({
          'userCode': senderUserCode,
          'name': peer.name,
          'lastConnected': DateTime.now().toIso8601String(),
        });

        // Update live stats: delivered to me + latency if available
        int? deliveryMillis;
        try {
          if (sendDate != null) {
            final sent = DateTime.tryParse(sendDate);
            if (sent != null) {
              deliveryMillis = DateTime.now().difference(sent).inMilliseconds;
            }
          }
        } catch (_) {}
        mesh.recordMessageSeen(
          deliveredToMe: true,
          deliveryMillis: deliveryMillis,
        );

        // Send delivery receipt back through mesh
        await _sendChatReceipt(
          msgId: msgId,
          senderUserCode: senderUserCode,
          receiverUserCode: receiverUserCode,
        );
      } else {
        // This message is not for us - store in nonUserMsgs for forwarding
        LogService.log(
          LogTypes.meshIncidentSync,
          'Received chat message $msgId from $senderUserCode to $receiverUserCode (not for me) via ${peer.id} - storing for forwarding',
        );

        await db.insertNonUserMsg({
          'msgId': msgId,
          'msg': msg,
          'sendDate': sendDate ?? DateTime.now().toIso8601String(),
          'receiveDate': null,
          'senderUserCode': senderUserCode,
          'receiverUserCode': receiverUserCode,
          'isReceived': 0, // Not received by destination yet
          'hops': hops + 1, // Increment hop count
        });

        // Update live stats: seen on network
        mesh.recordMessageSeen(deliveredToMe: false);
      }

      // Track unique hashes for UI stats
      await db.insertHashMsg(msgId);
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error processing incoming chat message from ${peer.id}: $e, $stack',
      );
    }
  }

  /// Process incoming chat delivery receipt
  Future<void> _processIncomingChatReceipt(
    Map<String, dynamic> receiptData,
    Peer peer,
  ) async {
    try {
      final msgId = receiptData['msgId'] as String?;
      final senderUserCode = receiptData['senderUserCode'] as String?;
      final receiverUserCode = receiptData['receiverUserCode'] as String?;
      final receivedAt = receiptData['receivedAt'] as String?;

      if (msgId == null ||
          senderUserCode == null ||
          receiverUserCode == null) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Invalid chat receipt from ${peer.id} - missing fields',
        );
        return;
      }

      final db = DBHelper();
      final myUserCode = await AppIdentifier.getId();

      // If I am the original sender, mark the message as delivered
      if (senderUserCode == myUserCode) {
        final deliveredAt =
            receivedAt ?? DateTime.now().toIso8601String();
        await db.markNonUserMsgReceived(msgId, receiveDate: deliveredAt);
        await db.markChatMsgDelivered(
          receiverUserCode,
          msgId,
          receiveDate: deliveredAt,
        );
        LogService.log(
          LogTypes.meshIncidentSync,
          'Delivery receipt for $msgId confirmed by $receiverUserCode',
        );
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error processing chat receipt from ${peer.id}: $e, $stack',
      );
    }
  }

  /// Send a delivery receipt for a chat message
  Future<void> _sendChatReceipt({
    required String msgId,
    required String senderUserCode,
    required String receiverUserCode,
  }) async {
    try {
      final payload = GossipPayload.chatReceipt(
        msgId: msgId,
        senderUserCode: senderUserCode,
        receiverUserCode: receiverUserCode,
        receivedAt: DateTime.now().toIso8601String(),
      );

      final message = GossipMessage(
        id: 'rcpt_$msgId',
        originId: _getDeviceId(),
        payload: payload,
        hops: 0,
        ttl: 24,
        timestamp: DateTime.now(),
      );

      await GossipService().gossip.broadcastMessage(message);
      LogService.log(
        LogTypes.meshIncidentSync,
        'Broadcasted delivery receipt for $msgId to mesh',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Failed to send chat receipt for $msgId: $e, $stack',
      );
    }
  }

  /// Process received confirmation - stop broadcasting this incident
  Future<void> _processReceivedConfirmation(
    Map<String, dynamic> confirmationData,
    Peer peer,
  ) async {
    try {
      final incidentId =
          confirmationData['form_id'] ??
          confirmationData['incident_id'] ??
          confirmationData['incidentId'];

      if (incidentId == null) return;

      final incidentIdStr = incidentId.toString();

      // Check if we already processed this confirmation
      if (_receivedByOwner.contains(incidentIdStr)) {
        return; // Already processed
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        'Received confirmation from ${peer.id}: Incident $incidentIdStr received by owner',
      );

      // Mark as received by owner - stop broadcasting
      _receivedByOwner.add(incidentIdStr);

      // Update database in both incoming and outgoing tables
      final db = DBHelper();
      await db.markIncidentAsReceived(incidentIdStr);

      // Re-broadcast this confirmation to other peers (so they also stop broadcasting)
      await _broadcastReceivedConfirmation(
        incidentIdStr,
        excludePeerId: peer.id,
      );

      LogService.log(
        LogTypes.meshIncidentSync,
        'Stopped broadcasting incident $incidentIdStr based on confirmation from ${peer.id}',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error processing confirmation from ${peer.id}: $e, $stack',
      );
    }
  }

  /// Handle peer discovery - sync data when new peer connects
  Future<void> _handlePeerDiscovered(Peer peer) async {
    LogService.log(
      LogTypes.meshIncidentSync,
      'New peer discovered: ${peer.id} (${peer.name}) - Initializing data sync, Total connected peers: ${_transportManager?.connectedPeers.length ?? 0}',
    );
    // Initialize tracking for this peer
    _sentToPeers[peer.id] = <String>{};
    // Sync all data to this new peer
    await _syncToPeer(peer);
    await _syncChatMessagesToPeer(peer);
    LogService.log(
      LogTypes.meshIncidentSync,
      'Completed initial sync with peer ${peer.id}',
    );
  }

  /// Sync all incident data to all connected peers (every 10 seconds)
  Future<void> _syncToAllPeers() async {
    if (_transportManager == null) return;

    final peers = _transportManager!.connectedPeers;
    if (peers.isEmpty) {
      // Don't log every 10 seconds when no peers - too verbose
      return;
    }

    LogService.log(
      LogTypes.meshIncidentSync,
      'Periodic sync: Syncing incident data and chat messages to ${peers.length} connected peer(s)',
    );

    for (final peer in peers) {
      await _syncToPeer(peer);
      await _syncChatMessagesToPeer(peer);
    }
  }

  /// Sync all incident data to a specific peer (only new incidents)
  Future<void> _syncToPeer(Peer peer) async {
    if (_transportManager == null) return;

    try {
      final db = DBHelper();

      // Get all incidents (both outgoing and incoming)
      final outgoing = await db.getOutgoingIncidents();
      final incoming = await db.getIncomingIncidents();

      // Get incidents already sent to this peer
      final sentToThisPeer = _sentToPeers[peer.id] ?? <String>{};

      // Combine all incidents and filter out already sent ones
      final allIncidents = <Map<String, dynamic>>[];

      // Send outgoing incidents (created by this user - has our userId/uniqueId)
      // Only send if not already received by owner
      for (final inc in outgoing) {
        final incidentId = inc['localId'] as String?;
        if (incidentId != null &&
            !sentToThisPeer.contains(incidentId) &&
            !_receivedByOwner.contains(incidentId)) {
          // Check if this incident is already synced/received
          final isSynced = inc['synced'] as int? ?? 0;
          if (isSynced == 0) {
            allIncidents.add({
              'localId': incidentId,
              'type': inc['type'],
              'riskLevel': inc['riskLevel'],
              'latitude': inc['latitude'],
              'longitude': inc['longitude'],
              'reportedAt': inc['reportedAt'],
              'photoPath': inc['photoPath'],
              'description': inc['description'],
              'userId': inc['userId'], // Our userId (original reporter)
              'uniqueId':
                  inc['uniqueId'] ??
                  incidentId, // Our uniqueId (original reporter)
            });
          }
        }
      }

      // Send incoming incidents (received from others - preserve original reporter's userId/uniqueId)
      // Only send if not already received by owner
      for (final inc in incoming) {
        final incidentId = inc['remoteId'] as String?;
        if (incidentId != null &&
            !sentToThisPeer.contains(incidentId) &&
            !_receivedByOwner.contains(incidentId)) {
          allIncidents.add({
            'localId': incidentId,
            'type': inc['type'],
            'riskLevel': inc['riskLevel'],
            'latitude': inc['latitude'],
            'longitude': inc['longitude'],
            'reportedAt': inc['reportedAt'],
            'photoPath': inc['photoPath'],
            'description': inc['description'],
            'userId':
                inc['userId'], // CRITICAL: Original reporter's userId (not ours!)
            'uniqueId':
                inc['uniqueId'] ??
                incidentId, // CRITICAL: Original reporter's uniqueId
          });
        }
      }

      if (allIncidents.isEmpty) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'No new incidents to send to ${peer.id}',
        );
        return;
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        'Sending ${allIncidents.length} new incident(s) to ${peer.id}...',
      );

      // Send each new incident to peer
      for (final incident in allIncidents) {
        final incidentId = incident['localId'] as String;

        try {
          final payload = GossipPayload(
            type: PayloadType.incidentData,
            data: incident,
          );
          // Use incident ID as message ID for deduplication
          final message = GossipMessage(
            id: incidentId, // Use stable incident ID instead of random UUID
            originId: _getDeviceId(),
            payload: payload,
            hops: 0,
            ttl: 24,
            timestamp: DateTime.now(),
          );

          await _transportManager!.sendMessage(peer, message);

          // Mark as sent to this peer
          _sentToPeers.putIfAbsent(peer.id, () => <String>{}).add(incidentId);

          // Small delay to prevent flooding
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to send incident $incidentId to ${peer.id}: $e',
          );
        }
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        '✅ Sent ${allIncidents.length} new incident(s) to ${peer.id}',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error syncing to peer ${peer.id}: $e, $stack',
      );
    }
  }

  /// Sync pending chat messages to a specific peer
  Future<void> _syncChatMessagesToPeer(Peer peer) async {
    if (_transportManager == null) return;

    try {
      final db = DBHelper();
      final pendingMessages = await db.getPendingNonUserMsgs();

      if (pendingMessages.isEmpty) {
        return; // No pending messages
      }

      // Get messages already sent to this peer
      final sentToThisPeer = _sentToPeers[peer.id] ?? <String>{};

      // Filter out already sent messages and messages that are already received
      final messagesToSend = pendingMessages.where((msg) {
        final msgId = msg['msgId'] as String?;
        final isReceived = (msg['isReceived'] as int?) ?? 0;
        return msgId != null &&
            !sentToThisPeer.contains(msgId) &&
            isReceived == 0;
      }).toList();

      if (messagesToSend.isEmpty) {
        return; // No new messages to send
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        'Syncing ${messagesToSend.length} pending chat message(s) to ${peer.id}',
      );

      for (final msgData in messagesToSend) {
        final msgId = msgData['msgId'] as String?;
        if (msgId == null) continue;

        try {
          final payload = GossipPayload.chatMessage(
            msgId: msgId,
            msg: msgData['msg'] as String? ?? '',
            senderUserCode: msgData['senderUserCode'] as String? ?? '',
            receiverUserCode: msgData['receiverUserCode'] as String? ?? '',
            sendDate:
                msgData['sendDate'] as String? ??
                DateTime.now().toIso8601String(),
            hops: (msgData['hops'] as int?) ?? 0,
          );

          final message = GossipMessage(
            id: msgId,
            originId: _getDeviceId(),
            payload: payload,
            hops: (msgData['hops'] as int?) ?? 0,
            ttl: 24,
            timestamp: DateTime.now(),
          );

          await _transportManager!.sendMessage(peer, message);

          // Mark as sent to this peer
          _sentToPeers.putIfAbsent(peer.id, () => <String>{}).add(msgId);

          // Small delay to prevent flooding
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to send chat message $msgId to ${peer.id}: $e',
          );
        }
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error syncing chat messages to peer ${peer.id}: $e, $stack',
      );
    }
  }

  /// Broadcast incident to all peers (except excluded one)
  /// IMPORTANT: Preserves original reporter's userId and uniqueId - never changes them
  /// Only broadcasts if not already received by owner
  Future<void> _broadcastIncident(
    Map<String, dynamic> incidentData, {
    String? excludePeerId,
  }) async {
    if (_transportManager == null) return;

    // Extract incident ID
    final incidentId =
        incidentData['localId'] ??
        incidentData['id'] ??
        _generateIncidentId(incidentData);

    // Don't broadcast if already received by owner
    if (_receivedByOwner.contains(incidentId)) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Skipping broadcast for $incidentId - already received by owner',
      );
      return;
    }

    final peers = _transportManager!.connectedPeers
        .where((p) => p.id != excludePeerId)
        .toList();

    if (peers.isEmpty) return;

    // CRITICAL: Use incidentData as-is to preserve original userId and uniqueId
    // We never modify or replace the original reporter's information
    try {
      final payload = GossipPayload(
        type: PayloadType.incidentData,
        data:
            incidentData, // Preserve all original data including userId & uniqueId
      );
      // Use incident ID as message ID for deduplication
      final message = GossipMessage(
        id: incidentId, // Use stable incident ID instead of random UUID
        originId: _getDeviceId(),
        payload: payload,
        hops: 0,
        ttl: 24,
        timestamp: DateTime.now(),
      );

      for (final peer in peers) {
        try {
          await _transportManager!.sendMessage(peer, message);
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to broadcast incident $incidentId to ${peer.id}: $e',
          );
        }
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error broadcasting incident $e, $stack',
      );
    }
  }

  /// Broadcast received confirmation to stop other devices from broadcasting
  Future<void> _broadcastReceivedConfirmation(
    String incidentId, {
    String? excludePeerId,
  }) async {
    if (_transportManager == null) return;

    final peers = _transportManager!.connectedPeers
        .where((p) => p.id != excludePeerId)
        .toList();

    if (peers.isEmpty) return;

    try {
      final payload = GossipPayload.confirmation(
        incidentId,
        'RECEIVED_BY_OWNER',
      );
      final message = GossipMessage(
        id: _generateUuid(),
        originId: _getDeviceId(),
        payload: payload,
        hops: 0,
        ttl: 24,
        timestamp: DateTime.now(),
      );

      for (final peer in peers) {
        try {
          await _transportManager!.sendMessage(peer, message);
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to broadcast confirmation for $incidentId to ${peer.id}: $e',
          );
        }
      }
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error broadcasting confirmation: $e, $stack',
      );
    }
  }

  /// Clean up tracking for disconnected peer
  void _handlePeerDisconnected(Peer peer) {
    _sentToPeers.remove(peer.id);
    LogService.log(
      LogTypes.meshIncidentSync,
      'Peer disconnected: ${peer.id}, cleaned up tracking',
    );
  }

  /// Periodic cleanup of non-owned data to reduce storage
  Timer? _cleanupTimer;

  /// Manually trigger cleanup (can be called from UI)
  Future<Map<String, int>> performManualCleanup() async {
    await _performCleanup();
    final db = DBHelper();
    return await db.getStorageStats();
  }

  /// Start periodic cleanup of data that doesn't belong to this device
  void _startPeriodicCleanup() {
    // Run cleanup every 30 minutes
    _cleanupTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => _performCleanup(),
    );

    // Also run initial cleanup after 5 minutes
    Future.delayed(const Duration(minutes: 5), () => _performCleanup());
  }

  /// Perform cleanup of non-owned data
  Future<void> _performCleanup() async {
    try {
      final db = DBHelper();
      final results = await db.cleanupNonOwnedData(
        hashMsgsDays: 7, // Keep hash messages for 7 days
        receivedIncidentsDays: 1, // Remove received incidents after 1 day
        oldIncidentsDays: 3, // Remove old unreceived incidents after 3 days
        deliveredMsgsDays: 1, // Remove delivered relay messages after 1 day
        oldNonUserMsgsDays: 3, // Remove old non-user messages after 3 days
      );

      final totalRemoved = results.values.fold(0, (sum, count) => sum + count);
      if (totalRemoved > 0) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'Cleanup completed: Removed $totalRemoved items (hashMsgs: ${results['hashMsgs']}, '
          'receivedIncidents: ${results['receivedIncidents']}, oldIncidents: ${results['oldIncidents']}, '
          'deliveredMsgs: ${results['deliveredMsgs']}, oldNonUserMsgs: ${results['oldNonUserMsgs']})',
        );
      }

      // Update cleanup stats for info page
      MeshService.instance.recordCleanup(
        removedCount: totalRemoved,
        nextCleanup: DateTime.now().add(const Duration(minutes: 30)),
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error during cleanup: $e, $stack',
      );
    }
  }

  /// Dispose and cleanup
  Future<void> dispose() async {
    _messageSubscription?.cancel();
    _peerSubscription?.cancel();
    _peerDisconnectedSubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _cleanupTimer?.cancel();
    _sentToPeers.clear();
    _receivedByOwner.clear();
    _isInitialized = false;
    LogService.log(LogTypes.meshIncidentSync, 'Service disposed');
  }

  // Helper methods
  String _generateUuid() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_getDeviceId()}';
  }

  String _getDeviceId() {
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _generateIncidentId(Map<String, dynamic> data) {
    return '${data['type']}_${data['latitude']}_${data['longitude']}_${data['reportedAt']}';
  }

  Future<String?> _getMyUserId() async {
    // Get user ID from shared preferences
    // This should match how userId is stored when creating incidents
    try {
      final db = DBHelper();
      // Get outgoing incidents to find our userId
      final outgoing = await db.getOutgoingIncidents();
      if (outgoing.isNotEmpty) {
        // Return the userId from our own incidents
        return outgoing.first['userId'] as String?;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
