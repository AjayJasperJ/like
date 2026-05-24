import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/interceptors/like_cache_interceptor.dart';
import 'package:like/src/services/like_service.dart';
import 'package:hive/hive.dart';
import '../mocks/mocks.dart';

void main() {
  late LikeCacheInterceptor interceptor;
  late ResponseInterceptorHandler handler;

  setUpAll(() async {
    setupMocks();
    await initTestHive();
    // Open boxes manually for testing
    await Hive.openBox(LikeConstants.boxApiCache);
    await Hive.openBox(LikeConstants.boxCacheMetadata);
    await Hive.openBox(LikeConstants.boxEtags);
    await Hive.openBox(LikeConstants.boxOfflineQueue);
  });

  setUp(() {
    interceptor = LikeCacheInterceptor();
    handler = ResponseInterceptorHandler();
  });

  group('LikeCacheInterceptor', () {
    test('onResponse should save GET response to cache when enabled', () async {
      final options = RequestOptions(
        path: 'test',
        method: 'GET',
        extra: {'disableCache': false},
      );
      final response = Response(
        requestOptions: options,
        data: {'success': true},
        statusCode: 200,
      );

      interceptor.onResponse(response, handler);

      // Wait a bit for the async save to happen
      await Future.delayed(const Duration(milliseconds: 100));

      final key = options.uri.toString();
      final cached = LikeService.cacheBox.get(key);

      expect(cached, isNotNull);
      expect(cached['data'], equals({'success': true}));
    });

    test('onResponse should NOT save if disableCache is true', () async {
      final options = RequestOptions(
        path: 'test-no-cache',
        method: 'GET',
        extra: {'disableCache': true},
      );
      final response = Response(
        requestOptions: options,
        data: {'success': true},
        statusCode: 200,
      );

      interceptor.onResponse(response, handler);
      await Future.delayed(const Duration(milliseconds: 100));

      final key = options.uri.toString();
      final cached = LikeService.cacheBox.get(key);

      expect(cached, isNull);
    });

    test('pruneCache should remove expired entries', () async {
      final box = LikeService.cacheBox;
      const key = 'expired-key';

      // Save an expired entry (10 days ago)
      final expiredTimestamp =
          DateTime.now().subtract(const Duration(days: 10)).toIso8601String();
      await box.put(key, {
        'data': 'stale',
        'timestamp': expiredTimestamp,
        'storageDurationMs': 1000, // 1 second TTL
      });

      // Save a fresh entry
      const freshKey = 'fresh-key';
      await box.put(freshKey, {
        'data': 'fresh',
        'timestamp': DateTime.now().toIso8601String(),
      });

      await interceptor.pruneCache();

      expect(box.get(key), isNull);
      expect(box.get(freshKey), isNotNull);
    });
  });
}
