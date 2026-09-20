import 'package:like/like.dart';
import 'api_user.dart';

final class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshExpiresIn,
  });

  final ApiUser user;
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final int refreshExpiresIn;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: ApiUser.fromJson(JsonParse.map(json['user'])),
        accessToken: JsonParse.string(json['accessToken']),
        refreshToken: JsonParse.string(json['refreshToken']),
        tokenType: JsonParse.string(json['tokenType']),
        expiresIn: JsonParse.integer(json['expiresIn']),
        refreshExpiresIn: JsonParse.integer(json['refreshExpiresIn']),
      );
}
