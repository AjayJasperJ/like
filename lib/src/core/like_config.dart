import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_data_unpacker.dart';

/// Global configuration for the LIKE engine's behavior and caching system.
class LikeConfig {
  /// The name of the project. Used as a namespace prefix for storage, cache
  /// directories, and Hive boxes.
  final String projectName;

  /// The main web address (API root URL) that your app talks to.
  ///
  /// **Example:** If you set this to `https://api.example.com`, all your API
  /// requests will start with this URL (e.g. fetching `/profile` will call `https://api.example.com/profile`).
  final String baseUrl;

  /// Extra web addresses you can use if your app talks to multiple different servers.
  ///
  /// **Example:** You might have your main server at [baseUrl], but keep your chat server
  /// at `https://chat.example.com` or your payment server at `https://pay.example.com`.
  /// You map them like: `{'chat': 'https://chat.example.com'}`.
  final Map<String, String> extraBaseUrls;

  /// How long the app should wait to establish a connection with the server before giving up.
  ///
  /// **Analogy:** If you dial a friend's phone number, how long will you let it ring
  /// before hanging up? If they don't pick up within this time, your app will trigger a "Connection Timeout" error.
  final Duration connectTimeout;

  /// How long the app should wait to receive data from the server once a connection is made.
  ///
  /// **Analogy:** Once your friend picks up the phone, how long are you willing to wait for
  /// them to start speaking or send the next sentence? If the server goes completely silent mid-response
  /// for longer than this duration, your app will trigger a "Receive Timeout" error.
  final Duration receiveTimeout;

  /// How long the app should wait while sending data (like uploading a file or photo) to the server.
  ///
  /// **Analogy:** How long are you willing to wait for a large package you sent by mail to be
  /// delivered to the recipient? If your phone takes too long to upload a post payload, this triggers a "Send Timeout".
  final Duration sendTimeout;

  /// How long the engine is allowed to take to set up and open its local databases (Hive) when the app starts.
  ///
  /// If your app takes longer than this duration to open local storage boxes at startup, it will fail with an error.
  final Duration initTimeout;

  /// How long to wait when doing a real-world internet check (like pinging a reliable website).
  ///
  /// Rationale: Sometimes your device says it is connected to Wi-Fi, but that Wi-Fi has no actual internet.
  /// We do a quick background ping to check, and this is the maximum time we wait for that ping to respond.
  final Duration connTimeout;

  /// The wait time (in milliseconds) before acting on a change in your internet connection.
  ///
  /// **Why it's useful:** When a user walks out of their house, their phone might rapidly switch
  /// back and forth between Wi-Fi and mobile data. This "debounce" waits a split second to make sure
  /// the connection is stable before triggering UI alerts or reconnection workflows.
  final int connDebounceMs;

  /// The master switch to turn the console logging system ON or OFF.
  ///
  /// When set to `true`, the LIKE package prints green/red messages in your terminal
  /// explaining exactly what requests are being sent, what cache is loaded, and any errors.
  final bool enableLogging;

  /// Suppresses all logs in the console, even if [enableLogging] is `true`.
  ///
  /// Useful in production releases when you want a completely clean console with no debug messages.
  final bool silentConsole;

  /// Hides background logs related to internet checks and sync actions.
  ///
  /// When set to `true`, this keeps your terminal focused on active foreground screen actions
  /// instead of repetitive background loops.
  final bool silentSyncLogs;

  /// Condenses all network request logs into a single clean line in your terminal.
  ///
  /// When `true`, instead of printing multiple lines of request and response details, it prints
  /// a simple: `[GET] 200 OK - /users/profile`, which is much easier to scan.
  final bool compactApiLogs;

  /// Hides logs that print the exact millisecond a request is initiated.
  ///
  /// Set this to `true` if you only want to see logs when requests succeed or fail,
  /// reducing noise when multiple calls are fired in parallel.
  final bool silentApiStartLogs;

  /// Disables writing log files to the physical device's storage.
  ///
  /// When `true`, no log files are saved to the device disk. This is highly recommended
  /// for production apps to save disk space and improve security.
  final bool disableFileLogging;

  /// Enables extremely deep, detailed logs for internal developer debugging.
  ///
  /// Shows everything under the hood: when a RAM cache gets saved, when a database write is successful,
  /// and microsecond timers for parser execution.
  final bool verboseLogging;

  /// List of headers (like password tokens or auth keys) that should be hidden/masked in logs.
  ///
  /// **Why it's crucial:** Prevents passwords or sensitive user credentials (like `Authorization` headers)
  /// from being printed out in plain text or saved to debug files.
  final List<String> sensitiveHeaders;

  /// The threshold size (in Kilobytes) above which JSON parsing is offloaded to a background thread.
  ///
  /// **Analogy:** If you have a small grocery bag (small JSON), you can carry it in your hand (UI thread).
  /// If you have a massive furniture box (huge JSON response), you should get a helper to carry it (background Isolate)
  /// so you don't stutter or freeze your application's UI frames.
  final int computeThresholdKB;

  /// A helper class that unpacks your JSON responses and extracts only the relevant data.
  ///
  /// **Example:** Often, servers wrap lists in envelopes like: `{"status": true, "data": [...your list...]}`.
  /// The unpacker automatically strips away the status envelope and hands you just `[...your list...]`.
  final LikeDataUnpacker unpacker;

  /// HTTP Headers that are automatically added to every single outgoing request.
  ///
  /// Useful for global identifiers like client platform version tags (e.g. `{'X-App-Platform': 'Flutter'}`).
  final Map<String, String> defaultHeaders;

  /// Whether to verify SSL/TLS security certificates of the servers you connect to.
  ///
  /// **Tip:** Keep this `true` for production. You can set it to `false` in local debug/development environments
  /// if your local mock API server does not have a verified security certificate.
  final bool verifySSL;

  /// The secure fingerprint string of your server's certificate used for "SSL Pinning".
  ///
  /// **What it does:** Guarantees that the app will *only* talk to your exact server. If a hacker attempts
  /// to intercept your app's network using a malicious proxy, the app detects a certificate mismatch and blocks the connection.
  final String sslCertSha256;

  // --- Feature Flags ---

  /// Globally turns the caching system ON or OFF.
  ///
  /// If set to `false`, all cache layers are ignored. Every single request will bypass storage and hit the network.
  final bool cacheEnabled;

  /// Master switch to enable the "Stale-While-Revalidate" (SWR) cache flow globally.
  ///
  /// **How it works:** When enabled, the app instantly shows the user their last stored cached data (even if it's old),
  /// and silently fetches the fresh data from the internet in the background to update the screen. Extremely fast user experience!
  final bool staleWhileRevalidateEnabled;

  /// Automatically groups identical network requests made at the exact same moment.
  ///
  /// **Example:** If two widgets on your screen request the user's profile at the exact same time, the app only
  /// makes one call to the internet and shares the response with both widgets, saving data and bandwidth.
  final bool deduplicateEnabled;

  /// Turns performance benchmark tracking ON or OFF globally.
  ///
  /// When `true`, the engine measures and reports how long each network request and parsing cycle takes,
  /// helping you find bottlenecks in your app.
  final bool perfTrackingEnabled;

  /// Prevents your app from spamming your API server with too many requests.
  ///
  /// Limits how frequently your app can call the same endpoint to protect servers from overload.
  final bool rateLimitEnabled;

  /// Automatically handles "Too Many Requests" (HTTP 429) errors from the server.
  ///
  /// If the server tells the app it is calling too fast, the app will read the server's `Retry-After` header,
  /// wait the exact amount of seconds requested, and automatically retry the call.
  final bool autoRetryRateLimit;

  /// Simulates internet responses using offline mock data files.
  ///
  /// When `true`, requests intercept their calls and return local simulation mock files instead of going to the actual internet.
  /// Excellent for testing when your backend server is down or still being built.
  final bool mockEnabled;

  /// Blocks consecutive identical requests fired in a tiny split second.
  ///
  /// **Example:** Prevents issues caused when a user accidentally double-taps a "Submit" button by blocking
  /// the second tap's request from sending.
  final bool throttleEnabled;

  /// Keeps background revalidation silent and seamless for the user.
  ///
  /// When `true`, background updates (like SWR refreshes) happen invisibly. The user does not see visual loading spinners
  /// or screen flickers while the data updates.
  final bool silentRefreshEnabled;

  // --- Resiliency ---

  /// Immediately falls back to your local cache if the user makes a request while offline.
  ///
  /// Instead of showing an offline error screen, the user will still see their cached data, keeping the app functional.
  final bool cacheOnOffline;

  /// Falls back to your local cache if the server crashes (5xx errors).
  ///
  /// If your server goes down, the app displays the last successfully cached data instead of a blank crash screen.
  final bool cacheOnError;

  /// Falls back to your local cache if a request fails due to an exception (like a network timeout).
  ///
  /// Displays stored data rather than a generic timeout error screen.
  final bool cacheOnException;

  /// The maximum number of times the app will automatically retry a failed request before finally giving up.
  final int maxAutoRetries;

  /// The delay times (in seconds) between each automatic retry attempt.
  ///
  /// **Example:** If set to `[1, 2, 4]`, the app waits 1 second before the 1st retry, 2 seconds before the 2nd retry,
  /// and 4 seconds before the 3rd retry. This exponential backup avoids spamming a recovering server.
  final List<int> retryDelays;

  /// Enables background connectivity checks after ambiguous terminal transport failures.
  ///
  /// These checks are fire-and-forget and never delay or replace the original
  /// request failure.
  final bool automaticConnectivityChecksEnabled;

  /// Minimum delay between automatic failure-triggered checks for one origin.
  ///
  /// Explicit checks are not throttled by this cooldown.
  final Duration automaticFailureCheckCooldown;

  /// Enables the persistent "Offline Action Sync Queue" globally.
  ///
  /// **How it works:** If a user performs an action that changes data (like "Liking" a post) while offline,
  /// the action is saved locally. The moment the phone gets internet again, the app sends the action to the server in the background.
  final bool offlineSyncEnabled;

  /// Allows background sync tasks to run even when the user closes or minimizes the app.
  ///
  /// Dispatches the offline sync queue and refreshes critical caches in the background so the app is up-to-date when reopened.
  final bool backgroundSyncEnabled;

  // --- Default Flags (Per-Request Behavior) ---

  /// Attaches authorization/login headers to requests by default.
  final bool withAuthByDefault;

  /// Legacy configuration hook for mutation replay defaults.
  ///
  /// The built-in mutation APIs intentionally require a request-local explicit
  /// opt-in, so the package default is `false`.
  final bool offlineSyncByDefault;

  /// Bypasses the cache and goes directly to the internet by default for all requests.
  final bool disableCacheByDefault;

  /// Turns off terminal logging for all requests by default.
  final bool disableLoggerByDefault;

  /// Prevents the app from showing automatic error popup toasts or alerts when a request fails by default.
  final bool suppressErrorsByDefault;

  /// Enforces Stale-While-Revalidate (SWR) behavior by default for all GET requests.
  final bool staleWhileRevalidateByDefault;

  /// Saves request results in fast RAM memory for the current session by default.
  ///
  /// The app will fetch the data once, and subsequent calls in the same session return it instantly from RAM with no network call.
  final bool sessionStaleByDefault;

  /// Restricts endpoints to be called exactly once per session by default, ignoring subsequent requests.
  final bool singleFetchByDefault;

  /// Ignores all cache levels and forces a hard internet refresh on every request by default.
  final bool refreshByDefault;

  /// Displays a subtle pagination-friendly loading indicator (like a bottom spinner) instead of a full-screen loading spinner.
  final bool bottomRefreshByDefault;

  /// Performs a pre-flight internet check to ensure the server is fully reachable before attempting the network call by default.
  final bool healthCheckByDefault;

  /// Groups identical concurrent requests together by default across the entire app.
  final bool deduplicateByDefault;

  // --- Cache Configuration ---

  /// How many days cached data stays in the local database before it is deleted to save space.
  final int cacheTTL;

  /// The maximum number of individual responses kept in fast RAM memory at once.
  final int maxL1CacheItems;

  /// The maximum number of network requests allowed to run at the exact same moment.
  final int maxInFlightRequests;

  /// How many minutes session-stale RAM data is considered fresh before it expires.
  final int sessionStaleTTL;

  /// How many days cached images are stored before they are marked stale and eligible for deletion.
  final int imageStalePeriod;

  /// The maximum number of image files allowed to be stored in the disk image cache.
  final int maxImageCacheItems;

  /// The absolute disk storage limit (in Megabytes) allowed for caching images on the phone.
  final double maxImageCacheMB;

  /// The target disk storage size (in Megabytes) the cache manager tries to clean down to when pruning old image files.
  final double minImageCacheMB;

  // --- Box Names ---

  /// The storage box table name used for general API response cache payloads.
  final String boxApiCache;

  /// The storage box table name used for queueing failed mutations waiting for offline sync.
  final String boxOfflineQueue;

  /// The storage box table name used for caching timestamps, expiration dates, and metadata.
  final String boxCacheMetadata;

  /// The storage box table name used for storing ETag markers to support 304 response validations.
  final String boxEtags;

  // --- Misc ---

  /// The host website address (defaults to `google.com`) used to verify if the device has actual, active internet.
  final String connCheckHost;

  /// Enabling this parameter configures the engine to operate fully safely and functionally
  /// on Web platforms without compromising key features (like caching and offline mutations).
  final bool supportWeb;

  // --- Network Access ---

  /// Custom Dio interceptors to inject into the global [LikeClient] singleton.
  ///
  /// These run on **every** request the app makes, in addition to the built-in Like
  /// interceptors (auth, cache, retry, logging, etc.).
  ///
  /// **Use cases:**
  /// - Token refresh logic specific to your backend.
  /// - Custom request signing (HMAC, API keys).
  /// - Analytics / tracing interceptors.
  ///
  /// **Ordering:** Custom interceptors are added **after** all built-in Like
  /// interceptors so they execute closest to the network.
  ///
  /// **Example:**
  /// ```dart
  /// LikeService.init(LikeConfig(
  ///   projectName: 'myApp',
  ///   baseUrl: 'https://api.example.com',
  ///   interceptors: [
  ///     MyTokenRefreshInterceptor(),
  ///     MyRequestSigningInterceptor(),
  ///   ],
  /// ));
  /// ```
  final List<Interceptor> interceptors;

  LikeConfig({
    required this.projectName,
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
    this.automaticConnectivityChecksEnabled = true,
    this.automaticFailureCheckCooldown = const Duration(seconds: 3),
    this.offlineSyncEnabled = true,
    this.backgroundSyncEnabled = true,
    this.withAuthByDefault = true,
    this.offlineSyncByDefault = false,
    this.disableCacheByDefault = false,
    this.disableLoggerByDefault = false,
    this.suppressErrorsByDefault = false,
    this.staleWhileRevalidateByDefault = false,
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
    String? boxApiCache,
    String? boxOfflineQueue,
    String? boxCacheMetadata,
    String? boxEtags,
    this.connCheckHost = 'google.com',
    this.supportWeb = false,
    this.interceptors = const [],
  })  : verifySSL = verifySSL ?? !kDebugMode,
        boxApiCache = boxApiCache ??
            '${projectName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_]"), "_")}_api_cache',
        boxOfflineQueue = boxOfflineQueue ??
            '${projectName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_]"), "_")}_offline_queue',
        boxCacheMetadata = boxCacheMetadata ??
            '${projectName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_]"), "_")}_cache_metadata',
        boxEtags = boxEtags ??
            '${projectName.toLowerCase().replaceAll(RegExp(r"[^a-z0-9_]"), "_")}_etags';

  LikeConfig copyWith({
    String? projectName,
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
    bool? automaticConnectivityChecksEnabled,
    Duration? automaticFailureCheckCooldown,
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
    String? connCheckHost,
    bool? supportWeb,
    List<Interceptor>? interceptors,
  }) {
    return LikeConfig(
      projectName: projectName ?? this.projectName,
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
      automaticConnectivityChecksEnabled: automaticConnectivityChecksEnabled ??
          this.automaticConnectivityChecksEnabled,
      automaticFailureCheckCooldown:
          automaticFailureCheckCooldown ?? this.automaticFailureCheckCooldown,
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
      boxApiCache:
          boxApiCache ?? (projectName != null ? null : this.boxApiCache),
      boxOfflineQueue: boxOfflineQueue ??
          (projectName != null ? null : this.boxOfflineQueue),
      boxCacheMetadata: boxCacheMetadata ??
          (projectName != null ? null : this.boxCacheMetadata),
      boxEtags: boxEtags ?? (projectName != null ? null : this.boxEtags),
      connCheckHost: connCheckHost ?? this.connCheckHost,
      supportWeb: supportWeb ?? this.supportWeb,
      interceptors: interceptors ?? this.interceptors,
    );
  }

  bool get disableLogger => !enableLogging;
}
