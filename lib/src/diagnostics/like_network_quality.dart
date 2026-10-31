import 'dart:async';
import 'package:dio/dio.dart';

enum LikeNetworkQuality { unknown, normal, slow }

/// Passive API-path measurements, not a device-wide internet speed test.
class LikeNetworkQualitySample {
  final String origin;
  final Duration elapsed;
  final double? estimatedBytesPerSecond;
  final LikeNetworkQuality quality;

  const LikeNetworkQualitySample(
      {required this.origin,
      required this.elapsed,
      required this.quality,
      this.estimatedBytesPerSecond});
}

/// Instance-owned monitor; inject it for deterministic tests and scoped clients.
class LikeNetworkQualityMonitor {
  static final shared = LikeNetworkQualityMonitor();
  final Duration slowAfter;
  final int minimumBytes;
  final double slowBytesPerSecond;
  final int samplesForSlow;
  final _events = StreamController<LikeNetworkQualitySample>.broadcast();
  final Map<String, int> _slowCounts = {};
  final Map<String, LikeNetworkQualitySample> _latest = {};
  bool _disposed = false;

  LikeNetworkQualityMonitor(
      {this.slowAfter = const Duration(seconds: 2),
      this.minimumBytes = 32768,
      this.slowBytesPerSecond = 32768,
      this.samplesForSlow = 2})
      : assert(samplesForSlow > 0);

  Stream<LikeNetworkQualitySample> get stream => _events.stream;
  LikeNetworkQualitySample? latest(String origin) => _latest[origin];

  void record(
      {required Uri uri,
      required Duration elapsed,
      int? bytes,
      bool timedOut = false}) {
    if (_disposed ||
        elapsed <= Duration.zero ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return;
    }
    if (_latest.length >= 100 && !_latest.containsKey(uri.origin)) {
      final oldest = _latest.keys.first;
      _latest.remove(oldest);
      _slowCounts.remove(oldest);
    }
    final origin = Uri(
            scheme: uri.scheme.toLowerCase(),
            host: uri.host.toLowerCase(),
            port: uri.hasPort ? uri.port : null)
        .origin;
    final rate = bytes != null && bytes >= minimumBytes
        ? bytes * Duration.microsecondsPerSecond / elapsed.inMicroseconds
        : null;
    final isSlow = timedOut ||
        elapsed >= slowAfter ||
        (rate != null && rate < slowBytesPerSecond);
    final count = isSlow ? (_slowCounts[origin] ?? 0) + 1 : 0;
    _slowCounts[origin] = count;
    final sample = LikeNetworkQualitySample(
        origin: origin,
        elapsed: elapsed,
        estimatedBytesPerSecond: rate,
        quality: count >= samplesForSlow
            ? LikeNetworkQuality.slow
            : isSlow
                ? LikeNetworkQuality.unknown
                : LikeNetworkQuality.normal);
    _latest[origin] = sample;
    _events.add(sample);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _slowCounts.clear();
    _latest.clear();
    await _events.close();
  }
}

/// Measures real HTTP attempts using a monotonic clock; ignores cached results,
/// cancellations and local failures. Works without browser-specific APIs.
class LikeNetworkQualityInterceptor extends Interceptor {
  static const _clockKey = 'like.quality.stopwatch';
  final LikeNetworkQualityMonitor monitor;

  LikeNetworkQualityInterceptor({LikeNetworkQualityMonitor? monitor})
      : monitor = monitor ?? LikeNetworkQualityMonitor.shared;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_clockKey] = Stopwatch()..start();
    handler.next(options);
  }

  void _record(RequestOptions options, Response? response,
      {bool timeout = false}) {
    final clock = options.extra.remove(_clockKey);
    if (clock is! Stopwatch) return;
    clock.stop();
    if (response?.extra['isFromCache'] == true ||
        response?.extra['isFromStaleWhileRevalidate'] == true ||
        response?.extra['isFrom304'] == true) {
      return;
    }
    final lengths = response?.headers.map['content-length'];
    final bytes = lengths != null && lengths.length == 1
        ? int.tryParse(lengths.first)
        : null;
    monitor.record(
        uri: options.uri,
        elapsed: clock.elapsed,
        bytes: bytes,
        timedOut: timeout);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _record(response.requestOptions, response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    const timeouts = {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout
    };
    if (err.response != null || timeouts.contains(err.type)) {
      _record(err.requestOptions, err.response,
          timeout: timeouts.contains(err.type));
    } else {
      err.requestOptions.extra.remove(_clockKey);
    }
    handler.next(err);
  }
}
