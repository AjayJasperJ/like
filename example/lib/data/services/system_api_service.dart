import 'package:like/like.dart';

import '../../core/constants/api_urls.dart';

final class SystemApiService extends LikeBaseApiService {
  SystemApiService()
      : super(
          client: LikeClient.scoped(
            LikeClientConfig(
              baseUrl: ApiUrls.baseUrl,
              defaultHeaders: const {
                'X-Client-Key': 'secondary_system_client',
              },
              authConfig: LikeAuthConfig(),
            ),
          ),
        );

  Future<ApiResult<Map<String, dynamic>>> metadata() => get(
        ApiUrls.metadata,
        withAuth: false,
        disableCache: true,
      ).mapSync(jsonMap);

  Future<ApiResult<Map<String, dynamic>>> health() => get(
        ApiUrls.health,
        withAuth: false,
        disableCache: true,
      ).mapSync(jsonMap);

  Future<ApiResult<Map<String, dynamic>>> reset() => post(
        ApiUrls.reset,
        withAuth: true,
      ).mapSync(jsonMap);

  Future<ApiResult<Map<String, dynamic>>> status(int code) => get(
        ApiUrls.status(code),
        withAuth: true,
        disableCache: true,
      ).mapSync(jsonMap);

  Future<ApiResult<Map<String, dynamic>>> delay(int milliseconds) => get(
        ApiUrls.delay(milliseconds),
        withAuth: true,
        disableCache: true,
      ).mapSync(jsonMap);
}
