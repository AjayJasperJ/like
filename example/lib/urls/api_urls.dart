import 'package:flutter/foundation.dart';

abstract final class ApiUrls {
  static String get baseUrl {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://192.168.1.16:8080';
    }
    return 'http://192.168.1.16:8080';
  }

  static const metadata = '/';
  static const health = '/health';
  static const register = '/api/auth/register';
  static const login = '/api/auth/login';
  static const refresh = '/api/auth/refresh';
  static const logout = '/api/auth/logout';
  static const me = '/api/auth/me';
  static const posts = '/api/posts';
  static const reset = '/api/reset';

  static String post(int id) => '$posts/$id';
  static String status(int code) => '/api/status/$code';
  static String delay(int milliseconds) => '/api/delay/$milliseconds';
}
