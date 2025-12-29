// ========================================
// 1. lib/core/gossip/gossip_message.dart
// ========================================

import 'dart:convert';
import 'gossip_payload.dart';

class GossipMessage {
  final String id;
  final String originId;
  final GossipPayload payload;
  final int hops;
  final int ttl;
  final DateTime timestamp;

  GossipMessage({
    required this.id,
    required this.originId,
    required this.payload,
    required this.hops,
    required this.ttl,
    required this.timestamp,
  });

  bool isExpired() {
    final age = DateTime.now().difference(timestamp);
    return age.inHours >= ttl;
  }

  GossipMessage incrementHops() {
    return GossipMessage(
      id: id,
      originId: originId,
      payload: payload,
      hops: hops + 1,
      ttl: ttl,
      timestamp: timestamp,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'origin_id': originId,
      'payload': payload.toJson(),
      'hops': hops,
      'ttl': ttl,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory GossipMessage.fromJson(Map<String, dynamic> json) {
    return GossipMessage(
      id: json['id'],
      originId: json['origin_id'],
      payload: GossipPayload.fromJson(json['payload']),
      hops: json['hops'],
      ttl: json['ttl'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  String toJsonString() => jsonEncode(toJson());
  
  factory GossipMessage.fromJsonString(String jsonStr) {
    return GossipMessage.fromJson(jsonDecode(jsonStr));
  }
}