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
  gossipProtocol,
  meshIncidentSync,
  permissionHandler,
  bluetoothController;

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
      case LogTypes.gossipProtocol:
        return 'GossipProtocol';
      case LogTypes.meshIncidentSync:
        return 'MeshIncidentSync';
      case LogTypes.permissionHandler:
        return 'PermissionHandler';
      case LogTypes.bluetoothController:
        return 'BluetoothController';
    }
  }
}
