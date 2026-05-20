import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_config.dart';

/// Centralized configuration and constants for the LIKE networking engine.
/// Provides production-grade networking configuration parity.
///
/// All values are read-only and must be configured via [LikeService.init]
/// or [LikeConstants.apply].
class LikeConstants {
  static LikeConfig _config = LikeConfig();

  /// Returns the current global configuration.
  static LikeConfig get current => _config;

  /// Updates the global engine configuration. This is the only way to modify constants.
  static void apply(LikeConfig config) {
    _config = config;
  }

  /// Resets the global configuration to defaults.
  ///
  /// Use in [setUp]/[tearDown] in tests to prevent config bleed between test cases.
  @visibleForTesting
  static void reset() => _config = LikeConfig();

  // --- Logs ---

  /// Whether to log full API success and error responses to the console.
  static bool get logApiResponses => _config.enableLogging;

  /// If true, disables all console logging from the LIKE package.
  static bool get silentConsole => _config.silentConsole;

  /// If true, disables logs related to background synchronization and connectivity tasks.
  static bool get silentSyncLogs => _config.silentSyncLogs;

  /// If true, uses a compact, one-liner format for API request/response logs.
  static bool get compactApiLogs => _config.compactApiLogs;

  /// If true, suppresses logs indicating when an API request has started.
  static bool get silentApiStartLogs => _config.silentApiStartLogs;

  /// Disables writing network and sync logs to persistent file storage.
  static bool get disableFileLogging => _config.disableFileLogging;

  // --- Feature Flags ---

  /// Enables advanced debugging features and highly verbose error reporting.
  static bool get debugMode => _config.verboseLogging; // Mapped to verbose

  /// Enables SSL certificate pinning and validation. Usually disabled in debug mode.
  static bool get verifySSL => _config.verifySSL;

  /// Global flag to allow or disallow queuing requests when the device is offline.
  static bool get offlineSyncEnabled => _config.offlineSyncEnabled;

  /// Enables background processing of synchronization tasks via the sync manager.
  static bool get backgroundSyncEnabled => _config.backgroundSyncEnabled;

  /// Enables the multi-layer (Memory/Persistent) caching system.
  static bool get cacheEnabled => _config.cacheEnabled;

  /// Enables the Stale-While-Revalidate strategy for serving cached data while fetching updates.
  static bool get staleWhileRevalidateEnabled =>
      _config.staleWhileRevalidateEnabled;

  /// Enables highly detailed internal logs for the networking engine's lifecycle.
  static bool get verboseLogging => _config.verboseLogging;

  /// If true, uses mock interceptors to return simulated data instead of making network calls.
  static bool get mockEnabled => _config.mockEnabled;

  /// Enables request throttling to prevent rapid, accidental duplicate requests.
  static bool get throttleEnabled => _config.throttleEnabled;

  /// Enables intelligent request deduplication for identical concurrent network calls.
  static bool get deduplicateEnabled => _config.deduplicateEnabled;

  /// Enables background data refreshing without showing global loading indicators.
  static bool get silentRefreshEnabled => _config.silentRefreshEnabled;

  /// Enables latency, throughput, and payload size tracking for all network requests.
  static bool get perfTrackingEnabled => _config.perfTrackingEnabled;

  /// Enables automatic detection and handling of 429 Rate Limit responses.
  static bool get rateLimitEnabled => _config.rateLimitEnabled;

  /// Automatically retries requests that hit rate limits after the suggested 'Retry-After' delay.
  static bool get autoRetryRateLimit => _config.autoRetryRateLimit;

  // --- Resiliency Flags ---

  /// Whether to automatically serve cached data when a request is made while offline.
  static bool get cacheOnOffline => _config.cacheOnOffline;

  /// Serves stale cache data as a resiliency fallback when a request fails with a network error.
  static bool get cacheOnError => _config.cacheOnError;

  /// Serves stale cache data when a request fails due to an unexpected code exception.
  static bool get cacheOnException => _config.cacheOnException;

  // --- Default Request Options ---

  /// The default 'Accept' header value for all outgoing requests.
  static String get defaultAcceptHeader => 'application/json';

  /// The default 'Content-Type' header value for all outgoing requests.
  static String get defaultContentTypeHeader => 'application/json';

  /// Whether requests include authentication headers by default.
  static bool get withAuthByDefault => _config.withAuthByDefault;

  /// Whether requests are added to the offline sync queue by default if they fail.
  static bool get offlineSyncByDefault => _config.offlineSyncByDefault;

  /// If true, requests will bypass the cache layer by default unless specified otherwise.
  static bool get disableCacheByDefault => _config.disableCacheByDefault;

  /// If true, request and response logging is disabled for all calls by default.
  static bool get disableLoggerByDefault => _config.disableLoggerByDefault;

  /// If true, forces a fresh fetch even for endpoints marked for single-fetch logic.
  static bool get resetSingleFetchByDefault => false; // not reset by default

  /// If true, resets the session-stale state for an endpoint on every new call.
  static bool get resetSessionStaleByDefault => false; // not reset by default

  /// If true, non-critical errors are suppressed and managed through the state engine.
  static bool get suppressErrorsByDefault => _config.suppressErrorsByDefault;

  /// Default configuration for Stale-While-Revalidate behavior on all requests.
  static bool get staleWhileRevalidateByDefault =>
      _config.staleWhileRevalidateByDefault;

  /// Whether to consider requests stale within the same session by default.
  static bool get sessionStaleByDefault => _config.sessionStaleByDefault;

  /// Only allows one successful fetch for a specific endpoint per application session.
  static bool get singleFetchByDefault => _config.singleFetchByDefault;

  /// Forces a fresh network request, bypassing any existing cache, by default.
  static bool get refreshByDefault => _config.refreshByDefault;

  /// Used for secondary/bottom-loading pagination patterns by default.
  static bool get bottomRefreshByDefault => _config.bottomRefreshByDefault;

  /// Enables an explicit connectivity health check before initiating a network request.
  static bool get healthCheckByDefault => _config.healthCheckByDefault;

  /// Whether to deduplicate concurrent identical requests by default.
  static bool get deduplicateByDefault => _config.deduplicateByDefault;

  // --- Timeout Durations (Seconds) ---

  /// Timeout for establishing an initial connection with the server.
  static int get connectTimeout => _config.connectTimeout.inSeconds;

  /// Timeout for receiving the full response body from the server.
  static int get receiveTimeout => _config.receiveTimeout.inSeconds;

  /// Timeout for sending the request data to the server.
  static int get sendTimeout => _config.sendTimeout.inSeconds;

  /// Timeout for the initial setup and configuration of the networking engine.
  static int get initTimeout => _config.initTimeout.inSeconds;

  /// Timeout for checking internet reachability during connectivity health checks.
  static int get connTimeout => _config.connTimeout.inSeconds;

  /// Debounce duration for connectivity change events to prevent flapping (milliseconds).
  static int get connDebounceMs => _config.connDebounceMs;

  // --- Misc Configuration ---

  /// The host used to verify internet reachability during health checks.
  static String get connCheckHost => _config.connCheckHost;

  // --- Retry Configuration ---

  /// Maximum number of automatic retries for failed network requests.
  static int get maxAutoRetries => _config.maxAutoRetries;

  /// List of delays in seconds between successive automatic retry attempts.
  static List<int> get retryDelays => _config.retryDelays;

  // --- Cache Configuration ---

  /// Time-to-live for cached API responses (in days).
  static int get cacheTTL => _config.cacheTTL;

  /// Maximum number of items kept in the fast, in-memory (L1) cache.
  static int get maxL1CacheItems => _config.maxL1CacheItems;

  /// Maximum number of concurrent network requests allowed globally.
  static int get maxInFlightRequests => _config.maxInFlightRequests;

  /// Duration after which data is considered stale within an application session (seconds).
  static int get sessionStaleTTL => _config.sessionStaleTTL;

  // --- Universal Image Cache Configuration ---

  /// Retention period for cached images in days.
  static int get imageStalePeriod => _config.imageStalePeriod;

  /// Maximum number of unique images to store in the persistent cache.
  static int get maxImageCacheItems => _config.maxImageCacheItems;

  /// Maximum allowed storage size for the image cache in megabytes.
  static double get maxImageCacheMB => _config.maxImageCacheMB;

  /// Target storage size (MB) to reach when performing image cache cleanup.
  static double get minImageCacheMB => _config.minImageCacheMB;

  // --- Security ---

  /// SHA-256 fingerprint for SSL certificate pinning.
  static String get sslCertSha256 => _config.sslCertSha256;

  // --- Performance Thresholds ---

  /// Payload size threshold (in bytes) above which parsing is moved to a background isolate.
  static int get computeThreshold => _config.computeThresholdKB * 1024;

  // --- Hive Box Names (LIKE Prefixed) ---

  /// Hive box name for storing API response cache data.
  static String get boxApiCache => _config.boxApiCache;

  /// Hive box name for the offline request persistent queue.
  static String get boxOfflineQueue => _config.boxOfflineQueue;

  /// Hive box name for tracking cache lifecycle and expiration metadata.
  static String get boxCacheMetadata => _config.boxCacheMetadata;

  /// Hive box name for storing ETag headers for 304 Not Modified validation.
  static String get boxEtags => _config.boxEtags;
}
