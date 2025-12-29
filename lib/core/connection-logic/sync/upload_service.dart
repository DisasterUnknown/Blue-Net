// ========================================
// 3. lib/core/sync/upload_service.dart
// ========================================

import 'package:bluetooth_chat_app/core/enums/logs_enums.dart';
import 'package:bluetooth_chat_app/services/log_service.dart';

import '../network/api_client.dart';

class UploadResult {
  final bool success;
  final String? errorMessage;
  final Map<String, dynamic>? response;

  UploadResult({
    required this.success,
    this.errorMessage,
    this.response,
  });
}

class UploadService {
  final ApiClient apiClient;

  UploadService({required this.apiClient});

  Future<UploadResult> uploadForm(Map<String, dynamic> formData) async {
    try {
      LogService.log(
        LogTypes.uploadService,
        'Uploading form ${formData['id']}',
      );

      final response = await apiClient.submitForm(formData);

      LogService.log(
        LogTypes.uploadService,
        'Upload successful: $response',
      );

      return UploadResult(
        success: true,
        response: response,
      );
    } catch (e, stack) {
      LogService.log(
        LogTypes.uploadService,
        'Upload failed: $e, $stack',
      );

      return UploadResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<bool> checkFormStatus(String formId) async {
    try {
      final response = await apiClient.getFormStatus(formId);
      return response['status'] == 'RECEIVED';
    } catch (e) {
      LogService.log(
        LogTypes.uploadService,
        'Failed to check status for form $formId: $e',
      );
      return false;
    }
  }
}