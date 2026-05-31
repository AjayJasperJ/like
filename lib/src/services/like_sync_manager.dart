import 'dart:async';
import 'package:collection/collection.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:like/src/models/like_sync_task.dart';

/// Status of the synchronization manager.
enum LikeSyncStatus { idle, syncing, completed, error }

/// Manager for orchestrating background synchronization tasks with priority-based execution.
/// Matches enterprise's SyncManager parity.
class LikeSyncManager {
  static final LikeSyncManager _instance = LikeSyncManager._internal();
  factory LikeSyncManager() => _instance;

  LikeSyncManager._internal() {
    _init();
  }

  final PriorityQueue<LikeSyncTask> _taskQueue = PriorityQueue<LikeSyncTask>((
    a,
    b,
  ) {
    return a.priority.index.compareTo(b.priority.index);
  });

  final Map<String, LikeSyncTask> _pendingTasks = {};
  bool _isProcessing = false;
  LikeSyncStatus _status = LikeSyncStatus.idle;

  final _statusController = StreamController<LikeSyncStatus>.broadcast();
  Stream<LikeSyncStatus> get statusStream => _statusController.stream;

  /// The current synchronization status.
  LikeSyncStatus get status => _status;

  int _totalTasks = 0;
  int _completedTasks = 0;
  bool _hasRecoveryTask = false;
  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  /// Whether there is currently a recovery task (e.g., offline sync) in the queue.
  bool get hasRecoveryTask => _hasRecoveryTask;

  void _init() {
    LikeConnectivityManager().connectionChange.listen((hasConnection) {
      if (hasConnection && _taskQueue.isNotEmpty && !_isProcessing) {
        processQueue();
      }
    });
  }

  /// Registers a task in the synchronization queue.
  ///
  /// Tasks are executed based on their [LikeSyncPriority]. If a task with the
  /// same ID already exists, its priority will be upgraded if the new task
  /// has a higher priority level.
  void registerTask(LikeSyncTask task) {
    final existingTask = _pendingTasks[task.id];
    if (existingTask != null) {
      if (task.priority.index < existingTask.priority.index) {
        LikeLogger.log(
          level: LikeLogLevel.info,
          category: 'sync',
          message:
              'Upgrading task ${task.id} priority: ${existingTask.priority.name} -> ${task.priority.name}',
        );
        _taskQueue.remove(existingTask);
        _taskQueue.add(task);
        _pendingTasks[task.id] = task;
      }
      return;
    }

    if (!_isProcessing && _taskQueue.isEmpty) {
      _totalTasks = 0;
      _completedTasks = 0;
      _hasRecoveryTask = false;
    }

    if (task.isRecovery) _hasRecoveryTask = true;

    _totalTasks++;
    _taskQueue.add(task);
    _pendingTasks[task.id] = task;

    LikeLogger.log(
      level: LikeLogLevel.info,
      category: 'sync',
      message:
          'Registered sync task: ${task.id} (Priority: ${task.priority.name}, Total: $_totalTasks)',
    );

    _updateProgress();

    if (LikeConnectivityManager().hasConnection && !_isProcessing) {
      processQueue();
    }
  }

  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;

  /// Manually starts the execution of the synchronization queue.
  ///
  /// The queue will only be processed if the device has an active connection.
  Future<void> processQueue() async {
    if (_isProcessing || _taskQueue.isEmpty) return;

    _isProcessing = true;
    _updateStatus(LikeSyncStatus.syncing);

    try {
      while (_taskQueue.isNotEmpty) {
        if (!LikeConnectivityManager().hasConnection) {
          LikeLogger.log(
            level: LikeLogLevel.warning,
            category: 'sync',
            message: 'Connectivity lost during sync. Pausing queue.',
          );
          break;
        }

        final task = _taskQueue.removeFirst();
        _pendingTasks.remove(task.id);

        try {
          LikeLogger.log(
            level: LikeLogLevel.info,
            category: 'sync',
            message: 'Executing sync task: ${task.id}',
          );

          await task.run();

          _completedTasks++;
          _updateProgress();
          _consecutiveFailures = 0; // Reset consecutive failures on success

          if (_taskQueue.isNotEmpty) {
            await Future.delayed(const Duration(milliseconds: 300));
          }
        } catch (e) {
          _consecutiveFailures++;
          LikeLogger.log(
            level: LikeLogLevel.error,
            category: 'sync',
            message: 'Error executing task ${task.id} (failure $_consecutiveFailures): $e',
          );

          // Circuit Breaker: Halt queue execution if server/network fails repeatedly
          if (_consecutiveFailures >= _maxConsecutiveFailures) {
            LikeLogger.log(
              level: LikeLogLevel.error,
              category: 'sync',
              message: 'Circuit breaker tripped after $_consecutiveFailures consecutive failures. Pausing queue and marking server as offline.',
            );
            // Put failed task back to front or let it be handled later. Since it was removed, we should re-register it to not lose it.
            _taskQueue.add(task);
            _pendingTasks[task.id] = task;
            
            // Trip: mark server as offline
            LikeConnectivityManager().markServerUnavailable();
            _consecutiveFailures = 0;
            break;
          }
        }
      }
    } finally {
      _isProcessing = false;
      _updateStatus(
        _taskQueue.isEmpty ? LikeSyncStatus.completed : LikeSyncStatus.error,
      );

      // Safety check: if tasks were added while we were finishing, restart the loop
      if (_taskQueue.isNotEmpty && LikeConnectivityManager().hasConnection) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (LikeConnectivityManager().hasConnection && !_isProcessing) {
            processQueue();
          }
        });
      }

      if (_status == LikeSyncStatus.completed) {
        Future.delayed(
          const Duration(seconds: 2),
          () => _updateStatus(LikeSyncStatus.idle),
        );
      }
    }
  }

  void _updateStatus(LikeSyncStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void _updateProgress() {
    if (_totalTasks == 0) {
      _progressController.add(0.0);
    } else {
      final progress = (_completedTasks / _totalTasks).clamp(0.0, 1.0);
      _progressController.add(progress);
    }
  }

  void dispose() {
    _statusController.close();
    _progressController.close();
  }
}
