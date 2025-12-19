import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerService {
  /// Requests necessary Bluetooth permissions
  static Future<void> requestBluetoothPermissions() async {
    if (Platform.isAndroid) {
      // 1. Create a list of permissions to request
      List<Permission> permissions = [];

      // For Android 12+ (API 31)
      permissions.add(Permission.bluetoothScan);
      permissions.add(Permission.bluetoothConnect);
      permissions.add(Permission.bluetoothAdvertise);

      // For Android 11 and below, Location is usually required for scanning
      permissions.add(Permission.location);

      // 2. Request all at once (shows a single or combined dialog)
      Map<Permission, PermissionStatus> statuses = await permissions.request();

      // 3. Check if crucial ones are granted
      if (statuses[Permission.bluetoothConnect]?.isDenied ?? false) {
        debugPrint("Bluetooth Connect permission denied");
      }
    }
  }
}