import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';

class _L1CacheEntry {
  final Response? response;
  final DateTime timestamp;

  _L1CacheEntry({
    required this.response,
    required this.timestamp,
  });
}

/// Registry to track in-flight requests and session-stale keys (L1 Memory Cache).
/// Matches enterprise's RequestRegistry parity.
///
/// Each [LikeClient] instance owns its own [LikeRequestRegistry]. This ensures
/// that clients with different base URLs (e.g., created via [LikeClient.copyWith])
/// never share or corrupt each other's cache state.
class LikeRequestRegistry {
  bool _disposed = false;

  final LinkedHashMap<String, _L1CacheEntry> _l1Cache = LinkedHashMap();

  final LinkedHashMap<String, (Future<Response>, CancelToken?)>
      _inFlightRequests = LinkedHashMap();

  /// Adds a key to the session-fetched set and stores its data in the L1 RAM cache.
  void addSessionKey(String key, {Response? response}) {
    if (_disposed) return;

    // Deduplicate: move key to the end to maintain LRU/MRU ordering
    _l1Cache.remove(key);
    _l1Cache[key] = _L1CacheEntry(
      response: response,
      timestamp: DateTime.now(),
    );

    // Enforce limits with a single eviction
    if (_l1Cache.length > LikeConstants.maxL1CacheItems) {
      _l1Cache.remove(_l1Cache.keys.first);
    }
  }

  /// Checks if a key has been fetched in the current session.
  bool isSessionStale(String key) => _l1Cache.containsKey(key);

  /// Retrieves a response directly from the O(1) L1 RAM cache.
  Response? getSessionData(String key) => _l1Cache[key]?.response;

  /// Checks if the data for this key is "fresh" within a given TTL.
  bool isFresh(String key, {Duration? ttl}) {
    final entry = _l1Cache[key];
    if (entry == null) return false;
    final effectiveTtl =
        ttl ?? Duration(seconds: LikeConstants.sessionStaleTTL);
    return DateTime.now().difference(entry.timestamp) < effectiveTtl;
  }

  /// Resets session stale keys and memory cache, optionally for a specific path prefix.
  void resetSessionStale({String? path}) {
    if (path != null) {
      _l1Cache.removeWhere((key, _) => key.contains(path));
    } else {
      _l1Cache.clear();
    }
  }

  /// Registers an in-flight request for deduplication.
  void addInFlight(String key, (Future<Response>, CancelToken?) entry) {
    if (_disposed) return;
    _inFlightRequests[key] = entry;

    if (_inFlightRequests.length > LikeConstants.maxInFlightRequests) {
      _inFlightRequests.remove(_inFlightRequests.keys.first);
    }
  }

  /// Checks if a request is already in flight.
  (Future<Response>, CancelToken?)? getInFlight(String key) =>
      _inFlightRequests[key];

  /// Removes an in-flight request only while [owner] still owns [key].
  ///
  /// A newer take-latest request may replace the entry before an older
  /// request's completion callback runs. Comparing the future by identity
  /// prevents that older callback from deleting the newer active request.
  bool removeInFlight(String key, Future<Response> owner) {
    final current = _inFlightRequests[key];
    if (current == null || !identical(current.$1, owner)) return false;
    _inFlightRequests.remove(key);
    return true;
  }

  /// Cancels all in-flight requests and clears state.
  void clear() {
    for (final entry in _inFlightRequests.values) {
      entry.$2?.cancel('Session cleared');
    }
    _inFlightRequests.clear();
    _l1Cache.clear();
    _disposed = false;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
