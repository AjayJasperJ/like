import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_sync_task.dart';

/// A class that encapsulates a [LikeStateResponse] and its associated [CancelToken].
///
/// This eliminates the boilerplate of declaring separate private backing fields,
/// getters, and cancel tokens in providers. Instead, you declare a single
/// final [LikeNotifierState] property and use the new `fetch` method.
class LikeNotifierState<T> extends ChangeNotifier {
  /// The current state response.
  LikeStateResponse<T> _value;

  LikeStateResponse<T> get value => _value;
  set value(LikeStateResponse<T> newValue) {
    if (_value == newValue) return;
    _value = newValue;
    notifyListeners();
  }

  /// The active cancel token for the request.
  CancelToken? ct;

  /// The captured query parameters from the last network request.
  Map<String, dynamic>? activeQuery;

  String? _endpointPath;
  String? _cleanEndpointPath;

  /// The captured endpoint path from the last network request.
  String? get endpointPath => _endpointPath;
  set endpointPath(String? value) {
    if (_endpointPath == value) return;
    _endpointPath = value;
    if (value != null) {
      if (value.startsWith('http://') || value.startsWith('https://')) {
        final uri = Uri.tryParse(value);
        _cleanEndpointPath = uri != null ? uri.path : value.split('?').first;
      } else {
        _cleanEndpointPath = value.split('?').first;
      }
    } else {
      _cleanEndpointPath = null;
    }
  }

  /// The cached clean endpoint path (without query parameters) for O(1) matching.
  String? get cleanEndpointPath => _cleanEndpointPath;

  /// Whether the notifier state should automatically resync when relevant mutations occur.
  bool autoResync = false;

  /// The priority queue level to assign during automated background resync.
  LikeSyncPriority syncPriority = LikeSyncPriority.normal;

  /// The stored trigger action to re-run the `fetch` in the background.
  Future<void> Function()? refreshAction;

  /// Optional mapper for automatic pipeline synchronization.
  ///
  /// When provided, the [LikeAutoReconnectMixin.fetch] method automatically
  /// registers this state as a pipeline listener. Any response from the same
  /// endpoint broadcast on the [LikePipeline] will be parsed using this mapper
  /// and applied to this state — with no extra configuration needed at the call site.
  final T Function(dynamic json)? mapper;

  LikeNotifierState({
    LikeStateResponse<T>? initialValue,
    this.mapper,
  }) : _value = initialValue ?? LikeStateResponse<T>.idle();

  // Convenience state getters
  bool get isSuccess => value.isSuccess;
  bool get isLoading => value.isLoading;
  bool get isError => value.isError;
  bool get isIdle => value.isIdle;
  bool get isException => value.isException;
  bool get isRefreshing => value.isRefreshing;
  bool get isStaleWhileRevalidate => value.isStaleWhileRevalidate;

  /// Retrieves the current data payload.
  T? get data => value.data;

  /// Retrieves the current descriptive message.
  String get message => value.message;

  /// Retrieves the error payload if in [LikeState.error].
  LikeError? get error => value.error;

  /// Resets the state to idle and cancels any active request.
  void clear({String? message}) {
    ct?.cancel('State cleared');
    ct = null;
    activeQuery = null;
    endpointPath = null;
    refreshAction = null;
    value = LikeStateResponse<T>.idle(message: message);
  }

  /// Cancels the active request if running.
  void cancel([String? message]) {
    if (ct != null && !ct!.isCancelled) {
      ct!.cancel(message ?? 'Request cancelled');
    }
    ct = null;
  }
}
