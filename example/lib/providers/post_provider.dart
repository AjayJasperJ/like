import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../repositories/post_repository.dart';

final class PostProvider extends ChangeNotifier {
  PostProvider(this._repository);

  final PostRepository _repository;

  List<ApiPost> _posts = const [];
  Pagination? _pagination;
  bool _busy = false;
  String? _error;
  String _search = '';
  bool? _published;

  List<ApiPost> get posts => _posts;
  Pagination? get pagination => _pagination;
  bool get busy => _busy;
  String? get error => _error;
  String get search => _search;
  bool? get published => _published;

  Future<void> load({int page = 1}) async {
    _busy = true;
    _error = null;
    notifyListeners();
    final result = await _repository.list(
      page: page,
      search: _search,
      published: _published,
    );
    if (result.isSuccess && result.data != null) {
      _posts = result.data!.posts;
      _pagination = result.data!.pagination;
    } else {
      _error = result.error?.message ?? 'Could not load posts';
    }
    _busy = false;
    notifyListeners();
  }

  Future<void> filter({String? search, bool? published, bool clear = false}) {
    _search = search?.trim() ?? _search;
    _published = clear ? null : published ?? _published;
    return load();
  }

  Future<ApiPost?> find(int id) async {
    final result = await _repository.find(id);
    if (!result.isSuccess) {
      _error = result.error?.message ?? 'Could not load post';
      notifyListeners();
      return null;
    }
    return result.data;
  }

  Future<ApiPost?> save({
    ApiPost? post,
    required String title,
    required String body,
    required bool published,
    required int userId,
  }) async {
    _busy = true;
    _error = null;
    notifyListeners();
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
    _busy = false;
    if (!result.isSuccess) {
      _error = result.error?.message ?? 'Could not save post';
      notifyListeners();
      return null;
    }
    await load();
    return result.data;
  }

  Future<bool> toggle(ApiPost post) async {
    final result = await _repository.togglePublished(post);
    if (!result.isSuccess) {
      _error = result.error?.message ?? 'Could not update post';
      notifyListeners();
      return false;
    }
    await load(page: _pagination?.page ?? 1);
    return true;
  }

  Future<bool> remove(int id) async {
    final result = await _repository.remove(id);
    if (!result.isSuccess) {
      _error = result.error?.message ?? 'Could not delete post';
      notifyListeners();
      return false;
    }
    await load(page: _pagination?.page ?? 1);
    return true;
  }
}
