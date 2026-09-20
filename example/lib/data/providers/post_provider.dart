import 'package:flutter/foundation.dart';
import 'package:like/like.dart';

import '../models/api_models.dart';
import '../repositories/post_repository.dart';

final class PostProvider extends ChangeNotifier with LikeStateMixin {
  PostProvider(this._repository);

  final PostRepository _repository;

  final postsState = PaginatedNotifierState<ApiPost>();

  String _search = '';
  bool? _published;

  PaginationTool<ApiPost> get pagination => postsState.pagination;

  String get search => _search;

  bool? get published => _published;

  bool get busy =>
      postsState.value.state == LikeState.loading ||
      postsState.value.state == LikeState.refreshing;

  Future<void> load({
    int page = 1,
    bool refresh = false,
    bool overwrite = false,
  }) async {
    await postsState.load(
      page: page,
      refresh: refresh,
      overwrite: overwrite,
      action: (p, limit) => _repository.list(
        page: p,
        search: _search,
        published: _published,
      ),
    );
  }

  Future<void> loadMore() async {
    await postsState.loadNext(
      action: (p, limit) => _repository.list(
        page: p,
        search: _search,
        published: _published,
      ),
    );
  }

  Future<void> filter({String? search, bool? published, bool clear = false}) {
    _search = search?.trim() ?? _search;
    _published = clear ? null : published ?? _published;
    return load(refresh: true);
  }

  Future<ApiResult<ApiPost>> find(int id) async {
    return _repository.find(id);
  }

  Future<ApiResult<ApiPost>> save({
    ApiPost? post,
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) async {
    final result = post == null
        ? await _repository.create(
            title: title,
            body: body,
            published: published,
            userId: userId,
          )
        : await _repository.replace(
            id: post.id,
            title: title,
            body: body,
            published: published,
            userId: userId,
          );
    if (result.isSuccess) {
      await load(refresh: true);
    }
    return result;
  }

  Future<ApiResult<ApiPost>> toggle(ApiPost post) async {
    final result = await _repository.togglePublished(post);
    if (result.isSuccess) {
      await load(page: pagination.page ?? 1, refresh: true);
    }
    return result;
  }

  Future<ApiResult<void>> remove(int id) async {
    final result = await _repository.remove(id);
    if (result.isSuccess) {
      await load(page: pagination.page ?? 1, refresh: true);
    }
    return result;
  }
}
