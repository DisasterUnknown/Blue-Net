// ========================================
// 2. lib/core/gossip/gossip_payload.dart
// ========================================

enum PayloadType {
  formSubmission,
  confirmation,
  ping,
  peerAnnouncement,
  incidentData, // For mesh incident synchronization
}

class GossipPayload {
  final PayloadType type;
  final Map<String, dynamic> data;

  GossipPayload({
    required this.type,
    required this.data,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.index,
      'data': data,
    };
  }

  factory GossipPayload.fromJson(Map<String, dynamic> json) {
    return GossipPayload(
      type: PayloadType.values[json['type']],
      data: Map<String, dynamic>.from(json['data']),
    );
  }

  // Factory constructors for common payload types
  factory GossipPayload.formSubmission(Map<String, dynamic> formData) {
    return GossipPayload(
      type: PayloadType.formSubmission,
      data: formData,
    );
  }

  factory GossipPayload.confirmation(String formId, String status) {
    return GossipPayload(
      type: PayloadType.confirmation,
      data: {
        'form_id': formId,
        'status': status,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  factory GossipPayload.ping() {
    return GossipPayload(
      type: PayloadType.ping,
      data: {'timestamp': DateTime.now().toIso8601String()},
    );
  }

  factory GossipPayload.incidentData(Map<String, dynamic> incidentData) {
    return GossipPayload(
      type: PayloadType.incidentData,
      data: incidentData,
    );
  }
}