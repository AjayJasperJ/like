import 'dart:convert';
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

      dynamic data = response.data;
      if (data is String && data.isNotEmpty) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }

      // Re-wrap response so that the emitted event has parsed data.
      final cleanResponse = Response(
        data: data,
        headers: response.headers,
        requestOptions: response.requestOptions,
        isRedirect: response.isRedirect,
        statusCode: response.statusCode,
        statusMessage: response.statusMessage,
        redirects: response.redirects,
        extra: response.extra,
      );

      LikePipeline().emit(
        key,
        cleanResponse,
        model: model,
        isSyncing: false,
        timestamp: DateTime.now(),
      );
    }
    handler.next(response);
  }
}
