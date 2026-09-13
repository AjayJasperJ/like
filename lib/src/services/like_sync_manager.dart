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
  StreamSubscription<bool>? _connectivitySubscription;
  Future<void>? _processingFuture;
  Timer? _idleTimer;
  bool _isProcessing = false;
  bool _isDisposed = false;
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
    _connectivitySubscription =
        LikeConnectivityManager().connectionChange.listen((hasConnection) {
      if (hasConnection && _taskQueue.isNotEmpty && !_isProcessing) {
        unawaited(processQueue());
      }
    });
  }

  /// Registers a task in the synchronization queue.
  ///
  /// Tasks are executed based on their [LikeSyncPriority]. If a task with the
  /// same ID already exists, its priority will be upgraded if the new task
  /// has a higher priority level.
  void registerTask(LikeSyncTask task) {
    if (_isDisposed) return;
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
      unawaited(processQueue());
    }
  }

  static const int _maxTaskAttempts = 3;

  /// Manually starts or joins execution of the synchronization queue.
  ///
  /// The queue will only be processed if the device has an active connection.
  /// Concurrent callers receive the same processing future.
  Future<void> processQueue() {
    final active = _processingFuture;
    if (active != null) return active;
    if (_isDisposed || _taskQueue.isEmpty) return Future<void>.value();

    final run = _processQueue();
    _processingFuture = run;
    run.whenComplete(() {
      if (identical(_processingFuture, run)) _processingFuture = null;
    });
    return run;
  }

  Future<void> _processQueue() async {
    _isProcessing = true;
    _idleTimer?.cancel();
    _updateStatus(LikeSyncStatus.syncing);
    var hadTerminalFailure = false;

    try {
      while (_taskQueue.isNotEmpty && !_isDisposed) {
        if (!LikeConnectivityManager().hasConnection) {
          LikeLogger.log(
            level: LikeLogLevel.warning,
            category: 'sync',
            message: 'Connectivity lost during sync. Pausing queue.',
          );
          break;
        }

        final task = _taskQueue.removeFirst();
        var succeeded = false;
        final maximumAttempts = task.retryOnError ? _maxTaskAttempts : 1;

        for (var attempt = 1; attempt <= maximumAttempts; attempt++) {
          if (_isDisposed || !LikeConnectivityManager().hasConnection) break;
          try {
            LikeLogger.log(
              level: LikeLogLevel.info,
              category: 'sync',
              message:
                  'Executing sync task: ${task.id} (attempt $attempt/$maximumAttempts)',
            );
            await task.run();
            succeeded = true;
            break;
          } catch (error) {
            LikeLogger.log(
              level: LikeLogLevel.error,
              category: 'sync',
              message:
                  'Error executing task ${task.id} (attempt $attempt/$maximumAttempts): $error',
            );
            if (attempt < maximumAttempts &&
                LikeConnectivityManager().hasConnection) {
              await Future<void>.delayed(
                Duration(milliseconds: 300 * attempt),
              );
            }
          }
        }

        if (!LikeConnectivityManager().hasConnection && !succeeded) {
          _taskQueue.add(task);
          break;
        }

        _pendingTasks.remove(task.id);
        if (succeeded) {
          _completedTasks++;
          _updateProgress();
        } else {
          hadTerminalFailure = true;
        }

        if (_taskQueue.isNotEmpty && !_isDisposed) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }
    } finally {
      _isProcessing = false;
      if (!_isDisposed) {
        final completed = _taskQueue.isEmpty && !hadTerminalFailure;
        _updateStatus(
          completed ? LikeSyncStatus.completed : LikeSyncStatus.error,
        );
        if (completed) {
          _idleTimer = Timer(const Duration(seconds: 2), () {
            if (!_isDisposed && !_isProcessing && _taskQueue.isEmpty) {
              _updateStatus(LikeSyncStatus.idle);
            }
          });
        }
      }
    }
  }

  void _updateStatus(LikeSyncStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) _statusController.add(newStatus);
  }

  void _updateProgress() {
    if (_progressController.isClosed) return;
    if (_totalTasks == 0) {
      _progressController.add(0.0);
    } else {
      final progress = (_completedTasks / _totalTasks).clamp(0.0, 1.0);
      _progressController.add(progress);
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _idleTimer?.cancel();
    _connectivitySubscription?.cancel();
    _taskQueue.clear();
    _pendingTasks.clear();
    _statusController.close();
    _progressController.close();
  }
}
