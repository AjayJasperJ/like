import 'dart:async';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:synchronized/synchronized.dart';
import 'package:like/src/services/like_sync_manager.dart';
import 'package:like/src/services/like_background_sync_service.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/services/like_utils.dart';
import 'package:like/src/models/like_sync_task.dart';

/// Interceptor that queues mutation requests (POST, PUT, DELETE, PATCH) when offline.
/// Matches enterprise's OfflineSyncInterceptor parity.
class LikeOfflineSyncInterceptor extends Interceptor {
  final Dio dio;
  final Box _queueBox;
  static final Lock _lock = Lock();

  LikeOfflineSyncInterceptor({required this.dio, required Box queueBox})
    : _queueBox = queueBox;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final bool offlineSync = err.requestOptions.extra['offlineSync'] ?? true;
    final bool isSyncRequest =
        err.requestOptions.extra['isSyncRequest'] ?? false;

    if (!isSyncRequest &&
        _isNetworkError(err) &&
        [
          'POST',
          'PUT',
          'DELETE',
          'PATCH',
        ].contains(err.requestOptions.method) &&
        offlineSync) {
      await _queueRequest(err.requestOptions);

      return handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          error: 'OFFLINE_QUEUED',
          type: DioExceptionType.unknown,
        ),
      );
    }
    handler.next(err);
  }

  Future<void> _queueRequest(RequestOptions options) async {
    final task = {
      'path': options.path,
      'method': options.method,
      'data': options.data,
      'query': options.queryParameters,
      'headers': Map<String, dynamic>.from(options.headers)
        ..remove('Authorization'),
      'contentType': options.contentType,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final exists = _queueBox.values.any((existing) {
      if (existing is! Map) return false;
      return existing['path'] == task['path'] &&
          existing['method'] == task['method'] &&
          existing['data'].toString() == task['data'].toString() &&
          existing['query'].toString() == task['query'].toString();
    });

    if (!exists) {
      await _lock.synchronized(() async {
        await _queueBox.add(task);
      });

      // Show notification via LikeUtils toast (parity with enterprise NotificationService)
      LikeUtils.showToast(
        message: 'Action saved offline',
        submessage: 'Will sync when connection is restored.',
        type: LikeToastType.info,
      );

      // Schedule background sync
      LikeBackgroundSyncService().scheduleSyncTask();
    }
  }

  bool _isNetworkError(DioException err) {
    return err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.receiveTimeout ||
        err.error.toString().toLowerCase().contains('socket');
  }

  dynamic _castToMapStringDynamic(dynamic data) {
    if (data is Map) {
      return data.map<String, dynamic>(
        (key, value) =>
            MapEntry(key.toString(), _castToMapStringDynamic(value)),
      );
    } else if (data is List) {
      return data.map((e) => _castToMapStringDynamic(e)).toList();
    }
    return data;
  }

  List<dynamic> get queueKeys => _queueBox.keys.toList();

  Future<void> syncSingle(dynamic key) async {
    final task = _queueBox.get(key);
    if (task == null) return;

    try {
      await dio.request(
        task['path'],
        data: _castToMapStringDynamic(task['data']),
        queryParameters: Map<String, dynamic>.from(task['query'] ?? {}),
        options: Options(
          method: task['method'],
          headers: Map<String, dynamic>.from(task['headers'] ?? {}),
          contentType: task['contentType'],
          extra: {'isSyncRequest': true},
        ),
      );

      await _lock.synchronized(() async {
        await _queueBox.delete(key);
      });

      // Notify the pipeline that a mutation happened so builders can refresh
      LikeClient().notifyRefresh(task['path']);

      await LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'offline_sync',
        message: 'Synced successfully: ${task['method']} ${task['path']}',
      );
    } catch (e) {
      await LikeLogger.log(
        level: LikeLogLevel.error,
        category: 'offline_sync',
        message: 'Sync failed: ${task['method']} ${task['path']} - Error: $e',
      );

      if (e is DioException && e.response != null) {
        final code = e.response!.statusCode ?? 0;
        // Delete if it's a client error (4xx) except for timeout or rate limiting
        if (code >= 400 && code < 500 && code != 408 && code != 429) {
          await _lock.synchronized(() async {
            await _queueBox.delete(key);
          });
        }
      }
      rethrow;
    }
  }

  Future<void> syncQueue() async {
    if (_queueBox.isEmpty) return;

    // Delegate to SyncManager via local mutation task
    LikeSyncManager().registerTask(_LikeOfflineMutationSyncTask(this));
  }
}

/// Task for processing the entire offline mutation queue.
class _LikeOfflineMutationSyncTask extends LikeSyncTask {
  final LikeOfflineSyncInterceptor _interceptor;

  _LikeOfflineMutationSyncTask(this._interceptor);

  @override
  String get id => 'offline_mutation_sync';

  @override
  LikeSyncPriority get priority => LikeSyncPriority.critical;

  @override
  bool get isRecovery => true;

  @override
  Future<void> run() async {
    final keys = _interceptor.queueKeys;
    if (keys.isEmpty) return;

    for (final key in keys) {
      LikeSyncManager().registerTask(
        _LikeSingleOfflineMutationTask(_interceptor, key),
      );
    }
  }
}

/// Task for processing a single offline mutation from the queue.
class _LikeSingleOfflineMutationTask extends LikeSyncTask {
  final LikeOfflineSyncInterceptor _interceptor;
  final dynamic key;

  _LikeSingleOfflineMutationTask(this._interceptor, this.key);

  @override
  String get id => 'offline_mutation_$key';

  @override
  LikeSyncPriority get priority => LikeSyncPriority.critical;

  @override
  bool get isRecovery => true;

  @override
  Future<void> run() async {
    try {
      await _interceptor.syncSingle(key);
    } catch (_) {
      // Individual errors are handled within syncSingle
    }
  }
}
