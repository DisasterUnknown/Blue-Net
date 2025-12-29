import 'package:bluetooth_chat_app/services/bluetooth_turn_on_service.dart';
import 'package:bluetooth_chat_app/services/mesh_service.dart';
import 'package:bluetooth_chat_app/data/data_base/db_helper.dart';
import 'package:bluetooth_chat_app/services/uuid_service.dart';
import 'package:bluetooth_chat_app/services/mesh_incident_sync_service.dart';
import 'package:bluetooth_chat_app/services/gossip_service.dart';
import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class InfoPage extends StatelessWidget {
  const InfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mesh = MeshService.instance;
    final gossipService = GossipService();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        title: const Text(
          'Mesh & DB Info',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Bluetooth & Mesh Status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<BluetoothAdapterState>(
            stream: BluetoothController.stateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              String label = 'Unknown';
              Color color = Colors.grey;
              if (state == BluetoothAdapterState.on) {
                label = 'On';
                color = Colors.greenAccent;
              } else if (state == BluetoothAdapterState.off) {
                label = 'Off';
                color = Colors.redAccent;
              } else if (state == BluetoothAdapterState.turningOn ||
                  state == BluetoothAdapterState.turningOff) {
                label = 'Changing';
                color = Colors.orangeAccent;
              }
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: color,
                  child: const Icon(Icons.bluetooth, color: Colors.black),
                ),
                title: const Text(
                  'Bluetooth Adapter',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade300),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          // Live connected devices count using StreamBuilder
          StreamBuilder<List<Peer>>(
            stream: gossipService.meshPeersStream,
            builder: (context, snapshot) {
              final connectedCount = snapshot.data?.length ?? 0;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: connectedCount > 0 
                      ? Colors.greenAccent.withOpacity(0.3)
                      : const Color(0xFF2A2A2A),
                  child: Icon(
                    Icons.devices,
                    color: connectedCount > 0 
                        ? Colors.greenAccent
                        : Colors.lightBlueAccent,
                  ),
                ),
                title: const Text(
                  'Connected Peers (Live)',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '$connectedCount device(s) currently connected.',
                  style: TextStyle(
                    color: connectedCount > 0 
                        ? Colors.greenAccent.shade200
                        : Colors.grey.shade400,
                    fontSize: 12,
                    fontWeight: connectedCount > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
          ValueListenableBuilder<MeshStats>(
            valueListenable: mesh.stats,
            builder: (context, stats, _) {
              final avgSeconds = stats.avgDeliveryMillis > 0
                  ? stats.avgDeliveryMillis / 1000
                  : 0;
              final nextCleanupStr = stats.nextCleanupTime != null
                  ? _formatTime(stats.nextCleanupTime!)
                  : 'Scheduled ~every 30 minutes';
              return Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.send, color: Colors.greenAccent),
                    ),
                    title: const Text(
                      'Messages',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Sent: ${stats.totalMessagesSent}  |  '
                      'Seen on network: ${stats.totalMessagesReceived}\n'
                      'Delivered to this device: ${stats.totalMessagesDeliveredToMe}',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.timer, color: Colors.orangeAccent),
                    ),
                    title: const Text(
                      'Delivery Time',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      stats.successfulDeliveries == 0
                          ? 'No deliveries recorded yet.'
                          : 'Average delivery: ${avgSeconds.toStringAsFixed(1)}s\n'
                            'Based on ${stats.successfulDeliveries} delivered message(s).',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.cleaning_services,
                          color: Colors.lightGreenAccent),
                    ),
                    title: const Text(
                      'Cleanup',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Last removed: ${stats.lastCleanupRemovedCount} relay message(s).\n'
                      'Next cleanup around: $nextCleanupStr',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'Data & Security Overview',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<Map<String, dynamic>>(
            future: _loadDbStatsWithId(),
            builder: (context, snapshot) {
              final data = snapshot.data ??
                  const {
                    'myId': null,
                    'users': 0,
                    'relayTotal': 0,
                    'relayPending': 0,
                    'hashes': 0,
                  };
              final myId = data['myId'] as String?;
              final userCount = data['users'] as int? ?? 0;
              final relayTotal = data['relayTotal'] as int? ?? 0;
              final relayPending = data['relayPending'] as int? ?? 0;
              final hashes = data['hashes'] as int? ?? 0;

              return Column(
                children: [
                  if (myId != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Your ID: $myId',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child:
                          Icon(Icons.people, color: Colors.lightBlueAccent),
                    ),
                    title: const Text(
                      'Known Users Stored Locally',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '$userCount user(s) saved with ID + display name.',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.sync_alt, color: Colors.orangeAccent),
                    ),
                    title: const Text(
                      'Relay Queue (nonUserMsgs)',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      'Total relay records: $relayTotal\n'
                      'Pending forwards: $relayPending',
                      style: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.verified, color: Colors.lightGreen),
                    ),
                    title: const Text(
                      'Hash-based Deduplication (hashMsgs)',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '$hashes unique message ID(s) seen so far.\n'
                      'Prevents the same encrypted message from\n'
                      'being processed or forwarded twice.',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child: Icon(Icons.lock, color: Colors.greenAccent),
                    ),
                    title: const Text(
                      'Message Encryption',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Messages are encrypted per receiver using a key\n'
                      'derived from their user ID before being stored or\n'
                      'forwarded through the mesh.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFF2A2A2A),
                      child:
                          Icon(Icons.storage_rounded, color: Colors.purple),
                    ),
                    title: const Text(
                      'Local-only Storage',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'All chats and routing metadata live inside a local\n'
                      'SQLite database on this device. No cloud or\n'
                      'internet connection is used.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      // Trigger manual cleanup
                      final meshIncidentSync = MeshIncidentSyncService();
                      final stats = await meshIncidentSync.performManualCleanup();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Cleanup completed. Removed old data.\n'
                            'Stats: ${stats.toString()}',
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                    icon: const Icon(Icons.cleaning_services),
                    label: const Text('Clean Up Old Data'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Future<Map<String, dynamic>> _loadDbStatsWithId() async {
  final db = DBHelper();
  final myId = await AppIdentifier.getId();
  final users = await db.getAllUsers();
  final totalRelay = await db.countNonUserMsgs();
  final pendingRelay = await db.countPendingNonUserMsgs();
  final hashes = await db.countHashMsgs();
  return {
    'myId': myId,
    'users': users.length,
    'relayTotal': totalRelay,
    'relayPending': pendingRelay,
    'hashes': hashes,
  };
}

String _formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final min = time.minute.toString().padLeft(2, '0');
  final ampm = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$min $ampm';
}


