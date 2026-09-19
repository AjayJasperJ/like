import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Interceptor to handle authentication tokens, 401 token refresh, and 429 rate limiting.
/// Matches enterprise's AuthInterceptor parity.
class LikeAuthInterceptor extends Interceptor {
  final Dio dio;

  /// Instance-specific authentication configuration.
  final LikeAuthConfig? authConfig;

  static final Map<String, DateTime> _rateLimitedUntilByOrigin = {};
  static const Duration _maximumRateLimitDelay = Duration(seconds: 60);
  static const String _retryCountKey = 'x-retry-count';

  /// Global synchronization lock for legacy static token refreshes.
  static Completer<String?>? _refreshCompleter;

  /// Global notifier indicating if a legacy token refresh is in progress.
  static final ValueNotifier<bool> isRefreshing = ValueNotifier<bool>(false);

  /// Instance-level synchronization lock for concurrent token refreshes on this client.
  Completer<String?>? _instanceRefreshCompleter;

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

  LikeAuthInterceptor({required this.dio, this.authConfig});

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

    // Handle 401 Unauthorized
    if (err.response?.statusCode == 401 && withAuth) {
      final bool isRetry = err.requestOptions.extra['isRetry'] ?? false;
      if (isRetry) {
        await _resolveLogout(statusCode: 401, force: true);
        return handler.next(err);
      }

      final hasRefresh = authConfig?.refreshToken != null ||
          LikeConstants.current.authConfig?.refreshToken != null ||
          refreshToken != null;

      if (hasRefresh) {
        final bool isScoped = authConfig?.refreshToken != null ||
            LikeConstants.current.authConfig?.refreshToken != null;

        if (isScoped) {
          if (_instanceRefreshCompleter != null) {
            final newToken = await _instanceRefreshCompleter!.future;
            if (newToken != null) {
              return _retryRequest(err.requestOptions, newToken, handler);
            } else {
              return handler.next(err);
            }
          }

          _instanceRefreshCompleter = Completer<String?>();
          instanceIsRefreshing.value = true;

          try {
            final newToken = await _resolveRefreshToken();
            _instanceRefreshCompleter?.complete(newToken);

            if (newToken != null) {
              return await _retryRequest(err.requestOptions, newToken, handler);
            } else {
              await _resolveLogout(statusCode: 401, force: true);
              return handler.next(err);
            }
          } catch (e) {
            _instanceRefreshCompleter?.complete(null);
            await _resolveLogout(statusCode: 401, force: true);
            return handler.next(err);
          } finally {
            _instanceRefreshCompleter = null;
            instanceIsRefreshing.value = false;
          }
        } else {
          // Legacy static completer path
          if (_refreshCompleter != null) {
            final newToken = await _refreshCompleter!.future;
            if (newToken != null) {
              return _retryRequest(err.requestOptions, newToken, handler);
            } else {
              return handler.next(err);
            }
          }

          _refreshCompleter = Completer<String?>();
          isRefreshing.value = true;

          try {
            final newToken = await _resolveRefreshToken();
            _refreshCompleter?.complete(newToken);

            if (newToken != null) {
              return await _retryRequest(err.requestOptions, newToken, handler);
            } else {
              await _resolveLogout(statusCode: 401, force: true);
              return handler.next(err);
            }
          } catch (e) {
            _refreshCompleter?.complete(null);
            await _resolveLogout(statusCode: 401, force: true);
            return handler.next(err);
          } finally {
            _refreshCompleter = null;
            isRefreshing.value = false;
          }
        }
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

      final waitDuration = _rateLimitDelay(err, retryCount);
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
        final response = await dio.fetch(options);
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

  static Duration _rateLimitDelay(DioException error, int retryCount) {
    final retryAfter = error.response?.headers.value('retry-after');
    final seconds = int.tryParse(retryAfter ?? '');
    final requested = seconds == null
        ? Duration(seconds: 1 << retryCount.clamp(0, 6))
        : Duration(seconds: seconds < 0 ? 0 : seconds);
    return requested > _maximumRateLimitDelay
        ? _maximumRateLimitDelay
        : requested;
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
    options.headers['Authorization'] = 'Bearer $token';

    final apiKey = await _resolveApiKey();
    if (apiKey != null && apiKey.isNotEmpty) {
      options.headers['x-api-key'] = apiKey;
    }

    options.extra['isRetry'] = true;

    // Refresh FormData if it's a multipart request
    if (options.data is FormData ||
        options.extra.containsKey('multipartFields')) {
      final fields = options.extra['multipartFields'] as Map<String, String>?;
      final filePaths = options.extra['multipartFilePaths'];
      final files = options.extra['multipartFiles'] as List<LikeMultipartFile>?;

      if (fields != null || filePaths != null || files != null) {
        final formData = FormData();
        if (fields != null) {
          formData.fields.addAll(
            fields.entries.map((e) => MapEntry(e.key, e.value)),
          );
        }

        // MultipartFile.fromFile() requires a native file-system path.
        // On web there is no file-system — filePaths retries are skipped.
        // Callers should use MultipartBytesFile (bytes) for web compatibility.
        if (filePaths != null && !kIsWeb) {
          if (filePaths is Map<String, String>) {
            for (final entry in filePaths.entries) {
              formData.files.add(
                MapEntry(entry.key, await MultipartFile.fromFile(entry.value)),
              );
            }
          }
        }

        if (files != null) {
          for (final f in files) {
            formData.files.add(
              MapEntry(
                f.field,
                MultipartFile.fromBytes(
                  f.bytes,
                  filename: f.filename,
                  contentType: f.contentType,
                ),
              ),
            );
          }
        }
        options.data = formData;
      }
    }

    try {
      final response = await dio.fetch(options);
      return handler.resolve(response);
    } catch (e) {
      if (e is DioException) return handler.next(e);
      return handler.reject(DioException(requestOptions: options, error: e));
    }
  }
}
