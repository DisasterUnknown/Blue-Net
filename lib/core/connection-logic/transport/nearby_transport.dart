import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter/material.dart';
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
        Permission.nearbyWifiDevices,
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
        debugPrint('[NearbyTransport] Missing permissions: $missingText');
        LogService.log(
          LogTypes.nearbyTransport,
          'Missing permissions: $missingText',
        );
        return;
      }

      await _startAdvertising();
      await _startDiscovery();

      LogService.log(LogTypes.nearbyTransport, 'Initialized');
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
      LogService.log(LogTypes.nearbyTransport, 'Advertising started');
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
          // Auto-connect on discovery
          await _requestConnectionWithRetry(id);
        },
        onEndpointLost: (String? id) {
          // Handle loss
          if (id != null) _onDisconnected(id);
        },
        serviceId: 'com.example.hackathon',
      );
      LogService.log(LogTypes.nearbyTransport, 'Discovery started');
    } catch (e, stack) {
      _handleNearbyFailure('Discovery', e, stack);
    }
  }

  Future<void> _requestConnectionWithRetry(String id, {int retries = 3}) async {
    // 1. Check if already connected
    if (_connectedPeers.containsKey(id)) {
      LogService.log(LogTypes.nearbyTransport, 'Already connected to $id');
      return;
    }

    // 2. Random delay to reduce collision probability (0-2 seconds)
    final randomDelay = Random().nextInt(2000);
    await Future.delayed(Duration(milliseconds: randomDelay));

    for (int i = 0; i < retries; i++) {
      // Check again before each attempt
      if (_connectedPeers.containsKey(id)) return;

      try {
        await Nearby().requestConnection(
          userName,
          id,
          onConnectionInitiated: (id, info) => _onConnectionInitiated(id, info),
          onConnectionResult: (id, status) => _onConnectionResult(id, status),
          onDisconnected: (id) => _onDisconnected(id),
        );
        return; // Success
      } catch (e) {
        if (e is PlatformException && e.message?.contains('8012') == true) {
          if (i == retries - 1) {
            _handleNearbyFailure(
              'Connection request (exhausted retries)',
              e,
              null,
            );
          } else {
            final delay = Duration(seconds: i + 1);
            LogService.log(
              LogTypes.nearbyTransport,
              'Connection request failed (8012), retrying in ${delay.inSeconds}s...',
            );
            await Future.delayed(delay);
          }
        } else {
          _handleNearbyFailure('Connection request', e, null);
          break; // Don't retry other errors
        }
      }
    }
  }

  Future<void> restart() async {
    LogService.log(LogTypes.nearbyTransport, 'Restarting transport...');
    await disconnect();
    await Future.delayed(const Duration(seconds: 1));
    await initialize();
  }

  void _onConnectionInitiated(String id, ConnectionInfo info) {
    // Auto-accept
    Nearby()
        .acceptConnection(
          id,
          onPayLoadRecieved: (endpointId, payload) {
            _onPayloadReceived(endpointId, payload);
          },
        )
        .catchError((error, stack) {
          _handleNearbyFailure(
            'Accept connection',
            error,
            stack is StackTrace ? stack : null,
          );
        });
  }

  void _onConnectionResult(String id, Status status) {
    if (status == Status.CONNECTED) {
      final peer = Peer(
        id: id,
        name: 'Peer $id',
        transport: TransportType.wifiDirect,
        hasInternet: false,
        signalStrength: 0,
      );

      _connectedPeers[id] = peer;
      _peerController.add(peer);

      LogService.log(LogTypes.nearbyTransport, 'Peer $id connected via ${peer.transport}');
    }
  }

  void _onDisconnected(String id) {
    final peer = _connectedPeers.remove(id);
    if (peer != null) {
      _peerDisconnectController.add(peer);
      LogService.log(LogTypes.nearbyTransport, 'Peer ${peer.id} disconnected');
    }
  }

  void _onPayloadReceived(String endpointId, Payload payload) {
    LogService.log(
      LogTypes.nearbyTransport,
      'Received payload from $endpointId type: ${payload.type}',
    );
    if (payload.type == PayloadType.BYTES) {
      try {
        final bytes = payload.bytes!;
        final jsonString = utf8.decode(bytes);
        final message = GossipMessage.fromJsonString(jsonString);

        LogService.log(
          LogTypes.nearbyTransport,
          'Parsed GossipMessage: ${message.id} type: ${message.payload.type}',
        );

        final peer =
            _connectedPeers[endpointId] ??
            Peer(
              id: endpointId,
              name: 'Peer $endpointId',
              transport: TransportType.wifiDirect,
            );

        _messageController.add(ReceivedMessage(message: message, peer: peer));
      } catch (e) {
        LogService.log(
          LogTypes.nearbyTransport,
          'Error parsing payload from $endpointId: $e',
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
          'Payload sent successfully to ${peer.id}',
        );
      } catch (e, stack) {
        _handleNearbyFailure('Send payload', e, stack);
      }
    } else {
      LogService.log(
        LogTypes.nearbyTransport,
        'Peer ${peer.id} not connected, cannot send message',
      );
    }
  }

  @override
  Future<void> disconnect() async {
    await Nearby().stopAdvertising();
    await Nearby().stopDiscovery();
    await Nearby().stopAllEndpoints();
    _connectedPeers.clear();
  }

  void _handleNearbyFailure(String action, Object error, StackTrace? stack) {
    if (error is PlatformException) {
      final message = error.message ?? '';
      if (message.contains('STATUS_RADIO_ERROR')) {
        debugPrint(
          '[NearbyTransport] Mesh radios are unavailable. Enable Bluetooth, Nearby Devices, and Location.',
        );
      } else if (message.contains('MISSING_PERMISSION')) {
        debugPrint(
          '[NearbyTransport] Missing permissions for Nearby Connections.',
        );
      }
    }

    LogService.log(
      LogTypes.nearbyTransport,
      '$action failed: $error${stack != null ? ', $stack' : ''}',
    );
  }
}
