import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:bluetooth_chat_app/core/constants/app_constants.dart';

class AppIdentifier {
  static const _storage = FlutterSecureStorage();
  static const _key = SharedPrefValues.appkey;

  static const _base62 = AppConstants.base64Data;

  static Future<String> getId() async {
    final existing = await _storage.read(key: _key);
    if (existing != null) return existing;

    // 1️⃣ Generate UUID
    final uuid = const Uuid().v4();

    // 2️⃣ Hash UUID (SHA-256)
    final hash = sha256.convert(utf8.encode(uuid)).bytes;

    // 3️⃣ Convert to Base62
    final shortId = _toBase62(hash).substring(0, 10);

    // 4️⃣ Store permanently
    await _storage.write(key: _key, value: shortId);

    return shortId;
  }

  static String _toBase62(List<int> bytes) {
    BigInt value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }

    final buffer = StringBuffer();
    while (value > BigInt.zero) {
      final mod = value % BigInt.from(62);
      buffer.write(_base62[mod.toInt()]);
      value = value ~/ BigInt.from(62);
    }

    return buffer.toString().split('').reversed.join();
  }
}
