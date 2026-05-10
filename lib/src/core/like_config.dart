import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_data_unpacker.dart';

/// Global configuration for the LIKE engine's behavior and caching system.
class LikeConfig {
  /// The primary base URL for all network requests.
  final String baseUrl;

  /// A map of alternative base URLs for multi-tenant or multi-service environments.
  final Map<String, String> extraBaseUrls;

  /// Maximum time to wait for a connection to be established.
  final Duration connectTimeout;

  /// Maximum time to wait for receiving a chunk of data from the server.
  final Duration receiveTimeout;

  /// Maximum time to wait for sending data to the server.
  final Duration sendTimeout;

  /// Timeout for the engine's initial setup and box opening.
  final Duration initTimeout;

  /// Timeout for connectivity reachability checks (e.g., pinging google.com).
  final Duration connTimeout;

  /// Debounce time in milliseconds for connectivity status changes to prevent flickering.
  final int connDebounceMs;

  /// Globally enables or disables the LIKE logging system.
  final bool enableLogging;

  /// If true, prevents logs from being printed to the system console.
  final bool silentConsole;

  /// If true, prevents logs related to background synchronization tasks.
  final bool silentSyncLogs;

  /// If true, simplifies API logs to a single line per request.
  final bool compactApiLogs;

  /// If true, hides logs indicating the start of an API request.
  final bool silentApiStartLogs;

  /// If true, disables writing logs to a local file for debugging.
  final bool disableFileLogging;

  /// Enables extremely detailed logs for internal engine cycles.
  final bool verboseLogging;

  /// List of HTTP headers that should be masked in logs for security (e.g., Authorization).
  final List<String> sensitiveHeaders;

  /// Threshold in KB above which JSON parsing will be offloaded to a background isolate.
  final int computeThresholdKB;

  /// Optional AES key for encrypting cached data on disk.
  final String? encryptionKey;

  /// An unpacker strategy used to extract domain data from standard API envelopes.
  final LikeDataUnpacker unpacker;

  /// Default HTTP headers to be included in every request.
  final Map<String, String> defaultHeaders;

  /// Whether to verify SSL certificates. Usually false in debug/development.
  final bool verifySSL;

  /// Optional SHA256 fingerprint for SSL pinning.
  final String sslCertSha256;

  // --- Feature Flags ---

  /// Enables the L2 (Disk) and L3 (SWR) caching systems globally.
  final bool cacheEnabled;

  /// Enables the Stale-While-Revalidate (SWR) background refresh logic.
  final bool staleWhileRevalidateEnabled;

  /// Enables request deduplication to prevent redundant concurrent calls.
  final bool deduplicateEnabled;

  /// Enables performance tracking for network requests and JSON parsing.
  final bool perfTrackingEnabled;

  /// Enables internal rate limiting to prevent API abuse.
  final bool rateLimitEnabled;

  /// Automatically retries requests that fail due to rate limiting (429).
  final bool autoRetryRateLimit;

  /// If true, the engine will intercept requests and return mock data if available.
  final bool mockEnabled;

  /// Enables request throttling to limit the frequency of identical calls.
  final bool throttleEnabled;

  /// Enables background refreshing of state without triggering UI loading indicators.
  final bool silentRefreshEnabled;

  // --- Resiliency ---

  /// If true, attempts to return cached data when the device is offline.
  final bool cacheOnOffline;

  /// If true, returns cached data when a server error (5xx) occurs.
  final bool cacheOnError;

  /// If true, returns cached data when a network exception (timeout, etc.) occurs.
  final bool cacheOnException;

  /// Maximum number of automatic retries for failed requests.
  final int maxAutoRetries;

  /// List of delays in seconds between consecutive retries (e.g., [1, 2, 4]).
  final List<int> retryDelays;

  /// Enables the offline queue for persisting mutation requests (POST/PUT/DELETE).
  final bool offlineSyncEnabled;

  /// Enables background synchronization tasks while the app is in the background.
  final bool backgroundSyncEnabled;

  // --- Default Flags (Per-Request Behavior) ---

  /// Whether to include authentication headers by default.
  final bool withAuthByDefault;

  /// Whether to queue mutation requests for offline sync by default.
  final bool offlineSyncByDefault;

  /// Whether to bypass the cache by default.
  final bool disableCacheByDefault;

  /// Whether to suppress logging for specific requests by default.
  final bool disableLoggerByDefault;

  /// Whether to suppress global error UI/toasts for failed requests by default.
  final bool suppressErrorsByDefault;

  /// Whether to enable SWR revalidation by default.
  final bool staleWhileRevalidateByDefault;

  /// Whether to use a short-lived "session cache" for this request by default.
  final bool sessionStaleByDefault;

  /// If true, ensures only one instance of this request type is active across the app.
  final bool singleFetchByDefault;

  /// Whether to force a network refresh and bypass cache by default.
  final bool refreshByDefault;

  /// Whether to trigger a "bottom" loading indicator for pagination by default.
  final bool bottomRefreshByDefault;

  /// Whether to perform a server health check before executing the request.
  final bool healthCheckByDefault;

  /// Whether to deduplicate identical concurrent requests by default.
  final bool deduplicateByDefault;

  // --- Cache Configuration ---

  /// Time-To-Live in days for data stored in the L2 (Disk) cache.
  final int cacheTTL;

  /// Maximum number of items to keep in the L1 (RAM) cache.
  final int maxL1CacheItems;

  /// Maximum number of concurrent network requests allowed.
  final int maxInFlightRequests;

  /// Time in minutes for which session-stale data is considered valid.
  final int sessionStaleTTL;

  /// Time in days after which cached images are considered stale.
  final int imageStalePeriod;

  /// Maximum number of images allowed in the persistent image cache.
  final int maxImageCacheItems;

  /// Maximum size in MB for the image cache on disk.
  final double maxImageCacheMB;

  /// Target size in MB to reach when cleaning up the image cache.
  final double minImageCacheMB;

  // --- Box Names ---

  /// Name of the Hive box for API response caching.
  final String boxApiCache;

  /// Name of the Hive box for the offline synchronization queue.
  final String boxOfflineQueue;

  /// Name of the Hive box for cache metadata and timestamps.
  final String boxCacheMetadata;

  /// Name of the Hive box for storing ETag values.
  final String boxEtags;

  // --- Misc ---

  /// Minimum duration in seconds to display the splash screen during init.
  final int minSplashDuration;

  /// Delay in seconds before redirecting to login after an auth failure.
  final int authRedirectDelay;

  /// Host used to check internet reachability (defaults to google.com).
  final String connCheckHost;

  LikeConfig({
    this.baseUrl = '',
    this.unpacker = const DefaultLikeUnpacker(),
    this.extraBaseUrls = const {},
    this.defaultHeaders = const {},
    this.connectTimeout = const Duration(seconds: 30),
    this.receiveTimeout = const Duration(seconds: 30),
    this.sendTimeout = const Duration(seconds: 30),
    this.initTimeout = const Duration(seconds: 15),
    this.connTimeout = const Duration(seconds: 5),
    this.connDebounceMs = 500,
    this.enableLogging = true,
    this.silentConsole = false,
    this.silentSyncLogs = false,
    this.compactApiLogs = false,
    this.silentApiStartLogs = false,
    this.disableFileLogging = false,
    this.verboseLogging = false,
    this.sensitiveHeaders = const ['Authorization', 'Cookie', 'Set-Cookie'],
    this.computeThresholdKB = 100,
    this.encryptionKey,
    bool? verifySSL,
    this.sslCertSha256 = '',
    this.cacheEnabled = true,
    this.staleWhileRevalidateEnabled = true,
    this.deduplicateEnabled = true,
    this.perfTrackingEnabled = true,
    this.rateLimitEnabled = true,
    this.autoRetryRateLimit = true,
    this.mockEnabled = false,
    this.throttleEnabled = true,
    this.silentRefreshEnabled = true,
    this.cacheOnOffline = false,
    this.cacheOnError = false,
    this.cacheOnException = false,
    this.maxAutoRetries = 3,
    this.retryDelays = const [1, 2, 4],
    this.offlineSyncEnabled = true,
    this.backgroundSyncEnabled = true,
    this.withAuthByDefault = true,
    this.offlineSyncByDefault = true,
    this.disableCacheByDefault = false,
    this.disableLoggerByDefault = false,
    this.suppressErrorsByDefault = true,
    this.staleWhileRevalidateByDefault = true,
    this.sessionStaleByDefault = false,
    this.singleFetchByDefault = false,
    this.refreshByDefault = false,
    this.bottomRefreshByDefault = false,
    this.healthCheckByDefault = false,
    this.deduplicateByDefault = true,
    this.cacheTTL = 7,
    this.maxL1CacheItems = 200,
    this.maxInFlightRequests = 100,
    this.sessionStaleTTL = 5,
    this.imageStalePeriod = 90,
    this.maxImageCacheItems = 5000,
    this.maxImageCacheMB = 500.0,
    this.minImageCacheMB = 400.0,
    this.boxApiCache = 'like_api_cache',
    this.boxOfflineQueue = 'like_offline_queue',
    this.boxCacheMetadata = 'like_cache_metadata',
    this.boxEtags = 'like_etags',
    this.minSplashDuration = 2,
    this.authRedirectDelay = 2,
    this.connCheckHost = 'google.com',
  }) : verifySSL = verifySSL ?? !kDebugMode;

  LikeConfig copyWith({
    String? baseUrl,
    LikeDataUnpacker? unpacker,
    Map<String, String>? extraBaseUrls,
    Map<String, String>? defaultHeaders,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    Duration? initTimeout,
    Duration? connTimeout,
    int? connDebounceMs,
    bool? enableLogging,
    bool? silentConsole,
    bool? silentSyncLogs,
    bool? compactApiLogs,
    bool? silentApiStartLogs,
    bool? disableFileLogging,
    bool? verboseLogging,
    List<String>? sensitiveHeaders,
    int? computeThresholdKB,
    String? encryptionKey,
    bool? verifySSL,
    String? sslCertSha256,
    bool? cacheEnabled,
    bool? staleWhileRevalidateEnabled,
    bool? deduplicateEnabled,
    bool? perfTrackingEnabled,
    bool? rateLimitEnabled,
    bool? autoRetryRateLimit,
    bool? mockEnabled,
    bool? throttleEnabled,
    bool? silentRefreshEnabled,
    bool? cacheOnOffline,
    bool? cacheOnError,
    bool? cacheOnException,
    int? maxAutoRetries,
    List<int>? retryDelays,
    bool? offlineSyncEnabled,
    bool? backgroundSyncEnabled,
    bool? withAuthByDefault,
    bool? offlineSyncByDefault,
    bool? disableCacheByDefault,
    bool? disableLoggerByDefault,
    bool? suppressErrorsByDefault,
    bool? staleWhileRevalidateByDefault,
    bool? sessionStaleByDefault,
    bool? singleFetchByDefault,
    bool? refreshByDefault,
    bool? bottomRefreshByDefault,
    bool? healthCheckByDefault,
    bool? deduplicateByDefault,
    int? cacheTTL,
    int? maxL1CacheItems,
    int? maxInFlightRequests,
    int? sessionStaleTTL,
    int? imageStalePeriod,
    int? maxImageCacheItems,
    double? maxImageCacheMB,
    double? minImageCacheMB,
    String? boxApiCache,
    String? boxOfflineQueue,
    String? boxCacheMetadata,
    String? boxEtags,
    int? minSplashDuration,
    int? authRedirectDelay,
    String? connCheckHost,
  }) {
    return LikeConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      unpacker: unpacker ?? this.unpacker,
      extraBaseUrls: extraBaseUrls ?? this.extraBaseUrls,
      defaultHeaders: defaultHeaders ?? this.defaultHeaders,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      sendTimeout: sendTimeout ?? this.sendTimeout,
      initTimeout: initTimeout ?? this.initTimeout,
      connTimeout: connTimeout ?? this.connTimeout,
      connDebounceMs: connDebounceMs ?? this.connDebounceMs,
      enableLogging: enableLogging ?? this.enableLogging,
      silentConsole: silentConsole ?? this.silentConsole,
      silentSyncLogs: silentSyncLogs ?? this.silentSyncLogs,
      compactApiLogs: compactApiLogs ?? this.compactApiLogs,
      silentApiStartLogs: silentApiStartLogs ?? this.silentApiStartLogs,
      disableFileLogging: disableFileLogging ?? this.disableFileLogging,
      verboseLogging: verboseLogging ?? this.verboseLogging,
      sensitiveHeaders: sensitiveHeaders ?? this.sensitiveHeaders,
      computeThresholdKB: computeThresholdKB ?? this.computeThresholdKB,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      verifySSL: verifySSL ?? this.verifySSL,
      sslCertSha256: sslCertSha256 ?? this.sslCertSha256,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      staleWhileRevalidateEnabled:
          staleWhileRevalidateEnabled ?? this.staleWhileRevalidateEnabled,
      deduplicateEnabled: deduplicateEnabled ?? this.deduplicateEnabled,
      perfTrackingEnabled: perfTrackingEnabled ?? this.perfTrackingEnabled,
      rateLimitEnabled: rateLimitEnabled ?? this.rateLimitEnabled,
      autoRetryRateLimit: autoRetryRateLimit ?? this.autoRetryRateLimit,
      mockEnabled: mockEnabled ?? this.mockEnabled,
      throttleEnabled: throttleEnabled ?? this.throttleEnabled,
      silentRefreshEnabled: silentRefreshEnabled ?? this.silentRefreshEnabled,
      cacheOnOffline: cacheOnOffline ?? this.cacheOnOffline,
      cacheOnError: cacheOnError ?? this.cacheOnError,
      cacheOnException: cacheOnException ?? this.cacheOnException,
      maxAutoRetries: maxAutoRetries ?? this.maxAutoRetries,
      retryDelays: retryDelays ?? this.retryDelays,
      offlineSyncEnabled: offlineSyncEnabled ?? this.offlineSyncEnabled,
      backgroundSyncEnabled:
          backgroundSyncEnabled ?? this.backgroundSyncEnabled,
      withAuthByDefault: withAuthByDefault ?? this.withAuthByDefault,
      offlineSyncByDefault: offlineSyncByDefault ?? this.offlineSyncByDefault,
      disableCacheByDefault:
          disableCacheByDefault ?? this.disableCacheByDefault,
      disableLoggerByDefault:
          disableLoggerByDefault ?? this.disableLoggerByDefault,
      suppressErrorsByDefault:
          suppressErrorsByDefault ?? this.suppressErrorsByDefault,
      staleWhileRevalidateByDefault:
          staleWhileRevalidateByDefault ?? this.staleWhileRevalidateByDefault,
      sessionStaleByDefault:
          sessionStaleByDefault ?? this.sessionStaleByDefault,
      singleFetchByDefault: singleFetchByDefault ?? this.singleFetchByDefault,
      refreshByDefault: refreshByDefault ?? this.refreshByDefault,
      bottomRefreshByDefault:
          bottomRefreshByDefault ?? this.bottomRefreshByDefault,
      healthCheckByDefault: healthCheckByDefault ?? this.healthCheckByDefault,
      deduplicateByDefault: deduplicateByDefault ?? this.deduplicateByDefault,
      cacheTTL: cacheTTL ?? this.cacheTTL,
      maxL1CacheItems: maxL1CacheItems ?? this.maxL1CacheItems,
      maxInFlightRequests: maxInFlightRequests ?? this.maxInFlightRequests,
      sessionStaleTTL: sessionStaleTTL ?? this.sessionStaleTTL,
      imageStalePeriod: imageStalePeriod ?? this.imageStalePeriod,
      maxImageCacheItems: maxImageCacheItems ?? this.maxImageCacheItems,
      maxImageCacheMB: maxImageCacheMB ?? this.maxImageCacheMB,
      minImageCacheMB: minImageCacheMB ?? this.minImageCacheMB,
      boxApiCache: boxApiCache ?? this.boxApiCache,
      boxOfflineQueue: boxOfflineQueue ?? this.boxOfflineQueue,
      boxCacheMetadata: boxCacheMetadata ?? this.boxCacheMetadata,
      boxEtags: boxEtags ?? this.boxEtags,
      minSplashDuration: minSplashDuration ?? this.minSplashDuration,
      authRedirectDelay: authRedirectDelay ?? this.authRedirectDelay,
      connCheckHost: connCheckHost ?? this.connCheckHost,
    );
  }

  bool get disableLogger => !enableLogging;
}
