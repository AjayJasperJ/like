import 'dart:async';
import 'package:like/src/core/like_session_scope.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/core/like_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_offline_sync_manager.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:like/src/services/like_utils.dart';
import 'package:like/src/services/app_cache_manager.dart';
import 'package:like/src/debug/like_suggestions.dart';

/// Diagnostic status of LIKE's persistent Hive storage backend.
enum LikeStorageStatus {
  /// [LikeService.init] has not run yet.
  uninitialized,

  /// Persistent Hive boxes are open and usable.
  available,

  /// Persistent cache was disabled via `LikeConfig.cacheEnabled = false`.
  disabled,

  /// Storage initialization exceeded `LikeConfig.initTimeout`.
  timedOut,

  /// Storage initialization failed (e.g. WASM `UnimplementedError` or blocked IndexedDB).
  unavailable,
}

/// Low-level service for interacting with LIKE's persistent Hive boxes.
/// Handles caching, ETags, and the offline queue.
/// Matches enterprise's NetworkBoxService parity.
class LikeService {
  static final Set<String> _invalidatedKeys = {};
  static final Map<String, int> _keyInvalidationGenerations = {};
  static int _invalidationGeneration = 0;
  static bool _initialized = false;
  static bool _storageAvailable = false;
  static LikeStorageStatus _storageStatus = LikeStorageStatus.uninitialized;
  static Object? _storageError;

  /// Whether LIKE's persistent Hive boxes are available for this process.
  ///
  /// Network requests remain usable when this is false; cache and durable
  /// offline replay are skipped.
  static bool get storageAvailable => _storageAvailable;

  /// Detailed capability status of persistent storage for diagnostics and UI.
  static LikeStorageStatus get storageStatus => _storageStatus;

  /// The last storage initialization error, if [_storageStatus] is
  /// [LikeStorageStatus.timedOut] or [LikeStorageStatus.unavailable].
  static Object? get storageError => _storageError;

  /// Resets [LikeService] lifecycle state. Primarily used in tests and logout/re-init flows.
  @visibleForTesting
  static Future<void> reset({bool closeBoxes = false}) async {
    _initialized = false;
    _storageAvailable = false;
    _storageStatus = LikeStorageStatus.uninitialized;
    _storageError = null;
    _invalidatedKeys.clear();
    _keyInvalidationGenerations.clear();
    _invalidationGeneration = 0;
    LikeOfflineSyncManager().dispose();
    if (closeBoxes) {
      await Hive.close();
    }
  }

  /// Initializes the LIKE engine and its persistent storage.
  ///
  /// This must be called before using any [LikeClient] or builders.
  /// It opens the necessary Hive boxes and configures global [LikeConstants].
  ///
  /// [baseUrl] (optional) can be set here or via [LikeClient].
  /// Numerous optional parameters allow fine-tuning the engine's behavior
  /// (timeouts, cache TTLs, logging levels, etc.).
  static Future<void> init({required LikeConfig config}) async {
    void logDebug(String msg) {
      if (config.verboseLogging && !config.silentConsole) {
        debugPrint(msg);
      }
    }

    if (_initialized) {
      LikeConstants.apply(config);
      await _configureStorage(config, logDebug);
      if (config.baseUrl.isNotEmpty) {
        await LikeConnectivityManager().init(serverUrl: config.baseUrl);
        LikeClient(
          baseUrl: config.baseUrl,
          timeout: Duration(seconds: LikeConstants.connectTimeout),
        ).updateBaseUrl(config.baseUrl);
      }
      if (_storageAvailable && config.offlineSyncEnabled) {
        LikeOfflineSyncManager().init();
      } else {
        LikeOfflineSyncManager().dispose();
      }
      return;
    }

    final baseUrl = config.baseUrl;

    logDebug('DEBUG: LikeService.init config: ${config.baseUrl}');
    // 0. Apply config settings to LikeConstants and init logger/error handling
    LikeConstants.apply(config);
    await LikeLogger.init();
    LikeLogger.initGlobalErrorHandling();

    // 1. Core Storage
    await _configureStorage(config, logDebug);

    // 2. Connectivity & Reachability
    if (baseUrl.isNotEmpty) {
      logDebug('DEBUG: LikeConnectivityManager.init starting for $baseUrl');
      await LikeConnectivityManager().init(serverUrl: baseUrl);
      logDebug('DEBUG: LikeConnectivityManager.init completed');
    }

    // 3. Client Singleton
    if (baseUrl.isNotEmpty) {
      LikeClient(
        baseUrl: baseUrl,
        timeout: Duration(seconds: LikeConstants.connectTimeout),
      );
    }

    // 4. Background Services & Cache Managers
    // Removed workmanager dependency
    if (_storageAvailable && config.offlineSyncEnabled) {
      LikeOfflineSyncManager().init();
    }

    // Ensure the disk image cache respects the configured limits on startup
    if (!kIsWeb && config.cacheEnabled && _storageAvailable) {
      try {
        await AppCacheManager().pruneCacheIfExceedsSize();
      } catch (_) {}
    }

    _initialized = true;

    if (kDebugMode && config.verboseLogging && !config.silentConsole) {
      printRandomSuggestion();
    }
  }

  static Future<void> _configureStorage(
    LikeConfig config,
    void Function(String) logDebug,
  ) async {
    if (!config.cacheEnabled) {
      _storageAvailable = false;
      _storageStatus = LikeStorageStatus.disabled;
      _storageError = null;
      return;
    }

    try {
      logDebug('DEBUG: Hive.initFlutter starting');
      final projectNamespace = LikeConstants.projectName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
      await Hive.initFlutter(projectNamespace).timeout(config.initTimeout);
      logDebug('DEBUG: Hive.initFlutter completed');

      logDebug('DEBUG: Opening Hive boxes starting');
      await Future.wait([
        Hive.openBox(LikeConstants.boxApiCache),
        Hive.openBox(LikeConstants.boxCacheMetadata),
        Hive.openBox(LikeConstants.boxEtags),
        Hive.openBox(LikeConstants.boxOfflineQueue),
      ]).timeout(config.initTimeout);
      _storageAvailable = true;
      _storageStatus = LikeStorageStatus.available;
      _storageError = null;
      logDebug('DEBUG: Opening Hive boxes completed');
    } on TimeoutException catch (error, stackTrace) {
      _storageAvailable = false;
      _storageStatus = LikeStorageStatus.timedOut;
      _storageError = error;
      if (kDebugMode) {
        debugPrint(
          'LIKE persistent storage timed out after ${config.initTimeout}; using network-only mode: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    } catch (error, stackTrace) {
      _storageAvailable = false;
      _storageStatus = LikeStorageStatus.unavailable;
      _storageError = error;
      if (kDebugMode) {
        debugPrint(
          'LIKE persistent storage unavailable; using network-only mode: $error',
        );
        debugPrintStack(stackTrace: stackTrace);
      }
    }
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
    if (!Hive.isBoxOpen(LikeConstants.boxEtags)) return;
    await etagBox.put(key, etag);
  }

  static String? getEtag(String key) {
    if (!Hive.isBoxOpen(LikeConstants.boxEtags)) return null;
    return etagBox.get(key) as String?;
  }

  static void deleteEtag(String key) {
    if (!Hive.isBoxOpen(LikeConstants.boxEtags)) return;
    etagBox.delete(key);
  }

  /// Fetches a [Response] from the L2 Hive cache if it exists and hasn't expired.
  ///
  /// Used internally by [LikeClient] during SWR and resiliency fallback cycles.
  static Future<Response?> fetchResponseFromCache(
    RequestOptions options,
  ) async {
    if (!Hive.isBoxOpen(LikeConstants.boxApiCache)) return null;
    final key = LikeSessionIdentity.forRequest(options);
    if (_invalidatedKeys.contains(key)) return null;
    final entry = cacheBox.get(key);

    if (entry != null && entry is Map) {
      final timestampStr = entry['timestamp'] as String?;
      final timestamp = DateTime.tryParse(timestampStr ?? '');
      if (timestamp == null) return null;

      final storageDurationMs =
          (entry['storageDurationMs'] as int?) ??
          (Hive.isBoxOpen(LikeConstants.boxCacheMetadata)
              ? (metadataBox.get(key) as int?)
              : null);

      final maxAge = storageDurationMs != null
          ? Duration(milliseconds: storageDurationMs)
          : Duration(days: LikeConstants.cacheTTL);

      if (DateTime.now().difference(timestamp) > maxAge) return null;

      final dynamic rawData = entry['data'];
      dynamic decodedData;

      if (entry['formatVersion'] == 2) {
        decodedData = rawData is Map
            ? LikeUtils.castToMapStringDynamic(rawData)
            : rawData;
      } else if (rawData is String &&
          rawData.length > LikeConstants.computeThreshold) {
        decodedData = await compute(LikeHelpers.parseJson, rawData);
      } else if (rawData is String) {
        decodedData = LikeHelpers.parseJson(rawData);
      } else if (rawData is List) {
        // Preserve list responses (e.g. GET /posts returns List<dynamic>)
        decodedData = rawData;
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

  /// Returns the current invalidation generation for [key] (0 if never invalidated).
  static int generationForKey(String key) => _keyInvalidationGenerations[key] ?? 0;

  /// Records that [keys] were invalidated so older in-flight responses cannot
  /// promote stale data into L1 or L2 caches.
  static void markKeysInvalidated(Iterable<String> keys) {
    if (keys.isEmpty) return;
    final gen = ++_invalidationGeneration;
    for (final key in keys) {
      _keyInvalidationGenerations.remove(key);
      _keyInvalidationGenerations[key] = gen;
    }
    while (_keyInvalidationGenerations.length > 1000) {
      _keyInvalidationGenerations.remove(_keyInvalidationGenerations.keys.first);
    }
  }

  /// Persists a successful [Response] to the L2 Hive cache.
  ///
  /// Respects the `disableCache` flag in the request options.
  static Future<void> saveResponseToCache(Response response) async {
    if (!Hive.isBoxOpen(LikeConstants.boxApiCache)) return;
    final options = response.requestOptions;
    if (options.extra['disableCache'] == true) return;

    final key = LikeSessionIdentity.forRequest(options);
    if (_invalidatedKeys.contains(key)) return;
    final startGen = options.extra['like.cacheGeneration'] as int?;
    if (startGen != null && startGen < generationForKey(key)) return;
    final data = response.data;
    final timestamp = DateTime.now().toIso8601String();
    final storageDurationMs =
        (options.extra['cacheStorageDuration'] as Duration?)?.inMilliseconds;

    await cacheBox.put(key, {
      'formatVersion': 2,
      'scope': options.extra[LikeSessionIdentity.scopeKey] ?? '',
      'origin': options.uri.hasAuthority ? options.uri.origin : '',
      'tags': options.extra['like.cacheTags'] ?? const <String>[],
      'data': data,
      'timestamp': timestamp,
      'storageDurationMs': ?storageDurationMs,
    });
    _invalidatedKeys.remove(key);
  }

  static Future<Set<String>> invalidateTags(
    Set<String> tags,
    String scope,
    String origin,
  ) async {
    if (!Hive.isBoxOpen(LikeConstants.boxApiCache) || cacheBox.isEmpty) {
      return {};
    }
    final keys = <String>{};
    for (final key in cacheBox.keys) {
      final entry = cacheBox.get(key);
      if (entry is Map &&
          (entry['scope'] ?? '') == scope &&
          entry['origin'] == origin &&
          (entry['tags'] as List? ?? const []).any(tags.contains)) {
        keys.add(key.toString());
      }
    }
    _invalidatedKeys.addAll(keys);
    markKeysInvalidated(keys);
    await cacheBox.deleteAll(keys);
    if (Hive.isBoxOpen(LikeConstants.boxCacheMetadata)) {
      await metadataBox.deleteAll(keys);
    }
    if (Hive.isBoxOpen(LikeConstants.boxEtags)) await etagBox.deleteAll(keys);
    _invalidatedKeys.removeAll(keys);
    return keys;
  }

  /// Global notifier for blocking synchronization events.
  /// The [Like] root wrapper listens to this by default.
  static final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  /// Sets the global syncing state.
  static void setSyncing(bool value) => isSyncing.value = value;
}
