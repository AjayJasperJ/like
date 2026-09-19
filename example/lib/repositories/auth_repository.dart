import 'package:like/like.dart';

import '../models/api_models.dart';
import '../services/auth_api_service.dart';
import '../services/token_storage_service.dart';

final class AuthRepository {
  AuthRepository(this._api, this._storage);

  final AuthApiService _api;
  final TokenStorageService _storage;

  Future<ApiResult<AuthSession>> login(String email, String password) =>
      _saveSuccessful(_api.login(email: email, password: password));

  Future<ApiResult<AuthSession>> register(
    String name,
    String email,
    String password,
  ) =>
      _saveSuccessful(
        _api.register(name: name, email: email, password: password),
      );

  Future<ApiResult<AuthSession>> refresh() async {
    final token = await _storage.readRefreshToken();
    if (token == null || token.isEmpty) {
      return LikeApiResult<AuthSession>.error(null);
    }
    return _saveSuccessful(_api.refresh(token));
  }

  Future<ApiResult<ApiUser>> currentUser() => _api.me();

  Future<void> logout() async {
    final token = await _storage.readRefreshToken();
    if (token != null && token.isNotEmpty) await _api.logout(token);
    await _storage.clear();
  }

  Future<void> clearSession() => _storage.clear();

  Future<bool> hasSession() async {
    final access = await _storage.readAccessToken();
    final refresh = await _storage.readRefreshToken();
    return access?.isNotEmpty == true && refresh?.isNotEmpty == true;
  }

  Future<ApiResult<AuthSession>> _saveSuccessful(
    Future<ApiResult<AuthSession>> request,
  ) async {
    final result = await request;
    if (result.isSuccess && result.data != null) {
      await _storage.saveSession(result.data!);
    }
    return result;
  }
}
