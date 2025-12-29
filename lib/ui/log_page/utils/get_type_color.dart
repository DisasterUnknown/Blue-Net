import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:flutter/material.dart';

Color getTypeColor(LogTypes type) {
  switch (type) {
    case LogTypes.error:
      return Colors.redAccent;
    case LogTypes.success:
      return Colors.greenAccent;
    case LogTypes.info:
      return Colors.yellowAccent;
    case LogTypes.bluetoothTransport:
      return Colors.blueAccent;
    case LogTypes.nearbyTransport:
      return Colors.purpleAccent;
    case LogTypes.wifiDirectTransport:
      return Colors.orangeAccent;
    case LogTypes.uploadService:
      return Colors.tealAccent;
    case LogTypes.syncManager:
      return Colors.cyanAccent;
    case LogTypes.conflict:
      return Colors.amberAccent;
    case LogTypes.gossipService:
      return Colors.indigoAccent;
    case LogTypes.gossipProtocol:
      return Colors.deepPurpleAccent;
    case LogTypes.meshIncidentSync:
      return Colors.limeAccent;
    case LogTypes.permissionHandler:
      return Colors.pinkAccent;
    case LogTypes.bluetoothController:
      return Colors.lightBlueAccent;
  }
}
