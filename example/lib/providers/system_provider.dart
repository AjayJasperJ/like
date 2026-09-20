import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../repositories/system_repository.dart';

final class SystemProvider extends ChangeNotifier {
  SystemProvider(this._repository);

  final SystemRepository _repository;

  bool _busy = false;
  String? _output;
  String? _error;

  bool get busy => _busy;
  String? get output => _output;
  String? get error => _error;

  Future<dynamic> Function()? _lastAction;

  Future<void> metadata() => _run(_repository.metadata);
  Future<void> health() => _run(_repository.health);
  Future<void> reset() => _run(_repository.reset);
  Future<void> status(int code) => _run(() => _repository.status(code));
  Future<void> delay(int milliseconds) =>
      _run(() => _repository.delay(milliseconds));

  Future<void> retryLastAction() async {
    if (_lastAction != null) {
      await _run(_lastAction!);
    }
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    _lastAction = action;
    _busy = true;
    _error = null;
    _output = null;
    notifyListeners();
    final result = await action();
    if (result.isSuccess) {
      _output = const JsonEncoder.withIndent('  ').convert(result.data);
    } else {
      _error = result.error?.message ?? 'Request failed';
    }
    _busy = false;
    notifyListeners();
  }
}
