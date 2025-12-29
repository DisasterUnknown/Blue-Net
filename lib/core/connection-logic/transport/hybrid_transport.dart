import 'dart:async';
import 'gossip_transport.dart';
import 'bluetooth_transport.dart';
import 'wifi_direct_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';
import 'package:async/async.dart';

class HybridTransport implements GossipTransport {
  final BluetoothTransport bluetooth;
  final WiFiDirectTransport wifiDirect;

  HybridTransport({required this.bluetooth, required this.wifiDirect});

  @override
  Future<void> initialize() async {
    await Future.wait([bluetooth.initialize(), wifiDirect.initialize()]);
  }

  @override
  Stream<ReceivedMessage> get onMessageReceived {
    return StreamGroup.merge([
      bluetooth.onMessageReceived,
      wifiDirect.onMessageReceived,
    ]);
  }

  @override
  Stream<Peer> get onPeerDiscovered {
    return StreamGroup.merge([
      bluetooth.onPeerDiscovered,
      wifiDirect.onPeerDiscovered,
    ]);
  }

  @override
  Stream<Peer> get onPeerDisconnected {
    return StreamGroup.merge([
      bluetooth.onPeerDisconnected,
      wifiDirect.onPeerDisconnected,
    ]);
  }

  @override
  Future<bool> hasInternet() async {
    return false; // Transport doesn't provide internet
  }

  @override
  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    // Try WiFi first (faster)
    if (peer.supportsWiFi) {
      try {
        await wifiDirect.sendMessage(peer, message);
        return;
      } catch (e) {
        // Fallback to Bluetooth
      }
    }

    // Try Bluetooth
    if (peer.supportsBluetooth) {
      await bluetooth.sendMessage(peer, message);
    } else {
      throw Exception('No transport available for peer ${peer.id}');
    }
  }

  @override
  Future<void> disconnect() async {
    await Future.wait([bluetooth.disconnect(), wifiDirect.disconnect()]);
  }
}
