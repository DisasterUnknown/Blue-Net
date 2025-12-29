import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';

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

    debugPrint('[GossipProtocol] Initialized with fanout=${_config.gossipFanout}, interval=${_config.gossipInterval.inSeconds}s');
  }

  final _messageStreamController = StreamController<GossipMessage>.broadcast();
  Stream<GossipMessage> get onMessage => _messageStreamController.stream;

  Future<void> _handleIncomingMessage(ReceivedMessage received) async {
    final message = received.message;
    final sender = received.peer;

    // 1. Mark peer as active
    await _storage.savePeer(sender..lastSeen = DateTime.now());

    // 2. Check if we've seen this message
    final seenIds = await _storage.getSeenMessageIds();
    if (seenIds.contains(message.id)) {
      // Track convergence even for duplicates
      _trackMessageReceipt(message.id, sender.id);
      return; // Already seen, ignore
    }

    // 3. Mark as seen and save
    await _storage.markAsSeen(message.id);
    _trackMessageReceipt(message.id, sender.id);

    // Store for carrying (Data Mule)
    // We store it so we can forward it to future peers we meet
    if (!message.isExpired()) {
      await _storage.savePendingMessage(message);
    }

    // 4. Notify app listeners
    _messageStreamController.add(message);
    debugPrint('Received new gossip message: ${message.id} from ${sender.id}');

    // 5. Add to batched gossip queue (OPTIMIZED: don't gossip immediately)
    // Urgent messages (formSubmission) get priority
    if (message.payload.type == PayloadType.formSubmission) {
      _pendingGossip.insert(0, message); // Priority queue
      // For urgent messages, gossip immediately instead of waiting for batch
      await _gossipMessageOptimized(message, excludePeerId: sender.id);
    } else {
      _pendingGossip.add(message);
    }
  }

  Future<void> _handlePeerDiscovered(Peer peer) async {
    await _storage.savePeer(peer..lastSeen = DateTime.now());
    
    // Store-and-Carry: Send all our pending (carried) messages to this new peer
    final pendingMessages = await _storage.getPendingMessages();
    if (pendingMessages.isNotEmpty) {
      debugPrint('Discovered ${peer.id}, syncing ${pendingMessages.length} carried messages...');
      for (final message in pendingMessages) {
        if (message.isExpired()) continue;
        
        try {
          // Small delay to prevent flooding connection setup
          await Future.delayed(Duration(milliseconds: 50));
          await _transport.sendMessage(peer, message);
        } catch (e) {
          debugPrint('Failed to sync carried message to ${peer.id}: $e');
        }
      }
    }
  }

  Future<void> broadcastMessage(GossipMessage message) async {
    await _storage.markAsSeen(message.id);
    // Use optimized gossip with fanout
    await _gossipMessageOptimized(message);
  }

  /// OPTIMIZED GOSSIP: Uses fanout limiting and weighted random selection
  /// Based on Boyd et al. "Randomized Gossip Algorithms"
  Future<void> _gossipMessageOptimized(GossipMessage message, {String? excludePeerId}) async {
    final peers = await _storage.getActivePeers(_peerStaleThreshold);

    // Filter out critical battery and excluded peer
    final candidatePeers = peers
        .where((p) => p.batteryLevel > 15 && p.id != excludePeerId)
        .toList();

    if (candidatePeers.isEmpty) {
      debugPrint('[GossipProtocol] No candidate peers for message ${message.id}');
      return;
    }

    // FANOUT LIMIT: Select only K peers (not all!)
    final selectedPeers = _selectPeersWithProbability(
      candidatePeers,
      _config.gossipFanout,
    );

    debugPrint(
      '[GossipProtocol] Gossiping message ${message.id} to ${selectedPeers.length} peers (of ${candidatePeers.length} available) - Fanout=${_config.gossipFanout}',
    );

    // Send to selected peers
    for (final peer in selectedPeers) {
      try {
        await _transport.sendMessage(peer, message);
        _trackMessageReceipt(message.id, peer.id);
        debugPrint('  → Sent to ${peer.id} (weight: ${_calculatePeerWeight(peer).toStringAsFixed(2)})');
      } catch (e) {
        debugPrint('  ✗ Failed to send to ${peer.id}: $e');
      }
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

    // Internet access: 3x weight (highest priority)
    if (peer.hasInternet) {
      weight *= 3.0;
    }

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

    debugPrint('[GossipProtocol] Processing ${uniqueMessages.length} batched messages');

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
