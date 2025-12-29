import 'dart:async';
import 'gossip_transport.dart';
import 'nearby_transport.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';

class TransportManager {
  static final TransportManager _instance = TransportManager._internal();
  factory TransportManager() => _instance;

  late final NearbyTransport _transport;
  bool _isInitialized = false;

  final _messageController = StreamController<ReceivedMessage>.broadcast();
  final _peerController = StreamController<Peer>.broadcast();
  final _peerDisconnectedController = StreamController<Peer>.broadcast();
  final _peerListController = StreamController<List<Peer>>.broadcast();
  final Map<String, Peer> _activePeers = {};

  TransportManager._internal();

  Future<void> initialize() async {
    if (_isInitialized) return;

    _transport = NearbyTransport();
    await _transport.initialize();

    // Listen to transport events
    _transport.onMessageReceived.listen(_messageController.add);

    _transport.onPeerDiscovered.listen((peer) {
      _peerController.add(peer);
      _activePeers[peer.id] = peer;
      _emitPeerSnapshot();
    });

    _transport.onPeerDisconnected.listen((peer) {
      _activePeers.remove(peer.id);
      _peerDisconnectedController.add(peer);
      _emitPeerSnapshot();
    });

    _emitPeerSnapshot();
    _isInitialized = true;
  }

  void _emitPeerSnapshot() {
    _peerListController.add(_activePeers.values.toList(growable: false));
  }

  Stream<ReceivedMessage> get onMessageReceived => _messageController.stream;
  Stream<Peer> get onPeerDiscovered => _peerController.stream;
  Stream<Peer> get onPeerDisconnected => _peerDisconnectedController.stream;
  Stream<List<Peer>> get connectedPeersStream => _peerListController.stream;
  List<Peer> get connectedPeers => _activePeers.values.toList(growable: false);

  Future<void> sendMessage(Peer peer, GossipMessage message) async {
    if (!_isInitialized) throw Exception('TransportManager not initialized');
    await _transport.sendMessage(peer, message);
  }

  Future<void> disconnect() async {
    if (!_isInitialized) return;
    await _transport.disconnect();
    _activePeers.clear();
    _emitPeerSnapshot();
    _isInitialized = false;
  }

  Future<bool> hasInternet() async {
    if (!_isInitialized) return false;
    return await _transport.hasInternet();
  }
}
