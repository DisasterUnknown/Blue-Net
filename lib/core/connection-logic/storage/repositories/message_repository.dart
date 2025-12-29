// ========================================
// 6. lib/core/storage/repositories/message_repository.dart
// ========================================

import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/message_entity.dart';
import '../../utils/constants.dart';
import '../../gossip/gossip_message.dart';

class MessageRepository {
  Future<void> insert(GossipMessage message) async {
    final db = await AppDatabase.database;
    final entity = MessageEntity.fromGossipMessage(message);
    await db.insert(
      AppConstants.messagesTable,
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<GossipMessage>> getAll() async {
    final db = await AppDatabase.database;
    final results = await db.query(
      AppConstants.messagesTable,
      orderBy: 'timestamp DESC',
    );

    return results
        .map((map) => MessageEntity.fromMap(map).toGossipMessage())
        .toList();
  }

  Future<List<GossipMessage>> getNotExpired(int ttlHours) async {
    final db = await AppDatabase.database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: ttlHours)).millisecondsSinceEpoch;

    final results = await db.query(
      AppConstants.messagesTable,
      where: 'timestamp > ?',
      whereArgs: [cutoff],
      orderBy: 'timestamp DESC',
    );

    return results
        .map((map) => MessageEntity.fromMap(map).toGossipMessage())
        .toList();
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete(
      AppConstants.messagesTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteExpired(int ttlHours) async {
    final db = await AppDatabase.database;
    final cutoff =
        DateTime.now().subtract(Duration(hours: ttlHours)).millisecondsSinceEpoch;

    await db.delete(
      AppConstants.messagesTable,
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> deleteAll() async {
    final db = await AppDatabase.database;
    await db.delete(AppConstants.messagesTable);
  }
}