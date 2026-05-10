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
