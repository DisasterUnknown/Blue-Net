import 'package:flutter/material.dart';

Color getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'error':
        return Colors.redAccent;
      case 'success':
        return Colors.greenAccent;
      case 'info':
      default:
        return Colors.lightBlueAccent;
    }
  }