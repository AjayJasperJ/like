/// Describes a meaningful reachability transition for one canonical API origin.
///
/// Origins use the canonical `scheme://host:effectivePort` form produced by
/// `LikeConnectivityManager.canonicalOrigin`.
class LikeConnectivityTransition {
  /// Canonical origin whose reachability changed.
  final String origin;

  /// Previously known reachability, or `null` when it was unknown.
  final bool? previousAvailability;

  /// Newly observed reachability, or `null` when it became unknown.
  final bool? availability;

  /// Time at which the transition was recorded.
  final DateTime timestamp;

  const LikeConnectivityTransition({
    required this.origin,
    required this.previousAvailability,
    required this.availability,
    required this.timestamp,
  });

  /// Whether this is an exact unavailable-to-available restoration.
  bool get isRestoration =>
      previousAvailability == false && availability == true;

  /// Whether this transition reports that the origin became unavailable.
  bool get becameUnavailable => availability == false;

  @override
  String toString() => 'LikeConnectivityTransition(origin: $origin, '
      'previousAvailability: $previousAvailability, '
      'availability: $availability, timestamp: $timestamp)';
}
