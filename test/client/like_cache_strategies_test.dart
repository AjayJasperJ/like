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
    await Hive.openBox(LikeConstants.boxEtags);
    await Hive.openBox(LikeConstants.boxOfflineQueue);
  });

  setUp(() {
    LikeClient.reset();
    mockDio = MockDio();
    client = LikeClient(baseUrl: baseUrl, dio: mockDio);
    when(() => mockDio.options).thenReturn(BaseOptions(baseUrl: baseUrl));

    // Reset singleton registry
    client.registry.clear();
    LikeConstants.apply(LikeConstants.current.copyWith(cacheOnOffline: false));
  });

  tearDown(() {
    client.dispose();
  });

  group('LikeClient - Cache & Fetch Strategies', () {
    test(
      'L1 Cache: should return from memory if already fetched in this session',
      () async {
        const path = '/l1-test';
        final absoluteUriKey = Uri.parse('$baseUrl$path').toString();

        final response = Response(
          requestOptions: RequestOptions(
            path: path,
            method: 'GET',
            baseUrl: baseUrl,
          ),
          data: {'status': 'ok'},
          statusCode: 200,
        );

        client.registry.addSessionKey(absoluteUriKey, response: response);

        // sessionStale must be true to trigger L1 check
        final result = await client.get(path, sessionStale: true);

        expect(result.data?.extra['isFromL1Cache'], isTrue);
        verifyNever(() => mockDio.request(any()));
      },
    );

    test(
      'L2 Cache (SingleFetch): should return from disk if available',
      () async {
        const path = '/l2-test';
        final options = RequestOptions(
          path: path,
          baseUrl: baseUrl,
          method: 'GET',
        );

        await LikeService.saveResponseToCache(
          Response(
            requestOptions: options,
            data: {'status': 'from-disk'},
            statusCode: 200,
          ),
        );

        final result = await client.get(path, singleFetch: true);

        expect(result.data?.extra['isFromCache'], isTrue);
        expect(result.data?.data['status'], equals('from-disk'));
        verifyNever(() => mockDio.request(any()));
      },
    );

    test(
      'SessionStale: should return from disk only if marked stale in this session',
      () async {
        const path = '/stale-test';
        final options = RequestOptions(
          path: path,
          baseUrl: baseUrl,
          method: 'GET',
        );
        final absoluteUriKey = options.uri.toString();

        // 1. Initial fetch to establish "session presence"
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
            data: {'status': 'network'},
            statusCode: 200,
          ),
        );

        final result1 = await client.get(path, sessionStale: true);
        expect(result1.data?.data['status'], equals('network'));

        // 2. NOW inject the data we want to see coming back from L2
        await LikeService.saveResponseToCache(
          Response(
            requestOptions: options,
            data: {'status': 'stale-data'},
            statusCode: 200,
          ),
        );

        // 3. Clear L1 RAM cache but keep the "session fetched" mark
        // We do this by clearing and re-adding only the key
        client.registry.clear();
        client.registry.addSessionKey(absoluteUriKey);

        // 4. Try again - should miss L1 and hit L2
        final result2 = await client.get(path, sessionStale: true);
        expect(result2.data?.extra['isFromL2Cache'], isTrue);
        expect(result2.data?.data['status'], equals('stale-data'));
      },
    );

    test(
      'Stale-While-Revalidate (Stale-While-Revalidate): should return cache and update via pipeline',
      () async {
        const path = '/staleWhileRevalidate-test';
        final options = RequestOptions(
          path: path,
          baseUrl: baseUrl,
          method: 'GET',
        );
        final key = options.uri.toString();

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
            data: '{"source": "network"}',
            statusCode: 200,
          ),
        );

        final events = <LikeEvent>[];
        final completer = Completer<void>();
        final sub = LikePipeline().stream.listen((e) {
          if (e.key == key && e.response.data['source'] == 'network') {
            events.add(e);
            if (!completer.isCompleted) completer.complete();
          }
        });

        final result = await client.get(path, staleWhileRevalidate: true);

        expect(result.data?.data['source'], equals('cache'));

        await completer.future.timeout(const Duration(seconds: 1));

        expect(events.length, greaterThan(0));
        await sub.cancel();
      },
    );
  });

  group('LikeClient - Resilience', () {
    test(
      'Offline Fallback: should return from L2 if network fails and offline',
      () async {
        const path = '/offline-test';
        final options = RequestOptions(
          path: path,
          baseUrl: baseUrl,
          method: 'GET',
        );

        await LikeService.saveResponseToCache(
          Response(
            requestOptions: options,
            data: {'status': 'offline-cached'},
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
          (_) async => throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          ),
        );

        LikeConnectivityManager().debugSetStatus(internet: false);
        LikeConstants.apply(
          LikeConstants.current.copyWith(cacheOnOffline: true),
        );

        final result = await client.get(path);

        expect(result.data?.data['status'], equals('offline-cached'));
        expect(result.data?.extra['isResiliencyFallback'], isTrue);
      },
    );
  });
}
