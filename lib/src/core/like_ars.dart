/// Advanced Request Settings (ARS) for fine-grained network control.
/// Mirrors the core enterprise network capabilities.
typedef ARS = LikeARS;

class LikeARS {
  /// Enables Stale-While-Revalidate (Instant UI + Background Refresh).
  /// If true, cached data is returned immediately while a network refresh
  /// occurs in the background.
  final bool staleWhileRevalidate;

  /// If true, the request is an explicit refresh (e.g., pull-to-refresh).
  /// Used by providers to decide whether to show a loading state or keep
  /// the current data visible (sticky data).
  final bool refresh;

  /// If true, only fetches from the network if no data has been successfully
  /// retrieved for this specific resource in the current application session.
  final bool singleFetch;

  /// If true, checks the L1 RAM cache before hitting the network or disk.
  /// Ideal for frequently accessed data that rarely changes during a session.
  final bool sessionStale;

  /// If true, bypasses all caching layers and forces a network request.
  final bool disableCache;

  /// If true, invalidates the `singleFetch` flag and forces a new network fetch.
  final bool resetSingleFetch;

  /// If true, invalidates the `sessionStale` flag and forces a network fetch
  /// even if L1 cache is available.
  final bool resetSessionStale;

  /// If true, suppresses toast notifications for errors.
  /// Useful for background syncs or non-critical pre-fetching.
  final bool suppressErrors;

  /// If true, this request will be persisted and re-tried if it fails
  /// due to connectivity issues (only for mutation methods like POST/PUT/DELETE).
  final bool offlineSync;

  /// Whether to verify the SSL certificate of the remote server.
  final bool verifySSL;

  /// Enables request deduplication.
  /// If true, multiple simultaneous calls to the same endpoint will wait
  /// for a single shared in-flight network request.
  final bool deduplicate;

  const LikeARS({
    this.staleWhileRevalidate = true,
    this.refresh = false,
    this.singleFetch = false,
    this.sessionStale = false,
    this.disableCache = false,
    this.resetSingleFetch = false,
    this.resetSessionStale = false,
    this.offlineSync = false,
    this.verifySSL = true,
    this.deduplicate = true,
    this.suppressErrors = true,
  });

  Map<String, dynamic> toJson() => {
    'staleWhileRevalidate': staleWhileRevalidate,
    'refresh': refresh,
    'singleFetch': singleFetch,
    'sessionStale': sessionStale,
    'disableCache': disableCache,
    'resetSingleFetch': resetSingleFetch,
    'resetSessionStale': resetSessionStale,
    'offlineSync': offlineSync,
    'verifySSL': verifySSL,
    'deduplicate': deduplicate,
    'suppressErrors': suppressErrors,
  };

  factory LikeARS.fromJson(Map<String, dynamic> json) => LikeARS(
    staleWhileRevalidate: json['staleWhileRevalidate'] ?? true,
    refresh: json['refresh'] ?? false,
    singleFetch: json['singleFetch'] ?? false,
    sessionStale: json['sessionStale'] ?? false,
    disableCache: json['disableCache'] ?? false,
    resetSingleFetch: json['resetSingleFetch'] ?? false,
    resetSessionStale: json['resetSessionStale'] ?? false,
    offlineSync: json['offlineSync'] ?? false,
    deduplicate: json['deduplicate'] ?? true,
    suppressErrors: json['suppressErrors'] ?? true,
  );
}
