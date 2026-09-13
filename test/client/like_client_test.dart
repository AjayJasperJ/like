import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
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

  group('LikeClient - Connectivity', () {
    test('manual checks use the client active base origin', () async {
      final manager = LikeConnectivityManager();
      await manager.reset();
      addTearDown(manager.reset);
      manager.debugConfigure(
        interfaceCheck: () async => <ConnectivityResult>[
          ConnectivityResult.wifi,
        ],
        internetCheck: (_, __) async => true,
        serverCheck: (host, port, _) async {
          expect(host, 'api.example.com');
          expect(port, 443);
          return true;
        },
        isWeb: false,
      );

      final connectivity = await client.checkConnectivity(force: true);
      final server = await client.checkServerReachability(force: true);

      expect(connectivity.origin, 'https://api.example.com:443');
      expect(connectivity.reason, LikeConnectivityCheckReason.manual);
      expect(server.origin, 'https://api.example.com:443');
      expect(server.reason, LikeConnectivityCheckReason.manualServer);
    });
  });

  group('LikeClient - Execution Logic', () {
    test('get should return success when dio returns 200', () async {
      const path = '/test';
      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
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
          cancelToken: any(named: 'cancelToken'),
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
        final started = List.generate(2, (_) => Completer<void>());
        final release = List.generate(2, (_) => Completer<void>());
        var requestIndex = 0;

        when(
          () => mockDio.request<dynamic>(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ),
        ).thenAnswer((invocation) async {
          final index = requestIndex++;
          final cancelToken =
              invocation.namedArguments[#cancelToken] as CancelToken?;
          started[index].complete();
          await release[index].future;
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: path),
              reason: cancelToken?.cancelError?.error,
            );
          }
          return Response(
            requestOptions: RequestOptions(path: path),
            data: {'request': index + 1},
            statusCode: 200,
          );
        });

        final first = client.get(path, deduplicate: true);
        await started[0].future;
        final second = client.get(path, deduplicate: true);
        await started[1].future;

        release[0].complete();
        release[1].complete();
        final results = await Future.wait([first, second]);

        expect(results[0].isSuccess, isFalse);
        expect(results[0].error?.type, LikeApiErrorType.cancelled);
        expect(results[1].isSuccess, isTrue);
        expect(results[1].data?.data, {'request': 2});

        verify(
          () => mockDio.request(
            any(),
            data: any(named: 'data'),
            queryParameters: any(named: 'queryParameters'),
            cancelToken: any(named: 'cancelToken'),
            onSendProgress: any(named: 'onSendProgress'),
            onReceiveProgress: any(named: 'onReceiveProgress'),
            options: any(named: 'options'),
          ),
        ).called(2);
      },
    );

    test('mutations require explicit durable replay opt-in', () async {
      final captured = <String, bool?>{};
      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((invocation) async {
        final options = invocation.namedArguments[#options] as Options;
        captured[options.method!] = options.extra?['offlineSync'] as bool?;
        return Response(
          requestOptions: RequestOptions(
            path: '/mutation',
            method: options.method,
          ),
          data: const <String, Object>{'status': 'ok'},
          statusCode: 200,
        );
      });

      await client.post('/mutation');
      await client.put('/mutation');
      await client.delete('/mutation');

      expect(captured, <String, bool?>{
        'POST': false,
        'PUT': false,
        'DELETE': false,
      });
    });

    test('post propagates an explicit durable replay opt-in', () async {
      bool? capturedOfflineSync;
      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ),
      ).thenAnswer((invocation) async {
        final options = invocation.namedArguments[#options] as Options;
        capturedOfflineSync = options.extra?['offlineSync'] as bool?;
        return Response(
          requestOptions: RequestOptions(path: '/mutation', method: 'POST'),
          data: const <String, Object>{'status': 'ok'},
          statusCode: 201,
        );
      });

      await client.post('/mutation', offlineSync: true);

      expect(capturedOfflineSync, isTrue);
    });

    test('post should return success and notify refresh', () async {
      const path = '/post-test';
      const effectivePath = '/post-test';

      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
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
          cancelToken: any(named: 'cancelToken'),
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

    test('request should propagate verifySSL and sslCertSha256 to Zone context',
        () async {
      const path = '/ssl-test';
      bool? capturedVerifySSL;
      String? capturedSha;

      when(
        () => mockDio.request<dynamic>(
          any(),
          data: any(named: 'data'),
          queryParameters: any(named: 'queryParameters'),
          cancelToken: any(named: 'cancelToken'),
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
