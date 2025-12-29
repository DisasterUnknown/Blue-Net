// ========================================
// 2. lib/core/storage/models/form_entity.dart
// ========================================

import 'dart:convert';

enum FormStatus { pending, synced, failed }

class FormEntity {
  final String id;
  final Map<String, dynamic> data;
  final FormStatus status;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int attempts;

  FormEntity({
    required this.id,
    required this.data,
    required this.status,
    required this.createdAt,
    this.syncedAt,
    this.attempts = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'data': jsonEncode(data),
      'status': status.name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'synced_at': syncedAt?.millisecondsSinceEpoch,
      'attempts': attempts,
    };
  }

  factory FormEntity.fromMap(Map<String, dynamic> map) {
    return FormEntity(
      id: map['id'],
      data: jsonDecode(map['data']),
      status: FormStatus.values.firstWhere((e) => e.name == map['status']),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at']),
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'])
          : null,
      attempts: map['attempts'] ?? 0,
    );
  }

  FormEntity copyWith({
    FormStatus? status,
    DateTime? syncedAt,
    int? attempts,
  }) {
    return FormEntity(
      id: id,
      data: data,
      status: status ?? this.status,
      createdAt: createdAt,
      syncedAt: syncedAt ?? this.syncedAt,
      attempts: attempts ?? this.attempts,
    );
  }
}