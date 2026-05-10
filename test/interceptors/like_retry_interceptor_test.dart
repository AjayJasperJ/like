import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    dio = Dio();
    mockAdapter = MockHttpClientAdapter();
    dio.httpClientAdapter = mockAdapter;
    interceptor = LikeRetryInterceptor(dio: dio);
    dio.interceptors.add(interceptor);

    // Default status: online
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
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
      LikeConnectivityManager().debugSetStatus(server: false);

      int callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        throw DioException(
          requestOptions: RequestOptions(path: 'test'),
          type: DioExceptionType.connectionTimeout,
        );
      });

      await expectLater(
        () => dio.get('http://test.com'),
        throwsA(isA<DioException>()),
      );

      expect(callCount, 1);
    });

    test('should retry POST on 429 Rate Limit', () async {
      int callCount = 0;
      when(() => mockAdapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return ResponseBody.fromString('{"error": "Too many requests"}', 429);
        }
        return ResponseBody.fromString(
          '{"success": true}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final response = await dio.post('http://test.com');

      expect(response.statusCode, 200);
      expect(callCount, 2);
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
