import 'package:like/src/models/like_error.dart';

/// A simple wrapper for API results, used internally by the LikeClient.
class LikeResult<T> {
  final T? data;
  final String message;
  final bool isSuccess;
  final LikeApiErrorType? errorType;
  final int? statusCode;

  LikeResult({
    this.data,
    required this.message,
    required this.isSuccess,
    this.errorType,
    this.statusCode,
  });

  factory LikeResult.success(T data, {String? message}) =>
      LikeResult(data: data, message: message ?? 'Success', isSuccess: true);

  factory LikeResult.error(
    String message, {
    LikeApiErrorType? type,
    int? code,
  }) =>
      LikeResult(
        message: message,
        isSuccess: false,
        errorType: type,
        statusCode: code,
      );
}
