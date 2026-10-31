import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/models/like_api_result.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/services/like_invalidation.dart';
import 'package:like/src/services/like_connectivity_manager.dart';

/// Framework-independent query lifecycle shared by every presentation adapter.
class LikeQuery<T> {
  final Future<LikeApiResult<T>> Function(CancelToken token) action;
  final String Function() scope;
  final String origin;
  final Set<String> tags;
  final _events = StreamController<LikeStateResponse<T>>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  LikeStateResponse<T> _state = LikeStateResponse.idle();
  LikeStateResponse<T> get state => _state;
  CancelToken? _token;
  int _generation = 0;
  bool _disposed = false;
  bool _refreshScheduled = false;

  LikeQuery({required this.action, required this.scope, required this.origin,
    Iterable<String> tags = const [], LikeInvalidationHub? invalidations,
    Stream<Object?>? sessionChanges, Stream<String>? restoredOrigins}) : tags = tags.toSet() {
    _subscriptions.add((invalidations ?? LikeInvalidationHub.shared).stream.listen((event) {
      if (event.scope == scope() && event.origin == origin && event.tags.any(this.tags.contains)) _scheduleRefresh();
    }));
    _subscriptions.add((restoredOrigins ?? LikeConnectivityManager().originRestorations
        .map((event) => event.origin)).listen((restored) {
      final uri = Uri.tryParse(restored);
      if (uri != null && uri.hasAuthority && uri.origin == origin) { _scheduleRefresh(); }
    }));
    if (sessionChanges != null) _subscriptions.add(sessionChanges.listen((_) {
      _generation++;
      _token?.cancel('Session changed');
      _set(LikeStateResponse.idle());
    }));
  }

  /// Emits a snapshot on every new subscription, then subsequent transitions.
  Stream<LikeStateResponse<T>> watch() => Stream.multi((controller) {
    controller.add(_state);
    final subscription = _events.stream.listen(controller.add,
      onError: controller.addError, onDone: controller.close);
    controller.onCancel = subscription.cancel;
  });

  void _set(LikeStateResponse<T> value) {
    if (_disposed) return;
    _state = value;
    _events.add(value);
  }

  void _scheduleRefresh() {
    if (_disposed || _refreshScheduled) return;
    _refreshScheduled = true;
    scheduleMicrotask(() {
      _refreshScheduled = false;
      if (!_disposed) unawaited(refresh());
    });
  }

  Future<void> refresh() async {
    if (_disposed) return;
    final generation = ++_generation;
    final owner = scope();
    _token?.cancel('Query superseded');
    final token = CancelToken();
    _token = token;
    final old = _state.data;
    _set(old == null ? LikeStateResponse.loading() : LikeStateResponse.refreshing(old));
    try {
      final result = await action(token);
      if (!_disposed && generation == _generation && owner == scope()) _set(result.toStateResponse());
    } catch (error) {
      if (!_disposed && generation == _generation && owner == scope() && !token.isCancelled) {
        _set(LikeStateResponse.error(LikeError(message: 'Query failed', type: LikeApiErrorType.unknown)));
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _token?.cancel('Query disposed');
    for (final subscription in _subscriptions) { await subscription.cancel(); }
    await _events.close();
  }
}

/// Provider/ValueListenable adapter. The owner chooses whether it owns the query.
class LikeQueryNotifier<T> extends ChangeNotifier {
  final LikeQuery<T> query;
  final bool ownsQuery;
  late final StreamSubscription<LikeStateResponse<T>> _subscription;
  LikeQueryNotifier(this.query, {this.ownsQuery = true}) {
    _subscription = query.watch().listen((_) => notifyListeners());
  }
  LikeStateResponse<T> get state => query.state;
  Future<void> refresh() => query.refresh();
  @override
  void dispose() {
    _subscription.cancel();
    if (ownsQuery) unawaited(query.dispose());
    super.dispose();
  }
}
