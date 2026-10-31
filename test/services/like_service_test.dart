import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_service.dart';
import '../mocks/mocks.dart';

void main() {
  setUpAll(() async {
    setupMocks();
    await initTestHive();
  });

  setUp(() async {
    // Open boxes for each test to ensure fresh state
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    await Hive.openBox(LikeConstants.boxOfflineQueue);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  group('LikeService', () {
    test('cache preserves strings, JSON-looking strings, bytes and lists', () async {
      final payloads = <dynamic>['OK', '123', '{"id":1}', <int>[0, 255],
        <dynamic>[{'id': 1}], null];
      for (var index = 0; index < payloads.length; index++) {
        final options = RequestOptions(
          path: '/payload/$index', baseUrl: 'https://cache.example',
        );
        await LikeService.saveResponseToCache(Response<dynamic>(
          requestOptions: options, data: payloads[index], statusCode: 200,
        ));
        final cached = await LikeService.fetchResponseFromCache(options);
        expect(cached, isNotNull);
        expect(cached!.data, equals(payloads[index]));
      }
    });

    test('legacy JSON cache entries remain readable', () async {
      final options = RequestOptions(
        path: '/legacy', baseUrl: 'https://cache.example',
      );
      await LikeService.cacheBox.put(options.uri.toString(), {
        'timestamp': DateTime.now().toIso8601String(),
        'data': '{"id":1}',
      });
      final cached = await LikeService.fetchResponseFromCache(options);
      expect(cached!.data, {'id': 1});
    });

    test('putEtag and getEtag should work correctly', () async {
      const key = 'test-key';
      const etag = 'W/"12345"';

      await LikeService.putEtag(key, etag);
      expect(LikeService.getEtag(key), equals(etag));

      LikeService.deleteEtag(key);
      expect(LikeService.getEtag(key), isNull);
    });

    test(
      'saveResponseToCache and fetchResponseFromCache should work correctly',
      () async {
        final options = RequestOptions(
          path: 'test-path',
          baseUrl: 'https://api.test.com',
          extra: {'disableCache': false},
        );
        final response = Response(
          requestOptions: options,
          data: {'id': 1, 'name': 'Test'},
          statusCode: 200,
        );

        await LikeService.saveResponseToCache(response);

        final fetched = await LikeService.fetchResponseFromCache(options);

        expect(fetched, isNotNull);
        expect(fetched!.data, equals({'id': 1, 'name': 'Test'}));
        expect(fetched.extra['isFromCache'], isTrue);
      },
    );

    test('fetchResponseFromCache should return null if expired', () async {
      final options = RequestOptions(
        path: 'expired-path',
        baseUrl: 'https://api.test.com',
        extra: {
          'disableCache': false,
          'cacheStorageDuration': const Duration(milliseconds: 1),
        },
      );
      final response = Response(
        requestOptions: options,
        data: 'expired-data',
        statusCode: 200,
      );

      await LikeService.saveResponseToCache(response);

      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 10));

      final fetched = await LikeService.fetchResponseFromCache(options);
      expect(fetched, isNull);
    });
  });
}
