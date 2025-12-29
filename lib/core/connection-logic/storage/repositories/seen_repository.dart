// ========================================
// 7. lib/core/storage/repositories/seen_repository.dart
// ========================================

import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../../utils/constants.dart';

class SeenRepository {
  Future<void> markAsSeen(String messageId) async {
    final db = await AppDatabase.database;
    await db.insert(
      AppConstants.seenTable,
      {
        'message_id': messageId,
        'seen_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<bool> hasSeen(String messageId) async {
    final db = await AppDatabase.database;
    final results = await db.query(
      AppConstants.seenTable,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return results.isNotEmpty;
  }

  Future<Set<String>> getAllSeenIds() async {
    final db = await AppDatabase.database;
    final results = await db.query(AppConstants.seenTable);
    return results.map((map) => map['message_id'] as String).toSet();
  }

  Future<void> deleteOld(Duration age) async {
    final db = await AppDatabase.database;
    final cutoff =
        DateTime.now().subtract(age).millisecondsSinceEpoch;

    await db.delete(
      AppConstants.seenTable,
      where: 'seen_at < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> clear() async {
    final db = await AppDatabase.database;
    await db.delete(AppConstants.seenTable);
  }
}