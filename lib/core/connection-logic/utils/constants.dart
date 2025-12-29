// ========================================
// 8. lib/core/utils/constants.dart
// ========================================

class AppConstants {
  // Bluetooth
  static const String bluetoothServiceUuid =
      '00001234-0000-1000-8000-00805f9b34fb';
  static const String bluetoothCharacteristicUuid =
      '00001235-0000-1000-8000-00805f9b34fb';

  // WiFi Direct
  static const String wifiDirectServiceName = 'GossipMeshNetwork';

  // Database
  static const String databaseName = 'gossip_mesh.db';
  static const int databaseVersion = 1;

  // Network
  static const String apiBaseUrl =
      'https://disaster-response-system-1u8d.onrender.com';
  static const Duration connectionTimeout = Duration(seconds: 30);
  static const Duration requestTimeout = Duration(seconds: 30);

  // Gossip
  static const Duration peerStaleThreshold = Duration(minutes: 5);
  static const Duration seenMessageCleanup = Duration(days: 7);
  static const int maxChunkSize = 512; // bytes for Bluetooth

  // Storage
  static const String formsTable = 'forms';
  static const String messagesTable = 'gossip_messages';
  static const String seenTable = 'seen_messages';
  static const String peersTable = 'peers';
}

class StorageKeys {
  static const String deviceId = 'device_id';
  static const String lastSync = 'last_sync';
  static const String gossipConfig = 'gossip_config';
}
