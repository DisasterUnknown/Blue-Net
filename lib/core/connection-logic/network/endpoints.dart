// ========================================
// 10. lib/core/network/endpoints.dart
// ========================================

import '../utils/constants.dart';

class ApiEndpoints {
  static const String base = AppConstants.apiBaseUrl;

  // Forms
  static const String submitForm = '$base/api/incidents';
  static String getFormStatus(String id) => '$base/api/forms/$id/status';

  // Health check
  static const String healthCheck = '$base/api/health';

  // Mesh stats (optional)
  static const String meshStats = '$base/api/mesh/stats';
}
