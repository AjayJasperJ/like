import 'package:dio/dio.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_data_unpacker.dart';

/// Configuration for creating an isolated, scoped [LikeClient] instance.
///
/// [LikeClientConfig] is passed to [LikeClient.scoped()] to produce a
/// **fully independent** client with its own Dio instance, interceptor stack,
/// and request registry. It does **not** share state with the global singleton.
///
/// All fields are optional — unset fields fall back to [LikeConstants] values.
///
/// ## When to use scoped clients vs. per-request config
///
/// | Situation | Recommended approach |
/// |---|---|
/// | One endpoint has special timeouts | `LikeRequestConfig` on that call |
/// | An entire feature module hits a different server | `LikeClient.scoped()` |
/// | A microservice needs its own auth header format | `LikeClient.scoped()` |
/// | A 3rd-party API uses a different response envelope | `LikeClient.scoped()` |
///
/// ## Example — Payments feature module
/// ```dart
/// // Create once in your DI container or feature module setup:
/// final paymentsClient = LikeClient.scoped(
///   LikeClientConfig(
///     baseUrl: 'https://pay.example.com',
///     connectTimeout: Duration(seconds: 15),
///     receiveTimeout: Duration(seconds: 30),
///     defaultHeaders: {'X-Payment-Version': '2'},
///     unpacker: PaymentsResponseUnpacker(),
///     interceptors: [PaymentsHmacSigningInterceptor()],
///     authConfig: LikeAuthConfig(getToken: () async => 'custom-jwt'),
///   ),
/// );
///
/// // Use it just like the global client:
/// final result = await paymentsClient.post('/charge', body: chargePayload);
/// ```
class LikeClientConfig {
  /// The base server URL for all requests made through this scoped client.
  ///
  /// Falls back to [LikeConstants.current.baseUrl] if `null`.
  final String? baseUrl;

  /// Optional authentication configuration scoped to this client.
  final LikeAuthConfig? authConfig;

  /// Timeout for establishing a connection with the server.
  ///
  /// Falls back to [LikeConstants.connectTimeout] if `null`.
  final Duration? connectTimeout;

  /// Timeout for receiving the full response body from the server.
  ///
  /// Falls back to [LikeConstants.receiveTimeout] if `null`.
  final Duration? receiveTimeout;

  /// Timeout for sending request data (e.g. file uploads) to the server.
  ///
  /// Falls back to [LikeConstants.sendTimeout] if `null`.
  final Duration? sendTimeout;

  /// HTTP headers included on every request made through this client.
  ///
  /// These are **merged** on top of the package-level `Accept` / `Content-Type`
  /// defaults. Keys defined here override the same keys from the global config.
  final Map<String, String>? defaultHeaders;

  /// The response envelope parser for all calls made through this client.
  ///
  /// Falls back to [LikeConstants.unpacker] (the global unpacker) if `null`.
  final LikeDataUnpacker? unpacker;

  /// Whether to verify SSL/TLS certificates for requests from this client.
  ///
  /// Falls back to [LikeConstants.verifySSL] if `null`.
  final bool? verifySSL;

  /// SHA-256 fingerprint for SSL certificate pinning on this client.
  ///
  /// Falls back to [LikeConstants.sslCertSha256] if `null` or empty.
  final String? sslCertSha256;

  /// Custom Dio interceptors to add to this scoped client's interceptor stack.
  ///
  /// These run on every request made through **this** client only and are added
  /// after the built-in Like interceptors.
  ///
  /// **Tip:** For global interceptors (all clients), use
  /// [LikeConfig.interceptors] instead.
  final List<Interceptor>? interceptors;

  const LikeClientConfig({
    this.baseUrl,
    this.authConfig,
    this.connectTimeout,
    this.receiveTimeout,
    this.sendTimeout,
    this.defaultHeaders,
    this.unpacker,
    this.verifySSL,
    this.sslCertSha256,
    this.interceptors,
  });

  @override
  String toString() {
    return 'LikeClientConfig('
        'baseUrl: $baseUrl, '
        'authConfig: $authConfig, '
        'connectTimeout: $connectTimeout, '
        'receiveTimeout: $receiveTimeout, '
        'sendTimeout: $sendTimeout, '
        'defaultHeaders: $defaultHeaders, '
        'unpacker: $unpacker, '
        'verifySSL: $verifySSL, '
        'interceptors: ${interceptors?.length ?? 0} item(s)'
        ')';
  }
}
