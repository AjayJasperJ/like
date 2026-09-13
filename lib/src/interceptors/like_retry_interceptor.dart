import 'dart:async';

import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Performs bounded, request-local retries for safe transport failures.
///
/// Retry count and delay schedule are resolved per request from
/// `maxAutoRetries` and `retryDelays` extras, with [LikeConstants] as fallback.
/// Unsafe mutation methods and HTTP responses (including 429) are deliberately
/// excluded; rate-limit retries are owned by `LikeAuthInterceptor`.
class LikeRetryInterceptor extends Interceptor {
  static const String retryCountKey = 'like.transportRetryCount';
  static const String _retryInterceptorKey = 'like.transportRetryEnabled';

  final Dio dio;

  LikeRetryInterceptor({required this.dio});

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_retryInterceptorKey] = true;
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final retryCount = _nonNegativeInt(options.extra[retryCountKey]);

    if (!canRetry(err)) {
      handler.next(err);
      return;
    }

    final origin = options.uri.toString();
    if (!LikeConnectivityManager().isOriginAvailable(origin)) {
      handler.next(err);
      return;
    }

    try {
      await _cancellableDelay(
        _delayForAttempt(options, retryCount),
        options.cancelToken,
      );
      if (options.cancelToken?.isCancelled ?? false) {
        handler.next(err);
        return;
      }

      options.extra[retryCountKey] = retryCount + 1;
      final response = await dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (error, stackTrace) {
      handler.next(
        DioException(
          requestOptions: options,
          error: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Whether an installed retry interceptor will handle [error].
  ///
  /// Connectivity diagnostics use this before forwarding an error so they do
  /// not race a retry by marking its origin unavailable. Exact-origin
  /// availability remains a separate decision in [onError].
  static bool willRetry(DioException error) {
    return error.requestOptions.extra[_retryInterceptorKey] == true &&
        canRetry(error);
  }

  /// Whether [error] is retryable and has a request-local attempt remaining.
  static bool canRetry(DioException error) {
    final options = error.requestOptions;
    final retryCount = _nonNegativeInt(options.extra[retryCountKey]);
    return retryCount < _resolveMaximumRetries(options) &&
        _isRetryableTransportFailure(error);
  }

  static bool _isRetryableTransportFailure(DioException error) {
    final method = error.requestOptions.method.toUpperCase();
    const safeMethods = <String>{'GET', 'HEAD', 'OPTIONS'};
    if (!safeMethods.contains(method) || error.response != null) return false;

    return const <DioExceptionType>{
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
      DioExceptionType.unknown,
    }.contains(error.type);
  }

  static int _resolveMaximumRetries(RequestOptions options) {
    final configured = options.extra['maxAutoRetries'];
    return _nonNegativeInt(configured, fallback: LikeConstants.maxAutoRetries);
  }

  static int _nonNegativeInt(Object? value, {int fallback = 0}) {
    final resolved = value is int ? value : fallback;
    return resolved < 0 ? 0 : resolved;
  }

  /// Resolves retry delays, preferring a request-local schedule.
  static List<Duration> resolveDelays(RequestOptions options) {
    final raw = options.extra['retryDelays'];
    if (raw is List) {
      final seconds =
          raw.whereType<int>().map((value) => value < 0 ? 0 : value);
      final resolved = seconds
          .map((value) => Duration(seconds: value))
          .toList(growable: false);
      if (resolved.isNotEmpty) return resolved;
    }
    return LikeConstants.retryDelays
        .map((seconds) => Duration(seconds: seconds < 0 ? 0 : seconds))
        .toList(growable: false);
  }

  static Duration _delayForAttempt(RequestOptions options, int attemptIndex) {
    final delays = resolveDelays(options);
    if (delays.isEmpty) return Duration.zero;
    if (attemptIndex < delays.length) return delays[attemptIndex];

    // Continue the configured schedule with bounded exponential backoff when a
    // request allows more attempts than it supplies delay entries for.
    final extraSteps = attemptIndex - delays.length + 1;
    final multiplier = 1 << extraSteps.clamp(0, 20);
    final milliseconds = delays.last.inMilliseconds * multiplier;
    return Duration(milliseconds: milliseconds.clamp(0, 60000));
  }

  static Future<void> _cancellableDelay(
    Duration duration,
    CancelToken? cancelToken,
  ) {
    if (duration <= Duration.zero) {
      if (cancelToken?.isCancelled ?? false) {
        return Future<void>.error(cancelToken!.cancelError!);
      }
      return Future<void>.value();
    }

    final completer = Completer<void>();
    final timer = Timer(duration, completer.complete);
    cancelToken?.whenCancel.then((cancelError) {
      if (!completer.isCompleted) {
        timer.cancel();
        completer.completeError(cancelError);
      }
    });
    return completer.future;
  }
}
