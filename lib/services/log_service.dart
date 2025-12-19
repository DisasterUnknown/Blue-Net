import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class LogService {
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static File? _logFile;

  /// Initialize log file (call in main)
  static Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File('${dir.path}/app_logs.log');
    if (!_logFile!.existsSync()) {
      _logFile!.createSync(recursive: true);
    }
    LogService.log("Success", 'Log file initialized at: ${_logFile!.path}');
  }

  /// Write log entry
  static void log(String tag, String message) {
    if (_logFile == null) return;
    try {
      final timestamp = DateTime.now().toIso8601String();
      final logLine = "[$timestamp] [$tag]: $message\n\n";
      _logFile!.writeAsStringSync(logLine, mode: FileMode.append, flush: true);
      _trimFileIfNeeded();
      debugPrint(logLine);
    } catch (e) {
      LogService.log("Error", 'Error writing log: $e');
    }
  }

  /// Keep log under max size
  static void _trimFileIfNeeded() {
    if (_logFile == null) return;
    try {
      final bytes = _logFile!.lengthSync();
      if (bytes <= maxFileSizeBytes) return;
      final lines = _logFile!.readAsLinesSync();
      int totalBytes = 0;
      int startIndex = 0;
      for (int i = lines.length - 1; i >= 0; i--) {
        totalBytes += lines[i].length + 1;
        if (totalBytes > maxFileSizeBytes) {
          startIndex = i + 1;
          break;
        }
      }
      final newLines = lines.sublist(startIndex);
      _logFile!.writeAsStringSync('${newLines.join('\n')}\n', flush: true);
    } catch (e) {
      LogService.log("Error", 'Error trimming log file: $e');
    }
  }

  /// Read all logs
  static String readAllLogs() {
    if (_logFile == null || !_logFile!.existsSync()) return '';
    return _logFile!.readAsStringSync();
  }

  /// Let user select location and save log file (desktop + Android)
  static Future<String?> downloadLogToUserSelectedLocation() async {
    if (_logFile == null || !_logFile!.existsSync()) return null;

    try {
      final String? dirPath = await getDirectoryPath();
      if (dirPath == null) return null;

      final file = File('$dirPath/app_logs.log');
      await file.writeAsBytes(await _logFile!.readAsBytes(), flush: true);
      LogService.log("Success", 'Log saved to: ${file.path}');
      return file.path;
    } catch (e) {
      LogService.log("Error", 'Error saving log: $e');
      return null;
    }
  }

  /// Clear all logs
  static Future<void> clearLogs() async {
    if (_logFile == null || !_logFile!.existsSync()) return;
    try {
      await _logFile!.writeAsString('', flush: true);
      debugPrint('All logs cleared.');
      log("Success", "Log file cleared.");
    } catch (e) {
      log("Error", 'Error clearing log file: $e');
    }
  }

  static String? get logFilePath => _logFile?.path;
}
