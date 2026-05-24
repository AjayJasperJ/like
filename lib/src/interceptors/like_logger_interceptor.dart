import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_logger.dart';

/// Interceptor to log all API requests and responses to console and disk.
/// Matches enterprise's LoggerInterceptor parity.
class LikeLoggerInterceptor extends Interceptor {
  final _uuid = const Uuid();

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!LikeConstants.silentConsole &&
        options.extra['disableLogger'] != true &&
        (LikeConstants.verboseLogging || LikeConstants.logApiResponses)) {
      final requestId = _uuid.v4();
      options.extra['requestId'] = requestId;

      Map<String, String>? fields;
      if (options.data is FormData) {
        final formData = options.data as FormData;
        fields = {};
        for (var field in formData.fields) {
          fields[field.key] = field.value;
        }
      }

      await LikeLogger.logApiRequest(
        options.path,
        requestId: requestId,
        method: options.method,
        headers: options.headers,
        body: options.data,
        fields: fields,
        query: options.queryParameters,
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    if (response.requestOptions.extra['disableLogger'] == true) {
      return handler.next(response);
    }
    final requestId = response.requestOptions.extra['requestId'] as String?;

    final bool isStaleWhileRevalidate =
        response.extra['isFromStaleWhileRevalidate'] ?? false;
    final bool isCache = response.extra['isFromCache'] ?? false;
    final bool isResiliency = response.extra['isResiliencyFallback'] ?? false;

    String statusText = 'SUCCESS';
    if (isStaleWhileRevalidate) {
      statusText = 'SWR HIT';
    } else if (isCache) {
      statusText = 'CACHE HIT';
    } else if (isResiliency) {
      statusText = 'RESILIENCY FALLBACK';
    }

    Map<String, String>? fields;
    if (response.requestOptions.data is FormData) {
      final formData = response.requestOptions.data as FormData;
      fields = {};
      for (var field in formData.fields) {
        fields[field.key] = field.value;
      }
    }

    await LikeLogger.logApi(
      response.requestOptions.path,
      success: true,
      statusCode: response.statusCode,
      response: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? response.data
          : null,
      requestId: requestId,
      method: response.requestOptions.method,
      statusText: statusText,
      requestHeaders: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? response.requestOptions.headers
          : null,
      responseHeaders:
          (LikeConstants.debugMode || LikeConstants.logApiResponses)
              ? response.headers.map
              : null,
      requestBody: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? response.requestOptions.data
          : null,
      requestFields: fields,
      requestQuery: response.requestOptions.queryParameters,
      shrinkEndpointOnly: LikeConstants.compactApiLogs,
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.requestOptions.extra['disableLogger'] == true) {
      return handler.next(err);
    }
    final requestId = err.requestOptions.extra['requestId'] as String?;

    final errorMessage =
        (err.type == DioExceptionType.cancel && err.error != null)
            ? err.error.toString()
            : err.message;

    Map<String, String>? fields;
    if (err.requestOptions.data is FormData) {
      final formData = err.requestOptions.data as FormData;
      fields = {};
      for (var field in formData.fields) {
        fields[field.key] = field.value;
      }
    }

    await LikeLogger.logApi(
      err.requestOptions.path,
      success: false,
      statusCode: err.response?.statusCode,
      response: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? (err.response?.data ?? errorMessage)
          : errorMessage,
      requestId: requestId,
      method: err.requestOptions.method,
      requestHeaders: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? err.requestOptions.headers
          : null,
      responseHeaders:
          (LikeConstants.debugMode || LikeConstants.logApiResponses)
              ? err.response?.headers.map
              : null,
      requestBody: (LikeConstants.debugMode || LikeConstants.logApiResponses)
          ? err.requestOptions.data
          : null,
      requestFields: fields,
      requestQuery: err.requestOptions.queryParameters,
    );
    handler.next(err);
  }
}
