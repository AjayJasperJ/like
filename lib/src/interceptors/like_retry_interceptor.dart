import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/core/like_constants.dart';

/// Intelligent retry interceptor with connectivity awareness.
/// Matches enterprise's AppRetryInterceptor parity.
///
/// Retry count and delay schedule are resolved per-request:
/// 1. `options.extra['maxAutoRetries']` — from [LikeRequestConfig.maxAutoRetries]
/// 2. [LikeConstants.maxAutoRetries] — global fallback from [LikeConfig]
///
/// The same two-level priority applies to `retryDelays`.
class LikeRetryInterceptor extends RetryInterceptor {
  LikeRetryInterceptor({required super.dio})
      : super(
          retries: LikeConstants.maxAutoRetries,
          retryDelays: LikeConstants.retryDelays
              .map((s) => Duration(seconds: s))
              .toList(),
          retryEvaluator: (error, attempt) {
            // --- Per-request retry count check ---
            // If the caller specified a lower maxAutoRetries via LikeRequestConfig,
            // respect it by refusing to retry beyond that limit.
            final extra = error.requestOptions.extra;
            final perRequestMax =
                extra['maxAutoRetries'] as int? ?? LikeConstants.maxAutoRetries;
            if (attempt > perRequestMax) return false;

            // 1. Connectivity & Server check
            // Don't retry if the server is known to be down or device is offline
            if (!LikeConnectivityManager().isServerAvailable) return false;

            final method = error.requestOptions.method;
            final isGet = method == 'GET';
            final statusCode = error.response?.statusCode;

            // 2. Safe-to-retry conditions for ALL methods
            final isSafeRateLimit = statusCode == 429;
            final isSafeConnection =
                error.type == DioExceptionType.connectionTimeout;

            if (isSafeRateLimit || isSafeConnection) return true;

            // 3. GET-only retries for other transient errors
            if (!isGet) return false;

            final retryableTypes = {
              DioExceptionType.sendTimeout,
              DioExceptionType.receiveTimeout,
              DioExceptionType.unknown,
            };

            return retryableTypes.contains(error.type);
          },
          // Per-request delay schedule is resolved at retry time via
          // the retryEvaluator above; the base delays here serve as the
          // global default when no per-request override is present.
        );

  /// Resolves the retry delays for a given request, preferring per-request
  /// overrides stashed in [RequestOptions.extra] by [LikeClient._execute].
  static List<Duration> resolveDelays(RequestOptions options) {
    final raw = options.extra['retryDelays'];
    if (raw is List<int>) {
      return raw.map((s) => Duration(seconds: s)).toList();
    }
    return LikeConstants.retryDelays.map((s) => Duration(seconds: s)).toList();
  }
}
