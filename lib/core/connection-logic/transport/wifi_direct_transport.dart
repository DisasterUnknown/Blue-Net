// ========================================
// 7. lib/core/transport/wifi_direct_transport.dart
// ========================================

import 'dart:async';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter/services.dart';
import 'gossip_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';

class WiFiDirectTransport implements GossipTransport {
  static const MethodChannel _channel = MethodChannel(
    'gossip_mesh/wifi_direct',
  );

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
      _channel.setMethodCallHandler(_handleMethodCall);
      await _channel.invokeMethod('initialize');
      await _channel.invokeMethod('startDiscovery');
      LogService.log(
        LogTypes.wifiDirectTransport,
        'WiFiDirectTransport initialized',
      );
    } catch (e, stack) {
      LogService.log(LogTypes.wifiDirectTransport, 'Initialization failed stack: $stack, error: $e');
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
          transport: TransportType.wifiDirect,
        );
        _peerController.add(peer);
        LogService.log(LogTypes.wifiDirectTransport, 'Peer discovered: ${peer.id}');
        break;

      case 'onPeerDisconnected':
        final peerData = Map<String, dynamic>.from(call.arguments);
        final peer = Peer(
          id: peerData['id'],
          name: peerData['name'] ?? 'Unknown',
          transport: TransportType.wifiDirect,
        );
        _peerDisconnectController.add(peer);
        break;

      case 'onMessageReceived':
        final messageData = Map<String, dynamic>.from(call.arguments);
        final message = GossipMessage.fromJsonString(messageData['message']);
        final peer = Peer(
          id: messageData['peer_id'],
          name: messageData['peer_name'] ?? 'Unknown',
          transport: TransportType.wifiDirect,
        );
        _messageController.add(ReceivedMessage(message: message, peer: peer));
        LogService.log(
          LogTypes.wifiDirectTransport,
          'Received message ${message.id} from peer ${peer.id}',
        );
        break;
    }
  }

  @override
  Future<bool> hasInternet() async {
    // WiFi Direct doesn't provide internet by itself
    return false;
  }

  @override
  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    try {
      await _channel.invokeMethod('sendMessage', {
        'peer_id': peer.id,
        'message': message.toJsonString(),
      });
      LogService.log(LogTypes.wifiDirectTransport, 'Message sent: ${message.id} to peer ${peer.id}');
    } catch (e, stack) {
      LogService.log(LogTypes.wifiDirectTransport, 'Send failed stack: $stack, error: $e');
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    await _channel.invokeMethod('stopDiscovery');
    await _messageController.close();
    await _peerController.close();
    await _peerDisconnectController.close();
  }
}
