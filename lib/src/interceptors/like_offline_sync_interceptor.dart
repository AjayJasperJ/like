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
  static const int queueSchemaVersion = 2;
  static const int _maximumReplayAttempts = 3;
  static const List<Duration> _replayDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final Dio dio;
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
    FutureOr<void> Function(String path)? notifyRefresh,
  })  : _queueBox = queueBox,
        _notifyRefresh =
            notifyRefresh ?? ((path) => LikeClient().notifyRefresh(path));

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

    if (!isReplay && eligible && isMutation && _isNetworkError(err)) {
      await _queueRequest(options);
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
        'id': stableId,
        'origin': origin,
        'eligible': true,
        // Keep the legacy path for schema compatibility, but replay through the
        // absolute, origin-bound URL so one client can safely drain work queued
        // for multiple backends.
        'path': options.path,
        'url': '$origin${options.uri.path}',
        'method': options.method.toUpperCase(),
        'data': options.data,
        'query': options.queryParameters,
        'headers': Map<String, dynamic>.from(options.headers)
          ..remove('Authorization'),
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
      LikeUtils.showToast(
        message: 'Action saved offline',
        submessage: 'Will sync when connection is restored.',
        type: LikeToastStyle.info,
      );
    }
  }

  static String _stableId(RequestOptions options, String origin) {
    final source = jsonEncode(<String, Object?>{
      'origin': origin,
      'method': options.method.toUpperCase(),
      'path': options.path,
      'query': _canonicalValue(options.queryParameters),
      'data': _canonicalValue(options.data),
    });
    return sha256.convert(utf8.encode(source)).toString();
  }

  static Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final entries = value.entries.toList(growable: false)
        ..sort((left, right) =>
            left.key.toString().compareTo(right.key.toString()));
      return <String, Object?>{
        for (final entry in entries)
          entry.key.toString(): _canonicalValue(entry.value),
      };
    }
    if (value is Iterable) {
      return value.map(_canonicalValue).toList(growable: false);
    }
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }
    return value.toString();
  }

  static bool _isNetworkError(DioException err) {
    return const <DioExceptionType>{
          DioExceptionType.connectionError,
          DioExceptionType.connectionTimeout,
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.unknown,
        }.contains(err.type) &&
        err.response == null;
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

    final headers = Map<String, dynamic>.from(task['headers'] ?? const {});
    final getTokenFn = authConfig?.getToken ??
        LikeConstants.current.authConfig?.getToken ??
        LikeAuthInterceptor.getToken;
    if (getTokenFn != null) {
      try {
        final token = await getTokenFn();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // The normal authentication interceptor remains responsible for auth.
      }
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

    try {
      await dio.request<dynamic>(
        requestTarget,
        data: _castToMapStringDynamic(task['data']),
        queryParameters: Map<String, dynamic>.from(task['query'] ?? const {}),
        cancelToken: cancelToken,
        options: Options(
          method: task['method'] as String?,
          headers: headers,
          contentType: task['contentType'] as String?,
          extra: <String, dynamic>{
            'isSyncRequest': true,
            'offlineSync': false,
            'withAuth': true,
          },
        ),
      );
    } catch (error) {
      if (!(error is DioException && CancelToken.isCancel(error))) {
        await _recordFailure(key, task, error);
      }
      rethrow;
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
    final attempts = ((task['attempts'] as int?) ?? 0) + 1;
    final maximum = (task['maxAttempts'] as int?) ?? _maximumReplayAttempts;

    if (error is DioException && error.response != null) {
      final code = error.response!.statusCode ?? 0;
      if (code >= 400 && code < 500 && code != 408 && code != 429) {
        await _lock.synchronized(() => _queueBox.delete(key));
        return;
      }
    }

    final delay =
        _replayDelays[(attempts - 1).clamp(0, _replayDelays.length - 1)];
    task['attempts'] = attempts.clamp(0, maximum);
    task['lastFailure'] = error.toString();
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
    final keys = queueKeys;
    Object? firstFailure;
    StackTrace? firstStackTrace;

    for (final key in keys) {
      if (token.isCancelled) break;
      final raw = _queueBox.get(key);
      if (raw is! Map) continue;
      final task = Map<String, dynamic>.from(raw);
      final taskOrigin = task['origin'] as String?;
      final eligible = task['eligible'] != false;
      if (!eligible || (origin != null && taskOrigin != origin)) continue;
      if (taskOrigin != null &&
          !LikeConnectivityManager().isOriginAvailable(taskOrigin)) {
        continue;
      }
      final attempts = (task['attempts'] as int?) ?? 0;
      final maximum = (task['maxAttempts'] as int?) ?? _maximumReplayAttempts;
      if (attempts >= maximum) continue;
      final nextAttempt =
          DateTime.tryParse(task['nextAttemptAt'] as String? ?? '');
      if (nextAttempt != null && nextAttempt.isAfter(DateTime.now())) continue;

      try {
        await syncSingle(key, cancelToken: token);
      } catch (error, stackTrace) {
        if (error is DioException && CancelToken.isCancel(error)) break;
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
