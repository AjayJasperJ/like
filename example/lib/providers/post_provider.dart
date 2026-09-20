import 'package:flutter/foundation.dart';
import 'package:like/like.dart' hide Pagination;

import '../models/api_models.dart';
import '../repositories/post_repository.dart';

final class PostProvider extends ChangeNotifier with LikeAutoReconnectMixin {
  PostProvider(this._repository);

  final PostRepository _repository;

  final postsState = LikeNotifierState<List<ApiPost>>(
    initialValue: LikeStateResponse.idle(),
    mapper: (json) {
      if (json is List) {
        return json.map((e) => ApiPost.fromJson(e as Map<String, dynamic>)).toList();
      }
      return const [];
    },
  );

  Pagination? _pagination;
  String _search = '';
  bool? _published;

  Pagination? get pagination => _pagination;
  String get search => _search;
  bool? get published => _published;
  bool get busy =>
      postsState.value.state == LikeState.loading ||
      postsState.value.state == LikeState.refreshing;

  Future<void> load({int page = 1, bool refresh = false}) async {
    await fetch<List<ApiPost>>(
      state: postsState,
      autoResync: true,
      ars: LikeARS(refresh: refresh || postsState.value.data != null),
      action: (ct, ars) async {
        final result = await _repository.list(
          page: page,
          search: _search,
          published: _published,
        );
        if (result.isSuccess && result.data != null) {
          _pagination = result.data!.pagination;
          return LikeStateResponse.success(result.data!.posts);
        }
        final error = result.error ??
            LikeError(
              message: 'Could not load posts',
              type: LikeApiErrorType.unknown,
            );
        return LikeStateResponse.error(error, data: postsState.value.data);
      },
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
      await load(page: _pagination?.page ?? 1, refresh: true);
    }
    return result;
  }

  Future<ApiResult<void>> remove(int id) async {
    final result = await _repository.remove(id);
    if (result.isSuccess) {
      await load(page: _pagination?.page ?? 1, refresh: true);
    }
    return result;
  }
}
