// ========================================
// 5. lib/core/sync/conflict_resolver.dart
// ========================================

import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';

import '../storage/repositories/form_repository.dart';
import '../storage/models/form_entity.dart';

enum ConflictResolution { keepLocal, keepRemote, merge, duplicate }

class ConflictResolver {
  final FormRepository formRepository;

  ConflictResolver({required this.formRepository});

  Future<void> resolveConflict(
    FormEntity localForm,
    Map<String, dynamic> remoteForm,
  ) async {
    final resolution = _determineResolution(localForm, remoteForm);

    switch (resolution) {
      case ConflictResolution.keepLocal:
        LogService.log(
          LogTypes.conflict,
          'Keeping local version for ${localForm.id}',
        );
        // Do nothing, local is already stored
        break;

      case ConflictResolution.keepRemote:
        LogService.log(
          LogTypes.conflict,
          'Keeping remote version for ${localForm.id}',
        );
        // Update local with remote
        await formRepository.updateStatus(
          localForm.id,
          FormStatus.synced,
          syncedAt: DateTime.now(),
        );
        break;

      case ConflictResolution.merge:
        LogService.log(
          LogTypes.conflict,
          'Merging versions for ${localForm.id}',
        );
        // Merge logic (app-specific)
        final merged = _mergeData(localForm.data, remoteForm);
        final updatedForm = FormEntity(
          id: localForm.id,
          data: merged,
          status: FormStatus.synced,
          createdAt: localForm.createdAt,
          syncedAt: DateTime.now(),
        );
        await formRepository.insert(updatedForm);
        break;

      case ConflictResolution.duplicate:
        LogService.log(
          LogTypes.conflict,
          'Marking as duplicate for ${localForm.id}',
        );
        // Mark as synced if it's actually a duplicate from mesh multi-path
        await formRepository.updateStatus(
          localForm.id,
          FormStatus.synced,
          syncedAt: DateTime.now(),
        );
        break;
    }
  }

  ConflictResolution _determineResolution(
    FormEntity localForm,
    Map<String, dynamic> remoteForm,
  ) {
    // If local is already synced, it's a duplicate
    if (localForm.status == FormStatus.synced) {
      return ConflictResolution.duplicate;
    }

    // If remote has more recent timestamp
    final localTime = localForm.createdAt;
    final remoteTime = DateTime.parse(
      remoteForm['created_at'] ?? localTime.toIso8601String(),
    );

    if (remoteTime.isAfter(localTime)) {
      return ConflictResolution.keepRemote;
    }

    // Default: keep local
    return ConflictResolution.keepLocal;
  }

  Map<String, dynamic> _mergeData(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // Simple merge: combine all fields, prefer non-null values
    final merged = Map<String, dynamic>.from(local);

    remote.forEach((key, value) {
      if (value != null && (merged[key] == null || merged[key] == '')) {
        merged[key] = value;
      }
    });

    return merged;
  }

  Future<bool> isDuplicate(String formId) async {
    final form = await formRepository.getById(formId);
    return form != null && form.status == FormStatus.synced;
  }
}
