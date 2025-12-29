import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class IncidentMapper {
  static Future<String?> imageFileToBase64(String? path) async {
    if (path == null || path.isEmpty) return null;

    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint("Something went wrong {$e}");
      return null;
    }
  }

  static Future<Map<String, dynamic>> toApiBody(
    Map<String, dynamic> dbRow,
  ) async {
    final String? photo = dbRow['photoPath'];
    final String? photoBase64 = await imageFileToBase64(photo);

    return {
      'incidentType': dbRow['type'].toLowerCase(),
      'severity': dbRow['riskLevel'].toString(), // backend wants string
      'description': dbRow['description'],
      'latitude': dbRow['latitude'],
      'longitude': dbRow['longitude'],

      'photoLocalPath': photoBase64,
      'hasPhoto': photo != null && photo.isNotEmpty,
      'reportedBy': dbRow['userId'],
      'reportedAt': dbRow['reportedAt'],
      'clientId': dbRow['uniqueId'],
    };
  }
}
