import 'package:dio/dio.dart';
import 'package:like/like.dart';

typedef BaseApiService = LikeBaseApiService;

abstract class LikeBaseApiService {
  final LikeClient _client;

  LikeBaseApiService({LikeClient? client}) : _client = client ?? LikeClient();

  Future<ApiResult<Response>> get(
    String path, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
    bool withAuth = false,
    bool disableCache = false,
    CancelToken? cancelToken,
    ARS? ars,
    LikeRequestConfig? requestConfig,
  }) {
    return _client.get(
      path,
      query: query,
      headers: headers,
      withAuth: withAuth,
      disableCache: disableCache,
      cancelToken: cancelToken,
      ars: ars,
      requestConfig: requestConfig,
    );
  }

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
  }) {
    return _client.post(
      path,
      body: body,
      query: query,
      headers: headers,
      withAuth: withAuth,
      offlineSync: offlineSync,
      cancelToken: cancelToken,
      ars: ars,
      requestConfig: requestConfig,
    );
  }

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
  }) {
    return _client.put(
      path,
      body: body,
      query: query,
      headers: headers,
      withAuth: withAuth,
      offlineSync: offlineSync,
      disableCache: disableCache,
      cancelToken: cancelToken,
      ars: ars,
      requestConfig: requestConfig,
    );
  }

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
  }) {
    return _client.delete(
      path,
      body: body,
      query: query,
      headers: headers,
      withAuth: withAuth,
      offlineSync: offlineSync,
      disableCache: disableCache,
      cancelToken: cancelToken,
      ars: ars,
      requestConfig: requestConfig,
    );
  }

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
  }) {
    return _client.patch(
      path,
      body: body,
      query: query,
      headers: headers,
      withAuth: withAuth,
      offlineSync: offlineSync,
      disableCache: disableCache,
      cancelToken: cancelToken,
      ars: ars,
      requestConfig: requestConfig,
    );
  }

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
  }) {
    return _client.multipart(
      path,
      method: method,
      fields: fields,
      filePaths: filePaths,
      files: files,
      headers: headers,
      withAuth: withAuth,
      offlineSync: offlineSync,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
      ars: ars,
      requestConfig: requestConfig,
    );
  }
}
