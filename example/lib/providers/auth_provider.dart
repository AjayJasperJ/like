import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

import '../models/api_models.dart';
import '../repositories/auth_repository.dart';
import '../services/token_storage_service.dart';

final class AuthProvider extends ChangeNotifier {
  AuthProvider(this._repository, this._storage);

  final AuthRepository _repository;
  final TokenStorageService _storage;
  

  

  ApiUser? _user;
  bool _initializing = true;
  bool _busy = false;
  String? _error;

  ApiUser? get user => _user;
  bool get initializing => _initializing;
  bool get busy => _busy;
  bool get isAuthenticated => _user != null;
  String? get error => _error;

  LikeAuthConfig createAuthConfig() {
    return LikeAuthConfig(
      getToken: _storage.readAccessToken,
      refreshToken: () async {
        final result = await _repository.refresh();
        if (result.isSuccess && result.data != null) {
          _user = result.data!.user;
          notifyListeners();
          return result.data!.accessToken;
        }
        await _expireSession();
        return null;
      },
      onLogout: ({int? statusCode, bool force = false}) async => _expireSession(),
    );
  }

  Future<void> restoreSession() async {
    _initializing = true;
    notifyListeners();
    if (await _repository.hasSession()) {
      final result = await _repository.currentUser();
      if (result.isSuccess && result.data != null) {
        _user = result.data;
      } else {
        await _storage.clear();
      }
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
    _busy = true;
    notifyListeners();
    await _repository.logout();
    _user = null;
    _busy = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> _authenticate(
    Future<ApiResult<AuthSession>> Function() action,
  ) async {
    _busy = true;
    _error = null;
    notifyListeners();
    final result = await action();
    if (result.isSuccess && result.data != null) {
      _user = result.data!.user;
    } else {
      _error = result.error?.message ?? 'Authentication failed';
    }
    _busy = false;
    notifyListeners();
    return result.isSuccess;
  }

  Future<void> _expireSession() async {
    await _repository.clearSession();
    _user = null;
    _busy = false;
    notifyListeners();
  }
}
