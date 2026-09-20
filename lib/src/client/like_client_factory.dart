// Conditional import: compiler selects the correct SSL implementation.
//   - Web   → like_ssl_stub.dart  (no-op, browser handles TLS)
//   - Native → like_ssl_io.dart   (IOHttpClientAdapter + HttpClient pinning)
import 'like_ssl_stub.dart' if (dart.library.io) 'like_ssl_io.dart' as ssl;

import 'package:dio/dio.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/client/like_request_registry.dart';
import 'package:like/src/interceptors/like_mock_interceptor.dart';
import 'package:like/src/interceptors/like_etag_interceptor.dart';
import 'package:like/src/interceptors/like_pipeline_interceptor.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/interceptors/like_logger_interceptor.dart';
import 'package:like/src/interceptors/like_cache_interceptor.dart';
import 'package:like/src/interceptors/like_offline_sync_interceptor.dart';
import 'package:like/src/interceptors/like_connectivity_interceptor.dart';
import 'package:like/src/interceptors/like_retry_interceptor.dart';
import 'package:like/src/interceptors/like_perf_interceptors.dart';
import 'package:like/src/services/like_service.dart';
import 'package:flutter/foundation.dart';

/// Factory to create and configure a Dio instance with all LIKE interceptors.
/// Matches enterprise's DioFactory parity.
class LikeClientFactory {
  static Dio create({
    required String baseUrl,
    Duration? timeout,
    required LikeRequestRegistry registry,

    /// Optional authentication configuration scoped to this Dio stack.
    LikeAuthConfig? authConfig,

    /// Custom Dio interceptors injected **after** the built-in Like stack.
    ///
    /// Sourced from [LikeConfig.interceptors] (global) or
    /// [LikeClientConfig.interceptors] (scoped client).
    List<Interceptor> customInterceptors = const [],

    /// Extra HTTP headers merged on top of the package-level defaults.
    ///
    /// Sourced from [LikeClientConfig.defaultHeaders] for scoped clients.
    Map<String, String> extraHeaders = const {},

    /// Explicit SSL verification override. Defaults to [LikeConstants.verifySSL].
    bool? verifySSL,

    /// Explicit SSL certificate SHA-256 pin override. Defaults to [LikeConstants.sslCertSha256].
    String? sslCertSha256,
  }) {
    final effectiveBaseUrl = LikeHelpers.normalizeBaseUrl(baseUrl);

    final dio = Dio(
      BaseOptions(
        baseUrl: effectiveBaseUrl,
        connectTimeout:
            timeout ?? Duration(seconds: LikeConstants.connectTimeout),
        receiveTimeout:
            timeout ?? Duration(seconds: LikeConstants.receiveTimeout),
        sendTimeout: kIsWeb
            ? null
            : (timeout ?? Duration(seconds: LikeConstants.sendTimeout)),
        headers: {
          'Accept': LikeConstants.defaultAcceptHeader,
          ...extraHeaders,
        },
      ),
    );

    _setupInterceptors(dio, registry, customInterceptors,
        authConfig: authConfig);

    // Delegate to the platform-correct SSL implementation:
    //   • Mobile/Desktop → like_ssl_io.dart  (IOHttpClientAdapter)
    //   • Web            → like_ssl_stub.dart (no-op)
    ssl.setupSSL(
      dio,
      verifySSL: verifySSL ?? LikeConstants.verifySSL,
      sslCertSha256: sslCertSha256 ?? LikeConstants.sslCertSha256,
    );

    return dio;
  }

  static void _setupInterceptors(
    Dio dio,
    LikeRequestRegistry registry,
    List<Interceptor> customInterceptors, {
    LikeAuthConfig? authConfig,
  }) {
    dio.interceptors.addAll(
      [
        // 0. Logging (Catches all requests)
        if (LikeConstants.logApiResponses) LikeLoggerInterceptor(),

        // 0.5 Mocking (Intercepts requests and returns mock data)
        LikeMockInterceptor(),

        // 1. Core Logic
        LikeEtagInterceptor(),
        LikeCacheInterceptor(),
        LikePipelineInterceptor(),

        // 2. Offline & Sync
        LikeConnectivityInterceptor(),
        if (LikeConstants.offlineSyncEnabled)
          LikeOfflineSyncInterceptor(
            dio: dio,
            queueBox: LikeService.boxOfflineQueue,
            authConfig: authConfig,
          ),

        // 3. Infrastructure
        LikeRetryInterceptor(dio: dio),
        if (LikeConstants.perfTrackingEnabled) LikePerformanceInterceptor(),
        LikeThrottlingInterceptor(),

        // 4. Security & Session (Last to ensure headers are final)
        LikeAuthInterceptor(dio: dio, authConfig: authConfig),

        // 5. Developer-injected custom interceptors (outermost layer,
        //    closest to the actual network wire).
        ...customInterceptors,
      ].whereType<Interceptor>(),
    );
  }
}
