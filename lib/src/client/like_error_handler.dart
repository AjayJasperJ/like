import 'package:universal_io/io.dart';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/core/like_data_unpacker.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Handles conversion of various errors (Dio, Socket, etc.) into unified [LikeError].
/// Matches the exact categorization and user-friendly messaging logic of enterprise's ErrorHandler.
class LikeErrorHandler {
  /// Static entry point for error handling.
  static Future<LikeError> handle(dynamic error) async {
    if (error is DioException) {
      return await _handleDioError(error);
    } else if (error is FormatException) {
      return LikeError(
        message: 'Bad response format',
        type: LikeApiErrorType.parsing,
      );
    } else {
      return LikeError(
        message: 'Unexpected error: $error',
        type: LikeApiErrorType.unknown,
      );
    }
  }

  static Future<LikeError> _handleDioError(DioException error) async {
    String defaultMsg = 'An error occurred';
    LikeApiErrorType type = LikeApiErrorType.unknown;
    int? code = error.response?.statusCode;

    if (error.error == 'OFFLINE_QUEUED') {
      return LikeError(
        message: 'Offline: Request queued for background sync.',
        type: LikeApiErrorType.offlineQueued,
        code: 202,
      );
    }

    if (error.response != null) {
      return await parseResponse(error.response!);
    }

    final conn = LikeConnectivityManager();

    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        if (!conn.isInternetConnected) {
          defaultMsg = 'No internet connection – Please check your network.';
          type = LikeApiErrorType.network;
        } else if (!conn.isServerAvailable) {
          defaultMsg = 'Server Unreachable – The backend is currently offline.';
          type = LikeApiErrorType.serverUnavailable;
        } else {
          defaultMsg =
              'Request timed out – Please check your connection stability.';
          type = LikeApiErrorType.timeout;
        }
        break;
      case DioExceptionType.badCertificate:
        defaultMsg = 'Security Error – Invalid SSL certificate.';
        type = LikeApiErrorType.network;
        break;
      case DioExceptionType.badResponse:
        defaultMsg = 'Server Error – Invalid response received.';
        type = LikeApiErrorType.parsing;
        break;
      case DioExceptionType.cancel:
        defaultMsg = 'Request cancelled';
        type = LikeApiErrorType.cancelled;
        break;
      case DioExceptionType.connectionError:
        if (!conn.isInternetConnected) {
          defaultMsg = 'No internet connection – Unable to reach the server.';
          type = LikeApiErrorType.network;
        } else if (!conn.isServerAvailable) {
          defaultMsg = 'Server Unreachable – The backend is currently offline.';
          type = LikeApiErrorType.serverUnavailable;
        } else {
          defaultMsg = 'Connection Error – Unable to reach the server.';
          type = LikeApiErrorType.network;
        }
        break;
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          if (!conn.isInternetConnected) {
            defaultMsg = 'No internet connection – Please check your network.';
            type = LikeApiErrorType.network;
          } else if (!conn.isServerAvailable) {
            defaultMsg =
                'Server Unreachable – The backend is currently offline.';
            type = LikeApiErrorType.serverUnavailable;
          } else {
            defaultMsg = 'Network Error – Unable to connect to the server.';
            type = LikeApiErrorType.network;
          }
        } else if (error.error is FormatException) {
          defaultMsg = 'Data Error – Specific format exception.';
          type = LikeApiErrorType.parsing;
        } else {
          defaultMsg = 'Unknown error: ${error.message}';
          type = LikeApiErrorType.unknown;
        }
        break;
    }

    return LikeError(message: defaultMsg, type: type, code: code);
  }

  static Future<LikeError> parseResponse(Response res) async {
    const unpacker = DefaultLikeUnpacker();
    final unpacked = unpacker.unpack(res.data);

    String defaultMsg;
    LikeApiErrorType type;

    switch (res.statusCode) {
      case 400:
        defaultMsg =
            'Bad Request – The server could not understand your request.';
        type = LikeApiErrorType.badRequest;
        break;
      case 401:
        defaultMsg = 'Unauthorized – Please log in again.';
        type = LikeApiErrorType.unauthorized;
        break;
      case 403:
        defaultMsg = 'Forbidden – You do not have permission for this action.';
        type = LikeApiErrorType.forbidden;
        break;
      case 404:
        defaultMsg = 'Not Found – The requested resource was not found.';
        type = LikeApiErrorType.notFound;
        break;
      case 408:
        defaultMsg = 'Request Timeout – The server took too long to respond.';
        type = LikeApiErrorType.timeout;
        break;
      case 429:
        defaultMsg = 'Too Many Requests – You’re sending requests too quickly.';
        type = LikeApiErrorType.rateLimit;
        break;
      case 422:
        defaultMsg = 'Validation Error – Please check your input.';
        type = LikeApiErrorType.badRequest;
        break;
      case 500:
        defaultMsg =
            'Internal Server Error – Something went wrong on the server.';
        type = LikeApiErrorType.server;
        break;
      case 502:
        defaultMsg = 'Bad Gateway – The server received an invalid response.';
        type = LikeApiErrorType.serverUnavailable;
        break;
      case 503:
        defaultMsg = 'Service Unavailable – The server is temporarily offline.';
        type = LikeApiErrorType.serverUnavailable;
        break;
      case 504:
        defaultMsg =
            'Gateway Timeout – The server is taking too long to respond.';
        type = LikeApiErrorType.timeout;
        break;
      default:
        defaultMsg = 'Unexpected HTTP error (${res.statusCode}).';
        type = LikeApiErrorType.unknown;
    }

    return LikeError(
      message: unpacked.message.isNotEmpty ? unpacked.message : defaultMsg,
      type: type,
      code: res.statusCode,
      rawResponse: res.data,
    );
  }
}
