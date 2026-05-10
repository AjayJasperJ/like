/// High-level error types for the LIKE networking layer.
/// Matches enterprise's ApiErrorType 1:1.
enum LikeApiErrorType {
  network,
  timeout,
  unauthorized,
  server,
  cancelled,
  parsing,
  unknown,
  badRequest,
  forbidden,
  notFound,
  rateLimit,
  serverUnavailable,
  offlineQueued,
}

/// A unified error model for all network operations.
/// Matches the exact logic and contract of enterprise's ApiError.
class LikeError {
  final String message;
  final int? code;
  final LikeApiErrorType type;
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
