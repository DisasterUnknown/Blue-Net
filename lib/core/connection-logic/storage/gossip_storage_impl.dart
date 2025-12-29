// ========================================
// 1. lib/core/storage/gossip_storage_impl.dart
// ========================================

import 'dart:async';
import 'gossip_storage.dart';
import '../gossip/gossip_message.dart';
import '../gossip/peer.dart';
import 'repositories/form_repository.dart';
import 'repositories/message_repository.dart';
import 'repositories/peer_repository.dart';
import 'repositories/seen_repository.dart';
import 'models/form_entity.dart';

class GossipStorageImpl implements GossipStorage {
  final FormRepository _formRepo = FormRepository();
  final MessageRepository _messageRepo = MessageRepository();
  final PeerRepository _peerRepo = PeerRepository();
  final SeenRepository _seenRepo = SeenRepository();

  bool _isInitialized = false;

  @override
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
  }

  // Seen messages
  @override
  Future<Set<String>> getSeenMessageIds() async {
    return await _seenRepo.getAllSeenIds();
  }

  @override
  Future<void> markAsSeen(String messageId) async {
    await _seenRepo.markAsSeen(messageId);
  }

  @override
  Future<void> cleanOldSeenMessages(Duration age) async {
    await _seenRepo.deleteOld(age);
  }

  // Pending messages
  @override
  Future<List<GossipMessage>> getPendingMessages() async {
    return await _messageRepo.getNotExpired(24);
  }

  @override
  Future<void> savePendingMessage(GossipMessage message) async {
    await _messageRepo.insert(message);
  }

  @override
  Future<void> deletePendingMessage(String messageId) async {
    await _messageRepo.delete(messageId);
  }

  @override
  Future<void> cleanExpiredMessages() async {
    await _messageRepo.deleteExpired(24);
  }

  // Forms
  @override
  Future<void> storeFormForRelay(Map<String, dynamic> formData) async {
    final form = FormEntity(
      id: formData['id'],
      data: formData,
      status: FormStatus.pending,
      createdAt: DateTime.parse(
        formData['created_at'] ?? DateTime.now().toIso8601String(),
      ),
    );
    await _formRepo.insert(form);
  }

  @override
  Future<void> markFormAsSubmitted(String formId) async {
    await _formRepo.updateStatus(
      formId,
      FormStatus.synced,
      syncedAt: DateTime.now(),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingForms() async {
    final forms = await _formRepo.getAllPending();
    return forms.map((f) => f.data).toList();
  }

  // Peers
  @override
  Future<void> savePeer(Peer peer) async {
    await _peerRepo.insert(peer);
  }

  @override
  Future<List<Peer>> getActivePeers(Duration staleThreshold) async {
    return await _peerRepo.getActive(staleThreshold);
  }

  @override
  Future<void> cleanStalePeers(Duration threshold) async {
    await _peerRepo.deleteStale(threshold);
  }
}
