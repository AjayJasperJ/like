import 'package:dio/dio.dart';
import 'package:like/src/interceptors/like_retry_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:universal_io/io.dart';

/// Interceptor that checks connectivity before every request.
/// Fails fast with [DioExceptionType.connectionError] if offline to avoid long timeouts.
class LikeConnectivityInterceptor extends Interceptor {
  static const String _preflightOfflineKey = 'like.syntheticPreflightOffline';

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
      options.extra[_preflightOfflineKey] = true;
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

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // Every real HTTP response, including 4xx/5xx when Dio accepts them, proves
    // that this request's origin was reachable.
    LikeConnectivityManager().markServerAvailable(
      serverUrl: response.requestOptions.uri.toString(),
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Dio routes rejected HTTP status responses through onError. They are still
    // positive reachability evidence and must never launch another probe.
    if (err.response != null) {
      LikeConnectivityManager().markServerAvailable(
        serverUrl: err.requestOptions.uri.toString(),
      );
    } else if (_shouldCheckAfter(err) && !LikeRetryInterceptor.willRetry(err)) {
      // Diagnose only a terminal transport failure. Probing an intermediate
      // failure can mark the origin unavailable before the retry interceptor
      // evaluates it, incorrectly suppressing the remaining logical request.
      // Deliberately do not await: delivery and identity of the terminal error
      // are unaffected by connectivity diagnostics.
      LikeConnectivityManager().checkAfterApiFailure(
        err.requestOptions.uri.toString(),
      );
    }
    handler.next(err);
  }

  static bool _shouldCheckAfter(DioException error) {
    if (error.requestOptions.extra[_preflightOfflineKey] == true ||
        error.error == 'OFFLINE_QUEUED') {
      return false;
    }

    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.unknown:
        return _isSocketFailure(error.error);
      case DioExceptionType.cancel:
      case DioExceptionType.badCertificate:
      case DioExceptionType.badResponse:
      case DioExceptionType.transformTimeout:
        return false;
    }
  }

  static bool _isSocketFailure(Object? error) {
    if (error is SocketException || error is OSError) return true;
    if (error is DioException && !identical(error.error, error)) {
      return _isSocketFailure(error.error);
    }
    return false;
  }
}
