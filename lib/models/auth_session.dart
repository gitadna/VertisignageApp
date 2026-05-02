/// Persisted auth credentials for Bearer APIs and optional refresh.
class AuthSession {
  const AuthSession({
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
  });

  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'accessTokenExpiresAt': accessTokenExpiresAt?.toIso8601String(),
      };

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final raw = json['accessTokenExpiresAt'];
    DateTime? expires;
    if (raw is String) {
      expires = DateTime.tryParse(raw);
    }
    return AuthSession(
      accessToken: json['accessToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      accessTokenExpiresAt: expires,
    );
  }

  bool get hasAccessToken =>
      accessToken != null && accessToken!.isNotEmpty;
}
