import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Interceptor to handle authentication tokens, 401 token refresh, and 429 rate limiting.
/// Matches enterprise's AuthInterceptor parity.
class LikeAuthInterceptor extends Interceptor {
  final Dio dio;
  static DateTime? _rateLimitedUntil;
  static int get _maxRetries => LikeConstants.maxAutoRetries;
  static const String _retryCountKey = 'x-retry-count';

  /// Synchronization lock for concurrent token refreshes.
  static Completer<String?>? _refreshCompleter;

  /// Global notifier indicating if a token refresh is currently in progress.
  static final ValueNotifier<bool> isRefreshing = ValueNotifier<bool>(false);

  /// Hook for the host app to provide the current access token.
  static Future<String?> Function()? getToken;

  /// Hook for the host app to perform token refresh.
  static Future<String?> Function()? refreshToken;

  /// Hook for the host app to handle logout on authentication error.
  static Future<void> Function({int? statusCode, bool force})? onLogout;

  /// Hook for the host app to provide an API Key (x-api-key).
  static Future<String?> Function()? getApiKey;

  LikeAuthInterceptor({required this.dio});

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // 1. Check for global rate limiting
    if (_rateLimitedUntil != null &&
        DateTime.now().isBefore(_rateLimitedUntil!)) {
      final waitTime = _rateLimitedUntil!.difference(DateTime.now());
      await Future.delayed(waitTime);
    }

    final bool withAuth =
        options.extra['withAuth'] ?? LikeConstants.withAuthByDefault;

    if (withAuth && getToken != null) {
      try {
        final token = await getToken!();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {}
    }

    if (getApiKey != null) {
      try {
        final apiKey = await getApiKey!();
        if (apiKey != null && apiKey.isNotEmpty) {
          options.headers['x-api-key'] = apiKey;
        }
      } catch (_) {}
    }

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
        if (onLogout != null) await onLogout!(statusCode: 401, force: true);
        return handler.next(err);
      }

      if (refreshToken != null) {
        // Handle concurrent refreshes using a Completer
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
          final newToken = await refreshToken!();
          _refreshCompleter?.complete(newToken);

          if (newToken != null) {
            return _retryRequest(err.requestOptions, newToken, handler);
          } else {
            if (onLogout != null) await onLogout!(statusCode: 401, force: true);
            return handler.next(err);
          }
        } catch (e) {
          _refreshCompleter?.complete(null);
          if (onLogout != null) await onLogout!(statusCode: 401, force: true);
          return handler.next(err);
        } finally {
          _refreshCompleter = null;
          isRefreshing.value = false;
        }
      }
    }

    // Handle 429 Too Many Requests
    if (err.response?.statusCode == 429 && LikeConstants.rateLimitEnabled) {
      final retryCount = (err.requestOptions.extra[_retryCountKey] ?? 0) as int;

      if (retryCount >= _maxRetries) {
        return handler.next(err);
      }

      final retryAfterStr = err.response?.headers.value('retry-after');
      final retryAfterSeconds = int.tryParse(retryAfterStr ?? '');

      final waitDuration = retryAfterSeconds != null
          ? Duration(seconds: retryAfterSeconds)
          : Duration(seconds: 1 << retryCount);

      _rateLimitedUntil = DateTime.now().add(waitDuration);
      await Future.delayed(waitDuration);

      err.requestOptions.extra[_retryCountKey] = retryCount + 1;
      try {
        if (!LikeConnectivityManager().hasConnection) {
          return handler.next(err);
        }
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (e) {
        if (e is DioException) return handler.next(e);
        return handler.reject(
          DioException(requestOptions: err.requestOptions, error: e),
        );
      }
    }

    return handler.next(err);
  }

  Future<void> _retryRequest(
    RequestOptions options,
    String token,
    ErrorInterceptorHandler handler,
  ) async {
    options.headers['Authorization'] = 'Bearer $token';

    if (getApiKey != null) {
      final apiKey = await getApiKey!();
      if (apiKey != null) options.headers['x-api-key'] = apiKey;
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

        if (filePaths != null) {
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
