import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/core/like_constants.dart';

/// Intelligent retry interceptor with connectivity awareness.
/// Matches enterprise's AppRetryInterceptor parity.
class LikeRetryInterceptor extends RetryInterceptor {
  LikeRetryInterceptor({required super.dio})
    : super(
        retries: LikeConstants.maxAutoRetries,
        retryDelays: LikeConstants.retryDelays
            .map((s) => Duration(seconds: s))
            .toList(),
        retryEvaluator: (error, attempt) {
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
      );
}
