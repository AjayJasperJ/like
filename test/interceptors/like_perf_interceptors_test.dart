import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/interceptors/like_perf_interceptors.dart';

class TestResponseInterceptorHandler extends ResponseInterceptorHandler {
  Response? resolvedResponse;
  Response? nextResponse;

  @override
  void next(Response response) {
    nextResponse = response;
  }

  @override
  void resolve(Response response) {
    resolvedResponse = response;
  }
}

class TestErrorInterceptorHandler extends ErrorInterceptorHandler {
  DioException? nextError;

  @override
  void next(DioException err) {
    nextError = err;
  }
}

class TestRequestInterceptorHandler extends RequestInterceptorHandler {
  RequestOptions? nextOptions;

  @override
  void next(RequestOptions options) {
    nextOptions = options;
  }
}

void main() {
  group('LikePerformanceInterceptor', () {
    late LikePerformanceInterceptor interceptor;

    setUp(() {
      interceptor = LikePerformanceInterceptor();
    });

    test('onRequest attaches startTime extra to requestOptions', () {
      final options = RequestOptions(path: '/test');
      final handler = TestRequestInterceptorHandler();

      interceptor.onRequest(options, handler);

      expect(options.extra['startTime'], isNotNull);
      expect(options.extra['startTime'], isA<int>());
    });

    test('onResponse calculates durationMs and stores in extra', () {
      final options = RequestOptions(
        path: '/test',
        extra: {'startTime': DateTime.now().millisecondsSinceEpoch - 100},
      );
      final response = Response(requestOptions: options, statusCode: 200);
      final handler = TestResponseInterceptorHandler();

      interceptor.onResponse(response, handler);

      expect(options.extra['durationMs'], isNotNull);
      expect(options.extra['durationMs'] as int, greaterThanOrEqualTo(90));
    });

    test('onError calculates durationMs when request fails', () {
      final options = RequestOptions(
        path: '/test',
        extra: {'startTime': DateTime.now().millisecondsSinceEpoch - 50},
      );
      final exception = DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 500),
      );
      final handler = TestErrorInterceptorHandler();

      interceptor.onError(exception, handler);

      expect(options.extra['durationMs'], isNotNull);
      expect(options.extra['durationMs'] as int, greaterThanOrEqualTo(40));
    });
  });

  group('LikeThrottlingInterceptor', () {
    late LikeThrottlingInterceptor interceptor;

    setUp(() {
      interceptor = LikeThrottlingInterceptor();
    });

    test('onRequest delays request if simulatedLatencyMs > 0', () {
      fakeAsync((async) {
        final options = RequestOptions(
          path: '/test',
          extra: {'simulatedLatencyMs': 100},
        );
        final handler = TestRequestInterceptorHandler();

        interceptor.onRequest(options, handler);
        expect(handler.nextOptions, isNull);

        async.elapse(const Duration(milliseconds: 50));
        expect(handler.nextOptions, isNotNull);
      });
    });
  });
}
