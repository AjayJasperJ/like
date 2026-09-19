import 'package:dio/dio.dart';
import 'package:like/src/interceptors/like_retry_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:universal_io/io.dart';

/// Interceptor that checks connectivity before every request.
/// Fails fast with [DioExceptionType.connectionError] if offline to avoid long timeouts.
class LikeConnectivityInterceptor extends Interceptor {
  static const String _preflightOfflineKey = 'like.syntheticPreflightOffline';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final customConnectTimeout = options.extra['connectTimeout'];
    if (customConnectTimeout is Duration) {
      options.connectTimeout = customConnectTimeout;
    }

    final bool offlineSync = options.extra['offlineSync'] ?? true;
    final bool isSyncRequest = options.extra['isSyncRequest'] ?? false;
    final String serverUrl = options.uri.toString();

    // If the system is currently marked offline for non-sync requests:
    // Run an instant probe to verify if the server/internet has recovered.
    if (!isSyncRequest &&
        offlineSync &&
        !LikeConnectivityManager().hasConnection) {
      final check = await LikeConnectivityManager().checkServerReachability(
        serverUrl,
        force: true,
      );

      // If probe confirms it is STILL offline, fail fast immediately (0ms delay).
      // This skips wasting network retries and long timeouts!
      if (!check.isOnline) {
        options.extra[_preflightOfflineKey] = true;
        return handler.reject(
          DioException(
            requestOptions: options,
            error: 'No internet connection',
            type: DioExceptionType.connectionError,
          ),
        );
      }
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
      // Diagnose terminal transport failures immediately with force: true
      LikeConnectivityManager().checkAfterApiFailure(
        err.requestOptions.uri.toString(),
        force: true,
      );
    }
    handler.next(err);
  }

  static bool _shouldCheckAfter(DioException error) {
    if (error.error == 'OFFLINE_QUEUED') {
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
    if (error == null) return true;
    if (error is SocketException || error is OSError) return true;
    if (error is DioException && !identical(error.error, error)) {
      return _isSocketFailure(error.error);
    }
    return false;
  }
}
