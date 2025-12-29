// ========================================
// 5. lib/core/gossip/bloom_filter.dart
// ========================================

import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class BloomFilter {
  late Uint8List _bits;
  final int _size;
  final int _hashCount;

  BloomFilter({
    required int expectedItems,
    double falsePositiveRate = 0.01,
  })  : _size = _calculateSize(expectedItems, falsePositiveRate),
        _hashCount = _calculateHashCount(
            _calculateSize(expectedItems, falsePositiveRate), expectedItems) {
    _bits = Uint8List((_size / 8).ceil());
  }

  static int _calculateSize(int n, double p) {
    return (-(n * log(p)) / pow(ln2, 2)).ceil();
  }

  static int _calculateHashCount(int m, int n) {
    return ((m / n) * ln2).ceil();
  }

  void add(String item) {
    final hashes = _getHashes(item);
    for (final hash in hashes) {
      final index = hash % _size;
      _setBit(index);
    }
  }

  bool mightContain(String item) {
    final hashes = _getHashes(item);
    for (final hash in hashes) {
      final index = hash % _size;
      if (!_getBit(index)) {
        return false;
      }
    }
    return true;
  }

  List<int> _getHashes(String item) {
    final hashes = <int>[];
    final bytes = utf8.encode(item);

    for (int i = 0; i < _hashCount; i++) {
      final hash = sha256.convert([...bytes, i]).bytes;
      final value = hash[0] |
          (hash[1] << 8) |
          (hash[2] << 16) |
          (hash[3] << 24);
      hashes.add(value.abs());
    }

    return hashes;
  }

  void _setBit(int index) {
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    _bits[byteIndex] |= (1 << bitIndex);
  }

  bool _getBit(int index) {
    final byteIndex = index ~/ 8;
    final bitIndex = index % 8;
    return (_bits[byteIndex] & (1 << bitIndex)) != 0;
  }

  void clear() {
    _bits = Uint8List((_size / 8).ceil());
  }
}