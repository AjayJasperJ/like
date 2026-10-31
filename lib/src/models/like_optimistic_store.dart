import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'like_api_result.dart';

class _OptimisticLayer<T> {
  final int id;
  T Function(T) apply;
  bool settled = false;
  _OptimisticLayer(this.id, this.apply);
}

/// Ordered optimistic layers prevent an older rollback from overwriting a newer
/// successful mutation. Reconciliation reducers should merge server entities by ID.
class LikeOptimisticStore<T> extends ValueNotifier<T> {
  T _base;
  int _sequence = 0;
  bool _disposed = false;
  final List<_OptimisticLayer<T>> _layers = [];
  final Map<int, CancelToken> _tokens = {};
  LikeOptimisticStore(T value) : _base = value, super(value);

  void replaceBase(T base) { if (!_disposed) { _base = base; _publish(); } }
  int begin(T Function(T) optimistic) {
    if (_disposed) throw StateError('Store disposed');
    final id = ++_sequence;
    _layers.add(_OptimisticLayer(id, optimistic));
    _publish();
    return id;
  }
  void commit(int id, T Function(T) reconcile) {
    if (_disposed) return;
    final matches = _layers.where((layer) => layer.id == id);
    if (matches.isEmpty) return;
    final layer = matches.first;
    layer.apply = reconcile;
    layer.settled = true;
    _drain();
  }
  void rollback(int id) {
    if (_disposed) return;
    _layers.removeWhere((layer) => layer.id == id);
    _drain();
  }
  void _drain() {
    while (_layers.isNotEmpty && _layers.first.settled) {
      _base = _layers.removeAt(0).apply(_base);
    }
    _publish();
  }
  void _publish() {
    var result = _base;
    for (final layer in _layers) { result = layer.apply(result); }
    value = result;
  }
  Future<LikeApiResult<R>> mutate<R>({required T Function(T) optimistic,
    required T Function(T base, R? result) reconcile,
    required Future<LikeApiResult<R>> Function(CancelToken) action}) async {
    final id = begin(optimistic);
    final token = CancelToken();
    _tokens[id] = token;
    try {
      final result = await action(token);
      if (result.isSuccess) { commit(id, (base) => reconcile(base, result.data)); }
      else { rollback(id); }
      return result;
    } catch (_) { rollback(id); rethrow; }
    finally { _tokens.remove(id); }
  }
  @override
  void dispose() {
    _disposed = true;
    for (final token in _tokens.values) { token.cancel('Optimistic store disposed'); }
    _layers.clear();
    super.dispose();
  }
}
