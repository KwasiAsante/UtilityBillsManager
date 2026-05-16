/// Represents an active authentication session returned by `POST /auth/login`.
class AuthSession {
  final String token;
  final String userId;

  const AuthSession({required this.token, required this.userId});

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token'] as String,
      userId: json['userId'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'token': token, 'userId': userId};
}
