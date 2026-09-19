import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../core/api_exception.dart';
import '../models/refresh_session.dart';
import '../models/user.dart';
import '../repositories/refresh_session_repository.dart';
import '../repositories/user_repository.dart';

final class AuthService {
  AuthService({
    required UserRepository users,
    required RefreshSessionRepository refreshSessions,
    required String jwtSecret,
  })  : _users = users,
        _refreshSessions = refreshSessions,
        _jwtSecret = jwtSecret;

  final UserRepository _users;
  final RefreshSessionRepository _refreshSessions;
  final String _jwtSecret;
  final Random _random = Random.secure();

  Map<String, Object?> register({
    required String name,
    required String email,
    required String password,
  }) {
    final normalizedEmail = email.toLowerCase();
    if (!_isEmail(normalizedEmail)) {
      throw ApiException(422, 'email must be a valid email address');
    }
    if (_users.findByEmail(normalizedEmail) != null) {
      throw ApiException(409, 'An account with this email already exists');
    }
    final salt = _randomToken(16);
    final user = _users.create(
      name: name,
      email: normalizedEmail,
      passwordHash: _hashPassword(password, salt),
      salt: salt,
    );
    return _createSession(user);
  }

  Map<String, Object?> login({
    required String email,
    required String password,
  }) {
    final user = _users.findByEmail(email.toLowerCase());
    if (user == null ||
        _hashPassword(password, user.salt) != user.passwordHash) {
      throw ApiException(401, 'Invalid email or password');
    }
    return _createSession(user);
  }

  Map<String, Object?> refresh(String oldToken) {
    final session = _refreshSessions.consume(_tokenHash(oldToken));
    if (session == null || session.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw ApiException(401, 'Invalid or expired refresh token');
    }
    final user = _users.findById(session.userId);
    if (user == null) throw ApiException(401, 'User no longer exists');
    return _createSession(user);
  }

  void logout({required int userId, required String refreshToken}) {
    final tokenHash = _tokenHash(refreshToken);
    final session = _refreshSessions.find(tokenHash);
    if (session == null || session.userId != userId) {
      throw ApiException(401, 'Invalid refresh token');
    }
    _refreshSessions.delete(tokenHash);
  }

  int verifyAccessToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_jwtSecret));
      final payload = jwt.payload;
      if (payload is! Map<String, dynamic> || payload['type'] != 'access') {
        throw const ApiException(401, 'Invalid access token');
      }
      final userId = int.tryParse(jwt.subject ?? '');
      if (userId == null || !_users.exists(userId)) {
        throw const ApiException(401, 'Invalid access token');
      }
      return userId;
    } on JWTExpiredException {
      throw ApiException(401, 'Access token has expired');
    } on JWTException {
      throw ApiException(401, 'Invalid access token');
    }
  }

  User findUser(int userId) =>
      _users.findById(userId) ??
      (throw ApiException(401, 'User no longer exists'));

  Map<String, Object?> _createSession(User user) {
    final accessToken = JWT(
      {'type': 'access', 'email': user.email, 'name': user.name},
      issuer: 'like-test-server',
      subject: '${user.id}',
    ).sign(SecretKey(_jwtSecret), expiresIn: const Duration(minutes: 1));
    final refreshToken = _randomToken(48);
    _refreshSessions.save(
      _tokenHash(refreshToken),
      RefreshSession(
        userId: user.id,
        expiresAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      ),
    );
    return {
      'user': user.toPublicJson(),
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenType': 'Bearer',
      'expiresIn': 60,
      'refreshExpiresIn': 86400,
    };
  }

  String _randomToken(int bytes) => base64UrlEncode(
        List<int>.generate(bytes, (_) => _random.nextInt(256)),
      ).replaceAll('=', '');

  String _tokenHash(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  String _hashPassword(String password, String salt) {
    List<int> value = utf8.encode('$salt:$password');
    for (var index = 0; index < 10000; index++) {
      value = sha256.convert(value).bytes;
    }
    return base64UrlEncode(value);
  }

  bool _isEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}
