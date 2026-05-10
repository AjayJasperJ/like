import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_service.dart';

/// Interceptor that persists successful GET responses to the L2 Hive cache.
/// Matches enterprise's CacheInterceptor parity.
class LikeCacheInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (LikeConstants.cacheEnabled &&
        response.requestOptions.method == 'GET' &&
        response.statusCode == 200 &&
        response.requestOptions.extra['disableCache'] != true) {
      // Save asynchronously to avoid blocking the network pipeline
      LikeService.saveResponseToCache(response);
    }
    handler.next(response);
  }

  /// Removes stale entries from the cache based on individual or global TTL.
  /// Matches the enterprise pruning logic for background maintenance.
  Future<void> pruneCache() async {
    final box = LikeService.cacheBox;
    final now = DateTime.now();
    final keysToDelete = <String>[];

    for (final key in box.keys) {
      final entry = box.get(key);
      if (entry is Map) {
        final timestampStr = entry['timestamp'] as String?;
        if (timestampStr == null) {
          keysToDelete.add(key.toString());
          continue;
        }

        final timestamp = DateTime.tryParse(timestampStr);
        if (timestamp == null) {
          keysToDelete.add(key.toString());
          continue;
        }

        final storageDurationMs = entry['storageDurationMs'] as int?;
        final maxAge = storageDurationMs != null
            ? Duration(milliseconds: storageDurationMs)
            : Duration(days: LikeConstants.cacheTTL);

        if (now.difference(timestamp) > maxAge) {
          keysToDelete.add(key.toString());
        }
      }
    }

    if (keysToDelete.isNotEmpty) {
      await box.deleteAll(keysToDelete);
    }
  }
}
