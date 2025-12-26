import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';

class LogEntry {
  final String timestamp;
  final logTypes type;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.type,
    required this.message,
  });
}