import 'package:dio/dio.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/services/like_service.dart';

/// Interceptor to handle HTTP ETag (Entity Tag) caching.
/// Matches enterprise's ETagInterceptor parity.
///
/// NOTE: Dio treats HTTP 304 as an error (non-2xx), so 304 handling
/// must live in [onError], not [onResponse].
class LikeEtagInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.method == 'GET' && options.extra['disableCache'] != true) {
      final key = LikeHelpers.generateRequestKey(
        options.path,
        options.queryParameters,
      );
      final etag = LikeService.getEtag(key);
      if (etag != null) {
        options.headers['If-None-Match'] = etag;
      }
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.method == 'GET') {
      // Store new ETag on successful 200
      final etag = response.headers.value('etag');
      if (etag != null && response.statusCode == 200) {
        final key = LikeHelpers.generateRequestKey(
          response.requestOptions.path,
          response.requestOptions.queryParameters,
        );
        LikeService.putEtag(key, etag);
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
      final key = LikeHelpers.generateRequestKey(
        err.requestOptions.path,
        err.requestOptions.queryParameters,
      );

      final cached =
          await LikeService.fetchResponseFromCache(err.requestOptions);
      if (cached != null) {
        cached.extra['isFromCache'] = true;
        cached.extra['isFrom304'] = true;
        LikePipeline().emit(key, cached);
        return handler.resolve(cached);
      }

      // Cache miss on 304 — delete stale ETag so next request gets fresh data
      LikeService.deleteEtag(key);
    }
    handler.next(err);
  }
}
