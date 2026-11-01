import 'dart:async';
import 'package:dio/dio.dart';

enum LikeResponseSource {
  network,
  mocked,
  memoryCache,
  diskCache,
  staleWhileRevalidate,
  notModified,
  fallback,
  queued,
  cancelled,
  failed
}

enum LikeTracePhase { started, completed }

/// Deliberately has no URL path/query, headers, bodies, error text or credentials.
class LikeRequestTrace {
  final String requestId;
  final String method;
  final String origin;
  final String scope;
  final LikeTracePhase phase;
  final LikeResponseSource source;
  final Duration elapsed;
  final int? statusCode;
  final int transportRetries;
  final int rateLimitRetries;
  final bool authRetried;
  final DateTime timestamp;
  LikeRequestTrace(
      {required this.requestId,
      required this.method,
      required this.origin,
      required this.scope,
      required this.phase,
      required this.source,
      this.elapsed = Duration.zero,
      this.statusCode,
      this.transportRetries = 0,
      this.rateLimitRetries = 0,
      this.authRetried = false})
      : timestamp = DateTime.now();

  Map<String, Object?> toLog() => {
        'timestamp': timestamp.toIso8601String(),
        'level': source == LikeResponseSource.failed ? 'error' : 'info',
        'category': 'api',
        'message': '$method $origin: ${source.name}',
        'details': {
          'action': phase == LikeTracePhase.started ? 'started' : 'completed',
          'requestId': requestId,
          'method': method,
          'statusCode': statusCode,
          'durationMs': elapsed.inMilliseconds,
          'source': source.name,
          'transportRetries': transportRetries,
          'rateLimitRetries': rateLimitRetries,
          'authRetried': authRetried,
          'scope': scope
        },
      };
}

class LikeDiagnostics {
  static final shared = LikeDiagnostics();
  final _events = StreamController<LikeRequestTrace>.broadcast();
  final List<LikeRequestTrace> _history = [];
  Stream<LikeRequestTrace> get stream => _events.stream;
  List<LikeRequestTrace> get history => List.unmodifiable(_history);
  void emit(LikeRequestTrace trace) {
    if (_events.isClosed) return;
    _history.add(trace);
    if (_history.length > 400) _history.removeAt(0);
    _events.add(trace);
  }

  void clear() => _history.clear();
  Future<void> dispose() => _events.close();
}

/// Mutable operation-local metadata only. It is never persisted or exported.
class LikeTraceContext {
  RequestOptions? lastOptions;
}

class LikeTraceCaptureInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final context = options.extra['like.trace'];
    if (context is LikeTraceContext) context.lastOptions = options;
    handler.next(options);
  }
}
