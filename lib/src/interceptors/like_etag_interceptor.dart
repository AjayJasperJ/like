import 'package:dio/dio.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/services/like_service.dart';

/// Interceptor to handle HTTP ETag (Entity Tag) caching.
/// Matches enterprise's ETagInterceptor parity.
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
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.requestOptions.method == 'GET') {
      final key = LikeHelpers.generateRequestKey(
        response.requestOptions.path,
        response.requestOptions.queryParameters,
      );

      // Handle 304 Not Modified
      if (response.statusCode == 304) {
        final cached = await LikeService.fetchResponseFromCache(
          response.requestOptions,
        );
        if (cached != null) {
          cached.extra['isFromCache'] = true;
          cached.extra['isFrom304'] = true;
          LikePipeline().emit(key, cached);
          return handler.resolve(cached);
        }
        // If 304 but cache is gone, retry without ETag
        LikeService.deleteEtag(key);
      }

      // Store new ETag
      final etag = response.headers.value('etag');
      if (etag != null && response.statusCode == 200) {
        LikeService.putEtag(key, etag);
      }
    }
    handler.next(response);
  }
}
