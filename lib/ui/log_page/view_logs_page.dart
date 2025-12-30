import 'dart:async';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:bluetooth_chat_app/ui/log_page/model/log_entry.dart';
import 'package:bluetooth_chat_app/ui/log_page/utils/get_type_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ViewLogsPage extends StatefulWidget {
  const ViewLogsPage({super.key});

  @override
  State<ViewLogsPage> createState() => _ViewLogsPageState();
}

class _ViewLogsPageState extends State<ViewLogsPage> {
  List<LogEntry> logEntries = [];
  StreamSubscription<LogEntry>? _logSubscription;
  Timer? _refreshTimer;
  final ScrollController _scrollController = ScrollController();
  bool _autoScroll = true;
  bool _isPaused = false;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _setupLiveUpdates();
  }

  void _setupLiveUpdates() {
    // Subscribe to live log stream
    _logSubscription = LogService.logStream.listen((logEntry) {
      if (!mounted || _isPaused) return;
      setState(() {
        // Add new log entry at the beginning (latest first)
        logEntries.insert(0, logEntry);
        // Keep only last 1000 entries to prevent memory issues
        if (logEntries.length > 1000) {
          logEntries = logEntries.take(1000).toList();
        }
      });
      
      // Auto-scroll to top if enabled
      if (_autoScroll && _scrollController.hasClients) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Periodic refresh as backup (every 2 seconds) to catch any missed logs
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshLogs(),
    );
  }

  void _refreshLogs() {
    if (!mounted || _isPaused) return;
    final currentCount = logEntries.length;
    _loadLogs();
    // Only auto-scroll if new logs were added
    if (logEntries.length > currentCount && _autoScroll && _scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _copyAllLogs() async {
    final buffer = StringBuffer();
    for (final entry in logEntries) {
      buffer.writeln('[${entry.timestamp}]');
      buffer.writeln('[${entry.type.displayName}]: ${entry.message}');
      buffer.writeln();
    }
    final text = buffer.toString();
    
    await Clipboard.setData(ClipboardData(text: text));
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('All logs copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _handleClearLogs() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Clear Logs',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to clear all logs?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(context);
              await LogService.clearLogs();
              if (!mounted) return;
              setState(() {
                logEntries.clear();
              });
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
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
        final typeString = typeMatch.group(1)!;
        final type = LogTypes.values.firstWhere(
          (e) => e.name.toLowerCase() == typeString.toLowerCase(),
          orElse: () => LogTypes.info,
        );
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
  void dispose() {
    _logSubscription?.cancel();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        title: Row(
          children: [
            const Text('Logs', style: TextStyle(color: Colors.white)),
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${logEntries.length}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _isPaused ? Icons.play_arrow : Icons.pause,
              color: _isPaused ? Colors.orange : Colors.white70,
            ),
            tooltip: _isPaused ? 'Resume logs' : 'Pause logs',
            onPressed: () {
              setState(() {
                _isPaused = !_isPaused;
              });
            },
          ),
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_top : Icons.vertical_align_center,
              color: _autoScroll ? Colors.greenAccent : Colors.white70,
            ),
            tooltip: _autoScroll ? 'Auto-scroll ON' : 'Auto-scroll OFF',
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all logs',
            onPressed: _copyAllLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh logs',
            onPressed: _loadLogs,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear logs',
            onPressed: _handleClearLogs,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: logEntries.isEmpty
            ? const Center(
                child: Text(
                  "No logs found",
                  style: TextStyle(color: Colors.white70),
                ),
              )
            : Scrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
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
                                text: '[${entry.type.displayName}]: ',
                                style: TextStyle(color: getTypeColor(entry.type)),
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
      ),
    );
  }
}
