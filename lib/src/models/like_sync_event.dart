/// Represents a synchronization event broadcasted after a successful mutation.
///
/// Carries the API [path] and a merged [payload] map (consisting of request body
/// and query parameters) used by automated resync systems to match active queries.
class LikeSyncEvent {
  /// The request path of the mutation that occurred (e.g., `/attendance`).
  final String path;

  /// The merged map of request body and query parameters.
  final Map<String, dynamic> payload;

  const LikeSyncEvent({required this.path, required this.payload});

  @override
  String toString() => 'LikeSyncEvent(path: $path, payload: $payload)';
}
