class StreamInviteEnvelope {
  StreamInviteEnvelope({
    required this.streamSessionId,
    required this.livekitUrl,
    required this.livekitRoomName,
  });

  final String streamSessionId;
  final String livekitUrl;
  final String livekitRoomName;

  factory StreamInviteEnvelope.fromMap(Map<String, dynamic> map) {
    final payload = Map<String, dynamic>.from(map['payload'] as Map);
    return StreamInviteEnvelope(
      streamSessionId: payload['streamSessionId'] as String,
      livekitUrl: payload['livekitUrl'] as String,
      livekitRoomName: payload['livekitRoomName'] as String,
    );
  }
}

class JoinGrant {
  JoinGrant({
    required this.streamSessionId,
    required this.livekitUrl,
    required this.livekitRoomName,
    required this.token,
  });

  final String streamSessionId;
  final String livekitUrl;
  final String livekitRoomName;
  final String token;

  factory JoinGrant.fromMap(Map<String, dynamic> map) {
    return JoinGrant(
      streamSessionId: map['streamSessionId'] as String,
      livekitUrl: map['livekitUrl'] as String,
      livekitRoomName: map['livekitRoomName'] as String,
      token: map['token'] as String,
    );
  }
}
