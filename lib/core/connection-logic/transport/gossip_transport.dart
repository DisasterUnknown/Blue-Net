// ========================================
// 6. lib/core/transport/gossip_transport.dart
// ========================================

import 'dart:async';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';

class ReceivedMessage {
  final GossipMessage message;
  final Peer peer;

  ReceivedMessage({required this.message, required this.peer});
}

abstract class GossipTransport {
  Stream<ReceivedMessage> get onMessageReceived;
  Stream<Peer> get onPeerDiscovered;
  Stream<Peer> get onPeerDisconnected;

  Future<void> initialize();
  Future<bool> hasInternet();
  Future<void> sendMessage(Peer peer, GossipMessage message);
  Future<void> disconnect();
}
