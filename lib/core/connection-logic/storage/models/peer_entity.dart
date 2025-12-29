// ========================================
// 4. lib/core/storage/models/peer_entity.dart
// ========================================

import 'dart:convert';
import '../../gossip/peer.dart';

class PeerEntity {
  final String id;
  final String name;
  final bool hasInternet;
  final int signalStrength;
  final int transport;
  final DateTime lastSeen;
  final String? metadata;

  PeerEntity({
    required this.id,
    required this.name,
    required this.hasInternet,
    required this.signalStrength,
    required this.transport,
    required this.lastSeen,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'has_internet': hasInternet ? 1 : 0,
      'signal_strength': signalStrength,
      'transport': transport,
      'last_seen': lastSeen.millisecondsSinceEpoch,
      'metadata': metadata,
    };
  }

  factory PeerEntity.fromMap(Map<String, dynamic> map) {
    return PeerEntity(
      id: map['id'],
      name: map['name'],
      hasInternet: map['has_internet'] == 1,
      signalStrength: map['signal_strength'],
      transport: map['transport'],
      lastSeen: DateTime.fromMillisecondsSinceEpoch(map['last_seen']),
      metadata: map['metadata'],
    );
  }

  factory PeerEntity.fromPeer(Peer peer) {
    return PeerEntity(
      id: peer.id,
      name: peer.name,
      hasInternet: peer.hasInternet,
      signalStrength: peer.signalStrength,
      transport: peer.transport.index,
      lastSeen: peer.lastSeen,
      metadata: peer.metadata.isNotEmpty ? jsonEncode(peer.metadata) : null,
    );
  }

  Peer toPeer() {
    return Peer(
      id: id,
      name: name,
      hasInternet: hasInternet,
      signalStrength: signalStrength,
      transport: TransportType.values[transport],
      lastSeen: lastSeen,
      metadata: metadata != null ? jsonDecode(metadata!) : {},
    );
  }
}