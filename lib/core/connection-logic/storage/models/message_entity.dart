// ========================================
// 3. lib/core/storage/models/message_entity.dart
// ========================================

import 'dart:convert';
import '../../gossip/gossip_message.dart';

class MessageEntity {
  final String id;
  final String originId;
  final String payload;
  final int hops;
  final int ttl;
  final DateTime timestamp;

  MessageEntity({
    required this.id,
    required this.originId,
    required this.payload,
    required this.hops,
    required this.ttl,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'origin_id': originId,
      'payload': payload,
      'hops': hops,
      'ttl': ttl,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory MessageEntity.fromMap(Map<String, dynamic> map) {
    return MessageEntity(
      id: map['id'],
      originId: map['origin_id'],
      payload: map['payload'],
      hops: map['hops'],
      ttl: map['ttl'],
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
    );
  }

  factory MessageEntity.fromGossipMessage(GossipMessage message) {
    return MessageEntity(
      id: message.id,
      originId: message.originId,
      payload: jsonEncode(message.payload.toJson()),
      hops: message.hops,
      ttl: message.ttl,
      timestamp: message.timestamp,
    );
  }

  GossipMessage toGossipMessage() {
    return GossipMessage.fromJsonString(
      jsonEncode({
        'id': id,
        'origin_id': originId,
        'payload': jsonDecode(payload),
        'hops': hops,
        'ttl': ttl,
        'timestamp': timestamp.toIso8601String(),
      }),
    );
  }
}