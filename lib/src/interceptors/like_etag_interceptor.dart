import 'package:like/src/core/like_session_scope.dart';
import 'package:dio/dio.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/services/like_service.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:hive/hive.dart';

/// Interceptor to handle HTTP ETag (Entity Tag) caching.
/// Matches enterprise's ETagInterceptor parity.
///
/// NOTE: Dio treats HTTP 304 as an error (non-2xx), so 304 handling
/// must live in [onError], not [onResponse].
class LikeEtagInterceptor extends Interceptor {
  final Dio? dio;

  LikeEtagInterceptor({this.dio});

  bool get _etagStorageReady =>
      LikeConstants.cacheEnabled &&
      (LikeService.storageAvailable || Hive.isBoxOpen(LikeConstants.boxEtags));

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_etagStorageReady &&
        options.method == 'GET' &&
        options.extra['disableCache'] != true) {
      final key = LikeSessionIdentity.forRequest(options);
      final etag = LikeService.getEtag(key);
      if (etag != null) {
        options.headers['If-None-Match'] = etag;
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    if (_etagStorageReady &&
        response.requestOptions.method == 'GET' &&
        response.requestOptions.extra['disableCache'] != true &&
        response.extra['isMocked'] != true) {
      // Store new ETag on successful 200
      final etag = response.headers.value('etag');
      if (etag != null && response.statusCode == 200) {
        final key = LikeSessionIdentity.forRequest(response.requestOptions);
        try {
          await LikeService.putEtag(key, etag);
        } catch (_) {}
      }
    }
    handler.next(response);
  }

  /// Dio delivers 304 as a [DioException] (non-2xx status code).
  /// Intercept it here and resolve from L2 Hive cache instead.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    if (response != null &&
        response.statusCode == 304 &&
        err.requestOptions.method == 'GET') {
      final key = LikeSessionIdentity.forRequest(err.requestOptions);

      final cached = await LikeService.fetchResponseFromCache(
        err.requestOptions,
      );
      if (cached != null) {
        cached.extra['isFromCache'] = true;
        cached.extra['isFrom304'] = true;
        if (LikeSessionIdentity.isCurrent(err.requestOptions)) {
          LikePipeline().emit(key, cached);
        }
        return handler.resolve(cached);
      }

      // Cache miss on 304 — delete stale ETag so next request gets fresh data
      LikeService.deleteEtag(key);

      // Perform a single unconditional retry when a Dio instance is available
      // so a 304 cache miss does not surface as a user-facing error.
      if (dio != null && err.requestOptions.extra['like.304Retried'] != true) {
        try {
          final headers = Map<String, dynamic>.from(err.requestOptions.headers)
            ..remove('If-None-Match');
          final retry = err.requestOptions.copyWith(
            headers: headers,
            extra: {...err.requestOptions.extra, 'like.304Retried': true},
          );
          final fresh = await dio!.fetch<dynamic>(retry);
          return handler.resolve(fresh);
        } on DioException catch (retryError) {
          return handler.next(retryError);
        } catch (_) {}
      }
    }
    handler.next(err);
  }
}
