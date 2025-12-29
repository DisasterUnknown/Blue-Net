// ========================================
// 1. lib/core/storage/database.dart
// ========================================

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../utils/constants.dart';

class AppDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.databaseName);

    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Forms table
    await db.execute('''
      CREATE TABLE ${AppConstants.formsTable} (
        id TEXT PRIMARY KEY,
        data TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        synced_at INTEGER,
        attempts INTEGER DEFAULT 0
      )
    ''');

    // Gossip messages table
    await db.execute('''
      CREATE TABLE ${AppConstants.messagesTable} (
        id TEXT PRIMARY KEY,
        origin_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        hops INTEGER NOT NULL,
        ttl INTEGER NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // Seen messages table (for deduplication)
    await db.execute('''
      CREATE TABLE ${AppConstants.seenTable} (
        message_id TEXT PRIMARY KEY,
        seen_at INTEGER NOT NULL
      )
    ''');

    // Peers table
    await db.execute('''
      CREATE TABLE ${AppConstants.peersTable} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        has_internet INTEGER NOT NULL,
        signal_strength INTEGER NOT NULL,
        transport INTEGER NOT NULL,
        last_seen INTEGER NOT NULL,
        metadata TEXT
      )
    ''');

    // Create indexes
    await db.execute(
        'CREATE INDEX idx_forms_status ON ${AppConstants.formsTable}(status)');
    await db.execute(
        'CREATE INDEX idx_messages_timestamp ON ${AppConstants.messagesTable}(timestamp)');
    await db.execute(
        'CREATE INDEX idx_peers_last_seen ON ${AppConstants.peersTable}(last_seen)');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    // Handle database migrations here
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}