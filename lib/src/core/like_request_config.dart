import 'package:dio/dio.dart';
import 'package:like/src/core/like_data_unpacker.dart';

/// Per-request network configuration overrides for the LIKE engine.
///
/// [LikeRequestConfig] lets you override global [LikeConfig] settings for
/// a **single** API call without changing the app-wide defaults.
///
/// **Priority chain (highest → lowest):**
/// `LikeRequestConfig` → `ARS` → `LikeConstants` (global defaults)
///
/// All fields are optional. Any field left as `null` automatically falls
/// back to the corresponding global constant.
///
/// ## Example — Long-running upload with a custom base URL
/// ```dart
/// final result = await client.post(
///   '/import',
///   body: payload,
///   requestConfig: LikeRequestConfig(
///     connectTimeout: Duration(seconds: 60),
///     sendTimeout: Duration(seconds: 120),
///     baseUrl: 'https://upload.example.com',
///   ),
/// );
/// ```
///
/// ## Example — 3rd-party endpoint with a different response envelope
/// ```dart
/// final result = await client.get(
///   '/external/catalog',
///   requestConfig: LikeRequestConfig(
///     baseUrl: 'https://partner-api.com',
///     unpacker: PartnerApiUnpacker(),
///     verifySSL: false,           // partner uses self-signed cert in staging
///   ),
/// );
/// ```
///
/// ## Example — Named server from [LikeConfig.extraBaseUrls]
/// ```dart
/// // Given:  extraBaseUrls: {'cdn': 'https://cdn.example.com'}
/// final result = await client.get(
///   '/assets/logo.png',
///   requestConfig: LikeRequestConfig(namedBaseUrl: 'cdn'),
/// );
/// ```
class LikeRequestConfig {
  /// Overrides the target server URL for this single request only.
  ///
  /// If both [baseUrl] and [namedBaseUrl] are supplied, [baseUrl] takes
  /// precedence.
  ///
  /// **Analogy:** Your app normally talks to `api.example.com`, but this one
  /// call should go to `cdn.example.com` instead.
  final String? baseUrl;

  /// Routes this request to a named server defined in
  /// [LikeConfig.extraBaseUrls].
  ///
  /// The key is looked up at call-time from the global config.
  /// Ignored if [baseUrl] is also provided.
  ///
  /// **Example:**
  /// ```dart
  /// // Config:  extraBaseUrls: {'chat': 'https://chat.example.com'}
  /// LikeRequestConfig(namedBaseUrl: 'chat')
  /// ```
  final String? namedBaseUrl;

  /// Overrides the connection-establishment timeout for this call only.
  ///
  /// **Analogy:** How long to wait for the server to pick up the phone.
  /// Defaults to [LikeConstants.connectTimeout] if `null`.
  final Duration? connectTimeout;

  /// Overrides the response-receive timeout for this call only.
  ///
  /// **Analogy:** Once the server picks up, how long to wait for it to speak.
  /// Defaults to [LikeConstants.receiveTimeout] if `null`.
  final Duration? receiveTimeout;

  /// Overrides the request-send timeout for this call only.
  ///
  /// Useful for file uploads where the default timeout is too short.
  /// Defaults to [LikeConstants.sendTimeout] if `null`.
  final Duration? sendTimeout;

  /// Extra HTTP headers merged **on top of** the global [LikeConfig.defaultHeaders].
  ///
  /// If a key exists in both this map and the global headers, the value here
  /// wins for this specific call.
  ///
  /// **Example:**
  /// ```dart
  /// LikeRequestConfig(
  ///   headers: {'X-Trace-Id': 'abc-123', 'X-Feature-Flag': 'new-checkout'},
  /// )
  /// ```
  final Map<String, String>? headers;

  /// Overrides the response envelope parser for this call only.
  ///
  /// Useful when a specific endpoint (or 3rd-party API) wraps its data
  /// differently from the rest of your app.
  ///
  /// **Example:**
  /// ```dart
  /// // Global unpacker reads `data` key.
  /// // This legacy endpoint wraps in `result` key.
  /// LikeRequestConfig(unpacker: LegacyResultUnpacker())
  /// ```
  final LikeDataUnpacker? unpacker;

  /// Overrides SSL certificate verification for this call only.
  ///
  /// Set to `false` to skip SSL validation for endpoints using self-signed
  /// certificates (staging/debug environments only — never in production).
  final bool? verifySSL;

  /// Overrides the SSL certificate SHA-256 fingerprint pin for this call only.
  ///
  /// When provided, the engine verifies that the server's certificate matches
  /// this exact fingerprint. Blocks MITM attacks that use fraudulent certs.
  final String? sslCertSha256;

  /// Extra Dio interceptors to inject for this call only.
  ///
  /// These are added to a **cloned** Dio instance scoped to this request, so
  /// they do not pollute the global client's interceptor stack.
  ///
  /// > **Note:** This creates a lightweight Dio clone per call. For
  /// > interceptors that should run on many calls, prefer using
  /// > [LikeConfig.interceptors] (global) or [LikeClient.scoped] (module).
  ///
  /// **Example:**
  /// ```dart
  /// LikeRequestConfig(
  ///   interceptors: [OneTimeDebugInterceptor()],
  /// )
  /// ```
  final List<Interceptor>? interceptors;

  // --- Resiliency Overrides ---

  /// Overrides [LikeConfig.cacheOnOffline] for this request only.
  ///
  /// When `true`, if the device has no internet connection, the engine
  /// immediately returns the last cached response instead of failing.
  ///
  /// **Analogy:** Your app is on a plane with no Wi-Fi. Instead of showing
  /// an error screen, the user still sees their last-loaded data.
  ///
  /// Defaults to [LikeConstants.cacheOnOffline] when `null`.
  final bool? cacheOnOffline;

  /// Overrides [LikeConfig.cacheOnError] for this request only.
  ///
  /// When `true`, if the server responds with a 5xx error, the engine
  /// falls back to the last successfully cached response.
  ///
  /// **Use case:** A dashboard that must always show *something* even if
  /// the backend is temporarily down during a deployment.
  ///
  /// Defaults to [LikeConstants.cacheOnError] when `null`.
  final bool? cacheOnError;

  /// Overrides [LikeConfig.cacheOnException] for this request only.
  ///
  /// When `true`, if the request fails due to a network exception (timeout,
  /// DNS failure, socket error), the engine returns cached data instead of
  /// propagating the exception to the UI.
  ///
  /// Defaults to [LikeConstants.cacheOnException] when `null`.
  final bool? cacheOnException;

  /// Overrides [LikeConfig.maxAutoRetries] for this request only.
  ///
  /// Sets how many times the engine will automatically retry this specific
  /// request before giving up and returning an error.
  ///
  /// **Example:** A critical payment confirmation call might use `maxAutoRetries: 5`
  /// while a non-critical analytics ping might use `maxAutoRetries: 0`.
  ///
  /// Defaults to [LikeConstants.maxAutoRetries] when `null`.
  final int? maxAutoRetries;

  /// Overrides [LikeConfig.retryDelays] for this request only.
  ///
  /// A list of wait times (in seconds) between each retry attempt.
  /// The engine uses the value at index `attempt - 1`, so the list length
  /// should be at least equal to [maxAutoRetries].
  ///
  /// **Example:** `[1, 3, 10]` means wait 1 s before retry 1, 3 s before
  /// retry 2, and 10 s before retry 3 (exponential-style backoff).
  ///
  /// Defaults to [LikeConstants.retryDelays] when `null`.
  final List<int>? retryDelays;

  const LikeRequestConfig({
    this.baseUrl,
    this.namedBaseUrl,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.headers,
    this.unpacker,
    this.verifySSL,
    this.sslCertSha256,
    this.interceptors,
    this.cacheOnOffline,
    this.cacheOnError,
    this.cacheOnException,
    this.maxAutoRetries,
    this.retryDelays,
  });

  /// Returns `true` if this config routes the request to a different server
  /// than the global [LikeConfig.baseUrl].
  bool get hasCustomBaseUrl => baseUrl != null || namedBaseUrl != null;

  /// Returns `true` if this config carries per-request interceptors.
  bool get hasInterceptors =>
      interceptors != null && interceptors!.isNotEmpty;

  /// Returns `true` if a custom SSL fingerprint pin is specified.
  bool get hasSslPin =>
      sslCertSha256 != null && sslCertSha256!.isNotEmpty;

  /// Returns `true` if any resiliency override is explicitly set,
  /// meaning this call deviates from the global fallback behaviour.
  bool get hasResiliencyOverrides =>
      cacheOnOffline != null ||
      cacheOnError != null ||
      cacheOnException != null ||
      maxAutoRetries != null ||
      retryDelays != null;

  @override
  String toString() {
    return 'LikeRequestConfig('
        'baseUrl: $baseUrl, '
        'namedBaseUrl: $namedBaseUrl, '
        'connectTimeout: $connectTimeout, '
        'receiveTimeout: $receiveTimeout, '
        'sendTimeout: $sendTimeout, '
        'headers: $headers, '
        'unpacker: $unpacker, '
        'verifySSL: $verifySSL, '
        'sslCertSha256: ${sslCertSha256 != null ? "***" : null}, '
        'interceptors: ${interceptors?.length ?? 0} item(s), '
        'cacheOnOffline: $cacheOnOffline, '
        'cacheOnError: $cacheOnError, '
        'cacheOnException: $cacheOnException, '
        'maxAutoRetries: $maxAutoRetries, '
        'retryDelays: $retryDelays'
        ')';
  }
}
