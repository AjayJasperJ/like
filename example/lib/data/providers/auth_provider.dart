import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

import '../models/api_models.dart';
import '../repositories/auth_repository.dart';
import '../storage/token_storage.dart';

final class AuthProvider extends ChangeNotifier with LikeStateMixin {
  AuthProvider(this._repository, this._storage);

  final AuthRepository _repository;
  final TokenStorageService _storage;

  final authState = LikeNotifierState<ApiUser?>(
    initialValue: LikeStateResponse.idle(),
  );

  bool _initializing = true;

  ApiUser? get user => authState.value.data;
  bool get initializing => _initializing;
  bool get busy => authState.value.state == LikeState.loading;
  bool get isAuthenticated => user != null;
  String? get error => authState.value.error?.message;

  LikeAuthConfig createAuthConfig() {
    return LikeAuthConfig(
      getToken: _storage.readAccessToken,
      refreshToken: () async {
        final result = await _repository.refresh();
        if (result.isSuccess && result.data != null) {
          authState.value = LikeStateResponse.success(result.data!.user);
          notifyListeners();
          return result.data!.accessToken;
        }
        await _expireSession();
        return null;
      },
      onLogout: ({int? statusCode, bool force = false}) async =>
          _expireSession(),
    );
  }

  Future<void> restoreSession() async {
    _initializing = true;
    notifyListeners();
    if (await _repository.hasSession()) {
      await fetch<ApiUser?>(
        state: authState,
        autoResync: true,
        action: (ct, ars) async {
          final result = await _repository.currentUser();
          if (result.isSuccess && result.data != null) {
            return LikeStateResponse.success(result.data!);
          }
          await _storage.clear();
          return LikeStateResponse.error(
            result.error ??
                LikeError(
                  message: 'Session expired',
                  type: LikeApiErrorType.unauthorized,
                ),
          );
        },
      );
    } else {
      authState.value = LikeStateResponse.idle();
    }
    _initializing = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) =>
      _authenticate(() => _repository.login(email.trim(), password));

  Future<bool> register(String name, String email, String password) =>
      _authenticate(
        () => _repository.register(name.trim(), email.trim(), password),
      );

  Future<void> logout() async {
    authState.value = LikeStateResponse.loading();
    notifyListeners();
    await _repository.logout();
    authState.value = LikeStateResponse.idle();
    notifyListeners();
  }

  void clearError() {
    if (user != null) {
      authState.value = LikeStateResponse.success(user!);
    } else {
      authState.value = LikeStateResponse.idle();
    }
    notifyListeners();
  }

  Future<bool> _authenticate(
    Future<ApiResult<AuthSession>> Function() action,
  ) async {
    authState.value = LikeStateResponse.loading();
    notifyListeners();
    final result = await action();
    if (result.isSuccess && result.data != null) {
      authState.value = LikeStateResponse.success(result.data!.user);
    } else {
      final err = result.error ??
          LikeError(
            message: 'Authentication failed',
            type: LikeApiErrorType.unauthorized,
          );
      authState.value = LikeStateResponse.error(err);
    }
    notifyListeners();
    return result.isSuccess;
  }

  Future<void> _expireSession() async {
    await _repository.clearSession();
    authState.value = LikeStateResponse.idle();
    notifyListeners();
  }
}
