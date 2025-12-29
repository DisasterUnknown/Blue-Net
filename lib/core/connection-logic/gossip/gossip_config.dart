// ========================================
// 3. lib/core/gossip/gossip_config.dart
// ========================================

class GossipConfig {
  final int maxHops;
  final int ttlHours;
  final int gossipFanout;
  final Duration gossipInterval;
  final bool enableBluetooth;
  final int maxPendingMessages;
  final int maxSeenMessageCache;

  const GossipConfig({
    this.maxHops = 10,
    this.ttlHours = 24,
    this.gossipFanout = 3,
    this.gossipInterval = const Duration(seconds: 30),
    this.enableBluetooth = true,
    this.maxPendingMessages = 100,
    this.maxSeenMessageCache = 10000,
  });

  static const GossipConfig defaultConfig = GossipConfig();

  static const GossipConfig batterySaver = GossipConfig(
    gossipFanout: 2,
    gossipInterval: Duration(minutes: 1),
    maxPendingMessages: 50,
  );

  static const GossipConfig aggressive = GossipConfig(
    gossipFanout: 5,
    gossipInterval: Duration(seconds: 15),
    maxPendingMessages: 200,
  );

  GossipConfig copyWith({
    int? maxHops,
    int? ttlHours,
    int? gossipFanout,
    Duration? gossipInterval,
    bool? enableBluetooth,
    int? maxPendingMessages,
    int? maxSeenMessageCache,
  }) {
    return GossipConfig(
      maxHops: maxHops ?? this.maxHops,
      ttlHours: ttlHours ?? this.ttlHours,
      gossipFanout: gossipFanout ?? this.gossipFanout,
      gossipInterval: gossipInterval ?? this.gossipInterval,
      enableBluetooth: enableBluetooth ?? this.enableBluetooth,
      maxPendingMessages: maxPendingMessages ?? this.maxPendingMessages,
      maxSeenMessageCache: maxSeenMessageCache ?? this.maxSeenMessageCache,
    );
  }
}