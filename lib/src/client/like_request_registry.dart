import 'dart:async';
import 'dart:collection';
import 'package:dio/dio.dart';
import 'package:like/src/core/like_constants.dart';

/// Registry to track in-flight requests and session-stale keys (L1 Memory Cache).
/// Matches enterprise's RequestRegistry parity.
///
/// Each [LikeClient] instance owns its own [LikeRequestRegistry]. This ensures
/// that clients with different base URLs (e.g., created via [LikeClient.copyWith])
/// never share or corrupt each other's cache state.
class LikeRequestRegistry {

  bool _disposed = false;

  final LinkedHashSet<String> _sessionFetchedKeys = LinkedHashSet();
  final LinkedHashMap<String, Response> _l1Cache = LinkedHashMap();

  final LinkedHashMap<String, (Future<Response>, CancelToken?)>
  _inFlightRequests = LinkedHashMap();

  final LinkedHashMap<String, DateTime> _lastFetchedTimestamps =
      LinkedHashMap();

  /// Adds a key to the session-fetched set and stores its data in the L1 RAM cache.
  void addSessionKey(String key, {Response? response}) {
    if (_disposed) return;

    // Manage session keys
    if (_sessionFetchedKeys.contains(key)) {
      _sessionFetchedKeys.remove(key);
    }
    _sessionFetchedKeys.add(key);

    // Manage L1 RAM cache
    if (response != null) {
      if (_l1Cache.containsKey(key)) {
        _l1Cache.remove(key);
      }
      _l1Cache[key] = response;
    }

    _lastFetchedTimestamps[key] = DateTime.now();

    // Enforce limits
    if (_sessionFetchedKeys.length > LikeConstants.maxL1CacheItems) {
      final oldKey = _sessionFetchedKeys.first;
      _sessionFetchedKeys.remove(oldKey);
      _l1Cache.remove(oldKey);
    }

    if (_l1Cache.length > LikeConstants.maxL1CacheItems) {
      _l1Cache.remove(_l1Cache.keys.first);
    }

    if (_lastFetchedTimestamps.length > LikeConstants.maxL1CacheItems) {
      _lastFetchedTimestamps.remove(_lastFetchedTimestamps.keys.first);
    }
  }

  /// Checks if a key has been fetched in the current session.
  bool isSessionStale(String key) => _sessionFetchedKeys.contains(key);

  /// Retrieves a response directly from the O(1) L1 RAM cache.
  Response? getSessionData(String key) => _l1Cache[key];

  /// resetSessionStale: Checks if the data for this key is "fresh" within a given TTL.
  bool isFresh(String key, {Duration? ttl}) {
    final last = _lastFetchedTimestamps[key];
    if (last == null) return false;
    final effectiveTtl =
        ttl ?? Duration(seconds: LikeConstants.sessionStaleTTL);
    return DateTime.now().difference(last) < effectiveTtl;
  }

  /// Resets session stale keys and memory cache, optionally for a specific path prefix.
  void resetSessionStale({String? path}) {
    if (path != null) {
      _sessionFetchedKeys.removeWhere((key) {
        if (key.contains(path)) {
          _l1Cache.remove(key);
          _lastFetchedTimestamps.remove(key);
          return true;
        }
        return false;
      });
    } else {
      _sessionFetchedKeys.clear();
      _l1Cache.clear();
      _lastFetchedTimestamps.clear();
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

  /// Removes a request from the in-flight map.
  void removeInFlight(String key) => _inFlightRequests.remove(key);

  /// Cancels all in-flight requests and clears state.
  void clear() {
    for (final entry in _inFlightRequests.values) {
      entry.$2?.cancel('Session cleared');
    }
    _inFlightRequests.clear();
    _sessionFetchedKeys.clear();
    _l1Cache.clear();
    _lastFetchedTimestamps.clear();
    _disposed = false;
  }

  void dispose() {
    _disposed = true;
    clear();
  }
}
