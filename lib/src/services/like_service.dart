import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_background_sync_service.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_offline_sync_manager.dart';
import 'package:like/src/services/like_utils.dart';

/// Low-level service for interacting with LIKE's persistent Hive boxes.
/// Handles caching, ETags, and the offline queue.
/// Matches enterprise's NetworkBoxService parity.
class LikeService {
  /// Initializes the LIKE engine and its persistent storage.
  ///
  /// This must be called before using any [LikeClient] or builders.
  /// It opens the necessary Hive boxes and configures global [LikeConstants].
  ///
  /// [baseUrl] (optional) can be set here or via [LikeClient].
  /// Numerous optional parameters allow fine-tuning the engine's behavior
  /// (timeouts, cache TTLs, logging levels, etc.).
  static Future<void> init({
    required LikeConfig config,
  }) async {
    final baseUrl = config.baseUrl;
    // 0. Apply config settings to LikeConstants
    LikeConstants.apply(config);

    // 1. Core Storage
    await Hive.initFlutter();
    await Future.wait([
      Hive.openBox(LikeConstants.boxApiCache),
      Hive.openBox(LikeConstants.boxCacheMetadata),
      Hive.openBox(LikeConstants.boxEtags),
      Hive.openBox(LikeConstants.boxOfflineQueue),
    ]);

    // 2. Connectivity & Reachability
    if (baseUrl.isNotEmpty) {
      await LikeConnectivityManager().init(serverUrl: baseUrl);
    }

    // 3. Client Singleton
    if (baseUrl.isNotEmpty) {
      LikeClient(
        baseUrl: baseUrl,
        timeout: Duration(seconds: LikeConstants.connectTimeout),
      );
    }

    // 4. Background Services
    await LikeBackgroundSyncService().init();
    LikeOfflineSyncManager().init();
  }

  static Box getBox(String name) {
    if (!Hive.isBoxOpen(name)) {
      throw StateError(
        'Hive box "$name" is not open. Call LikeService.init() first.',
      );
    }
    return Hive.box(name);
  }

  static Box get cacheBox => getBox(LikeConstants.boxApiCache);
  static Box get metadataBox => getBox(LikeConstants.boxCacheMetadata);
  static Box get etagBox => getBox(LikeConstants.boxEtags);
  static Box get boxOfflineQueue => getBox(LikeConstants.boxOfflineQueue);

  static Future<void> putEtag(String key, String etag) async {
    await etagBox.put(key, etag);
  }

  static String? getEtag(String key) => etagBox.get(key) as String?;

  static void deleteEtag(String key) => etagBox.delete(key);

  /// Fetches a [Response] from the L2 Hive cache if it exists and hasn't expired.
  ///
  /// Used internally by [LikeClient] during SWR and resiliency fallback cycles.
  static Future<Response?> fetchResponseFromCache(
    RequestOptions options,
  ) async {
    final key = options.uri.toString();
    final entry = cacheBox.get(key);

    if (entry != null && entry is Map) {
      final timestampStr = entry['timestamp'] as String?;
      final timestamp = DateTime.tryParse(timestampStr ?? '');
      if (timestamp == null) return null;

      final storageDurationMs =
          (entry['storageDurationMs'] as int?) ??
          (metadataBox.get(key) as int?);

      final maxAge = storageDurationMs != null
          ? Duration(milliseconds: storageDurationMs)
          : Duration(days: LikeConstants.cacheTTL);

      if (DateTime.now().difference(timestamp) > maxAge) return null;

      final dynamic rawData = entry['data'];
      dynamic decodedData;

      if (rawData is String &&
          rawData.length > LikeConstants.computeThreshold) {
        decodedData = await compute(LikeHelpers.parseJson, rawData);
      } else if (rawData is String) {
        decodedData = LikeHelpers.parseJson(rawData);
      } else {
        decodedData = LikeUtils.castToMapStringDynamic(rawData);
      }

      return Response(
        requestOptions: options,
        data: decodedData,
        statusCode: 200,
        extra: {'isFromCache': true, 'timestamp': entry['timestamp']},
      );
    }
    return null;
  }

  /// Persists a successful [Response] to the L2 Hive cache.
  ///
  /// Respects the `disableCache` flag in the request options.
  static Future<void> saveResponseToCache(Response response) async {
    final options = response.requestOptions;
    if (options.extra['disableCache'] == true) return;

    final key = options.uri.toString();
    final data = response.data;
    final timestamp = DateTime.now().toIso8601String();
    final storageDurationMs =
        (options.extra['cacheStorageDuration'] as Duration?)?.inMilliseconds;

    await cacheBox.put(key, {
      'data': data,
      'timestamp': timestamp,
      if (storageDurationMs != null) 'storageDurationMs': storageDurationMs,
    });
  }

  /// Global notifier for blocking synchronization events.
  /// The [Like] root wrapper listens to this by default.
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Sets the global syncing state.
  static void setSyncing(bool value) => isSyncing.value = value;
}
