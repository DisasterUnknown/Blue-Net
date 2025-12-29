// ========================================
// 8. lib/core/storage/repositories/peer_repository.dart
// ========================================

import 'package:sqflite/sqflite.dart';

import '../database.dart';
import '../models/peer_entity.dart';
import '../../utils/constants.dart';
import '../../gossip/peer.dart';

class PeerRepository {
  Future<void> insert(Peer peer) async {
    final db = await AppDatabase.database;
    final entity = PeerEntity.fromPeer(peer);
    await db.insert(
      AppConstants.peersTable,
      entity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Peer>> getAll() async {
    final db = await AppDatabase.database;
    final results = await db.query(
      AppConstants.peersTable,
      orderBy: 'last_seen DESC',
    );

    return results.map((map) => PeerEntity.fromMap(map).toPeer()).toList();
  }

  Future<List<Peer>> getActive(Duration staleThreshold) async {
    final db = await AppDatabase.database;
    final cutoff =
        DateTime.now().subtract(staleThreshold).millisecondsSinceEpoch;

    final results = await db.query(
      AppConstants.peersTable,
      where: 'last_seen > ?',
      whereArgs: [cutoff],
      orderBy: 'last_seen DESC',
    );

    return results.map((map) => PeerEntity.fromMap(map).toPeer()).toList();
  }

  Future<void> deleteStale(Duration threshold) async {
    final db = await AppDatabase.database;
    final cutoff = DateTime.now().subtract(threshold).millisecondsSinceEpoch;

    await db.delete(
      AppConstants.peersTable,
      where: 'last_seen < ?',
      whereArgs: [cutoff],
    );
  }

  Future<void> delete(String id) async {
    final db = await AppDatabase.database;
    await db.delete(
      AppConstants.peersTable,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}