import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/client/like_pipeline.dart';

/// A mixin that provides a universal way for [ChangeNotifier] providers
/// to listen to the global [LikePipeline] and synchronize their local state.
/// Matches the exact signature and logic of enterprise's DataPipelineMixin.
mixin LikePipelineMixin on ChangeNotifier {
  StreamSubscription? _pipelineSubscription;
  final Map<
    String,
    void Function(
      String key,
      dynamic data, {
      bool isSyncing,
      DateTime? timestamp,
    })
  >
  _pipelineListeners = {};

  /// Initializes the pipeline listener with a set of URI patterns and their corresponding callbacks.
  void initPipeline(
    Map<
      String,
      void Function(
        String key,
        dynamic data, {
        bool isSyncing,
        DateTime? timestamp,
      })
    >
    registrations,
  ) {
    _pipelineSubscription?.cancel();
    _pipelineListeners.clear();
    _pipelineListeners.addAll(registrations);

    _pipelineSubscription = LikePipeline().stream.listen((LikeEvent event) {
      bool handled = false;
      final incomingKey = event.key;

      // Extract path for matching (matches enterprise logic)
      final incomingPath = incomingKey.contains(':')
          ? incomingKey.split(':').last
          : incomingKey;
      final cleanIncomingPath = incomingPath.split('?').first;

      for (final entry in _pipelineListeners.entries) {
        final listenerPattern = entry.key;

        // Exact match or directory-style prefix match
        if (cleanIncomingPath == listenerPattern ||
            (cleanIncomingPath.startsWith(listenerPattern) &&
                cleanIncomingPath[listenerPattern.length] == '/')) {
          entry.value(
            incomingKey,
            event.data,
            isSyncing: event.isSyncing,
            timestamp: event.timestamp,
          );
          handled = true;
        }
      }

      if (handled) {
        notifyListeners();
      }
    });
  }

  /// Adds a single listener for a specific URI pattern.
  void registerPipelineListener(
    String pattern,
    void Function(
      String key,
      dynamic data, {
      bool isSyncing,
      DateTime? timestamp,
    })
    callback,
  ) {
    _pipelineListeners[pattern] = callback;
    if (_pipelineSubscription != null) {
      initPipeline(Map.from(_pipelineListeners));
    }
  }

  /// Removes a listener associated with a specific URI pattern.
  void unregisterPipelineListener(String pattern) {
    _pipelineListeners.remove(pattern);
    if (_pipelineSubscription != null) {
      initPipeline(Map.from(_pipelineListeners));
    }
  }

  @override
  void dispose() {
    _pipelineSubscription?.cancel();
    _pipelineListeners.clear();
    super.dispose();
  }
}
