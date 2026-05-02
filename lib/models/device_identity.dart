/// Persisted device context after successful pairing with the backend.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.orgId,
    this.groupId,
    this.name,
    this.location,
    this.paired = true,
  });

  final String deviceId;
  final String orgId;
  final String? groupId;
  final String? name;
  final String? location;
  final bool paired;

  /// Parses the Prisma device JSON returned under API `data`.
  factory DeviceIdentity.fromApi(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final org = json['orgId'] as String?;
    if (id == null || org == null) {
      throw const FormatException('device identity missing id or orgId');
    }
    return DeviceIdentity(
      deviceId: id,
      orgId: org,
      groupId: json['groupId'] as String?,
      name: json['name'] as String?,
      location: json['location'] as String?,
      paired: json['paired'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'orgId': orgId,
        'groupId': groupId,
        'name': name,
        'location': location,
        'paired': paired,
      };

  factory DeviceIdentity.fromJson(Map<String, dynamic> json) {
    final deviceId = json['deviceId'] as String? ?? json['id'] as String?;
    final orgId = json['orgId'] as String?;
    if (deviceId == null || orgId == null) {
      throw const FormatException('stored device identity invalid');
    }
    return DeviceIdentity(
      deviceId: deviceId,
      orgId: orgId,
      groupId: json['groupId'] as String?,
      name: json['name'] as String?,
      location: json['location'] as String?,
      paired: json['paired'] as bool? ?? true,
    );
  }
}
