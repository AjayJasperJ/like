import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Handles conversion of various errors (Dio, Socket, etc.) into unified [LikeError].
/// Matches the exact categorization and user-friendly messaging logic of enterprise's ErrorHandler.
class LikeErrorHandler {
  /// Static entry point for error handling.
  static Future<LikeError> handle(dynamic error) async {
    if (error is DioException) {
      return await _handleDioError(error);
    } else if (error is SocketException) {
      final conn = LikeConnectivityManager();
      if (!conn.isInternetConnected) {
        return LikeError(
          message: 'No internet connection – Please check your network.',
          type: LikeApiErrorType.network,
        );
      } else {
        conn.markServerUnavailable();
        return LikeError(
          message: 'Network Error – Unable to connect to the server.',
          type: LikeApiErrorType.network,
        );
      }
    } else if (error is TimeoutException) {
      return LikeError(
        message: 'Request timed out – Please check your connection stability.',
        type: LikeApiErrorType.timeout,
      );
    } else if (error is HttpException) {
      return LikeError(
        message: 'HTTP Protocol Error: ${error.message}',
        type: LikeApiErrorType.network,
      );
    } else if (error is FormatException) {
      return LikeError(
        message: 'Bad response format',
        type: LikeApiErrorType.parsing,
      );
    } else if (error is TypeError) {
      return LikeError(
        message: 'Type Mismatch Error – Failed to process server data structures.',
        type: LikeApiErrorType.parsing,
      );
    } else if (error is AssertionError) {
      return LikeError(
        message: 'Assertion Failed: ${error.message}',
        type: LikeApiErrorType.unknown,
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
        } else {
          conn.markServerUnavailable();
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
        } else {
          conn.markServerUnavailable();
          defaultMsg = 'Connection Error – Unable to reach the server.';
          type = LikeApiErrorType.network;
        }
        break;
      case DioExceptionType.unknown:
        // On native platforms, network errors surface as SocketException.
        // On web, Dio wraps browser network failures differently —
        // SocketException is never thrown. We check both to stay safe.
        final isSocketLike = error.error is SocketException ||
            // Web fallback: treat any non-HTTP unknown error as a network error
            (kIsWeb &&
                error.response == null &&
                error.type == DioExceptionType.unknown);
        if (isSocketLike) {
          if (!conn.isInternetConnected) {
            defaultMsg = 'No internet connection – Please check your network.';
            type = LikeApiErrorType.network;
          } else {
            conn.markServerUnavailable();
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
    final unpacker = LikeConstants.unpacker;
    final unpacked = unpacker.unpack(res.data);

    String defaultMsg;
    LikeApiErrorType type;

    switch (res.statusCode) {
      case 300:
        defaultMsg = 'Multiple Choices – The request has more than one possible response.';
        type = LikeApiErrorType.badRequest;
        break;
      case 301:
        defaultMsg = 'Moved Permanently – The resource has been permanently moved to a new URI.';
        type = LikeApiErrorType.badRequest;
        break;
      case 302:
        defaultMsg = 'Moved Temporarily – The resource resides temporarily under a different URI.';
        type = LikeApiErrorType.badRequest;
        break;
      case 304:
        defaultMsg = 'Not Modified – The resource has not changed since the last request.';
        type = LikeApiErrorType.badRequest;
        break;
      case 307:
        defaultMsg = 'Temporary Redirect – The resource resides temporarily under a different URI.';
        type = LikeApiErrorType.badRequest;
        break;
      case 308:
        defaultMsg = 'Permanent Redirect – The resource resides permanently under a different URI.';
        type = LikeApiErrorType.badRequest;
        break;
      case 400:
        defaultMsg =
            'Bad Request – The server could not understand your request.';
        type = LikeApiErrorType.badRequest;
        break;
      case 401:
        defaultMsg = 'Unauthorized – Please log in again.';
        type = LikeApiErrorType.unauthorized;
        break;
      case 402:
        defaultMsg = 'Payment Required – Access to this resource requires payment.';
        type = LikeApiErrorType.forbidden;
        break;
      case 403:
        defaultMsg = 'Forbidden – You do not have permission for this action.';
        type = LikeApiErrorType.forbidden;
        break;
      case 404:
        defaultMsg = 'Not Found – The requested resource was not found.';
        type = LikeApiErrorType.notFound;
        break;
      case 405:
        defaultMsg =
            'Method Not Allowed – The request method is not supported for this resource.';
        type = LikeApiErrorType.methodNotAllowed;
        break;
      case 406:
        defaultMsg =
            'Not Acceptable – The server cannot produce a response matching the requested headers.';
        type = LikeApiErrorType.badRequest;
        break;
      case 407:
        defaultMsg = 'Proxy Authentication Required – You must first authenticate with the proxy.';
        type = LikeApiErrorType.unauthorized;
        break;
      case 408:
        defaultMsg = 'Request Timeout – The server took too long to respond.';
        type = LikeApiErrorType.timeout;
        break;
      case 409:
        defaultMsg =
            'Conflict – The request conflicts with the current state of the server.';
        type = LikeApiErrorType.conflict;
        break;
      case 410:
        defaultMsg =
            'Gone – The requested resource is no longer available and will not return.';
        type = LikeApiErrorType.gone;
        break;
      case 411:
        defaultMsg = 'Length Required – The Content-Length header field is not defined.';
        type = LikeApiErrorType.badRequest;
        break;
      case 412:
        defaultMsg = 'Precondition Failed – Access to this resource has been denied.';
        type = LikeApiErrorType.badRequest;
        break;
      case 413:
        defaultMsg =
            'Payload Too Large – The request body exceeds the server limit.';
        type = LikeApiErrorType.payloadTooLarge;
        break;
      case 414:
        defaultMsg = 'URI Too Long – The URI provided was too long for the server to process.';
        type = LikeApiErrorType.badRequest;
        break;
      case 415:
        defaultMsg =
            'Unsupported Media Type – The server does not support the request media format.';
        type = LikeApiErrorType.badRequest;
        break;
      case 416:
        defaultMsg = 'Range Not Satisfiable – The request cannot be satisfied by the server.';
        type = LikeApiErrorType.badRequest;
        break;
      case 417:
        defaultMsg = 'Expectation Failed – The expectation given in the Expect header could not be met.';
        type = LikeApiErrorType.badRequest;
        break;
      case 418:
        defaultMsg = 'I\'m a teapot – The server refuses to brew coffee because it is a teapot.';
        type = LikeApiErrorType.badRequest;
        break;
      case 421:
        defaultMsg = 'Misdirected Request – The server cannot produce a response.';
        type = LikeApiErrorType.badRequest;
        break;
      case 422:
        defaultMsg = 'Validation Error – Please check your input.';
        type = LikeApiErrorType.badRequest;
        break;
      case 423:
        defaultMsg = 'Locked – The resource that is being accessed is locked.';
        type = LikeApiErrorType.forbidden;
        break;
      case 424:
        defaultMsg = 'Failed Dependency – The request failed due to failure of a previous request.';
        type = LikeApiErrorType.badRequest;
        break;
      case 425:
        defaultMsg = 'Too Early – The server is unwilling to risk processing a request that might be replayed.';
        type = LikeApiErrorType.badRequest;
        break;
      case 426:
        defaultMsg = 'Upgrade Required – The client should switch to a different protocol.';
        type = LikeApiErrorType.badRequest;
        break;
      case 428:
        defaultMsg = 'Precondition Required – The origin server requires the request to be conditional.';
        type = LikeApiErrorType.badRequest;
        break;
      case 429:
        defaultMsg = 'Too Many Requests – You’re sending requests too quickly.';
        type = LikeApiErrorType.rateLimit;
        break;
      case 431:
        defaultMsg = 'Request Header Fields Too Large – The server is unwilling to process the request because header fields are too large.';
        type = LikeApiErrorType.badRequest;
        break;
      case 451:
        defaultMsg = 'Unavailable For Legal Reasons – Access to the resource is blocked due to legal demands.';
        type = LikeApiErrorType.forbidden;
        break;
      case 500:
        defaultMsg =
            'Internal Server Error – Something went wrong on the server.';
        type = LikeApiErrorType.server;
        break;
      case 501:
        defaultMsg = 'Not Implemented – The server does not support the functionality required.';
        type = LikeApiErrorType.server;
        break;
      case 502:
        LikeConnectivityManager().markServerUnavailable();
        defaultMsg = 'Bad Gateway – The server received an invalid response.';
        type = LikeApiErrorType.serverUnavailable;
        break;
      case 503:
        LikeConnectivityManager().markServerUnavailable();
        defaultMsg = 'Service Unavailable – The server is temporarily offline.';
        type = LikeApiErrorType.serverUnavailable;
        break;
      case 504:
        LikeConnectivityManager().markServerUnavailable();
        defaultMsg =
            'Gateway Timeout – The server is taking too long to respond.';
        type = LikeApiErrorType.timeout;
        break;
      case 505:
        defaultMsg =
            'HTTP Version Not Supported – The server does not support the HTTP version used.';
        type = LikeApiErrorType.server;
        break;
      case 507:
        defaultMsg = 'Insufficient Storage – The server is unable to store the representation.';
        type = LikeApiErrorType.server;
        break;
      case 508:
        defaultMsg = 'Loop Detected – The server detected an infinite loop while processing the request.';
        type = LikeApiErrorType.server;
        break;
      case 511:
        defaultMsg = 'Network Authentication Required – The client needs to authenticate to gain network access.';
        type = LikeApiErrorType.unauthorized;
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
