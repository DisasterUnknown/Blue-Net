// ========================================
// 4. lib/core/gossip/peer.dart
// ========================================

enum TransportType {
  bluetooth,
  wifiDirect,
  both,
}

class Peer {
  final String id;
  final String name;
  final bool hasInternet;
  final int signalStrength;
  final int batteryLevel; // 0-100
  final TransportType transport;
  late final DateTime lastSeen;
  final Map<String, dynamic> metadata;

  Peer({
    required this.id,
    required this.name,
    this.hasInternet = false,
    this.signalStrength = 0,
    this.batteryLevel = 100,
    this.transport = TransportType.bluetooth,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  })  : lastSeen = lastSeen ?? DateTime.now(),
        metadata = metadata ?? {};

  bool get supportsBluetooth =>
      transport == TransportType.bluetooth || transport == TransportType.both;

  bool get supportsWiFi => false; // WiFi support removed

  bool isStale(Duration threshold) {
    return DateTime.now().difference(lastSeen) > threshold;
  }

  Peer copyWith({
    String? id,
    String? name,
    bool? hasInternet,
    int? signalStrength,
    int? batteryLevel,
    TransportType? transport,
    DateTime? lastSeen,
    Map<String, dynamic>? metadata,
  }) {
    return Peer(
      id: id ?? this.id,
      name: name ?? this.name,
      hasInternet: hasInternet ?? this.hasInternet,
      signalStrength: signalStrength ?? this.signalStrength,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      transport: transport ?? this.transport,
      lastSeen: lastSeen ?? this.lastSeen,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'has_internet': hasInternet,
      'signal_strength': signalStrength,
      'battery_level': batteryLevel,
      'transport': transport.index,
      'last_seen': lastSeen.toIso8601String(),
      'metadata': metadata,
    };
  }

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      id: json['id'],
      name: json['name'],
      hasInternet: json['has_internet'] ?? false,
      signalStrength: json['signal_strength'] ?? 0,
      batteryLevel: json['battery_level'] ?? 100,
      transport: TransportType.values[json['transport'] ?? 0],
      lastSeen: DateTime.parse(json['last_seen']),
      metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Peer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Peer($id, $name, internet: $hasInternet, battery: $batteryLevel%)';
}