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
    }
  }