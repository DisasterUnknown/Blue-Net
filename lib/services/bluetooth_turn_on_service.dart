import 'dart:io';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothController {
  
  /// Attempts to turn on Bluetooth
  static Future<void> turnOnBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      LogService.log(
        LogTypes.bluetoothController,
        'Bluetooth is not supported on this device - mesh functionality unavailable',
      );
      return;
    }

    if (Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
        LogService.log(
          LogTypes.bluetoothController,
          'Bluetooth adapter turned on successfully',
        );
      } catch (e) {
        LogService.log(
          LogTypes.bluetoothController,
          'Failed to turn on Bluetooth adapter: $e',
        );
      }
    } else if (Platform.isIOS) {
      LogService.log(
        LogTypes.bluetoothController,
        'iOS does not allow programmatic Bluetooth control - user must enable manually',
      );
    }
  }

  /// Optional: Check the current state (on/off)
  static Stream<BluetoothAdapterState> get stateStream => FlutterBluePlus.adapterState;
}