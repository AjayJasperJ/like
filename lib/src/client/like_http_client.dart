import 'package:dio/dio.dart';
import 'package:like/src/core/like_ars.dart';
import 'package:like/src/core/like_multipart_file.dart';
import 'package:like/src/core/like_request_config.dart';
import 'package:like/src/models/like_api_result.dart';

/// Injectable HTTP boundary for services. Implement or mock this contract in
/// unit tests without initializing Hive, connectivity, or the default client.
/// Implementations own their lifecycle; services never dispose injected clients.
abstract interface class LikeHttpClient {
  Future<ApiResult<Response>> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });

  Future<ApiResult<Response>> post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });

  Future<ApiResult<Response>> put(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });

  Future<ApiResult<Response>> delete(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });

  Future<ApiResult<Response>> patch(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });

  Future<ApiResult<Response>> multipart(
    String path, {
    String method = 'POST',
    Map<String, String>? fields,
    dynamic filePaths,
    List<MultipartBytesFile>? files,
    Map<String, String>? headers,
    bool withAuth = false,
    bool offlineSync = false,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  });
}
