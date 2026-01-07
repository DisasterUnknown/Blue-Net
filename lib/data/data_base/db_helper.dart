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

    return await openDatabase(path, version: 3, onCreate: _onCreate, onUpgrade: _onUpgrade);
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

    // Incident reports - incoming (received from other devices)
    await db.execute('''
      CREATE TABLE incident_reports_incoming(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        remoteId TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL,
        riskLevel INTEGER DEFAULT 3,
        latitude REAL,
        longitude REAL,
        reportedAt TEXT NOT NULL,
        receivedAt TEXT NOT NULL,
        photoPath TEXT,
        description TEXT,
        userId TEXT,
        uniqueId TEXT,
        isReceived INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Incident reports - outgoing (created by this device)
    await db.execute('''
      CREATE TABLE incident_reports_outgoing(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        localId TEXT UNIQUE NOT NULL,
        type TEXT NOT NULL,
        riskLevel INTEGER DEFAULT 3,
        latitude REAL,
        longitude REAL,
        reportedAt TEXT NOT NULL,
        photoPath TEXT,
        description TEXT,
        userId TEXT,
        uniqueId TEXT,
        synced INTEGER DEFAULT 0
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX idx_incoming_remoteId ON incident_reports_incoming(remoteId)');
    await db.execute('CREATE INDEX idx_outgoing_localId ON incident_reports_outgoing(localId)');
    await db.execute('CREATE INDEX idx_incoming_received ON incident_reports_incoming(isReceived)');
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add incident tables if they don't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS incident_reports_incoming(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          remoteId TEXT UNIQUE NOT NULL,
          type TEXT NOT NULL,
          riskLevel INTEGER DEFAULT 3,
          latitude REAL,
          longitude REAL,
          reportedAt TEXT NOT NULL,
          receivedAt TEXT NOT NULL,
          photoPath TEXT,
          description TEXT,
          userId TEXT,
          uniqueId TEXT,
          isReceived INTEGER DEFAULT 0,
          synced INTEGER DEFAULT 0
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS incident_reports_outgoing(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          localId TEXT UNIQUE NOT NULL,
          type TEXT NOT NULL,
          riskLevel INTEGER DEFAULT 3,
          latitude REAL,
          longitude REAL,
          reportedAt TEXT NOT NULL,
          photoPath TEXT,
          description TEXT,
          userId TEXT,
          uniqueId TEXT,
          synced INTEGER DEFAULT 0
        )
      ''');

      // Create indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_incoming_remoteId ON incident_reports_incoming(remoteId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_outgoing_localId ON incident_reports_outgoing(localId)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_incoming_received ON incident_reports_incoming(isReceived)');
    }
    if (oldVersion < 3) {
      // Add isRead column to all existing chat tables
      // We'll add it dynamically when accessing each chat table
      // This migration will be handled in createChatTable
    }
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
    
    // Check for duplicate by remoteId
    final remoteId = data['remoteId'] as String?;
    if (remoteId != null) {
      // Check in incoming incidents
      final existingIncoming = await database.query(
        'incident_reports_incoming',
        where: 'remoteId = ?',
        whereArgs: [remoteId],
      );
      
      // Also check in outgoing incidents (in case this is our own incident being relayed back)
      final existingOutgoing = await database.query(
        'incident_reports_outgoing',
        where: 'localId = ?',
        whereArgs: [remoteId],
      );
      
      if (existingIncoming.isNotEmpty) {
        // Update existing incoming record instead of inserting duplicate
        await database.update(
          'incident_reports_incoming',
          {
            ...data,
            'description': data['description'],
            'receivedAt': DateTime.now().toIso8601String(),
            // Preserve isReceived status if already set
            'isReceived': existingIncoming.first['isReceived'] ?? data['isReceived'] ?? 0,
          },
          where: 'remoteId = ?',
          whereArgs: [remoteId],
        );
        return existingIncoming.first['id'] as int;
      }
      
      if (existingOutgoing.isNotEmpty) {
        // This is our own incident being relayed back - don't insert as incoming
        // Just update the outgoing record if needed
        return existingOutgoing.first['id'] as int;
      }
    }
    
    final id = await database.insert(
      'incident_reports_incoming',
      {
        ...data,
        'description': data['description'],
        'receivedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace, // Replace on conflict
    );
    incomingCountNotifier.value++;
    return id;
  }

  Future<void> markIncidentAsReceived(String incidentId) async {
    final database = await db;
    // Update incoming incidents
    await database.update(
      'incident_reports_incoming',
      {'isReceived': 1},
      where: 'remoteId = ?',
      whereArgs: [incidentId],
    );
    // Also check and update outgoing incidents if this is our own incident
    await database.update(
      'incident_reports_outgoing',
      {'synced': 1}, // Mark as synced/received
      where: 'localId = ?',
      whereArgs: [incidentId],
    );
  }

  Future<bool> isIncidentReceived(String incidentId) async {
    final database = await db;
    // Check both incoming and outgoing
    final incoming = await database.query(
      'incident_reports_incoming',
      where: 'remoteId = ? AND isReceived = 1',
      whereArgs: [incidentId],
    );
    if (incoming.isNotEmpty) return true;
    
    final outgoing = await database.query(
      'incident_reports_outgoing',
      where: 'localId = ?',
      whereArgs: [incidentId],
    );
    return outgoing.isNotEmpty;
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

  Future<int> markNonUserMsgReceived(
    String msgId, {
    String? receiveDate,
  }) async {
    final database = await db;
    return await database.update(
      'nonUserMsgs',
      {
        'isReceived': 1,
        'receiveDate': receiveDate ?? DateTime.now().toIso8601String(),
      },
      where: 'msgId = ?',
      whereArgs: [msgId],
    );
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
        isReceived INTEGER,
        isRead INTEGER DEFAULT 0
      )
    ''');
    
    // Add isRead column if it doesn't exist (for existing tables)
    try {
      await database.execute('ALTER TABLE chat_$userCode ADD COLUMN isRead INTEGER DEFAULT 0');
    } catch (e) {
      // Column already exists, ignore
    }
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

    // Set isRead default: 1 for sent messages (isReceived=0), 0 for received messages (isReceived=1)
    if (!msgToInsert.containsKey('isRead')) {
      final isReceived = msgToInsert['isReceived'] as int? ?? 0;
      msgToInsert['isRead'] = isReceived == 0 ? 1 : 0; // Sent messages are "read", received are unread
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

  Future<int> getUnreadCount(String userCode) async {
    final database = await db;
    await createChatTable(userCode);
    final result = await database.rawQuery(
      'SELECT COUNT(*) as c FROM chat_$userCode WHERE isReceived = 1 AND isRead = 0',
    );
    return result.first['c'] as int? ?? 0;
  }

  Future<Map<String, dynamic>?> getLatestMessage(String userCode) async {
    final database = await db;
    await createChatTable(userCode);
    final result = await database.query(
      'chat_$userCode',
      orderBy: 'sendDate DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return result.first;
  }

  Future<void> markMessagesAsRead(String userCode) async {
    final database = await db;
    await createChatTable(userCode);
    await database.update(
      'chat_$userCode',
      {'isRead': 1},
      where: 'isReceived = 1 AND isRead = 0',
    );
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

  Future<int> markChatMsgDelivered(
    String userCode,
    String msgId, {
    String? receiveDate,
  }) async {
    final database = await db;
    await createChatTable(userCode);
    return await database.update(
      'chat_$userCode',
      {
        'isReceived': 1,
        'receiveDate': receiveDate ?? DateTime.now().toIso8601String(),
      },
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

  /// Remove old hash messages (seen message IDs) older than specified days
  /// These are used for deduplication and can be safely removed after a period
  Future<int> removeOldHashMsgs({int olderThanDays = 7}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    return await database.delete(
      'hashMsgs',
      where: 'seenDate <= ?',
      whereArgs: [cutoff],
    );
  }

  /// Remove incoming incidents that have been received by owner
  /// These are incidents we carried but don't belong to us
  Future<int> removeReceivedIncomingIncidents({int olderThanDays = 1}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    // Remove incidents that were received by owner more than X days ago
    return await database.delete(
      'incident_reports_incoming',
      where: 'isReceived = 1 AND receivedAt <= ?',
      whereArgs: [cutoff],
    );
  }

  /// Remove old incoming incidents that don't belong to this device
  /// Only keep incidents that haven't been received yet (still being carried)
  Future<int> removeOldIncomingIncidents({int olderThanDays = 3}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    // Remove old incidents that are not received and older than cutoff
    // These are incidents we've been carrying but are too old
    return await database.delete(
      'incident_reports_incoming',
      where: 'isReceived = 0 AND receivedAt <= ?',
      whereArgs: [cutoff],
    );
  }

  /// Remove delivered non-user messages (relay messages that have been delivered)
  Future<int> removeDeliveredNonUserMsgs({int olderThanDays = 1}) async {
    final database = await db;
    final cutoff = DateTime.now()
        .subtract(Duration(days: olderThanDays))
        .toIso8601String();
    // Remove messages that have been received (delivered) and are older than cutoff
    return await database.delete(
      'nonUserMsgs',
      where: 'isReceived = 1 AND receiveDate <= ?',
      whereArgs: [cutoff],
    );
  }

  /// Comprehensive cleanup: Remove all data that doesn't belong to this device
  /// This helps reduce storage by removing carried/relayed data
  Future<Map<String, int>> cleanupNonOwnedData({
    int hashMsgsDays = 7,
    int receivedIncidentsDays = 1,
    int oldIncidentsDays = 3,
    int deliveredMsgsDays = 1,
    int oldNonUserMsgsDays = 3,
  }) async {
    final results = <String, int>{};

    try {
      // Remove old hash messages (seen IDs)
      results['hashMsgs'] = await removeOldHashMsgs(olderThanDays: hashMsgsDays);

      // Remove received incoming incidents (don't belong to us, already delivered)
      results['receivedIncidents'] = await removeReceivedIncomingIncidents(
        olderThanDays: receivedIncidentsDays,
      );

      // Remove old incoming incidents that haven't been received (too old to carry)
      results['oldIncidents'] = await removeOldIncomingIncidents(
        olderThanDays: oldIncidentsDays,
      );

      // Remove delivered relay messages
      results['deliveredMsgs'] = await removeDeliveredNonUserMsgs(
        olderThanDays: deliveredMsgsDays,
      );

      // Remove old non-user messages
      results['oldNonUserMsgs'] = await removeOldNonUserMsgs(
        olderThanDays: oldNonUserMsgsDays,
      );

      return results;
    } catch (e) {
      // Log error but don't use LogService here to avoid circular dependency
      // Error will be logged by the calling service
      return results;
    }
  }

  /// Get storage statistics for monitoring
  Future<Map<String, int>> getStorageStats() async {
    final database = await db;
    final stats = <String, int>{};

    // Count incoming incidents
    final incomingResult = await database.rawQuery(
      'SELECT COUNT(*) as c FROM incident_reports_incoming',
    );
    stats['incomingIncidents'] = incomingResult.first['c'] as int? ?? 0;

    // Count received incoming incidents
    final receivedResult = await database.rawQuery(
      'SELECT COUNT(*) as c FROM incident_reports_incoming WHERE isReceived = 1',
    );
    stats['receivedIncidents'] = receivedResult.first['c'] as int? ?? 0;

    // Count outgoing incidents (our own)
    final outgoingResult = await database.rawQuery(
      'SELECT COUNT(*) as c FROM incident_reports_outgoing',
    );
    stats['outgoingIncidents'] = outgoingResult.first['c'] as int? ?? 0;

    // Count hash messages
    stats['hashMsgs'] = await countHashMsgs();

    // Count non-user messages
    stats['nonUserMsgs'] = await countNonUserMsgs();
    stats['pendingNonUserMsgs'] = await countPendingNonUserMsgs();

    return stats;
  }
}

// ===================== MSG ID GENERATOR =====================
String generateMsgId(String userCode) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return "$userCode-$timestamp";
}
