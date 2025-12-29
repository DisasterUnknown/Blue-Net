import 'dart:math';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';

import '../core/connection-logic/gossip/gossip_protocol.dart';
import '../core/connection-logic/gossip/gossip_config.dart';
import '../core/connection-logic/gossip/gossip_payload.dart';
import '../core/connection-logic/storage/gossip_storage_impl.dart';
import '../core/connection-logic/transport/transport_manager.dart';
import '../core/connection-logic/gossip/gossip_message.dart';
import '../core/connection-logic/gossip/peer.dart';
import 'mesh_incident_sync_service.dart';

class GossipService {
  late final GossipProtocol gossip;
  late final GossipStorageImpl storage;
  late final TransportManager transportManager;

  // Singleton pattern
  static final GossipService _instance = GossipService._internal();
  factory GossipService() => _instance;
  GossipService._internal();

  Future<void> initialize() async {
    // Initialize storage
    storage = GossipStorageImpl();
    await storage.initialize();

    // Initialize transport manager (handles Bluetooth mesh)
    transportManager = TransportManager();
    await transportManager.initialize();

    // Initialize gossip protocol with optimized config
    // Use default config (fanout=3, interval=30s) for balanced performance
    gossip = GossipProtocol(
      storage: storage,
      transport: transportManager,
      config:
          GossipConfig.defaultConfig, // OPTIMIZED: fanout=3 instead of flooding
    );
    await gossip.initialize();

    LogService.log(
      LogTypes.gossipService,
      'GossipService initialized with optimized gossip (fanout=${GossipConfig.defaultConfig.gossipFanout})',
    );

    // Initialize mesh incident sync service
    await MeshIncidentSyncService().initialize(transportManager);
  }

  Stream<List<Peer>> get meshPeersStream =>
      transportManager.connectedPeersStream;

  List<Peer> get currentMeshPeers => transportManager.connectedPeers;

  Future<void> submitForm(Map<String, dynamic> formData) async {
    LogService.log(
      LogTypes.gossipService,
      '[GossipService] submitForm called. Data: ${formData['type']}',
    );
    final myDeviceId =
        'local_${DateTime.now().millisecondsSinceEpoch}'; // Temporary ID

    // Add ID and timestamp if missing
    if (formData['id'] == null) formData['id'] = _generateUuid();
    formData['created_at'] = DateTime.now().toIso8601String();

    // Store locally first
    await storage.storeFormForRelay(formData);

    // Broadcast via gossip
    // Wrap payload in GossipMessage
    final payload = GossipPayload.formSubmission(formData);
    final message = GossipMessage(
      id: _generateUuid(),
      originId: myDeviceId,
      payload: payload,
      hops: 0,
      ttl: 24,
      timestamp: DateTime.now(),
    );

    LogService.log(
      LogTypes.gossipService,
      '[GossipService] Broadcasting message ${message.id} to mesh...',
    );
    await gossip.broadcastMessage(message);
    LogService.log(
      LogTypes.gossipService,
      '[GossipService] Broadcast complete.',
    );
  }

  Future<void> dispose() async {
    await MeshIncidentSyncService().dispose();
    gossip.dispose(); // gossip uses dispose(), not stop()
    await transportManager.disconnect();
  }

  String _generateUuid() {
    final random = Random();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hexChars = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hexChars.substring(0, 8)}-${hexChars.substring(8, 12)}-${hexChars.substring(12, 16)}-${hexChars.substring(16, 20)}-${hexChars.substring(20)}';
  }
}
