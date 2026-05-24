import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:like/src/models/like_state_response.dart';

/// Internal registry for tracking in-flight requests and L1 (RAM) cache.
/// Prevents duplicate network requests and provides near-zero latency for session data.
class LikeRegistry {
  static final LikeRegistry _instance = LikeRegistry._internal();
  factory LikeRegistry() => _instance;
  LikeRegistry._internal();

  bool _disposed = false;

  /// Tracks active network requests to prevent duplication.
  final LinkedHashMap<String,
          (Future<LikeStateResponse<dynamic>>, CancelToken?)> _inFlight =
      LinkedHashMap();

  /// L1 Cache: Fast RAM-based storage for the current session.
  final LinkedHashMap<String, LikeStateResponse<dynamic>> _l1Cache =
      LinkedHashMap();

  /// Tracks which paths have been fetched in the current session.
  final LinkedHashSet<String> _sessionFetchedKeys = LinkedHashSet();

  // --- In-Flight Management ---

  void addInFlight(
    String key,
    Future<LikeStateResponse<dynamic>> future, {
    CancelToken? cancelToken,
  }) {
    if (_disposed) return;
    _inFlight[key] = (future, cancelToken);

    // Limit management
    if (_inFlight.length > 50) {
      _inFlight.remove(_inFlight.keys.first);
    }
  }

  (Future<LikeStateResponse<dynamic>>, CancelToken?)? getInFlight(String key) =>
      _inFlight[key];

  void removeInFlight(String key) => _inFlight.remove(key);

  // --- L1 Cache Management ---

  void setL1(String key, LikeStateResponse<dynamic> response) {
    if (_disposed) return;

    _l1Cache[key] = response;
    _sessionFetchedKeys.add(key);

    // Enforce capacity limits (LRU)
    if (_l1Cache.length > 100) {
      final oldest = _l1Cache.keys.first;
      _l1Cache.remove(oldest);
      _sessionFetchedKeys.remove(oldest);
    }
  }

  LikeStateResponse<dynamic>? getL1(String key) => _l1Cache[key];

  void clearL1() {
    _l1Cache.clear();
    _sessionFetchedKeys.clear();
  }

  // --- Session Stale Management ---

  void markStale(String key) => _sessionFetchedKeys.add(key);

  bool isStale(String key) => _sessionFetchedKeys.contains(key);

  void resetStale({String? path}) {
    if (path != null) {
      _sessionFetchedKeys.removeWhere((key) {
        if (key.contains(path)) {
          _l1Cache.remove(key);
          return true;
        }
        return false;
      });
    } else {
      _sessionFetchedKeys.clear();
      _l1Cache.clear();
    }
  }

  // --- Cleanup ---

  void dispose() {
    _disposed = true;
    for (final entry in _inFlight.values) {
      entry.$2?.cancel('Registry disposed');
    }
    _inFlight.clear();
    _l1Cache.clear();
    _sessionFetchedKeys.clear();
  }
}
