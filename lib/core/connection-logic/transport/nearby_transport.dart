import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter/services.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';
import 'gossip_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';

class NearbyTransport implements GossipTransport {
  final Strategy strategy = Strategy.P2P_CLUSTER;
  final String userName = 'User_${DateTime.now().millisecondsSinceEpoch}';

  final StreamController<ReceivedMessage> _messageController =
      StreamController<ReceivedMessage>.broadcast();

  final StreamController<Peer> _peerController =
      StreamController<Peer>.broadcast();

  final StreamController<Peer> _peerDisconnectController =
      StreamController<Peer>.broadcast();

  // Map endpointId -> Peer metadata
  final Map<String, Peer> _connectedPeers = {};
  // Track peers that are currently connecting to avoid duplicate connection attempts
  final Set<String> _connectingPeers = {};
  // Track recently disconnected peers for reconnection attempts
  final Map<String, DateTime> _recentlyDisconnected = {};
  Timer? _reconnectionTimer;

  @override
  Stream<ReceivedMessage> get onMessageReceived => _messageController.stream;

  @override
  Stream<Peer> get onPeerDiscovered => _peerController.stream;

  @override
  Stream<Peer> get onPeerDisconnected => _peerDisconnectController.stream;

  @override
  Future<void> initialize() async {
    try {
      final requiredPermissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
        Permission.location,
      ];

      final statuses = await requiredPermissions.request();
      final missing = statuses.entries
          .where((entry) => !entry.value.isGranted)
          .map((entry) => entry.key)
          .toList();

      if (missing.isNotEmpty) {
        final missingText = missing
            .map((p) => p.toString().split('.').last)
            .join(', ');
        LogService.log(
          LogTypes.nearbyTransport,
          'Missing required permissions for Nearby Connections: $missingText',
        );
        LogService.log(
          LogTypes.nearbyTransport,
          'Missing permissions: $missingText',
        );
        return;
      }

      await _startAdvertising();
      await _startDiscovery();

      // Start periodic reconnection attempts for recently disconnected peers
      _startReconnectionTimer();

      LogService.log(
        LogTypes.nearbyTransport,
        'NearbyTransport initialized successfully - Advertising and Discovery started, Service ID: com.example.hackathon',
      );
    } catch (e, stack) {
      _handleNearbyFailure('Initialization', e, stack);
    }
  }

  Future<void> _startAdvertising() async {
    try {
      await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: (String id, ConnectionInfo info) {
          _onConnectionInitiated(id, info);
        },
        onConnectionResult: (String id, Status status) {
          _onConnectionResult(id, status);
        },
        onDisconnected: (String id) {
          _onDisconnected(id);
        },
        serviceId: 'com.example.hackathon', // Must match manifest
      );
      LogService.log(
        LogTypes.nearbyTransport,
        'Started advertising as server - Device name: $userName, Strategy: ${strategy.name}',
      );
    } catch (e, stack) {
      _handleNearbyFailure('Advertising', e, stack);
    }
  }

  Future<void> _startDiscovery() async {
    try {
      await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (String id, String name, String serviceId) async {
          // Auto-connect on discovery (if not already connected or connecting)
          if (!_connectedPeers.containsKey(id) &&
              !_connectingPeers.contains(id)) {
            await _requestConnectionWithRetry(id);
          }
        },
        onEndpointLost: (String? id) {
          // Handle loss
          if (id != null) _onDisconnected(id);
        },
        serviceId: 'com.example.hackathon',
      );
      LogService.log(
        LogTypes.nearbyTransport,
        'Started discovery as client - Looking for nearby devices with Service ID: com.example.hackathon',
      );
    } catch (e, stack) {
      _handleNearbyFailure('Discovery', e, stack);
    }
  }

  Future<void> _requestConnectionWithRetry(String id, {int retries = 3}) async {
    // 1. Check if already connected
    if (_connectedPeers.containsKey(id)) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Already connected to peer $id - skipping connection request',
      );
      return;
    }

    // 2. Check if already connecting to avoid duplicate attempts
    if (_connectingPeers.contains(id)) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Already connecting to peer $id - skipping duplicate connection request',
      );
      return;
    }

    // 3. Random delay to reduce collision probability (0-2 seconds)
    final randomDelay = Random().nextInt(2000);
    await Future.delayed(Duration(milliseconds: randomDelay));

    _connectingPeers.add(id);

    try {
      for (int i = 0; i < retries; i++) {
        // Check again before each attempt
        if (_connectedPeers.containsKey(id)) {
          _connectingPeers.remove(id);
          return;
        }

        try {
          await Nearby().requestConnection(
            userName,
            id,
            onConnectionInitiated: (id, info) =>
                _onConnectionInitiated(id, info),
            onConnectionResult: (id, status) => _onConnectionResult(id, status),
            onDisconnected: (id) => _onDisconnected(id),
          );
          // Don't remove from _connectingPeers here - wait for connection result
          return; // Success
        } catch (e) {
          if (e is PlatformException && e.message?.contains('8012') == true) {
            if (i == retries - 1) {
              _connectingPeers.remove(id);
              _handleNearbyFailure(
                'Connection request (exhausted retries)',
                e,
                null,
              );
            } else {
              final delay = Duration(seconds: i + 1);
              LogService.log(
                LogTypes.nearbyTransport,
                'Connection request to peer $id failed (error 8012) - Retry ${i + 1}/$retries in ${delay.inSeconds}s',
              );
              await Future.delayed(delay);
            }
          } else if (e is PlatformException &&
              e.message?.contains('8011') == true) {
            // Endpoint unknown — discard stale endpoint and wait for new discovery
            LogService.log(
              LogTypes.nearbyTransport,
              'Endpoint $id unknown (8011) - will retry when a new endpoint is discovered',
            );
            _connectingPeers.remove(id);
            _recentlyDisconnected.remove(id); // prevent retrying stale ID
            return; // exit retry loop
          } else {
            _connectingPeers.remove(id);
            _handleNearbyFailure('Connection request', e, null);
            break; // Don't retry other errors
          }
        }
      }
    } finally {
      // Remove from connecting set after a delay to allow connection result to process
      Future.delayed(Duration(seconds: 5), () {
        _connectingPeers.remove(id);
      });
    }
  }

  Future<void> restart() async {
    LogService.log(LogTypes.nearbyTransport, 'Restarting transport...');
    await disconnect();
    await Future.delayed(const Duration(seconds: 1));
    await initialize();
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    // Check if already connected to avoid duplicate acceptance
    if (_connectedPeers.containsKey(id)) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Connection already established with peer $id - ignoring duplicate connection initiation',
      );
      return;
    }

    LogService.log(
      LogTypes.nearbyTransport,
      'Connection initiated from peer $id - Auto-accepting connection request (Endpoint name: ${info.endpointName})',
    );

    // Remove from connecting set since we're accepting
    _connectingPeers.remove(id);

    // Auto-accept
    Nearby()
        .acceptConnection(
          id,
          onPayLoadRecieved: (endpointId, payload) {
            _onPayloadReceived(endpointId, payload);
          },
        )
        .catchError((error, stack) {
          LogService.log(
            LogTypes.nearbyTransport,
            'Failed to accept connection from peer $id: $error',
          );
          _handleNearbyFailure(
            'Accept connection',
            error,
            stack is StackTrace ? stack : null,
          );
          return Future.value(false);
        });
  }

  void _onConnectionResult(String id, Status status) {
    // Remove from connecting set regardless of status
    _connectingPeers.remove(id);
    // Remove from recently disconnected if present
    _recentlyDisconnected.remove(id);

    if (status == Status.CONNECTED) {
      final peer = Peer(
        id: id,
        name: 'Peer $id',
        transport: TransportType.bluetooth,
        hasInternet: false,
        signalStrength: 0,
      );

      _connectedPeers[id] = peer;
      _peerController.add(peer);

      LogService.log(
        LogTypes.nearbyTransport,
        'Peer $id connected via ${peer.transport} - Total connected: ${_connectedPeers.length}',
      );
    } else if (status == Status.REJECTED) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Connection to peer $id was REJECTED - Will retry on next discovery',
      );
      // Mark as recently disconnected so we can retry
      _recentlyDisconnected[id] = DateTime.now();
    } else if (status == Status.ERROR) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Connection to peer $id resulted in ERROR - Will retry on next discovery',
      );
      // Mark as recently disconnected so we can retry
      _recentlyDisconnected[id] = DateTime.now();
    } else {
      LogService.log(
        LogTypes.nearbyTransport,
        'Connection to peer $id resulted in status: $status',
      );
    }
  }

  void _onDisconnected(String id) {
    final peer = _connectedPeers.remove(id);
    if (peer != null) {
      _peerDisconnectController.add(peer);
      // Mark as recently disconnected for potential reconnection
      _recentlyDisconnected[id] = DateTime.now();
      LogService.log(
        LogTypes.nearbyTransport,
        'Peer ${peer.id} disconnected - Remaining connected: ${_connectedPeers.length} - Will attempt reconnection',
      );
    }
    // Also remove from connecting set if present
    _connectingPeers.remove(id);
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    LogService.log(
      LogTypes.nearbyTransport,
      'Received payload from peer $endpointId - Type: ${payload.type}, Size: ${payload.bytes?.length ?? 0} bytes',
    );
    if (payload.type == PayloadType.BYTES) {
      try {
        final bytes = payload.bytes!;
        final jsonString = utf8.decode(bytes);
        final message = GossipMessage.fromJsonString(jsonString);

        LogService.log(
          LogTypes.nearbyTransport,
          'Successfully parsed GossipMessage ${message.id} from peer $endpointId - Payload type: ${message.payload.type}, Hops: ${message.hops}',
        );

        final peer =
            _connectedPeers[endpointId] ??
            Peer(
              id: endpointId,
              name: 'Peer $endpointId',
              transport: TransportType.bluetooth,
            );

        _messageController.add(ReceivedMessage(message: message, peer: peer));
        LogService.log(
          LogTypes.nearbyTransport,
          'Message ${message.id} delivered to application layer from peer $endpointId',
        );
      } catch (e, stack) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Error parsing payload from peer $endpointId: $e\nStack: $stack',
        );
      }
    }
  }

  @override
  Future<bool> hasInternet() async {
    return false; // This transport doesn't provide internet
  }

  @override
  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    if (_connectedPeers.containsKey(peer.id)) {
      final jsonString = message.toJsonString();
      final bytes = utf8.encode(jsonString);
      LogService.log(
        LogTypes.nearbyTransport,
        'Sending ${bytes.length} bytes to ${peer.id}',
      );
      try {
        await Nearby().sendBytesPayload(peer.id, Uint8List.fromList(bytes));
        LogService.log(
          LogTypes.nearbyTransport,
          'Successfully sent message ${message.id} (${bytes.length} bytes) to peer ${peer.id}',
        );
      } catch (e, stack) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Failed to send message ${message.id} to peer ${peer.id}: $e',
        );
        _handleNearbyFailure('Send payload', e, stack);
      }
    } else {
      LogService.log(
        LogTypes.nearbyTransport,
        'Peer ${peer.id} not connected, cannot send message',
      );
    }
  }

  void _startReconnectionTimer() {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _attemptReconnections();
    });
  }

  void _attemptReconnections() {
    if (_recentlyDisconnected.isEmpty) return;

    final now = DateTime.now();
    final peersToRetry = <String>[];
    final peersToRemove = <String>[];

    // Find peers that were disconnected recently (within last 2 minutes)
    _recentlyDisconnected.forEach((id, disconnectTime) {
      if (now.difference(disconnectTime).inSeconds < 120) {
        // Only retry if not already connected or connecting
        if (!_connectedPeers.containsKey(id) &&
            !_connectingPeers.contains(id)) {
          peersToRetry.add(id);
        }
      } else {
        // Mark old entries for removal (older than 2 minutes)
        peersToRemove.add(id);
      }
    });

    // Remove old entries
    for (final id in peersToRemove) {
      _recentlyDisconnected.remove(id);
    }

    if (peersToRetry.isNotEmpty) {
      LogService.log(
        LogTypes.nearbyTransport,
        'Attempting to reconnect to ${peersToRetry.length} recently disconnected peers',
      );
      for (final id in peersToRetry) {
        _requestConnectionWithRetry(id, retries: 2);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _reconnectionTimer?.cancel();
    _reconnectionTimer = null;
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    _connectedPeers.clear();
    _connectingPeers.clear();
    _recentlyDisconnected.clear();
  }

  void _handleNearbyFailure(String action, Object error, StackTrace? stack) {
    if (error is PlatformException) {
      final message = error.message ?? '';
      if (message.contains('STATUS_RADIO_ERROR')) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Mesh radios unavailable - ensure Bluetooth, Nearby Devices, and Location services are enabled',
        );
      } else if (message.contains('MISSING_PERMISSION')) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Missing permissions for Nearby Connections - please grant required permissions',
        );
      }
    }

    LogService.log(
      LogTypes.nearbyTransport,
      '$action failed: $error${stack != null ? ', $stack' : ''}',
    );
  }
}
