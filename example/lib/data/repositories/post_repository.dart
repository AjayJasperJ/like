import '../models/api_models.dart';
import '../services/post_api_service.dart';

abstract interface class PostsRepository {
  Future<ApiResult<PaginatedPosts>> list({
    int page = 1,
    String? search,
    bool? published,
  });

  Future<ApiResult<ApiPost>> find(int id);

  Future<ApiResult<ApiPost>> create({
    required String title,
    required String body,
    required bool published,
    required int userId,
  });

  Future<ApiResult<ApiPost>> replace({
    required int id,
    required String title,
    required String body,
    required bool published,
    required int userId,
  });

  Future<ApiResult<ApiPost>> togglePublished(ApiPost post);
  Future<ApiResult<void>> remove(int id);
}

final class PostRepository implements PostsRepository {
  PostRepository(this._api);

  final PostApiService _api;

  @override
  Future<ApiResult<PaginatedPosts>> list({
    int page = 1,
    String? search,
    bool? published,
  }) =>
      _api.list(page: page, search: search, published: published);

  @override
  Future<ApiResult<ApiPost>> find(int id) => _api.find(id);

  @override
  Future<ApiResult<ApiPost>> create({
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) =>
      _api.create(
        title: title,
        body: body,
        published: published,
        userId: userId,
      );

  @override
  Future<ApiResult<ApiPost>> replace({
    required int id,
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) =>
      _api.replace(
        id: id,
        title: title,
        body: body,
        published: published,
        userId: userId,
      );

  @override
  Future<ApiResult<ApiPost>> togglePublished(ApiPost post) =>
      _api.update(post.id, {'published': !post.published});

  @override
  Future<ApiResult<void>> remove(int id) => _api.remove(id);
}
