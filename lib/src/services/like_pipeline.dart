import 'dart:async';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_event.dart';

/// A reactive event bus for the LIKE networking engine.
/// Broadcasts successful network events (including cache and SWR) to observers.
/// Matches enterprise's NetworkPipeline parity.
class LikePipeline {
  static final LikePipeline _instance = LikePipeline._internal();
  factory LikePipeline() => _instance;
  LikePipeline._internal();

  final StreamController<LikeEvent> _responseController =
      StreamController<LikeEvent>.broadcast();

  /// Stream of [LikeEvent]s emitted by the client and interceptors.
  Stream<LikeEvent> get stream => _responseController.stream;

  /// Emits a new event to all observers.
  void emit(
    String key,
    Response data, {
    dynamic model,
    bool isSyncing = false,
    DateTime? timestamp,
  }) {
    if (!_responseController.isClosed) {
      _responseController.add(
        LikeEvent(
          key: key,
          response: data,
          model: model,
          isSyncing: isSyncing,
          timestamp: timestamp ?? DateTime.now(),
        ),
      );
    }
  }

  /// Closes the pipeline.
  void dispose() {
    _responseController.close();
  }
}
