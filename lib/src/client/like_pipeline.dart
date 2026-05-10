import 'dart:async';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_event.dart';

/// The global event bus for all network traffic in the LIKE engine.
/// Emits [LikeEvent] whenever a request completes, allowing global state synchronization.
class LikePipeline {
  static final LikePipeline _instance = LikePipeline._internal();
  factory LikePipeline() => _instance;
  LikePipeline._internal();

  final StreamController<LikeEvent> _streamController =
      StreamController<LikeEvent>.broadcast();

  /// Stream of all network events.
  Stream<LikeEvent> get stream => _streamController.stream;

  /// Emits an event to the pipeline.
  void emit(
    String key,
    Response response, {
    dynamic model,
    bool isSyncing = false,
    DateTime? timestamp,
  }) {
    if (!_streamController.isClosed) {
      _streamController.add(
        LikeEvent(
          key: key,
          response: response,
          model: model,
          isSyncing: isSyncing,
          timestamp: timestamp,
        ),
      );
    }
  }

  /// Broadcasts a manual refresh signal for a specific path.
  void refresh(String path) {
    // Note: Manual refresh doesn't carry a response, but triggers listeners.
    // In enterprise, this is often handled by invalidating cache and re-fetching.
  }

  void dispose() {
    _streamController.close();
  }
}
