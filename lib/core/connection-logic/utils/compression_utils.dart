// ========================================
// 11. lib/core/utils/compression_utils.dart
// ========================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CompressionUtils {
  // Compress JSON data using GZIP
  static List<int> compressJson(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);
    return gzip.encode(bytes);
  }

  static Map<String, dynamic> decompressJson(Uint8List compressed) {
    final decompressed = gzip.decode(compressed);
    final jsonString = utf8.decode(decompressed);
    return jsonDecode(jsonString);
  }

  // Compress string
  static List<int> compressString(String input) {
    final bytes = utf8.encode(input);
    return gzip.encode(bytes);
  }

  static String decompressString(Uint8List compressed) {
    final decompressed = gzip.decode(compressed);
    return utf8.decode(decompressed);
  }

  // Check if compression is beneficial
  static bool shouldCompress(String data, {int threshold = 1024}) {
    return data.length > threshold;
  }
}