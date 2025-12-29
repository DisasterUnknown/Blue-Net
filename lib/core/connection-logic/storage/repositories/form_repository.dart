// ========================================
// 5. lib/core/storage/repositories/form_repository.dart
// ========================================

import 'package:sqflite/sqflite.dart';
import '../database.dart';
import '../models/form_entity.dart';
import '../../utils/constants.dart';

class FormRepository {
  Future<void> insert(FormEntity form) async {
    final db = await AppDatabase.database;
    await db.insert(
      AppConstants.formsTable,
      form.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FormEntity?> getById(String id) async {
    final db = await AppDatabase.database;
    final results = await db.query(
      AppConstants.formsTable,
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isEmpty) return null;
    return FormEntity.fromMap(results.first);
  }

  Future<List<FormEntity>> getByStatus(FormStatus status) async {
    final db = await AppDatabase.database;
    final results = await db.query(
      AppConstants.formsTable,
      where: 'status = ?',
      whereArgs: [status.name],
      orderBy: 'created_at DESC',
    );

    return results.map((map) => FormEntity.fromMap(map)).toList();
  }

  Future<List<FormEntity>> getAllPending() async {
    return getByStatus(FormStatus.pending);
  }

  Future<void> updateStatus(String id, FormStatus status,
      {DateTime? syncedAt}) async {
    final db = await AppDatabase.database;
    await db.update(
      AppConstants.formsTable,
      {
        'status': status.name,
        if (syncedAt != null) 'synced_at': syncedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> incrementAttempts(String id) async {
    final db = await AppDatabase.database;
    await db.rawUpdate(
      'UPDATE ${AppConstants.formsTable} SET attempts = attempts + 1 WHERE id = ?',
      [id],
    );
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete(
      AppConstants.formsTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> count() async {
    final db = await AppDatabase.database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM ${AppConstants.formsTable}');
    return Sqflite.firstIntValue(result) ?? 0;
  }
}