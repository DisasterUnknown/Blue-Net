// ========================================
// 7. lib/core/storage/gossip_storage.dart
// ========================================

import 'package:bluetooth_chat_app/core/connection-logic/gossip/peer.dart';

import '../gossip/gossip_message.dart';

abstract class GossipStorage {
  Future<void> initialize();
  
  // Seen messages
  Future<Set<String>> getSeenMessageIds();
  Future<void> markAsSeen(String messageId);
  Future<void> cleanOldSeenMessages(Duration age);
  
  // Pending messages
  Future<List<GossipMessage>> getPendingMessages();
  Future<void> savePendingMessage(GossipMessage message);
  Future<void> deletePendingMessage(String messageId);
  Future<void> cleanExpiredMessages();
  
  // Forms
  Future<void> storeFormForRelay(Map<String, dynamic> formData);
  Future<void> markFormAsSubmitted(String formId);
  Future<List<Map<String, dynamic>>> getPendingForms();
  
  // Peers
  Future<void> savePeer(Peer peer);
  Future<List<Peer>> getActivePeers(Duration staleThreshold);
  Future<void> cleanStalePeers(Duration threshold);
}