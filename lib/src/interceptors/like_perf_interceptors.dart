import 'package:dio/dio.dart';

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
    // Metrics can be emitted to a monitoring service here
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
