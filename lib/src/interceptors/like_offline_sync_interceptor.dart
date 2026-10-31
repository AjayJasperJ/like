import 'package:universal_io/io.dart' show SocketException;
import 'package:like/src/services/like_replay_codec.dart';
import 'package:like/src/models/like_offline_task.dart';
import 'package:uuid/uuid.dart';
import 'package:like/src/core/like_session_scope.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:hive/hive.dart';
import 'package:like/src/client/like_client.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:like/src/services/like_connectivity_manager.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:like/src/services/like_utils.dart';
import 'package:synchronized/synchronized.dart';

/// Queues explicitly eligible mutation requests after ambiguous network errors.
///
/// Durable work is application-owned and is never used for GET/UI refreshes.
class LikeOfflineSyncInterceptor extends Interceptor {
  static const int queueSchemaVersion = 3;
  static const int _maximumReplayAttempts = 3;
  static const List<Duration> _replayDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final LikeReplayCodec codec;
  final bool autoSchedule;
  Timer? _retryTimer;
  StreamSubscription<BoxEvent>? _queueSubscription;
  bool _disposed = false;
  bool _paused = false;
  final _changes = StreamController<List<LikeOfflineTask>>.broadcast();
  final Map<dynamic, CancelToken> _running = {};
  Stream<List<LikeOfflineTask>> get taskChanges => _changes.stream;

  List<LikeOfflineTask> get tasks => queueKeys.map((key) {
    final task = Map<String, dynamic>.from(_queueBox.get(key) as Map);
    final ownerMatches = task['scope'] == currentSession().key;
    final state = !ownerMatches ? LikeOfflineTaskStatus.blocked
        : _running.containsKey(key) ? LikeOfflineTaskStatus.running
        : task['status'] == 'failed' ? LikeOfflineTaskStatus.failed
        : LikeOfflineTaskStatus.pending;
    return LikeOfflineTask(key: key, id: task['id'] as String? ?? '',
      origin: task['origin'] as String? ?? '', attempts: task['attempts'] as int? ?? 0,
      status: state, failure: ownerMatches ? task['lastFailure'] as String? : 'Session owner unavailable',
      nextAttemptAt: DateTime.tryParse(task['nextAttemptAt'] as String? ?? ''));
  }).toList(growable: false);

  void _publish() {
    if (!_disposed && !_changes.isClosed) _changes.add(tasks);
  }

  void _scheduleNext() {
    _retryTimer?.cancel();
    if (_disposed || _paused || !autoSchedule || _originDrains.isNotEmpty) return;
    DateTime? next;
    final blockedOrigins = _queueBox.values.whereType<Map>().where(
      (task) => task['scope'] == currentSession().key && task['status'] == 'failed')
        .map((task) => task['origin']).toSet();
    for (final raw in _queueBox.values) {
      if (raw is! Map || raw['scope'] != currentSession().key || raw['eligible'] == false ||
          raw['status'] == 'failed' || (raw['attempts'] as int? ?? 0) >= (raw['maxAttempts'] as int? ?? 3)) continue;
      final origin = raw['origin'] as String?;
      if (origin == null || blockedOrigins.contains(origin) || !LikeConnectivityManager().isOriginAvailable(origin)) continue;
      final due = DateTime.tryParse(raw['nextAttemptAt'] as String? ?? '') ?? DateTime.now();
      if (next == null || due.isBefore(next)) next = due;
    }
    if (next != null) {
      final wait = next.difference(DateTime.now());
      _retryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
        unawaited(syncQueue().catchError((Object _) {}));
      });
    }
  }

  void resume() { _paused = false; _scheduleNext(); }

  Future<void> retryTask(dynamic key) async {
    if (_running.containsKey(key)) throw StateError('Cancel the running action before retrying');
    final task = Map<String, dynamic>.from(_queueBox.get(key) as Map);
    if (task['scope'] != currentSession().key) throw StateError('Session owner unavailable');
    task['attempts'] = 0;
    task['status'] = 'pending';
    task['nextAttemptAt'] = DateTime.now().toIso8601String();
    task['lastFailure'] = null;
    await _queueBox.put(key, task);
    _publish();
    _scheduleNext();
  }

  Future<void> cancelTask(dynamic key) async {
    _running[key]?.cancel('Queued action cancelled');
    await _lock.synchronized(() => _queueBox.delete(key));
    _publish();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _retryTimer?.cancel();
    cancelSync(reason: 'Queue disposed');
    await _queueSubscription?.cancel();
    await _changes.close();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['offlineSync'] == true && options.extra['isSyncRequest'] != true &&
        const {'POST', 'PUT', 'PATCH', 'DELETE'}.contains(options.method.toUpperCase())) {
      final supplied = options.extra['idempotencyKey'];
      final existing = options.headers.entries.where((e) => e.key.toLowerCase() == 'idempotency-key');
      final id = supplied is String ? supplied : existing.isNotEmpty
          ? existing.first.value.toString() : const Uuid().v4();
      if (!RegExp(r'^[A-Za-z0-9._:-]{1,200}$').hasMatch(id)) {
        handler.reject(DioException(requestOptions: options,
          error: ArgumentError('Invalid idempotency key')));
        return;
      }
      options.extra['like.operationId'] ??= id;
      options.headers.removeWhere((name, _) => name.toLowerCase() == 'idempotency-key');
      options.headers['Idempotency-Key'] = id;
    }
    handler.next(options);
  }

  final Dio dio;
  final LikeSessionScope Function() currentSession;
  final Box _queueBox;
  final LikeAuthConfig? authConfig;
  final FutureOr<void> Function(String path) _notifyRefresh;
  final Lock _lock = Lock();
  final Lock _drainLock = Lock();
  final Map<String, Future<void>> _originDrains = {};
  final Map<String, CancelToken> _drainTokens = {};

  LikeOfflineSyncInterceptor({
    required this.dio,
    required Box queueBox,
    this.authConfig,
    this.codec = const DefaultLikeReplayCodec(),
    this.autoSchedule = false,
    LikeSessionScope Function()? currentSession,
    FutureOr<void> Function(String path)? notifyRefresh,
  })  : currentSession = currentSession ?? (() => const LikeSessionScope()),
        _queueBox = queueBox,
        _notifyRefresh =
            notifyRefresh ?? ((path) => LikeClient().notifyRefresh(path)) {
    if (autoSchedule) {
      _queueSubscription = _queueBox.watch().listen((_) { _publish(); _scheduleNext(); });
      _scheduleNext();
    }
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    final eligible = options.extra['offlineSync'] == true;
    final isReplay = options.extra['isSyncRequest'] == true;
    final isMutation = const <String>{'POST', 'PUT', 'DELETE', 'PATCH'}
        .contains(options.method.toUpperCase());

    final unscopedAuth = options.extra['withAuth'] == true && currentSession().isAnonymous;
    if (!isReplay && eligible && isMutation && !unscopedAuth &&
        LikeSessionIdentity.isCurrent(options) && _isNetworkError(err)) {
      try {
        await _queueRequest(options);
      } catch (error, stack) {
        handler.next(DioException(requestOptions: options, type: err.type,
          error: error, stackTrace: stack, message: 'Unable to persist offline action'));
        return;
      }
      handler.reject(
        DioException(
          requestOptions: options,
          error: 'OFFLINE_QUEUED',
          type: DioExceptionType.unknown,
        ),
      );
      return;
    }
    handler.next(err);
  }

  Future<void> _queueRequest(RequestOptions options) async {
    final origin =
        LikeConnectivityManager.canonicalOrigin(options.uri.toString());
    if (origin == null) return;
    final encodedBody = await codec.encode(options.data);
    final stableId = _stableId(options, origin);
    var added = false;

    await _lock.synchronized(() async {
      final exists = _queueBox.values.any(
        (value) => value is Map && value['id'] == stableId,
      );
      if (exists) return;

      final now = DateTime.now();
      await _queueBox.add(<String, dynamic>{
        'version': queueSchemaVersion,
        'scope': options.extra[LikeSessionIdentity.scopeKey] ?? currentSession().key,
        'withAuth': options.extra['withAuth'] == true,
        'id': stableId,
        'origin': origin,
        'eligible': true,
        // Keep the legacy path for schema compatibility, but replay through the
        // absolute, origin-bound URL so one client can safely drain work queued
        // for multiple backends.
        'path': options.path,
        'url': '$origin${options.uri.path}',
        'method': options.method.toUpperCase(),
        'body': encodedBody,
        'status': 'pending',
        'query': options.queryParameters,
        'headers': Map<String, dynamic>.from(options.headers)
          ..removeWhere((name, _) => const {'authorization', 'x-api-key', 'cookie'}.contains(name.toLowerCase())),
        'contentType': options.contentType,
        'createdAt': now.toIso8601String(),
        // Legacy readers used this field.
        'timestamp': now.toIso8601String(),
        'attempts': 0,
        'maxAttempts': _maximumReplayAttempts,
        'nextAttemptAt': now.toIso8601String(),
        'lastFailure': null,
      });
      added = true;
    });

    if (added) {
      const msg =
          'Action saved offline. Will sync when connection is restored.';
      final customCb = LikeConstants.current.toastConfig?.actionQueued;
      if (customCb != null) {
        customCb(msg);
      } else {
        LikeUtils.showToast(
          message: 'Action saved offline',
          submessage: 'Will sync when connection is restored.',
          type: LikeToastStyle.info,
        );
      }
    }
  }

  static String _stableId(RequestOptions options, String origin) {
    final source = jsonEncode(<String, Object?>{
      'origin': origin,
      'scope': options.extra[LikeSessionIdentity.scopeKey],
      'method': options.method.toUpperCase(),
      'path': options.uri.path,
      'operation': options.extra['like.operationId'] ??= const Uuid().v4(),
    });
    return sha256.convert(utf8.encode(source)).toString();
  }

  static bool _isNetworkError(DioException err) {
    return const <DioExceptionType>{
          DioExceptionType.connectionError,
          DioExceptionType.connectionTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.unknown,
        }.contains(err.type) &&
        err.response == null &&
        (err.type != DioExceptionType.unknown || err.error is SocketException);
  }

  dynamic _castToMapStringDynamic(dynamic data) {
    if (data is Map) {
      return data.map<String, dynamic>(
        (key, value) =>
            MapEntry(key.toString(), _castToMapStringDynamic(value)),
      );
    }
    if (data is List) {
      return data.map(_castToMapStringDynamic).toList();
    }
    return data;
  }

  List<dynamic> get queueKeys => _queueBox.keys.toList(growable: false);

  /// Replays one queued entry. Failures remain observable to the drain caller.
  Future<void> syncSingle(dynamic key, {CancelToken? cancelToken}) async {
    final raw = _queueBox.get(key);
    if (raw is! Map) return;
    final task = Map<String, dynamic>.from(raw);
    if (task['eligible'] == false) return;
    if (task['scope'] != currentSession().key) {
      throw StateError('Queued action belongs to another or legacy session');
    }

    final headers = Map<String, dynamic>.from(task['headers'] ?? const {});
    final getTokenFn = authConfig?.getToken ??
        LikeConstants.current.authConfig?.getToken ??
        LikeAuthInterceptor.getToken;
    if (task['withAuth'] == true && getTokenFn != null) {
      try {
        final token = await getTokenFn();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // The normal authentication interceptor remains responsible for auth.
      }
    }

    if (task['scope'] != currentSession().key) {
      throw StateError('Session changed during replay authorization');
    }
    final taskOrigin = task['origin'] as String?;
    final persistedUrl = task['url'] as String?;
    final requestTarget = persistedUrl ??
        (taskOrigin == null
            ? task['path'] as String
            : '$taskOrigin${Uri.parse(task['path'] as String).path}');
    final requestOrigin =
        LikeConnectivityManager.canonicalOrigin(requestTarget);
    if (taskOrigin != null && requestOrigin != taskOrigin) {
      await _lock.synchronized(() => _queueBox.delete(key));
      throw StateError('Offline queue origin does not match replay URL');
    }

    final token = cancelToken ?? CancelToken();
    _running[key] = token;
    _publish();
    try {
      await dio.request<dynamic>(
        requestTarget,
        data: task['body'] is Map ? codec.decode(task['body'] as Map)
            : _castToMapStringDynamic(task['data']),
        queryParameters: Map<String, dynamic>.from(task['query'] ?? const {}),
        cancelToken: token,
        options: Options(
          method: task['method'] as String?,
          headers: headers,
          contentType: task['contentType'] as String?,
          extra: <String, dynamic>{
            'isSyncRequest': true,
            'offlineSync': false,
            'withAuth': task['withAuth'] == true,
            LikeSessionIdentity.scopeKey: task['scope'],
          },
        ),
      );
    } catch (error) {
      if (!(error is DioException && CancelToken.isCancel(error))) {
        await _recordFailure(key, task, error);
      }
      rethrow;
    } finally {
      _running.remove(key);
      _publish();
    }

    // Once the server acknowledges the mutation, remove its durable entry
    // before notifying presentation code. A refresh-listener failure must never
    // reclassify acknowledged work as a failed replay.
    await _lock.synchronized(() => _queueBox.delete(key));
    try {
      await _notifyRefresh(task['path'] as String);
    } catch (error) {
      await LikeLogger.log(
        level: LikeLogLevel.warning,
        category: 'offline_sync',
        message: 'Refresh notification failed after successful sync: $error',
      );
    }
    await LikeLogger.log(
      level: LikeLogLevel.info,
      category: 'offline_sync',
      message: 'Synced successfully: ${task['method']} ${task['path']}',
    );
  }

  Future<void> _recordFailure(
    dynamic key,
    Map<String, dynamic> task,
    Object error,
  ) async {
    if (_queueBox.get(key) == null) return;
    final attempts = ((task['attempts'] as int?) ?? 0) + 1;
    final maximum = (task['maxAttempts'] as int?) ?? _maximumReplayAttempts;

    if (error is DioException && error.response != null) {
      final code = error.response!.statusCode ?? 0;
      if (code >= 400 && code < 500 && code != 408 && code != 429) {
        task['status'] = 'failed';
        task['lastFailure'] = 'HTTP $code';
        await _lock.synchronized(() => _queueBox.put(key, task));
        return;
      }
    }

    final delay =
        _replayDelays[(attempts - 1).clamp(0, _replayDelays.length - 1)];
    task['attempts'] = attempts.clamp(0, maximum);
    task['status'] = attempts >= maximum ? 'failed' : 'pending';
    task['lastFailure'] = error is DioException
        ? '${error.type.name}:${error.response?.statusCode ?? 0}' : 'Replay body unavailable';
    task['nextAttemptAt'] = DateTime.now().add(delay).toIso8601String();
    await _lock.synchronized(() => _queueBox.put(key, task));
    await LikeLogger.log(
      level: LikeLogLevel.error,
      category: 'offline_sync',
      message: 'Sync failed: ${task['method']} ${task['path']} - $error',
    );
  }

  /// Joins or starts a drain, optionally restricted to one canonical [origin].
  Future<void> syncQueue({String? origin}) {
    if (_disposed) return Future<void>.value();
    _paused = false;
    final canonical = origin == null
        ? null
        : LikeConnectivityManager.canonicalOrigin(origin) ?? origin;
    final drainKey = canonical ?? '*';
    final active = _originDrains[drainKey];
    if (active != null) return active;

    final token = CancelToken();
    _drainTokens[drainKey] = token;
    final future = _drainLock.synchronized(() => _drain(canonical, token));
    _originDrains[drainKey] = future;
    void cleanup() {
      if (identical(_originDrains[drainKey], future)) {
        _originDrains.remove(drainKey);
        _drainTokens.remove(drainKey);
      }
      _scheduleNext();
    }

    // Do not discard a `whenComplete` future: if the drain fails, that creates
    // a second unobserved error. This cleanup branch consumes its own result
    // while the original future still propagates to the caller.
    future.then<void>((_) => cleanup(), onError: (Object _, StackTrace __) {
      cleanup();
    });
    return future;
  }

  Future<void> _drain(String? origin, CancelToken token) async {
    final keys = queueKeys..sort((a, b) {
      final left = (_queueBox.get(a) as Map)['createdAt'] as String? ?? '';
      final right = (_queueBox.get(b) as Map)['createdAt'] as String? ?? '';
      return left.compareTo(right);
    });
    final failedOrigins = <String?>{};
    Object? firstFailure;
    StackTrace? firstStackTrace;

    for (final key in keys) {
      if (token.isCancelled) break;
      final raw = _queueBox.get(key);
      if (raw is! Map) continue;
      final task = Map<String, dynamic>.from(raw);
      final taskOrigin = task['origin'] as String?;
      final eligible = task['eligible'] != false;
      if (failedOrigins.contains(taskOrigin)) continue;
      if (!eligible || task['scope'] != currentSession().key ||
          (origin != null && taskOrigin != origin)) continue;
      if (taskOrigin != null &&
          !LikeConnectivityManager().isOriginAvailable(taskOrigin)) {
        continue;
      }
      final attempts = (task['attempts'] as int?) ?? 0;
      final maximum = (task['maxAttempts'] as int?) ?? _maximumReplayAttempts;
      if (attempts >= maximum || task['status'] == 'failed') {
        failedOrigins.add(taskOrigin);
        continue;
      }
      final nextAttempt =
          DateTime.tryParse(task['nextAttemptAt'] as String? ?? '');
      if (nextAttempt != null && nextAttempt.isAfter(DateTime.now())) continue;

      try {
        await syncSingle(key, cancelToken: token);
      } catch (error, stackTrace) {
        if (error is DioException && CancelToken.isCancel(error)) break;
        failedOrigins.add(taskOrigin);
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstFailure != null) {
      Error.throwWithStackTrace(firstFailure, firstStackTrace!);
    }
  }

  /// Cancels active drains without deleting pending durable entries.
  void cancelSync({String? origin, String reason = 'Offline sync cancelled'}) {
    _paused = true;
    _retryTimer?.cancel();
    if (origin == null) {
      for (final token in _drainTokens.values) {
        if (!token.isCancelled) token.cancel(reason);
      }
      return;
    }
    final canonical = LikeConnectivityManager.canonicalOrigin(origin) ?? origin;
    final token = _drainTokens[canonical];
    if (token != null && !token.isCancelled) token.cancel(reason);
  }
}
