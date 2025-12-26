import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/ui/log_page/model/log_entry.dart';
import 'package:bluetooth_chat_app/ui/log_page/utils/get_type_color.dart';
import 'package:flutter/material.dart';

class ViewLogsPage extends StatefulWidget {
  const ViewLogsPage({super.key});

  @override
  State<ViewLogsPage> createState() => _ViewLogsPageState();
}

class _ViewLogsPageState extends State<ViewLogsPage> {
  List<LogEntry> logEntries = [];

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() {
    final rawLogs = LogService.readAllLogs();
    final entries = <LogEntry>[];

    final lines = rawLogs.split('\n');
    for (var line in lines) {
      if (line.trim().isEmpty) continue;

      // Correct regex to take second [] for type
      final timestampMatch = RegExp(r'\[(.*?)\]').firstMatch(line);
      final typeMatch = RegExp(r'\[.*?\]\s*\[(.*?)\]:').firstMatch(line);

      if (timestampMatch != null && typeMatch != null) {
        final timestamp = timestampMatch.group(1)!;
        final type = typeMatch.group(1)! as logTypes;
        final message = line.substring(line.indexOf(']:') + 2).trim();
        entries.add(
          LogEntry(timestamp: timestamp, type: type, message: message),
        );
      }
    }

    setState(() {
      logEntries = entries.reversed.toList(); // latest first
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Logs',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: logEntries.isEmpty
            ? const Center(child: Text("No logs found"))
            : SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                    children: logEntries
                        .map(
                          (entry) => [
                            TextSpan(
                              text: '[${entry.timestamp}]\n',
                              style: const TextStyle(color: Colors.grey),
                            ),
                            TextSpan(
                              text: '[${entry.type}]: ',
                              style: TextStyle(
                                color: getTypeColor(entry.type),
                              ),
                            ),
                            TextSpan(text: '${entry.message}\n\n'),
                          ],
                        )
                        .expand((element) => element)
                        .toList(),
                  ),
                ),
              ),
      ),
    );
  }
}
