// ========================================
// 10. lib/core/utils/crypto_utils.dart
// ========================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class CryptoUtils {
  // Generate SHA256 hash
  static String sha256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Simple encryption (for sensitive form data)
  static String encryptData(String plainText, String key) {
    final keyBytes = encrypt.Key.fromUtf8(key.padRight(32, '0').substring(0, 32));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(keyBytes));
    
    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return encrypted.base64;
  }

  static String decryptData(String encryptedText, String key) {
    final keyBytes = encrypt.Key.fromUtf8(key.padRight(32, '0').substring(0, 32));
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(keyBytes));
    
    final decrypted = encrypter.decrypt64(encryptedText, iv: iv);
    return decrypted;
  }

  // Generate checksum for data integrity
  static String generateChecksum(Uint8List data) {
    final digest = sha256.convert(data);
    return digest.toString();
  }

  static bool verifyChecksum(Uint8List data, String checksum) {
    return generateChecksum(data) == checksum;
  }
}