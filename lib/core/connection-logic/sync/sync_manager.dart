import 'dart:async';
import 'dart:math';
import 'package:bluetooth_chat_app/core/connection-logic/storage/models/form_entity.dart';
import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../storage/gossip_storage.dart';
import '../network/network_detector.dart';
import '../network/api_client.dart';
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
  final NetworkDetector networkDetector;
  final ApiClient apiClient;
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
    required this.networkDetector,
    required this.apiClient,
    required this.formRepository,
    this.gossipProtocol,
  });

  Future<void> initialize() async {
    // Start periodic sync check
    _periodicSyncTimer = Timer.periodic(Duration(minutes: 5), (_) {
      attemptSync();
    });

    // Listen to network changes
    networkDetector.connectionStream.listen((connectionType) {
      if (connectionType == ConnectionType.wifi ||
          connectionType == ConnectionType.cellular) {
        LogService.log(
          LogTypes.syncManager,
          'Internet connection detected, attempting sync',
        );
        attemptSync();
      }
    });

    // Listen to gossip messages
    if (gossipProtocol != null) {
      gossipProtocol!.onMessage.listen((message) async {
        if (message.payload.type == PayloadType.formSubmission) {
          debugPrint('Received gossiped form submission: ${message.id}');
          final hasInternet = await networkDetector.hasInternet();
          if (hasInternet) {
            LogService.log(LogTypes.syncManager, 'Received form via gossip');
            try {
              final formData = message.payload.data;
              await apiClient.submitForm(formData);
              LogService.log(
                LogTypes.syncManager,
                'Gossiped form ${formData['id']} submitted successfully to server',
              );

              // Broadcast confirmation
              final confirmation = GossipPayload.confirmation(
                formData['id'],
                'SUCCESS',
              );
              final confMsg = GossipMessage(
                id: _generateUuid(),
                originId: _localPeerId,
                payload: confirmation,
                hops: 0,
                ttl: 24,
                timestamp: DateTime.now(),
              );
              await gossipProtocol!.broadcastMessage(confMsg);
            } catch (e) {
              LogService.log(
                LogTypes.error,
                'Failed to submit gossiped form: $e',
              );
            }
          }
        } else if (message.payload.type == PayloadType.confirmation) {
          final formId = message
              .payload
              .data['form_id']; // This is likely the localId or UUID
          // If we have this form as pending, mark it as synced!
          try {
            // We need to find the report with this ID (assuming formId maps to localId or we need to check)
            // DBHelper uses int ID for local, but localId (String) for UUID.
            // Assuming formId is the UUID (localId).
            // But DBHelper.markReportAsSynced takes int ID.
            // We might need to look it up.
            // For now, skipping complex lookup as DBHelper doesn't expose getByLocalId easily without query.
            LogService.log(
              LogTypes.syncManager,
              'Received confirmation for $formId. (Sync marking not fully implemented for gossip confirmation yet)',
            );
          } catch (_) {
            // Probably don't have this form or it's already synced
          }
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

      // Check if we have internet
      final hasInternet = await networkDetector.hasInternet();

      if (!hasInternet) {
        LogService.log(LogTypes.syncManager, 'No internet connection');

        // Check if WiFi/Bluetooth enabled (Permissions check as proxy for enabled state check availability)
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
          'Attempting to gossip ${pendingForms.length} forms',
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
            'Gossiped $gossipedCount forms via gossip protocol',
          );
          if (gossipedCount > 0) {
            debugPrint(
              'Gossiped $gossipedCount forms via Bluetooth/WiFi Direct.',
            );
          }
        } else {
          LogService.log(
            LogTypes.syncManager,
            'GossipProtocol not available, cannot gossip.',
          );
        }

        _updateState(_currentState.copyWith(status: SyncStatus.idle));
        return;
      }

      // We have internet, proceed with upload
      LogService.log(
        LogTypes.syncManager,
        'Syncing ${pendingForms.length} forms via Internet',
      );

      int successCount = 0;
      int errorCount = 0;

      for (final form in pendingForms) {
        try {
          // Upload to server
          await apiClient.submitForm(form);

          // Mark as synced
          await formRepository.updateStatus(
            form['id'],
            FormStatus.synced,
            syncedAt: DateTime.now(),
          );

          successCount++;

          // Broadcast confirmation via gossip
          if (gossipProtocol != null) {
            final payload = GossipPayload.confirmation(
              (form['localId'] ?? form['id']).toString(),
              'SUCCESS',
            );
            final message = GossipMessage(
              id: _generateUuid(),
              originId: _localPeerId,
              payload: payload,
              hops: 0,
              ttl: 24,
              timestamp: DateTime.now(),
            );
            await gossipProtocol!.broadcastMessage(message);
          }

          LogService.log(
            LogTypes.syncManager,
            'Form ${form['id']} synced successfully',
          );
        } catch (e) {
          errorCount++;
          // await formRepository.incrementAttempts(form.id); // DBHelper doesn't have attempts column yet
          LogService.log(
            LogTypes.syncManager,
            'Failed to sync form ${form['id']}'
          );
        }
      }

      _updateState(
        _currentState.copyWith(
          status: successCount > 0 ? SyncStatus.success : SyncStatus.error,
          pendingCount: pendingForms.length - successCount,
          syncedCount: successCount,
          errorMessage: errorCount > 0
              ? '$errorCount forms failed to sync'
              : null,
        ),
      );

      LogService.log(
        LogTypes.syncManager,
        'Sync complete: $successCount success, $errorCount errors',
      );
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
