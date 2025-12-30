import 'dart:async';
import 'dart:math';
import '../../../../services/log_service.dart';
import '../../../../core/enums/logs_enums.dart';

import '../storage/gossip_storage_impl.dart';
import '../transport/transport_manager.dart';
import '../transport/gossip_transport.dart';
import 'gossip_message.dart';
import 'gossip_config.dart';
import 'gossip_payload.dart';
import 'peer.dart';

class GossipProtocol {
  final GossipStorageImpl _storage;
  final TransportManager _transport;
  final GossipConfig _config;

  // Configuration
  static const Duration _seenMessageTTL = Duration(hours: 24);
  static const Duration _peerStaleThreshold = Duration(minutes: 5);
  static const Duration _cleanupInterval = Duration(minutes: 10);

  Timer? _cleanupTimer;
  Timer? _gossipTimer;

  // Random number generator for probabilistic selection
  final Random _random = Random();

  // Batched gossip queue
  final List<GossipMessage> _pendingGossip = [];

  // Convergence tracking: messageId -> Set<peerId>
  final Map<String, Set<String>> _messageReceipts = {};

  GossipProtocol({
    GossipStorageImpl? storage,
    TransportManager? transport,
    GossipConfig? config,
  })  : _storage = storage ?? GossipStorageImpl(),
        _transport = transport ?? TransportManager(),
        _config = config ?? GossipConfig.defaultConfig;

  Future<void> initialize() async {
    await _storage.initialize();
    await _transport.initialize();

    _transport.onMessageReceived.listen(_handleIncomingMessage);
    _transport.onPeerDiscovered.listen(_handlePeerDiscovered);

    // Periodic cleanup of old messages and stale peers
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      _cleanup();
    });

    // Batched gossip timer (optimized scheduling)
    _gossipTimer = Timer.periodic(_config.gossipInterval, (_) {
      _processBatchedGossip();
    });

    LogService.log(
      LogTypes.gossipProtocol,
      'GossipProtocol initialized successfully - Fanout: ${_config.gossipFanout}, Interval: ${_config.gossipInterval.inSeconds}s, TTL: ${_config.ttlHours}h, MaxHops: ${_config.maxHops}',
    );
  }

  final _messageStreamController = StreamController<GossipMessage>.broadcast();
  Stream<GossipMessage> get onMessage => _messageStreamController.stream;

  Future<void> _handleIncomingMessage(ReceivedMessage received) async {
    final message = received.message;
    final sender = received.peer;

    // 1. Mark peer as active
    await _storage.savePeer(sender..lastSeen = DateTime.now());

    // 2. Check if this is a confirmation message - don't gossip these, just process
    if (message.payload.type == PayloadType.confirmation) {
      // Confirmations are handled by MeshIncidentSyncService
      // We just notify listeners but don't gossip confirmations
      _messageStreamController.add(message);
      LogService.log(
        LogTypes.gossipProtocol,
        'Received confirmation message ${message.id} from peer ${sender.id} - stopping gossip propagation',
      );
      return;
    }

    // 3. Check if we've seen this message
    final seenIds = await _storage.getSeenMessageIds();
    if (seenIds.contains(message.id)) {
      // Track convergence even for duplicates
      _trackMessageReceipt(message.id, sender.id);
      return; // Already seen, ignore
    }

    // 4. Mark as seen and save
    await _storage.markAsSeen(message.id);
    _trackMessageReceipt(message.id, sender.id);

    // Store for carrying (Data Mule)
    // We store it so we can forward it to future peers we meet
    if (!message.isExpired()) {
      await _storage.savePendingMessage(message);
    }

    // 5. Notify app listeners
    _messageStreamController.add(message);
    LogService.log(
      LogTypes.gossipProtocol,
      'Received new gossip message ${message.id} (type: ${message.payload.type}) from peer ${sender.id}, hops: ${message.hops}, TTL: ${message.ttl}h',
    );

    // 6. Add to batched gossip queue (OPTIMIZED: don't gossip immediately)
    // Urgent messages (formSubmission, incidentData, chatMessage) get priority
    if (message.payload.type == PayloadType.formSubmission ||
        message.payload.type == PayloadType.incidentData ||
        message.payload.type == PayloadType.chatMessage) {
      _pendingGossip.insert(0, message); // Priority queue
      // For urgent messages, gossip immediately instead of waiting for batch
      await _gossipMessageOptimized(message, excludePeerId: sender.id);
    } else {
      _pendingGossip.add(message);
    }
  }

  Future<void> _handlePeerDiscovered(Peer peer) async {
    await _storage.savePeer(peer..lastSeen = DateTime.now());
    
    // Verify peer is actually connected before sending messages
    final connectedPeerIds = _transport.connectedPeers.map((p) => p.id).toSet();
    if (!connectedPeerIds.contains(peer.id)) {
      LogService.log(
        LogTypes.gossipProtocol,
        'Peer ${peer.id} discovered but not yet connected - skipping message sync',
      );
      return;
    }
    
    // Store-and-Carry: Send all our pending (carried) messages to this new peer
    final pendingMessages = await _storage.getPendingMessages();
    if (pendingMessages.isNotEmpty) {
      LogService.log(
        LogTypes.gossipProtocol,
        'Peer ${peer.id} discovered and connected - syncing ${pendingMessages.length} carried message(s) via store-and-carry',
      );
      for (final message in pendingMessages) {
        if (message.isExpired()) {
          LogService.log(
            LogTypes.gossipProtocol,
            'Skipping expired message ${message.id} for peer ${peer.id}',
          );
          continue;
        }
        
        // Double-check peer is still connected before sending
        final stillConnected = _transport.connectedPeers.any((p) => p.id == peer.id);
        if (!stillConnected) {
          LogService.log(
            LogTypes.gossipProtocol,
            'Peer ${peer.id} disconnected during sync - stopping message sync',
          );
          break;
        }
        
        try {
          // Small delay to prevent flooding connection setup
          await Future.delayed(Duration(milliseconds: 50));
          await _transport.sendMessage(peer, message);
          LogService.log(
            LogTypes.gossipProtocol,
            'Successfully synced carried message ${message.id} to peer ${peer.id}',
          );
        } catch (e) {
          LogService.log(
            LogTypes.gossipProtocol,
            'Failed to sync carried message ${message.id} to peer ${peer.id}: $e',
          );
        }
      }
    } else {
      LogService.log(
        LogTypes.gossipProtocol,
        'Peer ${peer.id} discovered and connected - no pending messages to sync',
      );
    }
  }

  Future<void> broadcastMessage(GossipMessage message) async {
    await _storage.markAsSeen(message.id);
    // Use optimized gossip with fanout
    await _gossipMessageOptimized(message);
  }

  /// OPTIMIZED GOSSIP: Uses fanout limiting and weighted random selection
  /// Based on Boyd et al. "Randomized Gossip Algorithms"
  /// IMPORTANT: Confirmation messages are handled separately and not gossiped
  Future<void> _gossipMessageOptimized(GossipMessage message, {String? excludePeerId}) async {
    // Check if this is a confirmation message - don't gossip these
    // Confirmations are handled by MeshIncidentSyncService and stop gossip propagation
    if (message.payload.type == PayloadType.confirmation) {
      LogService.log(
        LogTypes.gossipProtocol,
        'Skipping gossip for confirmation message ${message.id} - confirmations are not gossiped',
      );
      return;
    }

    // CRITICAL: Only use actually connected peers, not just stored peers
    final connectedPeerIds = _transport.connectedPeers.map((p) => p.id).toSet();
    final storedPeers = await _storage.getActivePeers(_peerStaleThreshold);

    // Filter to only peers that are actually connected AND meet other criteria
    final candidatePeers = storedPeers
        .where((p) => 
            connectedPeerIds.contains(p.id) && // Must be actually connected
            p.batteryLevel > 15 && 
            p.id != excludePeerId)
        .toList();

    if (candidatePeers.isEmpty) {
      final connectedCount = connectedPeerIds.length;
      LogService.log(
        LogTypes.gossipProtocol,
        'No candidate peers available for message ${message.id} - $connectedCount connected peer(s), but none meet criteria (low battery, excluded, or not in stored peers)',
      );
      return;
    }

    // FANOUT LIMIT: Select only K peers (not all!)
    final selectedPeers = _selectPeersWithProbability(
      candidatePeers,
      _config.gossipFanout,
    );

    LogService.log(
      LogTypes.gossipProtocol,
      'Gossiping message ${message.id} to ${selectedPeers.length} peer(s) (selected from ${candidatePeers.length} candidates, fanout=${_config.gossipFanout})',
    );

    // Send to selected peers
    int successCount = 0;
    for (final peer in selectedPeers) {
      try {
        await _transport.sendMessage(peer, message);
        _trackMessageReceipt(message.id, peer.id);
        successCount++;
        LogService.log(
          LogTypes.gossipProtocol,
          'Successfully sent message ${message.id} to peer ${peer.id} (weight: ${_calculatePeerWeight(peer).toStringAsFixed(2)}, battery: ${peer.batteryLevel}%)',
        );
      } catch (e) {
        LogService.log(
          LogTypes.gossipProtocol,
          'Failed to send message ${message.id} to peer ${peer.id}: $e',
        );
      }
    }
    
    if (successCount > 0) {
      LogService.log(
        LogTypes.gossipProtocol,
        'Message ${message.id} gossiped successfully to $successCount/${selectedPeers.length} peer(s)',
      );
    }
  }

  /// Weighted random peer selection
  /// Returns up to `fanout` peers selected probabilistically based on weights
  List<Peer> _selectPeersWithProbability(List<Peer> peers, int fanout) {
    if (peers.length <= fanout) {
      return peers; // Return all if we have fewer than fanout
    }

    // Calculate weights for all peers
    final peerWeights = peers.map((p) => _calculatePeerWeight(p)).toList();

    // Weighted random selection (reservoir sampling variant)
    final selected = <Peer>[];
    final remaining = List<Peer>.from(peers);
    final remainingWeights = List<double>.from(peerWeights);

    for (int i = 0; i < fanout && remaining.isNotEmpty; i++) {
      // Weighted random selection
      final currentTotal = remainingWeights.reduce((a, b) => a + b);
      final randomValue = _random.nextDouble() * currentTotal;

      double cumulative = 0;
      int selectedIndex = 0;

      for (int j = 0; j < remainingWeights.length; j++) {
        cumulative += remainingWeights[j];
        if (randomValue <= cumulative) {
          selectedIndex = j;
          break;
        }
      }

      // Add selected peer and remove from pool
      selected.add(remaining[selectedIndex]);
      remaining.removeAt(selectedIndex);
      remainingWeights.removeAt(selectedIndex);
    }

    return selected;
  }

  /// Calculate peer weight for probabilistic selection
  /// Higher weight = higher probability of selection
  double _calculatePeerWeight(Peer peer) {
    double weight = 1.0;

    // Battery level: 0.5x to 2x weight
    // Low battery (15-30%) = 0.5x
    // Medium battery (30-70%) = 1.0x
    // High battery (70-100%) = 2.0x
    if (peer.batteryLevel < 30) {
      weight *= 0.5;
    } else if (peer.batteryLevel > 70) {
      weight *= 2.0;
    }

    // Signal strength: 0.7x to 1.3x weight
    // Weak signal (0-30%) = 0.7x
    // Medium signal (30-70%) = 1.0x
    // Strong signal (70-100%) = 1.3x
    if (peer.signalStrength < 30) {
      weight *= 0.7;
    } else if (peer.signalStrength > 70) {
      weight *= 1.3;
    }

    return weight;
  }

  /// Batched gossip processing (called periodically)
  Future<void> _processBatchedGossip() async {
    if (_pendingGossip.isEmpty) return;

    // Get unique messages (dedup by ID)
    final uniqueMessages = <String, GossipMessage>{};
    for (final msg in _pendingGossip) {
      uniqueMessages[msg.id] = msg;
    }

    LogService.log(
      LogTypes.gossipProtocol,
      'Processing ${uniqueMessages.length} batched message(s) from queue',
    );

    // Process each unique message
    for (final message in uniqueMessages.values) {
      await _gossipMessageOptimized(message);
      await Future.delayed(Duration(milliseconds: 50)); // Small delay between messages
    }

    // Clear the batch
    _pendingGossip.clear();
  }

  /// Track message receipt for convergence monitoring
  void _trackMessageReceipt(String messageId, String peerId) {
    _messageReceipts.putIfAbsent(messageId, () => <String>{}).add(peerId);
  }

  /// Get convergence statistics for a message
  /// Returns percentage of nodes that have received the message
  double getConvergenceStats(String messageId, int totalNodes) {
    final receipts = _messageReceipts[messageId];
    if (receipts == null || totalNodes == 0) return 0.0;
    return (receipts.length / totalNodes) * 100;
  }

  /// Estimate convergence time based on node count
  /// Based on Boyd et al: O(n log n) rounds
  int estimateConvergenceTime(int nodeCount) {
    if (nodeCount <= 1) return 0;

    // Convergence rounds = k * n * log(n) where k ≈ 1.5
    final rounds = (1.5 * nodeCount * (log(nodeCount) / ln10)).ceil();

    // Convert to seconds based on gossipInterval
    final seconds = rounds * _config.gossipInterval.inSeconds;

    return seconds;
  }

  Future<void> _cleanup() async {
    await _storage.cleanOldSeenMessages(_seenMessageTTL);
    await _storage.cleanStalePeers(_peerStaleThreshold);

    // Clean up empty convergence tracking entries
    _messageReceipts.removeWhere((messageId, receipts) {
      return receipts.isEmpty;
    });
  }

  void dispose() {
    _cleanupTimer?.cancel();
    _gossipTimer?.cancel();
    _transport.disconnect();
    _pendingGossip.clear();
    _messageReceipts.clear();
    _messageStreamController.close();
  }
}
