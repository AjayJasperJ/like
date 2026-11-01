import '../models/api_models.dart';
import '../../core/constants/api_urls.dart';

final class PostApiService extends LikeBaseApiService {
  PostApiService({super.client});

  Future<ApiResult<PaginatedPosts>> list({
    int page = 1,
    CancelToken? cancelToken,
    int limit = 10,
    String? search,
    bool? published,
    int? userId,
    String sort = 'createdAt',
    String order = 'desc',
  }) => get(
    ApiUrls.posts,
    cancelToken: cancelToken,
    requestConfig: const LikeRequestConfig(cacheTags: ['posts']),
    query: {
      'page': page,
      'limit': limit,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (published != null) 'published': published,
      if (userId != null) 'userId': userId,
      'sort': sort,
      'order': order,
    },
    withAuth: true,
    disableCache: true,
  ).mapSync((value) => PaginatedPosts.fromJson(jsonMap(value)));

  Future<ApiResult<ApiPost>> find(int id, {CancelToken? cancelToken}) => get(
    ApiUrls.post(id),
    cancelToken: cancelToken,
    requestConfig: const LikeRequestConfig(cacheTags: ['posts']),
    withAuth: true,
    disableCache: true,
  ).mapSync((value) => ApiPost.fromJson(_envelopeData(value)));

  Future<ApiResult<ApiPost>> create({
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) => post(
    ApiUrls.posts,
    requestConfig: const LikeRequestConfig(invalidates: ['posts']),
    body: {
      'title': title,
      'body': body,
      'published': published,
      'userId': userId,
    },
    withAuth: true,
  ).mapSync((value) => ApiPost.fromJson(_envelopeData(value)));

  Future<ApiResult<ApiPost>> replace({
    required int id,
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) => put(
    ApiUrls.post(id),
    requestConfig: const LikeRequestConfig(invalidates: ['posts']),
    body: {
      'title': title,
      'body': body,
      'published': published,
      'userId': userId,
    },
    withAuth: true,
    disableCache: true,
  ).mapSync((value) => ApiPost.fromJson(_envelopeData(value)));

  Future<ApiResult<ApiPost>> update(int id, Map<String, dynamic> values) =>
      patch(
        ApiUrls.post(id),
        requestConfig: const LikeRequestConfig(invalidates: ['posts']),
        body: values,
        withAuth: true,
        disableCache: true,
      ).mapSync((value) => ApiPost.fromJson(_envelopeData(value)));

  Future<ApiResult<void>> remove(int id) async {
    final result = await delete(
      ApiUrls.post(id),
      requestConfig: const LikeRequestConfig(invalidates: ['posts']),
      withAuth: true,
      disableCache: true,
    );
    return result.isSuccess
        ? LikeApiResult<void>.success(null)
        : LikeApiResult<void>.error(result.error);
  }
}

Map<String, dynamic> _envelopeData(Object? value) =>
    jsonMap(jsonMap(value)['data']);
