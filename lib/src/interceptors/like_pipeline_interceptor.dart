import 'package:dio/dio.dart';
import 'package:like/src/core/like_helpers.dart';
import 'package:like/src/services/like_pipeline.dart';

/// Interceptor to automatically emit successful responses to the LikePipeline.
/// Matches enterprise's PipelineInterceptor parity.
class LikePipelineInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (response.requestOptions.method == 'GET') {
      final key = LikeHelpers.generateRequestKey(
        response.requestOptions.path,
        response.requestOptions.queryParameters,
      );

      final model = response.extra['mappedModel'];

      LikePipeline().emit(
        key,
        response,
        model: model,
        isSyncing: false,
        timestamp: DateTime.now(),
      );
    }
    handler.next(response);
  }
}
