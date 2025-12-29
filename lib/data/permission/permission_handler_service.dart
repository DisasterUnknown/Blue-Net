import 'dart:io';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
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
        LogService.log(
          LogTypes.permissionHandler,
          'Bluetooth Connect permission denied - mesh functionality may be limited',
        );
      } else {
        LogService.log(
          LogTypes.permissionHandler,
          'Bluetooth permissions granted successfully',
        );
      }
    }
  }
}