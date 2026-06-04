import 'package:dio/dio.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Interceptor that checks connectivity before every request.
/// Fails fast with [DioExceptionType.connectionError] if offline to avoid long timeouts.
class LikeConnectivityInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final customConnectTimeout = options.extra['connectTimeout'];
    if (customConnectTimeout is Duration) {
      options.connectTimeout = customConnectTimeout;
    }

    final bool offlineSync = options.extra['offlineSync'] ?? true;
    final bool isSyncRequest = options.extra['isSyncRequest'] ?? false;

    // We only fail-fast for non-sync requests that expect offline queuing.
    // Sync requests (from the queue) must be allowed to try reaching the network.
    if (!isSyncRequest &&
        offlineSync &&
        !LikeConnectivityManager().hasConnection) {
      return handler.reject(
        DioException(
          requestOptions: options,
          error: 'No internet connection',
          type: DioExceptionType.connectionError,
        ),
      );
    }

    return handler.next(options);
  }
}
