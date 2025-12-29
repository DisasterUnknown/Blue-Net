enum LogTypes {
  info,
  success,
  error,
  conflict,
  syncManager,
  uploadService,
  bluetoothTransport,
  nearbyTransport,
  wifiDirectTransport,
  gossipService,
  meshIncidentSync;

  String get displayName {
    switch (this) {
      case LogTypes.info:
        return 'Info';
      case LogTypes.success:
        return 'Warning';
      case LogTypes.error:
        return 'Error';
      case LogTypes.conflict:
        return 'Conflict';
      case LogTypes.syncManager:
        return 'SyncManager';
      case LogTypes.uploadService:
        return 'UploadService';
      case LogTypes.bluetoothTransport:
        return 'BluetoothTransport';
      case LogTypes.nearbyTransport:
        return 'NearbyTransport';
      case LogTypes.wifiDirectTransport:
        return 'WiFiDirectTransport';
      case LogTypes.gossipService:
        return 'GossipService';
      case LogTypes.meshIncidentSync:
        return 'MeshIncidentSync';
    }
  }
}
