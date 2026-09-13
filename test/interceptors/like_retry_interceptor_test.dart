import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/interceptors/like_retry_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:mocktail/mocktail.dart';
import '../mocks/mocks.dart';

void main() {
  late Dio dio;
  late MockHttpClientAdapter mockAdapter;
  late LikeRetryInterceptor interceptor;

  setUpAll(() {
    setupMocks();
  });

  setUp(() async {
    await LikeConnectivityManager().reset();
    LikeConstants.apply(
      LikeConfig(
        projectName: 'retry-test',
        maxAutoRetries: 3,
        retryDelays: const [0],
      ),
    );
    dio = Dio();
    mockAdapter = MockHttpClientAdapter();
    dio.httpClientAdapter = mockAdapter;
    interceptor = LikeRetryInterceptor(dio: dio);
    dio.interceptors.add(interceptor);

    // Default status: online.
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
  });

  tearDown(() async {
    LikeConstants.reset();
    await LikeConnectivityManager().reset();
  });

  group('LikeRetryInterceptor', () {
    test('should retry GET on connection timeout', () async {
      int callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw DioException(
            requestOptions: RequestOptions(path: 'test'),
            type: DioExceptionType.connectionTimeout,
          );
        }
        return ResponseBody.fromString(
          '{"success": true}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final response = await dio.get('http://test.com');

      expect(response.statusCode, 200);
      expect(callCount, 2);
    });

    test('should NOT retry if server is offline', () async {
      LikeConnectivityManager().markServerUnavailable(
        serverUrl: 'http://test.com',
      );

      int callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any()))
          .thenAnswer((invocation) async {
        callCount++;
        throw DioException(
          requestOptions:
              invocation.positionalArguments.first as RequestOptions,
          type: DioExceptionType.connectionTimeout,
        );
      });

      await expectLater(
        () => dio.get('http://test.com'),
        throwsA(isA<DioException>()),
      );

      expect(callCount, 1);
    });

    test('does not own HTTP 429 retries', () async {
      var callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        return ResponseBody.fromString('{"error": "Too many requests"}', 429);
      });

      await expectLater(
        () => dio.post('http://test.com'),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status code',
            429,
          ),
        ),
      );

      expect(callCount, 1);
    });

    test('honors a lower request-local retry limit', () async {
      var callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any()))
          .thenAnswer((invocation) async {
        callCount++;
        throw DioException(
          requestOptions:
              invocation.positionalArguments.first as RequestOptions,
          type: DioExceptionType.connectionTimeout,
        );
      });

      await expectLater(
        () => dio.get<void>(
          'http://test.com',
          options: Options(
            extra: <String, Object>{
              'maxAutoRetries': 1,
              'retryDelays': <int>[0],
            },
          ),
        ),
        throwsA(isA<DioException>()),
      );

      expect(callCount, 2);
    });

    test('cancels while waiting for a retry without another fetch', () async {
      final cancelToken = CancelToken();
      var callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        throw DioException(
          requestOptions: RequestOptions(path: 'test', method: 'GET'),
          type: DioExceptionType.connectionTimeout,
        );
      });

      final request = dio.get<void>(
        'http://test.com',
        cancelToken: cancelToken,
        options: Options(
          extra: <String, Object>{
            'maxAutoRetries': 1,
            'retryDelays': <int>[10],
          },
        ),
      );
      while (callCount == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      cancelToken.cancel('test cancellation');

      await expectLater(
        request,
        throwsA(
          isA<DioException>().having(
            (error) => error.type,
            'type',
            DioExceptionType.cancel,
          ),
        ),
      );
      expect(callCount, 1);
    });

    test('should NOT retry POST on receive timeout (unsafe)', () async {
      int callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        throw DioException(
          requestOptions: RequestOptions(path: 'test', method: 'POST'),
          type: DioExceptionType.receiveTimeout,
        );
      });

      await expectLater(
        () => dio.post('http://test.com'),
        throwsA(isA<DioException>()),
      );

      expect(callCount, 1);
    });
  });
}
