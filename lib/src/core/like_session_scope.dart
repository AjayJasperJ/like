import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';

/// Stable identity supplied by the application after authentication.
/// Never use an access token as accountId: tokens rotate independently of users.
class LikeSessionScope {
  final String environment;
  final String? accountId;
  const LikeSessionScope({this.environment = 'default', this.accountId});
  bool get isAnonymous => accountId == null || accountId!.isEmpty;
  String get key => isAnonymous && environment == 'default' ? ''
      : sha256.convert(utf8.encode(jsonEncode([environment, accountId]))).toString();
}

/// Shared cache identity used by L1, persistent cache and ETags.
class LikeSessionIdentity {
  static const scopeKey = 'like.sessionScope';
  static const currentKey = 'like.sessionIsCurrent';
  static String forRequest(RequestOptions options) {
    final scope = options.extra[scopeKey] as String? ?? '';
    return scope.isEmpty ? options.uri.toString() : '$scope::${options.uri}';
  }
  static bool isCurrent(RequestOptions options) {
    final check = options.extra[currentKey];
    return check is bool Function() ? check() : true;
  }
}

/// Rejects stale requests before they can acquire another session's credentials.
class LikeSessionInterceptor extends Interceptor {
  final LikeSessionScope Function() currentSession;
  LikeSessionInterceptor(this.currentSession);
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final scope = currentSession();
    final captured = options.extra[LikeSessionIdentity.scopeKey] as String?;
    if ((captured != null && captured != scope.key) ||
        !LikeSessionIdentity.isCurrent(options)) {
      handler.reject(DioException.requestCancelled(
        requestOptions: options, reason: 'Session changed'));
      return;
    }
    options.extra[LikeSessionIdentity.scopeKey] = scope.key;
    options.extra[LikeSessionIdentity.currentKey] ??= () => currentSession().key == scope.key;
    // Authenticated persistence requires a stable application-owned identity.
    if (scope.isAnonymous &&
        (options.extra['withAuth'] ?? LikeConstants.withAuthByDefault) == true) {
      options.extra['disableCache'] = true;
      options.extra['offlineSync'] = false;
    }
    handler.next(options);
  }
}
