import 'package:like/like.dart';
import '../models/api_models.dart';
import '../../core/constants/api_urls.dart';

final class AuthApiService extends LikeBaseApiService {
  Future<ApiResult<AuthSession>> register({
    required String name,
    required String email,
    required String password,
  }) =>
      post(
        ApiUrls.register,
        body: {'name': name, 'email': email, 'password': password},
        withAuth: false,
      ).mapSync(_sessionFromEnvelope);

  Future<ApiResult<AuthSession>> login({
    required String email,
    required String password,
  }) =>
      post(
        ApiUrls.login,
        body: {'email': email, 'password': password},
        withAuth: false,
      ).mapSync(_sessionFromEnvelope);

  Future<ApiResult<AuthSession>> refresh(String refreshToken) => post(
        ApiUrls.refresh,
        body: {'refreshToken': refreshToken},
        withAuth: false,
      ).mapSync(_sessionFromEnvelope);

  Future<ApiResult<String>> logout(String refreshToken) => post(
        ApiUrls.logout,
        body: {'refreshToken': refreshToken},
        withAuth: true,
      ).mapSync((value) => jsonMap(value)['message'] as String);

  Future<ApiResult<ApiUser>> me() => get(
        ApiUrls.me,
        withAuth: true,
        disableCache: true,
      ).mapSync((value) => ApiUser.fromJson(_envelopeData(value)));
}

AuthSession _sessionFromEnvelope(dynamic value) =>
    AuthSession.fromJson(_envelopeData(value));

Map<String, dynamic> _envelopeData(Object? value) =>
    jsonMap(jsonMap(value)['data']);
