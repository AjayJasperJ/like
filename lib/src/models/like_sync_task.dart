/// Priority levels for background synchronization.
///
/// Aligned with enterprise's SyncPriority architecture.
enum LikeSyncPriority {
  /// Immediate execution. Used when a user is actively waiting for data
  /// (e.g., current screen needs this result).
  critical,

  /// Default priority for most background tasks.
  normal,

  /// Lowest priority. Used for maintenance, cleanup, or non-urgent pre-fetching.
  background,
}

/// A task to be executed by the [LikeSyncManager].
/// Refactored to an abstract class for better parity with enterprise's SyncTask.
abstract class LikeSyncTask {
  /// Base endpoint this task is associated with.
  /// Used for deduplication and potentially triggering UI refreshes.
  String? get endpoint => null;

  /// Unique identifier for this task.
  String get id =>
      endpoint != null ? 'sync_$endpoint' : 'task_${runtimeType.toString()}';

  /// Priority level for scheduling.
  LikeSyncPriority get priority;

  /// The actual implementation of the work to be performed.
  /// This method is called by the [LikeSyncManager].
  Future<void> run();

  /// Whether this task should be retried if it fails.
  bool get retryOnError => true;

  /// Whether this task represents a recovery from error (e.g., offline sync).
  bool get isRecovery => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LikeSyncTask &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A concrete implementation of [LikeSyncTask] that allows defining the work
/// via an inline function or callback.
class LikeAdHocSyncTask extends LikeSyncTask {
  @override
  final String id;
  @override
  final LikeSyncPriority priority;
  final Future<void> Function() _action;
  @override
  final String? endpoint;
  @override
  final bool retryOnError;
  @override
  final bool isRecovery;

  LikeAdHocSyncTask({
    required this.id,
    this.priority = LikeSyncPriority.normal,
    required Future<void> Function() action,
    this.endpoint,
    this.retryOnError = true,
    this.isRecovery = false,
  }) : _action = action;

  @override
  Future<void> run() => _action();
}
