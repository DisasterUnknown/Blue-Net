import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothController {
  
  /// Attempts to turn on Bluetooth
  static Future<void> turnOnBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      debugPrint("Bluetooth not supported by this device");
      return;
    }

    if (Platform.isAndroid) {
      await FlutterBluePlus.turnOn();
    } else if (Platform.isIOS) {
      debugPrint("iOS does not allow programmatically turning on Bluetooth.");
    }
  }

  /// Optional: Check the current state (on/off)
  static Stream<BluetoothAdapterState> get stateStream => FlutterBluePlus.adapterState;
}