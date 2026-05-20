import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/services/like_pipeline.dart';
import 'package:like/src/models/like_notifier_state.dart';
import 'package:like/src/models/like_state_response.dart';

class _LikePipelineStateBinding {
  final Object identity; // Used for deduplication
  final String? Function() getEndpointPath;
  final Map<String, dynamic> Function() getActiveQuery;
  final bool exactQueryMatch;
  final void Function(dynamic rawData) processAndAssign;

  _LikePipelineStateBinding({
    required this.identity,
    required this.getEndpointPath,
    required this.getActiveQuery,
    required this.exactQueryMatch,
    required this.processAndAssign,
  });

  @override
  bool operator ==(Object other) =>
      other is _LikePipelineStateBinding && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// A mixin that provides a universal way for [ChangeNotifier] providers
/// to listen to the global [LikePipeline] and synchronize their local state.
/// Matches the exact signature and logic of enterprise's DataPipelineMixin,
/// and includes an automated [bindPipeline] declarative mechanism.
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

  final Set<_LikePipelineStateBinding> _pipelineBindings = {};

  /// Declarative pipeline synchronization using [LikeNotifierState].
  ///
  /// Automatically listens to the pipeline and updates the [state] whenever
  /// a network response for the same endpoint is broadcast.
  ///
  /// The [state] must have a [LikeNotifierState.mapper] defined.
  /// The endpoint is resolved lazily from [state.endpointPath], populated
  /// after the first fetch — safely before any mutation can broadcast.
  void bindPipeline<T>(LikeNotifierState<T> state) {
    assert(
      state.mapper != null,
      '[like] bindPipeline requires LikeNotifierState to have a mapper. '
      'Pass mapper: (json) => YourModel.fromJson(json) in the constructor.',
    );

    // Deduplicate: remove any prior binding for this exact state object
    _pipelineBindings.removeWhere((b) => b.identity == state);
    _pipelineBindings.add(_LikePipelineStateBinding(
      identity: state,
      getEndpointPath: () => state.endpointPath,
      getActiveQuery: () => state.activeQuery ?? const {},
      exactQueryMatch: false,
      processAndAssign: (rawData) {
        if (state.value.isLoading || state.value.isRefreshing) return;
        final mappedData = state.mapper!(rawData);
        state.value = LikeStateResponse<T>.success(
          mappedData,
          isFromCache: false,
        );
      },
    ));

    if (_pipelineSubscription == null) {
      _startPipelineListener();
    }
  }

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
    _pipelineListeners.clear();
    _pipelineListeners.addAll(registrations);
    _startPipelineListener();
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
    _startPipelineListener();
  }

  /// Removes a listener associated with a specific URI pattern.
  void unregisterPipelineListener(String pattern) {
    _pipelineListeners.remove(pattern);
    if (_pipelineListeners.isEmpty && _pipelineBindings.isEmpty) {
      _pipelineSubscription?.cancel();
      _pipelineSubscription = null;
    } else {
      _startPipelineListener();
    }
  }

  void _startPipelineListener() {
    _pipelineSubscription?.cancel();
    _pipelineSubscription = LikePipeline().stream.listen((LikeEvent event) {
      bool handled = false;
      final incomingKey = event.key;

      // Extract path for matching
      final incomingPath = incomingKey.contains(':')
          ? incomingKey.split(':').last
          : incomingKey;
      final cleanIncomingPath = incomingPath.split('?').first;
      
      // Extract query from event
      final eventQuery = event.response.requestOptions.queryParameters;

      // 1. Process legacy manual listeners
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

      // 2. Process declarative bindings
      for (final binding in _pipelineBindings) {
        final endpointPath = binding.getEndpointPath();
        if (endpointPath == null) continue;

        final statePath = endpointPath.split('?').first;

        if (cleanIncomingPath == statePath ||
            (cleanIncomingPath.startsWith(statePath) &&
                cleanIncomingPath[statePath.length] == '/')) {
          
          final overlap = _checkQueryOverlap(
            binding.getActiveQuery(), 
            eventQuery, 
            exact: binding.exactQueryMatch
          );
          
          if (overlap) {
            try {
              binding.processAndAssign(event.data);
              handled = true;
            } catch (e) {
              debugPrint('LikePipelineMixin Mapping Error: $e');
            }
          }
        }
      }

      if (handled) {
        notifyListeners();
      }
    });
  }

  bool _checkQueryOverlap(Map<String, dynamic> stateQuery, Map<String, dynamic> eventQuery, {bool exact = false}) {
    if (exact) {
      if (stateQuery.length != eventQuery.length) return false;
      for (final key in stateQuery.keys) {
        if (stateQuery[key]?.toString() != eventQuery[key]?.toString()) return false;
      }
      return true;
    }

    if (stateQuery.isEmpty || eventQuery.isEmpty) return true;
    for (final entry in eventQuery.entries) {
      final key = entry.key;
      if (stateQuery.containsKey(key)) {
        if (stateQuery[key]?.toString() != entry.value?.toString()) {
          return false;
        }
      }
    }
    return true;
  }

  @override
  void dispose() {
    _pipelineSubscription?.cancel();
    _pipelineListeners.clear();
    _pipelineBindings.clear();
    super.dispose();
  }
}
