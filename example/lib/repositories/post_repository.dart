import 'package:like/like.dart';
import '../models/post.dart';

// Top-level mappers — required for compute() isolate compatibility
List<Post> _postsFromJson(dynamic json) => (json as List<dynamic>)
    .map((e) => Post.fromJson(e as Map<String, dynamic>))
    .toList();

Post _postFromJson(dynamic json) => Post.fromJson(json as Map<String, dynamic>);

class PostRepository extends LikeBaseApiService {
  Future<ApiResult<List<Post>>> getPosts({
    int page = 1,
    int limit = 10,
  }) async {
    assert(page > 0, 'page must be greater than zero');
    assert(limit > 0, 'limit must be greater than zero');
    return await get('/posts', query: {'_page': page, '_limit': limit})
        .mapAsync(_postsFromJson);
  }

  Future<ApiResult<Post>> getPost(int id) async =>
      await get('/posts/$id').mapAsync(_postFromJson);

  Future<ApiResult<List<Post>>> getPostComments(int id) async =>
      await get('/posts/$id/comments').mapAsync(_postsFromJson);

  Future<ApiResult<List<Post>>> getCommentsByPostId(int postId) async =>
      await get('/comments', query: {'postId': postId}).mapAsync(_postsFromJson);

  Future<ApiResult<Post>> createPost(Map<String, dynamic> data) async =>
      await post('/posts', body: data).mapAsync(_postFromJson);

  Future<ApiResult<Post>> updatePost(int id, Map<String, dynamic> data) async =>
      await put('/posts/$id', body: data).mapAsync(_postFromJson);

  Future<ApiResult<Post>> patchPost(int id, Map<String, dynamic> data) async =>
      await patch('/posts/$id', body: data).mapAsync(_postFromJson);

  Future<ApiResult<Post>> deletePost(int id) async =>
      await delete('/posts/$id').mapAsync(_postFromJson);
}
