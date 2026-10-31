import 'package:like/src/core/like_retry_policy.dart';
import 'package:like/src/core/like_session_scope.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Interceptor to handle authentication tokens, 401 token refresh, and 429 rate limiting.
/// Matches enterprise's AuthInterceptor parity.
class LikeAuthInterceptor extends Interceptor {
  final Dio dio;

  /// Instance-specific authentication configuration.
  final LikeAuthConfig? authConfig;

  static final Map<String, DateTime> _rateLimitedUntilByOrigin = {};
  final LikeRetryPolicy retryPolicy;
  static final Map<String, Future<String?>> _legacyRefreshes = {};
  final Map<String, Future<String?>> _scopedRefreshes = {};
  Future<void>? _logoutFuture;
  static const String _retryCountKey = 'x-retry-count';

  /// Global synchronization lock for legacy static token refreshes.


  /// Global notifier indicating if a legacy token refresh is in progress.
  static final ValueNotifier<bool> isRefreshing = ValueNotifier<bool>(false);

  /// Instance-level synchronization lock for concurrent token refreshes on this client.


  /// Instance-level notifier indicating if a token refresh is in progress on this client.
  final ValueNotifier<bool> instanceIsRefreshing = ValueNotifier<bool>(false);

  /// Hook for the host app to provide the current access token (legacy static API).
  static FutureOr<String?> Function()? getToken;

  /// Hook for the host app to perform token refresh (legacy static API).
  static FutureOr<String?> Function()? refreshToken;

  /// Hook for the host app to handle logout on authentication error (legacy static API).
  static FutureOr<void> Function({int? statusCode, bool force})? onLogout;

  /// Hook for the host app to provide an API Key (x-api-key) (legacy static API).
  static FutureOr<String?> Function()? getApiKey;

  LikeAuthInterceptor({required this.dio, this.authConfig, LikeRetryPolicy? retryPolicy})
      : retryPolicy = retryPolicy ?? LikeRetryPolicy();

  Future<void> _safeLogout() {
    final active = _logoutFuture;
    if (active != null) return active;
    final future = Future<void>(() async {
      try { await _resolveLogout(statusCode: 401, force: true); } catch (_) {}
    });
    _logoutFuture = future;
    future.then((_) { if (identical(_logoutFuture, future)) _logoutFuture = null; });
    return future;
  }

  Future<String?> _joinRefresh(RequestOptions options) {
    final scoped = authConfig?.refreshToken != null || LikeConstants.current.authConfig?.refreshToken != null;
    final map = scoped ? _scopedRefreshes : _legacyRefreshes;
    final scope = options.extra[LikeSessionIdentity.scopeKey] as String? ?? '';
    final active = map[scope];
    if (active != null) return active;
    final future = Future<String?>(() async {
      try {
        if (!LikeSessionIdentity.isCurrent(options)) return null;
        final token = await _resolveRefreshToken();
        if (!LikeSessionIdentity.isCurrent(options)) return null;
        if (token == null || token.isEmpty) { await _safeLogout(); return null; }
        return token;
      } catch (_) {
        if (LikeSessionIdentity.isCurrent(options)) await _safeLogout();
        return null;
      }
    });
    map[scope] = future;
    final notifier = scoped ? instanceIsRefreshing : isRefreshing;
    notifier.value = true;
    future.then((_) {
      if (identical(map[scope], future)) map.remove(scope);
      notifier.value = map.isNotEmpty;
    });
    return future;
  }

  FutureOr<String?> _resolveToken() {
    if (authConfig?.getToken != null) {
      return authConfig!.getToken!();
    }
    if (LikeConstants.current.authConfig?.getToken != null) {
      return LikeConstants.current.authConfig!.getToken!();
    }
    if (getToken != null) {
      return getToken!();
    }
    return null;
  }

  FutureOr<String?> _resolveRefreshToken() {
    if (authConfig?.refreshToken != null) {
      return authConfig!.refreshToken!();
    }
    if (LikeConstants.current.authConfig?.refreshToken != null) {
      return LikeConstants.current.authConfig!.refreshToken!();
    }
    if (refreshToken != null) {
      return refreshToken!();
    }
    return null;
  }

  FutureOr<void> _resolveLogout({int? statusCode, bool force = false}) {
    if (authConfig?.onLogout != null) {
      return authConfig!.onLogout!(statusCode: statusCode, force: force);
    }
    if (LikeConstants.current.authConfig?.onLogout != null) {
      return LikeConstants.current.authConfig!.onLogout!(
        statusCode: statusCode,
        force: force,
      );
    }
    if (onLogout != null) {
      return onLogout!(statusCode: statusCode, force: force);
    }
  }

  FutureOr<String?> _resolveApiKey() {
    if (authConfig?.getApiKey != null) {
      return authConfig!.getApiKey!();
    }
    if (LikeConstants.current.authConfig?.getApiKey != null) {
      return LikeConstants.current.authConfig!.getApiKey!();
    }
    if (getApiKey != null) {
      return getApiKey!();
    }
    return null;
  }

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Rate-limit evidence is scoped to the outgoing request's origin.
    final origin =
        LikeConnectivityManager.canonicalOrigin(options.uri.toString());
    final limitedUntil =
        origin == null ? null : _rateLimitedUntilByOrigin[origin];
    if (limitedUntil != null && DateTime.now().isBefore(limitedUntil)) {
      final waitTime = limitedUntil.difference(DateTime.now());
      try {
        await _cancellableDelay(waitTime, options.cancelToken);
      } on DioException catch (error) {
        handler.reject(error);
        return;
      }
    }

    final bool withAuth =
        options.extra['withAuth'] ?? LikeConstants.withAuthByDefault;
    final bool isRetry = options.extra['isRetry'] ?? false;

    if (withAuth && !isRetry) {
      try {
        final token = await _resolveToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
    }

    try {
      final apiKey = await _resolveApiKey();
      if (apiKey != null && apiKey.isNotEmpty) {
        options.headers['x-api-key'] = apiKey;
      }
    } catch (_) {}

    return handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final bool withAuth =
        err.requestOptions.extra['withAuth'] ?? LikeConstants.withAuthByDefault;

    if (!LikeSessionIdentity.isCurrent(err.requestOptions)) {
      handler.next(DioException.requestCancelled(requestOptions: err.requestOptions,
        reason: 'Session changed'));
      return;
    }
    if (err.response?.statusCode == 401 && withAuth) {
      if (err.requestOptions.extra['isRetry'] == true) {
        await _safeLogout();
        handler.next(err);
        return;
      }
      final hasRefresh = authConfig?.refreshToken != null ||
          LikeConstants.current.authConfig?.refreshToken != null || refreshToken != null;
      if (hasRefresh) {
        final token = await _joinRefresh(err.requestOptions);
        if (token == null) { handler.next(err); return; }
        await _retryRequest(err.requestOptions, token, handler);
        return;
      }
    }

    // This interceptor is the sole owner of 429 retries. The retry remains
    // bounded, origin-aware, and cancellable as part of the original request.
    if (err.response?.statusCode == 429 &&
        LikeConstants.rateLimitEnabled &&
        LikeConstants.autoRetryRateLimit) {
      final options = err.requestOptions;
      final retryCount = (options.extra[_retryCountKey] as int?) ?? 0;
      final configuredMaximum = (options.extra['maxAutoRetries'] as int?) ??
          LikeConstants.maxAutoRetries;
      final maximumRetries = configuredMaximum < 0 ? 0 : configuredMaximum;

      if (retryCount >= maximumRetries) return handler.next(err);

      final waitDuration = retryPolicy.rateLimit(err.response?.headers.value('retry-after'), retryCount);
      if (waitDuration == null) { handler.next(err); return; }
      final origin =
          LikeConnectivityManager.canonicalOrigin(options.uri.toString());
      if (origin != null) {
        _rateLimitedUntilByOrigin[origin] = DateTime.now().add(waitDuration);
      }

      try {
        await _cancellableDelay(waitDuration, options.cancelToken);
        if (!LikeConnectivityManager()
            .isOriginAvailable(options.uri.toString())) {
          return handler.next(err);
        }
        options.extra[_retryCountKey] = retryCount + 1;
        final retry = options.copyWith(data: options.data is FormData
            ? (options.data as FormData).clone() : options.data);
        final response = await dio.fetch(retry);
        return handler.resolve(response);
      } on DioException catch (error) {
        return handler.next(error);
      } catch (error, stackTrace) {
        return handler.reject(
          DioException(
            requestOptions: options,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }

    return handler.next(err);
  }

  static Future<void> _cancellableDelay(
    Duration duration,
    CancelToken? cancelToken,
  ) {
    if (cancelToken?.isCancelled ?? false) {
      return Future<void>.error(cancelToken!.cancelError!);
    }
    if (duration <= Duration.zero) return Future<void>.value();

    final completer = Completer<void>();
    final timer = Timer(duration, completer.complete);
    cancelToken?.whenCancel.then((error) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  Future<void> _retryRequest(
    RequestOptions options,
    String token,
    ErrorInterceptorHandler handler,
  ) async {
    try {
      if (!LikeSessionIdentity.isCurrent(options)) {
        throw DioException.requestCancelled(requestOptions: options, reason: 'Session changed');
      }
      final apiKey = await _resolveApiKey();
      final retry = options.copyWith(
        headers: {...options.headers, 'Authorization': 'Bearer $token',
          if (apiKey != null && apiKey.isNotEmpty) 'x-api-key': apiKey},
        extra: {...options.extra, 'isRetry': true},
        data: options.data is FormData ? (options.data as FormData).clone() : options.data,
      );
      final response = await dio.fetch(retry);
      handler.resolve(response);
    } catch (error) {
      handler.next(error is DioException ? error : DioException(requestOptions: options, error: error));
    }
  }
}
