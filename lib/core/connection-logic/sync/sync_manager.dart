import 'dart:async';
import 'dart:math';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:permission_handler/permission_handler.dart';
import '../storage/gossip_storage.dart';
import '../gossip/gossip_protocol.dart';
import '../gossip/gossip_payload.dart';
import '../gossip/gossip_message.dart';
import '../storage/repositories/form_repository.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final int pendingCount;
  final int syncedCount;
  final String? errorMessage;

  SyncState({
    required this.status,
    this.pendingCount = 0,
    this.syncedCount = 0,
    this.errorMessage,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? pendingCount,
    int? syncedCount,
    String? errorMessage,
  }) {
    return SyncState(
      status: status ?? this.status,
      pendingCount: pendingCount ?? this.pendingCount,
      syncedCount: syncedCount ?? this.syncedCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class SyncManager {
  final GossipStorage storage;
  final GossipProtocol? gossipProtocol;
  final FormRepository formRepository;

  // Temporary local ID for this session (should be persisted in production)
  final String _localPeerId = 'local_${DateTime.now().millisecondsSinceEpoch}';

  final StreamController<SyncState> _stateController =
      StreamController<SyncState>.broadcast();

  Stream<SyncState> get stateStream => _stateController.stream;

  SyncState _currentState = SyncState(status: SyncStatus.idle);
  Timer? _periodicSyncTimer;

  SyncManager({
    required this.storage,
    required this.formRepository,
    this.gossipProtocol,
  });

  Future<void> initialize() async {
    // Start periodic sync check (gossip only, no server sync)
    _periodicSyncTimer = Timer.periodic(Duration(minutes: 5), (_) {
      attemptSync();
    });

    // Listen to gossip messages for confirmations
    if (gossipProtocol != null) {
      gossipProtocol!.onMessage.listen((message) async {
        if (message.payload.type == PayloadType.confirmation) {
          final formId = message.payload.data['form_id'] ?? 
                         message.payload.data['incident_id'] ??
                         message.payload.data['incidentId'];
          LogService.log(
            LogTypes.syncManager,
            'Received confirmation for $formId via gossip',
          );
        }
      });
    }
  }

  Future<void> attemptSync() async {
    if (_currentState.status == SyncStatus.syncing) {
      LogService.log(LogTypes.syncManager, 'Sync already in progress');
      return;
    }

    _updateState(_currentState.copyWith(status: SyncStatus.syncing));

    try {
      // Get pending forms from FormRepository
      final pendingEntities = await formRepository.getAllPending();
      final pendingForms = pendingEntities.map((e) => e.data).toList();

      if (pendingForms.isEmpty) {
        LogService.log(LogTypes.syncManager, 'No pending forms to sync');
        _updateState(
          _currentState.copyWith(status: SyncStatus.idle, pendingCount: 0),
        );
        return;
      }

      // Check if Bluetooth enabled (Permissions check as proxy for enabled state)
      bool locationGranted = await Permission.location.isGranted;
      bool bluetoothGranted =
          await Permission.bluetoothAdvertise.isGranted ||
          await Permission.bluetoothConnect.isGranted;

      if (!locationGranted || !bluetoothGranted) {
        LogService.log(LogTypes.syncManager,
            'Missing permissions for gossip (Location: $locationGranted, Bluetooth: $bluetoothGranted). Aborting gossip.');
        _updateState(_currentState.copyWith(status: SyncStatus.idle));
        return;
      }

      LogService.log(
        LogTypes.syncManager,
        'Attempting to gossip ${pendingForms.length} forms via Bluetooth mesh',
      );

      if (gossipProtocol != null) {
        int gossipedCount = 0;
        for (final form in pendingForms) {
          try {
            final payload = GossipPayload.formSubmission(form);
            final message = GossipMessage(
              id: _generateUuid(),
              originId: _localPeerId,
              payload: payload,
              hops: 0,
              ttl: 24, // 24 hours
              timestamp: DateTime.now(),
            );

            await gossipProtocol!.broadcastMessage(message);
            gossipedCount++;
          } catch (e) {
            LogService.log(
              LogTypes.syncManager,
              'Failed to gossip form ${form['id']}',
            );
          }
        }
        LogService.log(
          LogTypes.syncManager,
          'Gossiped $gossipedCount forms via Bluetooth mesh',
        );
        
        _updateState(
          _currentState.copyWith(
            status: gossipedCount > 0 ? SyncStatus.success : SyncStatus.idle,
            syncedCount: gossipedCount,
          ),
        );
      } else {
        LogService.log(
          LogTypes.syncManager,
          'GossipProtocol not available, cannot gossip.',
        );
        _updateState(_currentState.copyWith(status: SyncStatus.idle));
      }
    } catch (e, stack) {
      LogService.log(LogTypes.syncManager, 'Sync error: $e, $stack');
      _updateState(
        _currentState.copyWith(
          status: SyncStatus.error,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _updateState(SyncState newState) {
    _currentState = newState;
    _stateController.add(newState);
  }

  Future<void> dispose() async {
    _periodicSyncTimer?.cancel();
    await _stateController.close();
  }

  String _generateUuid() {
    final random = Random();
    final bytes = List<int>.generate(16, (i) => random.nextInt(256));

    // Set version (4) and variant (RFC4122) bits
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final hexChars = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hexChars.substring(0, 8)}-${hexChars.substring(8, 12)}-'
        '${hexChars.substring(12, 16)}-${hexChars.substring(16, 20)}-'
        '${hexChars.substring(20)}';
  }
}
