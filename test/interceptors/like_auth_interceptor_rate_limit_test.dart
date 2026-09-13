import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:mocktail/mocktail.dart';

import '../mocks/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late MockHttpClientAdapter adapter;

  setUpAll(setupMocks);

  setUp(() async {
    LikeConstants.apply(
      LikeConfig(
        projectName: 'auth-rate-limit-test',
        maxAutoRetries: 3,
      ),
    );
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugSetStatus(internet: true, server: true);
    LikeAuthInterceptor.getToken = null;
    LikeAuthInterceptor.refreshToken = null;
    LikeAuthInterceptor.onLogout = null;
    LikeAuthInterceptor.getApiKey = null;

    dio = Dio();
    adapter = MockHttpClientAdapter();
    dio.httpClientAdapter = adapter;
    dio.interceptors.add(LikeAuthInterceptor(dio: dio));
  });

  tearDown(() async {
    LikeConstants.reset();
    await LikeConnectivityManager().reset();
  });

  group('LikeAuthInterceptor rate-limit ownership', () {
    test('retries 429 and respects the request-local maximum', () async {
      var callCount = 0;
      when(() => adapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          return ResponseBody.fromString(
            '{"error":"rate limited"}',
            429,
            headers: <String, List<String>>{
              'retry-after': <String>['0'],
            },
          );
        }
        return ResponseBody.fromString('{"ok":true}', 200);
      });

      final response = await dio.post<void>(
        'https://rate-limit-success.example/items',
        options: Options(
          extra: <String, Object>{
            'withAuth': false,
            'maxAutoRetries': 1,
          },
        ),
      );

      expect(response.statusCode, 200);
      expect(callCount, 2);
    });

    test('propagates the terminal 429 after bounded retries', () async {
      var callCount = 0;
      when(() => adapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        return ResponseBody.fromString(
          '{"error":"rate limited"}',
          429,
          headers: <String, List<String>>{
            'retry-after': <String>['0'],
          },
        );
      });

      await expectLater(
        () => dio.get<void>(
          'https://rate-limit-bounded.example/items',
          options: Options(
            extra: <String, Object>{
              'withAuth': false,
              'maxAutoRetries': 1,
            },
          ),
        ),
        throwsA(
          isA<DioException>().having(
            (error) => error.response?.statusCode,
            'status code',
            429,
          ),
        ),
      );

      expect(callCount, 2);
    });

    test('does not retry when automatic rate-limit retry is disabled',
        () async {
      LikeConstants.apply(
        LikeConfig(
          projectName: 'auth-rate-limit-disabled-test',
          autoRetryRateLimit: false,
        ),
      );
      var callCount = 0;
      when(() => adapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        return ResponseBody.fromString('{"error":"rate limited"}', 429);
      });

      await expectLater(
        () => dio.get<void>('https://rate-limit-disabled.example/items'),
        throwsA(isA<DioException>()),
      );

      expect(callCount, 1);
    });

    test('cancels during Retry-After wait without replaying', () async {
      final cancelToken = CancelToken();
      var callCount = 0;
      when(() => adapter.fetch(any(), any(), any())).thenAnswer((_) async {
        callCount++;
        return ResponseBody.fromString(
          '{"error":"rate limited"}',
          429,
          headers: <String, List<String>>{
            'retry-after': <String>['10'],
          },
        );
      });

      final request = dio.get<void>(
        'https://rate-limit-cancel.example/items',
        cancelToken: cancelToken,
        options: Options(
          extra: <String, Object>{
            'withAuth': false,
            'maxAutoRetries': 1,
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
  });
}
