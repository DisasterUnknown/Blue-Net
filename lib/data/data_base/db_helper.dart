import 'package:bluetooth_chat_app/data/data_base/db_crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:convert';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _db;

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

    // Attempt decryption for incoming messages
    if (myUserCode != null) {
      return rawMsgs.map((m) {
        final msgValue = m['msg'];
        String? decrypted;
        if (msgValue is String) {
          decrypted = CryptoHelper.decryptMsg(msgValue, myUserCode);
          if (decrypted != null) {
            m['msg'] = decrypted;
          }
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
