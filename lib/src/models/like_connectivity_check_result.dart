/// Describes why a connectivity check was started.
enum LikeConnectivityCheckReason {
  /// A caller explicitly requested a full connectivity check.
  manual,

  /// A caller explicitly requested a server-only reachability check.
  manualServer,

  /// A connectivity interface change triggered the check.
  connectivityChange,

  /// A terminal, ambiguous Dio transport failure triggered the check.
  apiFailure,
}

/// Structured snapshot produced by a LIKE connectivity check.
class LikeConnectivityCheckResult {
  /// Why this check was performed.
  final LikeConnectivityCheckReason reason;

  /// Whether the platform reports at least one usable network interface.
  final bool hasNetworkInterface;

  /// Whether general internet reachability was established.
  ///
  /// On web this reflects browser-safe interface evidence and is never changed
  /// to false merely because one API origin produced a no-response failure.
  final bool isInternetReachable;

  /// Reachability of [origin], or `null` when it cannot be established safely.
  final bool? isServerAvailable;

  /// Canonical lower-case `scheme://host:effectivePort`, if a server was checked.
  final String? origin;

  /// Time at which the result was produced.
  final DateTime timestamp;

  const LikeConnectivityCheckResult({
    required this.reason,
    required this.hasNetworkInterface,
    required this.isInternetReachable,
    required this.isServerAvailable,
    required this.origin,
    required this.timestamp,
  });

  /// Legacy-compatible combined online status.
  ///
  /// Unknown server state does not make an otherwise reachable network offline.
  bool get hasConnection =>
      hasNetworkInterface && isInternetReachable && (isServerAvailable ?? true);

  /// Alias retained for callers using the manager's legacy naming.
  bool get isOnline => hasConnection;
}
