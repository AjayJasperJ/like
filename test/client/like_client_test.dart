import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mocktail/mocktail.dart';
import 'package:hive/hive.dart';
import 'package:like/like.dart';
import '../mocks/mocks.dart';

void main() {
  late LikeClient client;
  late MockDio mockDio;
  const baseUrl = 'https://api.example.com';

  setUpAll(() async {
    setupMocks();
    await initTestHive();
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
  });

  setUp(() {
    LikeClient.reset();
    mockDio = MockDio();
    client = LikeClient(baseUrl: baseUrl, dio: mockDio);
    when(() => mockDio.options).thenReturn(BaseOptions(baseUrl: baseUrl));

    // Clear registry
    client.registry.clear();
  });

  tearDown(() {
    client.dispose();
  });

  group('LikeClient - Execution Logic', () {
    test('get should return success when dio returns 200', () async {
      const path = '/test';
      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: path),
          data: {'status': 'ok'},
          statusCode: 200,
        ),
      );

      final result = await client.get(path);

      expect(result.isSuccess, isTrue);
      expect(result.data?.data['status'], equals('ok'));
    });

    test('get should handle DioException', () async {
      const path = '/error';
      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => throw DioException(
          requestOptions: RequestOptions(path: path),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await client.get(path);

      expect(result.isError, isTrue);
      expect(result.error?.type, equals(LikeApiErrorType.timeout));
    });

    test(
      'get with Deduplication enabled should deduplicate identical in-flight requests',
      () async {
        const path = '/deduplicate-test';
        final response = Response(
          requestOptions: RequestOptions(path: path),
          data: {'status': 'deduplicate'},
          statusCode: 200,
        );

        when(
          () => mockDio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((_) async {
          await Future.delayed(const Duration(milliseconds: 100));
          return response;
        });

        // Fire multiple identical requests, slightly staggered to avoid microtask race
        final f1 = client.get(path, deduplicate: true);
        await Future.delayed(const Duration(milliseconds: 1));
        final f2 = client.get(path, deduplicate: true);

        final results = await Future.wait([f1, f2]);

        expect(results[0].isSuccess, isTrue);
        expect(results[1].isSuccess, isTrue);

        // Verification
        verify(
          () => mockDio.request(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          ),
        ).called(1);
      },
    );

    test('post should return success and notify refresh', () async {
      const path = '/post-test';
      const effectivePath = '/post-test';

      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: RequestOptions(path: path, method: 'POST'),
          data: {'status': 'created'},
          statusCode: 201,
        ),
      );

      final refreshEvents = <String>[];
      final sub = client.refreshStream.listen((e) => refreshEvents.add(e));

      final result = await client.post(path);
      await Future.delayed(Duration.zero);

      expect(result.isSuccess, isTrue);
      expect(refreshEvents.contains(effectivePath), isTrue);
      await sub.cancel();
    });

    test('get with Stale-While-Revalidate should return cache', () async {
      const path = '/staleWhileRevalidate-test';
      final options = RequestOptions(
        path: path,
        baseUrl: baseUrl,
        method: 'GET',
      );

      await LikeService.saveResponseToCache(
        Response(
          requestOptions: options,
          data: {'source': 'cache'},
          statusCode: 200,
        ),
      );

      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response(
          requestOptions: options,
          data: {'source': 'network'},
          statusCode: 200,
        ),
      );

      final result = await client.get(path, staleWhileRevalidate: true);

      expect(result.data?.data['source'], equals('cache'));
    });

    test('request should propagate verifySSL and sslCertSha256 to Zone context', () async {
      const path = '/ssl-test';
      bool? capturedVerifySSL;
      String? capturedSha;

      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((_) async {
        capturedVerifySSL = Zone.current[#verifySSL] as bool?;
        capturedSha = Zone.current[#sslCertSha256] as String?;
        return Response(
          requestOptions: RequestOptions(path: path),
          data: {'status': 'ok'},
          statusCode: 200,
        );
      });

      await client.get(
        path,
        requestConfig: const LikeRequestConfig(
          verifySSL: false,
          sslCertSha256: 'some-sha',
        ),
      );

      expect(capturedVerifySSL, isFalse);
      expect(capturedSha, equals('some-sha'));
    });
  });
}
