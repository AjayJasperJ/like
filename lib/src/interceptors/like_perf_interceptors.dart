import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_logger.dart';

/// Interceptor to track request performance.
/// Matches enterprise's PerformanceInterceptor parity.
class LikePerformanceInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['startTime'] = DateTime.now().millisecondsSinceEpoch;
    super.onRequest(options, handler);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _checkPerformance(response, response.requestOptions, response.statusCode);
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _checkPerformance(
      err.response,
      err.requestOptions,
      err.response?.statusCode,
    );
    super.onError(err, handler);
  }

  void _checkPerformance(
    Response? response,
    RequestOptions options,
    int? statusCode,
  ) {
    final startTime = options.extra['startTime'] as int?;
    if (startTime != null) {
      final durationMs = DateTime.now().millisecondsSinceEpoch - startTime;
      options.extra['durationMs'] = durationMs;
      if (LikeConstants.debugMode || LikeConstants.verboseLogging) {
        LikeLogger.log(
          level: LikeLogLevel.debug,
          category: 'perf',
          message:
              '${options.method} ${options.path} completed in ${durationMs}ms (Status: ${statusCode ?? 'N/A'})',
        );
      }
    }
  }
}

/// Minimal throttling interceptor for simulating various network conditions in dev.
class LikeThrottlingInterceptor extends Interceptor {
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final int? latency = options.extra['simulatedLatencyMs'];
    if (latency != null && latency > 0) {
      await Future.delayed(Duration(milliseconds: latency ~/ 2));
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    final int? latency = response.requestOptions.extra['simulatedLatencyMs'];
    if (latency != null && latency > 0) {
      await Future.delayed(Duration(milliseconds: latency ~/ 2));
    }
    handler.next(response);
  }
}
