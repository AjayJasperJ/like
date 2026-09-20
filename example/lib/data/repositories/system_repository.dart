import 'package:like/like.dart';

import '../services/system_api_service.dart';

final class SystemRepository {
  SystemRepository(this._api);

  final SystemApiService _api;

  Future<ApiResult<Map<String, dynamic>>> metadata() => _api.metadata();
  Future<ApiResult<Map<String, dynamic>>> health() => _api.health();
  Future<ApiResult<Map<String, dynamic>>> reset() => _api.reset();
  Future<ApiResult<Map<String, dynamic>>> status(int code) => _api.status(code);
  Future<ApiResult<Map<String, dynamic>>> delay(int milliseconds) =>
      _api.delay(milliseconds);
}
