// ========================================
// 9. lib/core/network/network_detector.dart
// ========================================

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

enum ConnectionType { none, wifi, cellular, mesh }

class NetworkDetector {
  final Connectivity _connectivity = Connectivity();
  final StreamController<ConnectionType> _controller =
      StreamController<ConnectionType>.broadcast();

  Stream<ConnectionType> get connectionStream => _controller.stream;

  Future<void> initialize() async {
    // Initial check
    await _checkConnection();

    // Listen to connectivity changes
    _connectivity.onConnectivityChanged.listen((result) async {
      await _checkConnection();
    });
  }

  Future<ConnectionType> getCurrentConnectionType() async {
    final result = await _connectivity.checkConnectivity();

    if (result == ConnectivityResult.none) {
      return ConnectionType.none;
    }

    // Verify actual internet access
    final hasInternet = await _pingTest();

    if (!hasInternet) {
      return ConnectionType.none;
    }

    if (result == ConnectivityResult.wifi) {
      return ConnectionType.wifi;
    } else if (result == ConnectivityResult.mobile) {
      return ConnectionType.cellular;
    }

    return ConnectionType.none;
  }

  Future<bool> hasInternet() async {
    final type = await getCurrentConnectionType();
    return type == ConnectionType.wifi || type == ConnectionType.cellular;
  }

  Future<void> _checkConnection() async {
    final type = await getCurrentConnectionType();
    _controller.add(type);
  }

  Future<bool> _pingTest() async {
    try {
      final response = await http
          .head(Uri.parse('https://www.google.com'))
          .timeout(Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _controller.close();
  }
}