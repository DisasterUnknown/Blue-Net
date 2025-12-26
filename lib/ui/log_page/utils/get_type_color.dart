import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:flutter/material.dart';

Color getTypeColor(logTypes type) {
    switch (type) {
      case logTypes.error:
        return Colors.redAccent;
      case logTypes.success:
        return Colors.greenAccent;
      case logTypes.info:
        return Colors.yellowAccent;
    }
  }