import 'package:bluetooth_chat_app/data/data_base/db_crypto.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

  final ValueNotifier<int> incomingCountNotifier = ValueNotifier(0);

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bluetooth_chat.db');

    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future _onCreate(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userCode TEXT UNIQUE,
        name TEXT,
        lastConnected DATETIME
      )
    ''');

    // Non-user messages table
    await db.execute('''
      CREATE TABLE nonUserMsgs(
        msgId TEXT PRIMARY KEY,
        msg TEXT,
        sendDate DATETIME,
        receiveDate DATETIME,
        senderUserCode TEXT,
        receiverUserCode TEXT,
        isReceived INTEGER,
        hops INTEGER
      )
    ''');

    // Hash messages table
    await db.execute('''
      CREATE TABLE hashMsgs(
        msgId TEXT PRIMARY KEY,
        seenDate DATETIME
      )
    ''');
  }

  // ===================== USERS =====================
  Future<int> insertUser(Map<String, dynamic> user) async {
    final database = await db;
    return await database.insert(
      'users',
      user,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getUserByCode(String userCode) async {
    final database = await db;
    final result = await database.query(
      'users',
      where: 'userCode = ?',
      whereArgs: [userCode],
    );
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final database = await db;
    return await database.query('users');
  }

  Future<List<Map<String, dynamic>>> getIncomingIncidents() async {
    final database = await db;
    return database.query(
      'incident_reports_incoming',
      orderBy: 'receivedAt DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getOutgoingIncidents() async {
    final database = await db;
    return database.query(
      'incident_reports_outgoing',
      orderBy: 'reportedAt DESC',
    );
  }

  Future<int> insertIncomingIncident(Map<String, dynamic> data) async {
    final database = await db;
    final id = await database.insert(
      'incident_reports_incoming',
      {
        ...data,
        'description': data['description'] ?? null,
        'receivedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore, // prevents duplicates
    );
    incomingCountNotifier.value++;
    return id;
  }

  Future<void> markReportAsSynced(int id) async {
    final database = await db;
    await database.update(
      'incident_reports_outgoing',
      {'synced': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> updateUserName(String userCode, String newName) async {
    final database = await db;
    return await database.update(
      'users',
      {'name': newName, 'lastConnected': DateTime.now().toIso8601String()},
      where: 'userCode = ?',
      whereArgs: [userCode],
    );
  }

  Future<void> deleteUserAndChats(String userCode) async {
    final database = await db;
    await database.delete(
      'users',
      where: 'userCode = ?',
      whereArgs: [userCode],
    );
    // Drop per-user chat table if it exists.
    await database.execute('DROP TABLE IF EXISTS chat_$userCode');
    // Optionally clean relay rows linked to this user.
    await database.delete(
      'nonUserMsgs',
      where: 'senderUserCode = ? OR receiverUserCode = ?',
      whereArgs: [userCode, userCode],
    );
  }

  // ===================== NON-USER MSGS =====================
  Future<int> insertNonUserMsg(Map<String, dynamic> msg) async {
    final database = await db;
    return await database.insert(
      'nonUserMsgs',
      msg,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getPendingNonUserMsgs() async {
    final database = await db;
    return await database.query('nonUserMsgs', where: 'isReceived = 0');
  }

  Future<int> removeNonUserMsg(String msgId) async {
    final database = await db;
    return await database.delete(
      'nonUserMsgs',
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
  }

  Future<int> countNonUserMsgs() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM nonUserMsgs',
    );
    return result.first['c'] as int? ?? 0;
  }

  Future<int> countPendingNonUserMsgs() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM nonUserMsgs WHERE isReceived = 0',
    );
    return result.first['c'] as int? ?? 0;
  }

  // ===================== CHAT MSGS =====================
  Future<void> createChatTable(String userCode) async {
    final database = await db;
    await database.execute('''
      CREATE TABLE IF NOT EXISTS chat_$userCode(
        msgId TEXT PRIMARY KEY,
        msg TEXT,
        sendDate DATETIME,
        receiveDate DATETIME,
        isReceived INTEGER
      )
    ''');
  }

  Future<int> insertChatMsg(
    String userCode,
    Map<String, dynamic> msg, {
    bool encrypt = true,
    String? receiverUserCode,
    String? myUserCode,
  }) async {
    final database = await db;
    await createChatTable(userCode);

    Map<String, dynamic> msgToInsert = Map.from(msg);

    // Encrypt only if message is plain text
    if (encrypt && receiverUserCode != null && !_isEncrypted(msg['msg'])) {
      msgToInsert['msg'] = CryptoHelper.encryptMsg(
        msg['msg'],
        receiverUserCode,
      );
    }

    return await database.insert(
      'chat_$userCode',
      msgToInsert,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getChatMsgs(
    String userCode, {
    String? myUserCode,
  }) async {
    final database = await db;
    await createChatTable(userCode);
    final rawMsgs = await database.query(
      'chat_$userCode',
      orderBy: 'sendDate ASC',
    );

    // Attempt decryption only for incoming messages (isReceived == 1)
    if (myUserCode != null) {
      return rawMsgs.map((m) {
        try {
          final isReceived = m['isReceived'] as int? ?? 0;
          if (isReceived == 1) {
            final msgValue = m['msg'];
            if (msgValue is String) {
              final decrypted = CryptoHelper.decryptMsg(msgValue, myUserCode);
              if (decrypted != null) {
                m['msg'] = decrypted;
              }
            }
          }
        } catch (_) {
          // best-effort; leave message as-is on any failure
        }
        return m;
      }).toList();
    }

    return rawMsgs;
  }

  Future<int> removeChatMsg(String userCode, String msgId) async {
    final database = await db;
    await createChatTable(userCode);
    return await database.delete(
      'chat_$userCode',
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
  }

  Future<int> updateChatMsg(
    String userCode,
    String msgId,
    String newText, {
    bool encrypt = false,
    String? receiverUserCode,
  }) async {
    final database = await db;
    await createChatTable(userCode);

    String textToStore = newText;
    if (encrypt && receiverUserCode != null && !_isEncrypted(newText)) {
      textToStore = CryptoHelper.encryptMsg(newText, receiverUserCode);
    }

    return await database.update(
      'chat_$userCode',
      {'msg': textToStore},
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
  }

  bool _isEncrypted(String msg) {
    try {
      final parts = msg.split(':');
      if (parts.length != 2) return false;
      final iv = base64.decode(parts[0]);
      return iv.length == 16; // IV is 16 bytes for AES
    } catch (e) {
      return false;
    }
  }

  // ===================== HASH MSGS =====================
  Future<int> insertHashMsg(String msgId) async {
    final database = await db;
    return await database.insert('hashMsgs', {
      'msgId': msgId,
      'seenDate': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> isMsgInHash(String msgId) async {
    final database = await db;
    final result = await database.query(
      'hashMsgs',
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
    return result.isNotEmpty;
  }

  Future<int> countHashMsgs() async {
    final database = await db;
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM hashMsgs',
    );
    return result.first['c'] as int? ?? 0;
  }

  // ===================== CLEANUP =====================
  Future<int> removeOldNonUserMsgs({int olderThanDays = 3}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    return await database.delete(
      'nonUserMsgs',
      where: 'receiveDate <= ?',
      whereArgs: [cutoff],
    );
  }
}

// ===================== MSG ID GENERATOR =====================
String generateMsgId(String userCode) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return "$userCode-$timestamp";
}
