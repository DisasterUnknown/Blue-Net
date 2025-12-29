// ========================================
// 11. lib/core/network/api_client.dart
// ========================================

import 'dart:convert';
import 'package:bluetooth_chat_app/core/shared_prefs/shared_pref_service.dart';
import 'package:http/http.dart' as http;
import '../utils/constants.dart';
import 'endpoints.dart';
import 'package:bluetooth_chat_app/core/constants/app_constants.dart' as old_constants;
import 'package:bluetooth_chat_app/mapper/incident_mapper.dart';

class ApiClient {
  final http.Client _client = http.Client();

  Future<Map<String, dynamic>> submitForm(Map<String, dynamic> formData) async {
    final token = await LocalSharedPreferences.getString(
      old_constants.SharedPrefValues.token,
    );
    if (token == null) throw Exception('No auth token found');

    final apiBody = await IncidentMapper.toApiBody(formData);

    final response = await _client
        .post(
          Uri.parse(ApiEndpoints.submitForm),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(apiBody),
        )
        .timeout(AppConstants.requestTimeout);

    if (response.statusCode == 200 || response.statusCode == 201) {
      // Handle empty body or non-json response if necessary, but assuming JSON for now
      if (response.body.isEmpty) return {};
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to submit form: ${response.statusCode} ${response.body}',
      );
    }
  }

  Future<Map<String, dynamic>> getFormStatus(String formId) async {
    final response = await _client
        .get(Uri.parse(ApiEndpoints.getFormStatus(formId)))
        .timeout(AppConstants.requestTimeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get form status: ${response.statusCode}');
    }
  }

  Future<bool> healthCheck() async {
    try {
      final response = await _client
          .get(Uri.parse(ApiEndpoints.healthCheck))
          .timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}
