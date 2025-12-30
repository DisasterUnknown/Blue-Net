import 'dart:io';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionHandlerService {
  static Future<void> requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return;

    final List<Permission> permissions = [];

    // ───────── Android 12+ (API 31+) ─────────
    permissions.addAll([
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
    ]);

    // ───────── Android 13+ (API 33+) ─────────
    permissions.add(Permission.nearbyWifiDevices);

    // ───────── Android 11 and below ─────────
    permissions.add(Permission.location);

    final statuses = await permissions.request();

    // ---- Logging ----
    if (statuses[Permission.nearbyWifiDevices]?.isGranted == true) {
      LogService.log(
        LogTypes.permissionHandler,
        'Nearby Wi-Fi Devices permission granted',
      );
    } else {
      LogService.log(
        LogTypes.permissionHandler,
        'Nearby Wi-Fi Devices permission denied — discovery WILL FAIL',
      );
    }

    if (statuses[Permission.bluetoothConnect]?.isGranted == true) {
      LogService.log(
        LogTypes.permissionHandler,
        'Bluetooth permissions granted successfully',
      );
    }
  }
}
