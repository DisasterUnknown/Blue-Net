// ========================================
// 6. lib/core/transport/bluetooth_transport.dart
// ========================================

import 'dart:async';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter/services.dart';
import 'gossip_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';

class BluetoothTransport implements GossipTransport {
  static const MethodChannel _channel = MethodChannel('gossip_mesh/bluetooth');

  final StreamController<ReceivedMessage> _messageController =
      StreamController<ReceivedMessage>.broadcast();

  final StreamController<Peer> _peerController =
      StreamController<Peer>.broadcast();

  final StreamController<Peer> _peerDisconnectController =
      StreamController<Peer>.broadcast();

  @override
  Stream<ReceivedMessage> get onMessageReceived => _messageController.stream;

  @override
  Stream<Peer> get onPeerDiscovered => _peerController.stream;

  @override
  Stream<Peer> get onPeerDisconnected => _peerDisconnectController.stream;

  @override
  Future<void> initialize() async {
    try {
      // Set up method call handler for native callbacks
      _channel.setMethodCallHandler(_handleMethodCall);

      // Initialize Bluetooth on native side
      await _channel.invokeMethod('initialize');

      // Start scanning
      await _channel.invokeMethod('startScanning');

      LogService.log(
        LogTypes.bluetoothTransport,
        'BluetoothTransport initialized',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.bluetoothTransport,
        'BluetoothTransport initialization failed: $e, $stack',
      );
      rethrow;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPeerDiscovered':
        final peerData = Map<String, dynamic>.from(call.arguments);
        final peer = Peer(
          id: peerData['id'],
          name: peerData['name'] ?? 'Unknown',
          hasInternet: peerData['has_internet'] ?? false,
          signalStrength: peerData['rssi'] ?? 0,
          transport: TransportType.bluetooth,
        );
        _peerController.add(peer);
        LogService.log(
          LogTypes.bluetoothTransport,
          'Peer discovered: ${peer.id}',
        );
        break;

      case 'onPeerDisconnected':
        final peerData = Map<String, dynamic>.from(call.arguments);
        final peer = Peer(
          id: peerData['id'],
          name: peerData['name'] ?? 'Unknown',
          transport: TransportType.bluetooth,
        );
        _peerDisconnectController.add(peer);
        break;

      case 'onMessageReceived':
        final messageData = Map<String, dynamic>.from(call.arguments);
        final message = GossipMessage.fromJsonString(messageData['message']);
        final peer = Peer(
          id: messageData['peer_id'],
          name: messageData['peer_name'] ?? 'Unknown',
          transport: TransportType.bluetooth,
        );
        _messageController.add(ReceivedMessage(message: message, peer: peer));
        LogService.log(
          LogTypes.bluetoothTransport,
          'Message received: ${message.id} from peer: ${peer.id}',
        );
        break;

      case 'onError':
        LogService.log(
          LogTypes.bluetoothTransport,
          'Native error: ${call.arguments}',
        );
        break;
    }
  }

  @override
  Future<bool> hasInternet() async {
    // Bluetooth transport doesn't provide internet
    return false;
  }

  @override
  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    try {
      await _channel.invokeMethod('sendMessage', {
        'peer_id': peer.id,
        'message': message.toJsonString(),
      });
      LogService.log(
        LogTypes.bluetoothTransport,
        'Message sent: ${message.id} to peer: ${peer.id}',
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.bluetoothTransport,
        'Send failed: $e, $stack',
      );
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod('stopScanning');
    await _messageController.close();
    await _peerController.close();
    await _peerDisconnectController.close();
  }
}
