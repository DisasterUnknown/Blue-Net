import 'dart:convert';

import 'package:encrypt/encrypt.dart';

class CryptoHelper {
  static Key _getKey(String userCode) {
    final bytes = utf8.encode(userCode.padRight(32, '0'));
    return Key(bytes);
  }

  static String encryptMsg(String plainText, String receiverUserCode) {
    final key = _getKey(receiverUserCode);
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(key));
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return '${base64.encode(iv.bytes)}:${encrypted.base64}';
  }

  static String? decryptMsg(String encryptedText, String myUserCode) {
    try {
      final parts = encryptedText.split(':');
      final iv = IV(base64.decode(parts[0]));
      final encrypted = Encrypted.fromBase64(parts[1]);
      final key = _getKey(myUserCode);
      final encrypter = Encrypter(AES(key));
      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      // Not for this user
      return null;
    }
  }
}