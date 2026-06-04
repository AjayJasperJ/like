/// High-level error types for the LIKE networking layer.
/// Matches enterprise's ApiErrorType 1:1.
enum LikeApiErrorType {
  /// General network/connectivity failure.
  network,

  /// Request timed out (connection or receive).
  timeout,

  /// 401 Unauthorized - Authentication required or expired.
  unauthorized,

  /// 500 Internal Server Error - Server-side failure.
  server,

  /// Request was manually cancelled.
  cancelled,

  /// Data parsing failure (JSON/Model mapping).
  parsing,

  /// Unknown or unexpected error.
  unknown,

  /// 400 Bad Request.
  badRequest,

  /// 403 Forbidden - Access denied.
  forbidden,

  /// 404 Not Found.
  notFound,

  /// 429 Too Many Requests.
  rateLimit,

  /// 503 Service Unavailable.
  serverUnavailable,

  /// Request was queued for offline synchronization.
  offlineQueued,

  /// 405 Method Not Allowed.
  methodNotAllowed,

  /// 409 Conflict.
  conflict,

  /// 410 Gone.
  gone,

  /// 413 Payload Too Large.
  payloadTooLarge,
}

/// A unified error model for all network operations.
/// Matches the exact logic and contract of enterprise's ApiError.
class LikeError {
  /// Human-readable error message.
  final String message;

  /// HTTP status code or internal status code.
  final int? code;

  /// The high-level category of the error.
  final LikeApiErrorType type;

  /// The raw response data from the server (if any).
  final dynamic rawResponse;

  LikeError({
    required this.message,
    this.code,
    required this.type,
    this.rawResponse,
  });

  /// Extracts structured error map from raw response if available.
  /// Matches 'errors' property of enterprise's ApiError.
  Map<String, dynamic> get errors {
    if (rawResponse is Map<String, dynamic>) {
      final data = rawResponse as Map<String, dynamic>;
      if (data.containsKey('errors')) {
        final errData = data['errors'];
        if (errData is Map<String, dynamic>) {
          return errData;
        }
      }
    }
    return {};
  }

  @override
  String toString() => 'LikeError(message: $message, code: $code, type: $type)';
}
