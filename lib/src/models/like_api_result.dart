import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_state_response.dart';

/// Generic result wrapper for API responses.
/// Note: Both 200 OK and 304 Not Modified are considered success states.
class LikeApiResult<T> {
  final T? data;
  final LikeError? error;
  final bool isSuccess;
  final bool isFromCache;
  final bool isFromStaleWhileRevalidate;
  final bool isResiliencyFallback;
  final bool isFrom304;

  bool get isError => !isSuccess;

  LikeApiResult.success(
    this.data, {
    this.isFromCache = false,
    this.isFromStaleWhileRevalidate = false,
    this.isResiliencyFallback = false,
    this.isFrom304 = false,
  }) : error = null,
       isSuccess = true;

  LikeApiResult.error(
    this.error, {
    this.isFromCache = false,
    this.isFromStaleWhileRevalidate = false,
    this.isResiliencyFallback = false,
    this.isFrom304 = false,
  }) : data = null,
       isSuccess = false;

  /// `when()` lets you handle success or error elegantly
  R when<R>({
    required R Function(T data) onSuccess,
    required R Function(LikeError error) onError,
  }) {
    if (isSuccess && data != null) {
      return onSuccess(data as T);
    } else {
      return onError(error!);
    }
  }

  /// Optional: `maybeWhen` allows partial handling
  R maybeWhen<R>({
    R Function(T data)? onSuccess,
    R Function(LikeError error)? onError,
    required R Function() orElse,
  }) {
    if (isSuccess && data != null && onSuccess != null) {
      return onSuccess(data as T);
    } else if (!isSuccess && onError != null && error != null) {
      return onError(error!);
    } else {
      return orElse();
    }
  }

  /// Maps the success data to a new type.
  LikeApiResult<R> mapSuccess<R>(R Function(T data) mapper) {
    if (isSuccess && data != null) {
      try {
        return LikeApiResult.success(
          mapper(data as T),
          isFromCache: isFromCache,
          isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
          isResiliencyFallback: isResiliencyFallback,
        );
      } catch (e) {
        // If mapping fails, consider it an error (parsing error)
        return LikeApiResult.error(
          LikeError(
            message: 'Mapping failed: $e',
            type: LikeApiErrorType.unknown,
          ),
          isFromCache: isFromCache,
          isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
          isResiliencyFallback: isResiliencyFallback,
        );
      }
    }
    return LikeApiResult.error(
      error,
      isFromCache: isFromCache,
      isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
      isResiliencyFallback: isResiliencyFallback,
    );
  }

  /// Maps the success data to a new type using a background isolate.
  /// Ideal for parsing large lists or complex models in the Repository layer.
  Future<LikeApiResult<R>> mapSuccessAsync<R>(
    LikeModelFactory<R> mapper,
  ) async {
    if (isSuccess && data != null) {
      try {
        final Map<String, dynamic> rawData;
        if (data is Response) {
          rawData = (data as Response).data as Map<String, dynamic>;
        } else if (data is Map<String, dynamic>) {
          rawData = data as Map<String, dynamic>;
        } else {
          return mapSuccess((d) => mapper(d as Map<String, dynamic>));
        }

        final result = await compute<_IsolateMapperParams<R>, R>(
          _isolateMapper,
          _IsolateMapperParams<R>(rawData, mapper),
        );

        return LikeApiResult.success(
          result,
          isFromCache: isFromCache,
          isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
          isResiliencyFallback: isResiliencyFallback,
        );
      } catch (e) {
        return LikeApiResult.error(
          LikeError(
            message: 'Async mapping failed: $e',
            type: LikeApiErrorType.parsing,
          ),
          isFromCache: isFromCache,
          isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
          isResiliencyFallback: isResiliencyFallback,
        );
      }
    }
    return LikeApiResult.error(
      error,
      isFromCache: isFromCache,
      isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
      isResiliencyFallback: isResiliencyFallback,
    );
  }

  /// Converts this result to a [LikeStateResponse].
  LikeStateResponse<T> toStateResponse() {
    if (isSuccess && data != null) {
      return LikeStateResponse.success(
        data as T,
        isFromCache: isFromCache,
        isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
        isResiliencyFallback: isResiliencyFallback,
        isFrom304: isFrom304,
      );
    } else {
      final err =
          error ??
          LikeError(message: 'Unknown error', type: LikeApiErrorType.unknown);
      return LikeStateResponse<T>.error(
        err,
        data: data,
        isFromCache: isFromCache,
        isFromStaleWhileRevalidate: isFromStaleWhileRevalidate,
        isResiliencyFallback: isResiliencyFallback,
        isFrom304: isFrom304,
      );
    }
  }
}

/// Extension to reduce boilerplate in repositories when dealing with Futures of results.
extension LikeApiResultFutureX on Future<LikeApiResult<Response>> {
  /// Maps a [Response] to a model [R] asynchronously in a background isolate.
  Future<LikeApiResult<R>> mapAsync<R>(LikeModelFactory<R> mapper) async {
    final result = await this;
    return await result.mapSuccessAsync(mapper);
  }

  /// Maps a [Response] to a model [R] synchronously on the main thread.
  Future<LikeApiResult<R>> mapSync<R>(
    R Function(Map<String, dynamic> data) mapper,
  ) async {
    final result = await this;
    return result.mapSuccess((res) => mapper(res.data as Map<String, dynamic>));
  }
}

/// Isolate mapper internal helpers
class _IsolateMapperParams<T> {
  final Map<String, dynamic> data;
  final LikeModelFactory<T> factory;
  _IsolateMapperParams(this.data, this.factory);
}

T _isolateMapper<T>(_IsolateMapperParams<T> params) {
  return params.factory(params.data);
}
