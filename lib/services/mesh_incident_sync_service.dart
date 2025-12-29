import 'dart:async';
import 'dart:convert';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_message.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/gossip_payload.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';
import 'package:bluetooth_chat_app/core/connection-logic/transport/gossip_transport.dart';
import 'package:bluetooth_chat_app/core/connection-logic/transport/transport_manager.dart';
import 'package:bluetooth_chat_app/core/constants/app_constants.dart';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/core/shared_prefs/shared_pref_service.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/mapper/incident_mapper.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Mesh Incident Sync Service
///
/// Handles:
/// 1. Periodic data exchange every 10 seconds between all connected devices
/// 2. Duplicate detection and prevention
/// 3. Server sync when internet comes back
/// 4. Confirmation messages to peers when help is on the way
class MeshIncidentSyncService {
  static final MeshIncidentSyncService _instance =
      MeshIncidentSyncService._internal();
  factory MeshIncidentSyncService() => _instance;
  MeshIncidentSyncService._internal();

  TransportManager? _transportManager;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _peerSubscription;
  StreamSubscription? _peerDisconnectedSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _periodicSyncTimer;
  Timer? _serverSyncTimer;
  bool _isInitialized = false;
  bool _isSyncingToServer = false;

  // Track which incidents have been sent to which peers
  // Map<peerId, Set<incidentId>> - tracks what each peer already has
  final Map<String, Set<String>> _sentToPeers = {};

  // Track which incidents have been synced to server (don't keep re-sending these)
  final Set<String> _syncedToServer = {};

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

    // Listen to connectivity changes to sync to server when internet comes back
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      _handleConnectivityChange,
    );

    // Start periodic mesh sync every 10 seconds
    _periodicSyncTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _syncToAllPeers(),
    );

    // Periodic server sync check every 30 seconds
    _serverSyncTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkAndSyncToServer(),
    );

    // Initial sync
    _syncToAllPeers();
    _checkAndSyncToServer();

    _isInitialized = true;
    LogService.log(LogTypes.meshIncidentSync, 'Service initialized');
  }

  /// Handle incoming messages from peers
  Future<void> _handleIncomingMessage(ReceivedMessage received) async {
    try {
      final message = received.message;
      final peer = received.peer;

      // Check if this is an incident data message (formSubmission is used by gossip protocol)
      if (message.payload.type == PayloadType.formSubmission ||
          message.payload.type == PayloadType.incidentData) {
        // Process as incident data
        await _processIncomingIncident(message.payload.data, peer);
      }
      // Check if this is a confirmation message
      else if (message.payload.type == PayloadType.confirmation) {
        await _processConfirmation(message.payload.data, peer);
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

      // Check if we already have this incident (duplicate detection)
      final db = DBHelper();
      final existingIncoming = await db.getIncomingIncidents();
      final existingOutgoing = await db.getOutgoingIncidents();

      // Check in incoming incidents
      bool isDuplicate = existingIncoming.any(
        (inc) => inc['remoteId'] == incidentId,
      );

      // Check in outgoing incidents
      if (!isDuplicate) {
        isDuplicate = existingOutgoing.any(
          (inc) => inc['localId'] == incidentId,
        );
      }

      if (isDuplicate) {
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

      // Re-broadcast to other peers (gossip protocol) - preserve original data
      await _broadcastIncident(incidentData, excludePeerId: peer.id);
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error processing incoming incident from ${peer.id}: $e, $stack',
      );
    }
  }

  /// Process confirmation message
  Future<void> _processConfirmation(
    Map<String, dynamic> confirmationData,
    Peer peer,
  ) async {
    try {
      final formId =
          confirmationData['form_id'] ?? confirmationData['incident_id'];
      final status = confirmationData['status'];

      LogService.log(
        LogTypes.meshIncidentSync,
        'Received confirmation from ${peer.id}: Incident $formId - $status',
      );

      // You can update UI or show notification here
      // For now, just log it
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
      'New peer discovered: ${peer.id}, syncing data...',
    );
    // Initialize tracking for this peer
    _sentToPeers[peer.id] = <String>{};
    // Sync all data to this new peer
    await _syncToPeer(peer);
  }

  /// Handle connectivity changes - sync to server when internet comes back
  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    if (results.any((r) => r != ConnectivityResult.none)) {
      // Internet might be available, check and sync
      await _checkAndSyncToServer();
    }
  }

  /// Sync all incident data to all connected peers (every 10 seconds)
  Future<void> _syncToAllPeers() async {
    if (_transportManager == null) return;

    final peers = _transportManager!.connectedPeers;
    if (peers.isEmpty) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'No peers connected, skipping sync',
      );
      return;
    }

    LogService.log(
      LogTypes.meshIncidentSync,
      'Syncing to all connected peers...',
    );

    for (final peer in peers) {
      await _syncToPeer(peer);
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
      for (final inc in outgoing) {
        final incidentId = inc['localId'] as String?;
        if (incidentId != null && !sentToThisPeer.contains(incidentId)) {
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

      // Send incoming incidents (received from others - preserve original reporter's userId/uniqueId)
      for (final inc in incoming) {
        final incidentId = inc['remoteId'] as String?;
        if (incidentId != null && !sentToThisPeer.contains(incidentId)) {
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

  /// Broadcast incident to all peers (except excluded one)
  /// IMPORTANT: Preserves original reporter's userId and uniqueId - never changes them
  Future<void> _broadcastIncident(
    Map<String, dynamic> incidentData, {
    String? excludePeerId,
  }) async {
    if (_transportManager == null) return;

    final peers = _transportManager!.connectedPeers
        .where((p) => p.id != excludePeerId)
        .toList();

    if (peers.isEmpty) return;

    // CRITICAL: Use incidentData as-is to preserve original userId and uniqueId
    // We never modify or replace the original reporter's information
    try {
      // Extract incident ID for stable message ID
      final incidentId =
          incidentData['localId'] ??
          incidentData['id'] ??
          _generateIncidentId(incidentData);

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

  /// Check internet connectivity and sync to server if available
  Future<void> _checkAndSyncToServer() async {
    if (_isSyncingToServer) return;

    try {
      // Quick connectivity check
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        return; // No internet
      }

      // Verify actual internet access
      try {
        final response = await http
            .head(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode != 200) {
          return; // No real internet
        }
      } catch (e) {
        return; // No internet
      }

      // Internet is available, sync to server
      await _syncAllToServer();
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error checking connectivity: $e, $stack',
      );
    }
  }

  /// Sync all incidents to server and send confirmations to peers
  Future<void> _syncAllToServer() async {
    if (_isSyncingToServer) return;
    _isSyncingToServer = true;

    try {
      final db = DBHelper();

      // Get all unsynced incidents (both outgoing and incoming)
      final outgoing = await db.getOutgoingIncidents();
      final incoming = await db.getIncomingIncidents();

      final allUnsynced = [
        ...outgoing.where((inc) => (inc['synced'] ?? 0) == 0),
        ...incoming, // All incoming incidents need to be synced
      ];

      if (allUnsynced.isEmpty) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'No incidents to sync to server',
        );
        return;
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        'Syncing ${allUnsynced.length} incident(s) to server...',
      );

      final String? token = await LocalSharedPreferences.getString(
        SharedPrefValues.token,
      );

      if (token == null) {
        LogService.log(
          LogTypes.meshIncidentSync,
          'No auth token, cannot sync to server',
        );
        return;
      }

      final syncedIds = <String>[];

      bool isSynced = false;
      for (final incident in allUnsynced) {
        try {
          final apiBody = await IncidentMapper.toApiBody(incident);

          final response = await http
              .post(
                Uri.parse(
                  'https://disaster-response-system-1u8d.onrender.com/api/incidents',
                ),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token',
                },
                body: jsonEncode(apiBody),
              )
              .timeout(const Duration(seconds: 30));

          if (response.statusCode == 201) {
            isSynced = true;

            final incidentId = (incident['localId'] ?? incident['remoteId'])
                .toString();
            syncedIds.add(incidentId);

            // Mark as synced to server (so we don't keep re-sending it)
            _syncedToServer.add(incidentId);

            // Mark as synced in database if it's outgoing
            if (incident.containsKey('id')) {
              await db.markReportAsSynced(incident['id'] as int);
            }

            LogService.log(
              LogTypes.meshIncidentSync,
              'Synced incident $incidentId to server successfully',
            );
          }
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to sync incident: $e',
          );
        }
      }

      if (isSynced) {
        isSynced = false;
        LogService.log(
          LogTypes.meshIncidentSync,
          '✅ Synced ${syncedIds.length} incident(s) to server successfully',
        );
      }

      // Send confirmation messages to all peers
      if (syncedIds.isNotEmpty && _transportManager != null) {
        await _sendConfirmationsToPeers(syncedIds);
      }

      LogService.log(
        LogTypes.meshIncidentSync,
        '✅ Synced ${syncedIds.length} incident(s) to server',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.meshIncidentSync,
        'Error syncing to server: $e, $stack',
      );
    } finally {
      _isSyncingToServer = false;
    }
  }

  /// Send confirmation messages to all peers that help is on the way
  Future<void> _sendConfirmationsToPeers(List<String> incidentIds) async {
    if (_transportManager == null) return;

    final peers = _transportManager!.connectedPeers;
    if (peers.isEmpty) return;

    LogService.log(
      LogTypes.meshIncidentSync,
      'Sending confirmations to peers...',
    );

    for (final incidentId in incidentIds) {
      for (final peer in peers) {
        try {
          final payload = GossipPayload.confirmation(
            incidentId,
            'HELP_ON_THE_WAY',
          );
          final message = GossipMessage(
            id: _generateUuid(),
            originId: _getDeviceId(),
            payload: payload,
            hops: 0,
            ttl: 24,
            timestamp: DateTime.now(),
          );

          await _transportManager!.sendMessage(peer, message);
          await Future.delayed(const Duration(milliseconds: 50));
        } catch (e) {
          LogService.log(
            LogTypes.meshIncidentSync,
            'Failed to send confirmation for $incidentId to ${peer.id}: $e',
          );
        }
      }
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

  /// Dispose and cleanup
  Future<void> dispose() async {
    _messageSubscription?.cancel();
    _peerSubscription?.cancel();
    _peerDisconnectedSubscription?.cancel();
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _serverSyncTimer?.cancel();
    _sentToPeers.clear();
    _syncedToServer.clear();
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
}
