import 'package:flutter/foundation.dart';

abstract final class ApiUrls {
  static const _port = 8080;

  /// Android emulators reach the host through `10.0.2.2`; all other example
  /// targets use the loopback host documented by the bundled API server.
  static String get baseUrl {
    final host = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    return 'http://$host:$_port';
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
