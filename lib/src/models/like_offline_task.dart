enum LikeOfflineTaskStatus { pending, running, blocked, failed }

/// Metadata-only queue view. Bodies and credentials are deliberately excluded.
class LikeOfflineTask {
  final dynamic key;
  final String id;
  final String origin;
  final int attempts;
  final LikeOfflineTaskStatus status;
  final String? failure;
  final DateTime? nextAttemptAt;
  const LikeOfflineTask({required this.key, required this.id, required this.origin,
    required this.attempts, required this.status, this.failure, this.nextAttemptAt});
}
