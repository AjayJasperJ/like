import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

import '../repositories/system_repository.dart';

final class SystemProvider extends ChangeNotifier with StateMixin {
  SystemProvider(this._repository);

  final SystemRepository _repository;

  final systemState = LikeNotifierState<String>(
    initialValue: LikeStateResponse.idle(),
  );

  bool get busy => systemState.value.state == LikeState.loading;
  String? get output => systemState.value.data;
  String? get error => systemState.value.error?.message;

  Future<dynamic> Function()? _lastAction;

  Future<void> metadata() => _run(_repository.metadata);
  Future<void> health() => _run(_repository.health);
  Future<void> reset() => _run(_repository.reset);
  Future<void> status(int code) => _run(() => _repository.status(code));
  Future<void> delay(int milliseconds) =>
      _run(() => _repository.delay(milliseconds));
  Future<void> triggerException() => _run(() async {
        throw FormatException(
            'Malformed response payload: Invalid character at line 1');
      });

  Future<void> retryLastAction() async {
    if (_lastAction != null) {
      await _run(_lastAction!);
    }
  }

  Future<void> _run(Future<dynamic> Function() action) async {
    _lastAction = action;
    await fetch<String>(
      state: systemState,
      action: (ct, ars) async {
        final result = await action();
        if (result.isSuccess) {
          final jsonOutput =
              const JsonEncoder.withIndent('  ').convert(result.data);
          return LikeStateResponse.success(jsonOutput);
        }
        final err = result.error ??
            LikeError(
              message: 'Request failed',
              type: LikeApiErrorType.unknown,
            );
        return LikeStateResponse.error(err);
      },
    );
  }
}
