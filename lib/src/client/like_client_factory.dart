import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/client/like_request_registry.dart';
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

/// Factory to create and configure a Dio instance with all LIKE interceptors.
/// Matches enterprise's DioFactory parity.
class LikeClientFactory {
  static Dio create({
    required String baseUrl,
    Duration? timeout,
    required LikeRequestRegistry registry,
  }) {
    final effectiveBaseUrl = LikeHelpers.normalizeBaseUrl(baseUrl);

    final dio = Dio(
      BaseOptions(
        baseUrl: effectiveBaseUrl,
        connectTimeout:
            timeout ?? Duration(seconds: LikeConstants.connectTimeout),
        receiveTimeout:
            timeout ?? Duration(seconds: LikeConstants.receiveTimeout),
        sendTimeout: timeout ?? Duration(seconds: LikeConstants.sendTimeout),
        headers: {
          'Accept': LikeConstants.defaultAcceptHeader,
          'Content-Type': LikeConstants.defaultContentTypeHeader,
        },
      ),
    );

    _setupInterceptors(dio, registry);
    _setupSSL(dio);

    return dio;
  }

  static void _setupInterceptors(Dio dio, LikeRequestRegistry registry) {
    dio.interceptors.addAll(
      [
        // 0. Logging (Catches all requests)
        if (LikeConstants.logApiResponses) LikeLoggerInterceptor(),

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
          ),

        // 3. Infrastructure
        LikeRetryInterceptor(dio: dio),
        if (LikeConstants.perfTrackingEnabled) LikePerformanceInterceptor(),
        LikeThrottlingInterceptor(),

        // 4. Security & Session (Last to ensure headers are final)
        LikeAuthInterceptor(dio: dio),
      ].whereType<Interceptor>(),
    );
  }

  static void _setupSSL(Dio dio) {
    if (LikeConstants.verifySSL) {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) {
          if (LikeConstants.sslCertSha256.isEmpty) return kDebugMode;

          final certSha256 = sha256
              .convert(cert.der)
              .bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(':')
              .toLowerCase();

          return certSha256 == LikeConstants.sslCertSha256.toLowerCase();
        };
        return client;
      };
    } else {
      (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      };
    }
  }
}
