import 'package:flutter/material.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_api_result.dart';

/// A shorter, cleaner alias for [LikeStateResponse].
typedef StateResponse<T> = LikeStateResponse<T>;

/// Function signature for creating models from JSON.
typedef LikeModelFactory<T> = T Function(dynamic json);

/// Represents the possible states of a network request or data stream.
enum LikeState {
  /// Initial state before any request is made.
  idle,

  /// Initial network fetch in progress. UI should show a primary loading indicator
  /// as there is no data to display yet.
  loading,

  /// An explicit refresh (e.g., Pull-to-Refresh) is in progress.
  /// Existing data is still available for display (Sticky Data).
  refreshing,

  /// Stale-While-Revalidate: Cached data is being displayed while a background
  /// network request attempts to update it.
  staleWhileRevalidate,

  /// Request completed successfully with valid data.
  success,

  /// Request failed with a specific API or server error (e.g., 404, 500).
  error,

  /// An unexpected system or runtime exception occurred (e.g., No Internet, FormatException).
  exception,
}

/// The State Engine of the LIKE package.
/// Manages the lifecycle of a request, including SWR and background refreshes.
class LikeStateResponse<T> {
  /// The current lifecycle status of the request.
  final LikeState state;

  /// A descriptive message representing the current state or error.
  final String message;

  /// The data payload returned from the network or cache.
  final T? data;

  /// Detailed error information if the state is [LikeState.error].
  final LikeError? error;

  /// The high-level category of the error (e.g., unauthorized, timeout).
  final LikeApiErrorType? errorType;

  /// The HTTP status code or internal error code.
  final int? code;

  /// Whether the data was retrieved from the local persistence layer.
  final bool isFromCache;

  /// Whether the data is being served as a stale-while-revalidate fallback.
  final bool isFromStaleWhileRevalidate;

  /// Whether the data is a local fallback provided when the network is unreachable.
  final bool isResiliencyFallback;

  /// Whether the response was a "304 Not Modified", using local data.
  final bool isFrom304;

  const LikeStateResponse({
    required this.state,
    required this.message,
    this.data,
    this.error,
    this.errorType,
    this.code,
    this.isFromCache = false,
    this.isFromStaleWhileRevalidate = false,
    this.isResiliencyFallback = false,
    this.isFrom304 = false,
  });

  factory LikeStateResponse.idle({String? message}) =>
      LikeStateResponse(state: LikeState.idle, message: message ?? 'Idle');

  factory LikeStateResponse.loading({String? message}) => LikeStateResponse(
        state: LikeState.loading,
        message: message ?? 'Loading...',
      );

  factory LikeStateResponse.success(
    T data, {
    String? message,
    bool isFromCache = false,
    bool isFromStaleWhileRevalidate = false,
    bool isResiliencyFallback = false,
    bool isFrom304 = false,
  }) =>
      LikeStateResponse(
        state: LikeState.success,
        message: message ?? 'Success',
        data: data,
        isFromCache: isFromCache,
        isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
        isResiliencyFallback: isResiliencyFallback,
        isFrom304: isFrom304,
      );

  factory LikeStateResponse.staleWhileRevalidate(T data, {String? message}) =>
      LikeStateResponse(
        state: LikeState.staleWhileRevalidate,
        message: message ?? 'Serving from cache...',
        data: data,
        isFromCache: true,
        isFromStaleWhileRevalidate: true,
      );

  factory LikeStateResponse.refreshing(
    T data, {
    String? message,
    bool isFromCache = false,
  }) =>
      LikeStateResponse(
        state: LikeState.refreshing,
        message: message ?? 'Refreshing...',
        data: data,
        isFromCache: isFromCache,
      );

  factory LikeStateResponse.error(
    LikeError error, {
    T? data,
    bool isFromCache = false,
    bool isFromStaleWhileRevalidate = false,
    bool isResiliencyFallback = false,
    bool isFrom304 = false,
  }) {
    T? extractedData = data;
    if (extractedData == null && error.rawResponse != null) {
      try {
        if (error.rawResponse is T) {
          extractedData = error.rawResponse as T;
        }
      } catch (_) {}
    }
    return LikeStateResponse(
      state: LikeState.error,
      message: error.message,
      error: error,
      errorType: error.type,
      code: error.code,
      data: extractedData,
      isFromCache: isFromCache,
      isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
      isResiliencyFallback: isResiliencyFallback,
      isFrom304: isFrom304,
    );
  }

  factory LikeStateResponse.exception(
    String message, {
    T? data,
    bool isFromCache = false,
    bool isFromStaleWhileRevalidate = false,
    bool isResiliencyFallback = false,
    bool isFrom304 = false,
  }) =>
      LikeStateResponse(
        state: LikeState.exception,
        message: message,
        data: data,
        error: LikeError(message: message, type: LikeApiErrorType.unknown),
        isFromCache: isFromCache,
        isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
        isResiliencyFallback: isResiliencyFallback,
        isFrom304: isFrom304,
      );

  // --- Common Error Helpers ---

  static LikeError parseError() =>
      LikeError(message: 'Data parsing failed', type: LikeApiErrorType.parsing);

  factory LikeStateResponse.unknown() => LikeStateResponse<T>.exception(
        'Something went wrong. Please try again later.',
      );

  factory LikeStateResponse.missingData(String message) =>
      LikeStateResponse<T>.error(
        LikeError(message: message, type: LikeApiErrorType.unknown),
      );

  /// Creates a [LikeStateResponse] from a [LikeApiResult].
  factory LikeStateResponse.fromResult(LikeApiResult<dynamic> result) {
    if (result.isSuccess) {
      return LikeStateResponse.success(
        result.data as T,
        isFromCache: result.isFromCache,
        isFromStaleWhileRevalidate: result.isFromStaleWhileRevalidate,
        isResiliencyFallback: result.isResiliencyFallback,
      );
    } else {
      return LikeStateResponse.error(
        result.error!,
        isFromCache: result.isFromCache,
        isFromStaleWhileRevalidate: result.isFromStaleWhileRevalidate,
        isResiliencyFallback: result.isResiliencyFallback,
      );
    }
  }

  // Helper getters
  bool get isSuccess => state == LikeState.success;
  bool get isLoading => state == LikeState.loading;
  bool get isError => state == LikeState.error;
  bool get isIdle => state == LikeState.idle;
  bool get isException => state == LikeState.exception;
  bool get isRefreshing => state == LikeState.refreshing;
  bool get isStaleWhileRevalidate => state == LikeState.staleWhileRevalidate;

  /// Resolves a user-friendly message from the data or error.
  String get resolvedMessage {
    String msg = message;
    if (state == LikeState.success && (msg == 'Success' || msg.isEmpty)) {
      try {
        final dynamic d = data;
        if (d != null) {
          if (d is Map && d['message'] != null) {
            return d['message'].toString();
          }
          // Check if data has a message property
          try {
            final dynamic dataMsg = (d as dynamic).message;
            if (dataMsg != null && dataMsg.toString().isNotEmpty) {
              return dataMsg.toString();
            }
          } catch (_) {}
        }
      } catch (_) {}
    }
    return msg;
  }

  /// Creates a copy of this response with updated fields.
  LikeStateResponse<T> copyWith({
    LikeState? state,
    String? message,
    T? data,
    LikeError? error,
    LikeApiErrorType? errorType,
    int? code,
    bool? isFromCache,
    bool? isFromStaleWhileRevalidate,
    bool? isResiliencyFallback,
    bool? isFrom304,
  }) {
    return LikeStateResponse<T>(
      state: state ?? this.state,
      message: message ?? this.message,
      data: data ?? this.data,
      error: error ?? this.error,
      errorType: errorType ?? this.errorType,
      code: code ?? this.code,
      isFromCache: isFromCache ?? this.isFromCache,
      isFromStaleWhileRevalidate:
          isFromStaleWhileRevalidate ?? this.isFromStaleWhileRevalidate,
      isResiliencyFallback: isResiliencyFallback ?? this.isResiliencyFallback,
      isFrom304: isFrom304 ?? this.isFrom304,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LikeStateResponse<T> &&
        other.state == state &&
        other.message == message &&
        other.data == data &&
        other.error == error &&
        other.errorType == errorType &&
        other.code == code &&
        other.isFromCache == isFromCache &&
        other.isFromStaleWhileRevalidate == isFromStaleWhileRevalidate &&
        other.isResiliencyFallback == isResiliencyFallback &&
        other.isFrom304 == isFrom304;
  }

  @override
  int get hashCode => Object.hash(
        state,
        message,
        data,
        error,
        errorType,
        code,
        isFromCache,
        isFromStaleWhileRevalidate,
        isResiliencyFallback,
        isFrom304,
      );
}

extension LikeStateResponseExtension<T> on LikeStateResponse<T> {
  /// Simple helper to build UI based on the current state.
  R when<R>({
    required R Function(
      T data,
      bool isRefreshing,
      bool isFromStaleWhileRevalidate,
      bool isResiliencyFallback,
    ) onSuccess,
    R Function()? onLoading,
    R Function()? onIdle,
    R Function(LikeError error)? onError,
    R Function(String message)? onException,
    required R Function() orElse,
  }) {
    switch (state) {
      case LikeState.idle:
        return onIdle?.call() ?? orElse();
      case LikeState.loading:
        return onLoading?.call() ?? orElse();
      case LikeState.error:
        return onError?.call(error!) ?? orElse();
      case LikeState.exception:
        return onException?.call(message) ?? orElse();
      case LikeState.success:
      case LikeState.refreshing:
      case LikeState.staleWhileRevalidate:
        if (data == null) return orElse();
        return onSuccess(
          data as T,
          state == LikeState.refreshing,
          state == LikeState.staleWhileRevalidate || isFromStaleWhileRevalidate,
          isResiliencyFallback,
        );
    }
  }

  /// Specialized helper for building slivers.
  List<Widget> whenSliver({
    required List<Widget> Function(
      T data,
      bool isRefreshing,
      bool isFromStaleWhileRevalidate,
      bool isResiliencyFallback,
    ) onSuccess,
    List<Widget> Function()? onLoading,
    List<Widget> Function()? onIdle,
    List<Widget> Function(LikeError error)? onError,
    List<Widget> Function(String message)? onException,
  }) {
    return when<List<Widget>>(
      onSuccess: onSuccess,
      onLoading: onLoading,
      onIdle: onIdle,
      onError: onError,
      onException: onException,
      orElse: () => [],
    );
  }
}
