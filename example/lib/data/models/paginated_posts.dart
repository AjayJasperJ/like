import 'package:like/like.dart';
import 'api_post.dart';

final class PaginatedPosts extends PaginationTool<ApiPost> {
  PaginatedPosts({
    required this.posts,
    super.page,
    super.contentLimit,
    super.totalContent,
    super.totalPages,
    super.hasNextOverride,
    super.hasPreviousOverride,
    super.cursor,
    super.nextCursor,
  }) : super(listData: posts);

  final List<ApiPost> posts;

  factory PaginatedPosts.fromJson(Map<String, dynamic> json) {
    final posts = (json['data'] as List<dynamic>?)
            ?.map((item) => ApiPost.fromJson(JsonParse.map(item)))
            .toList(growable: false) ??
        const [];
    final meta = PaginationTool<ApiPost>.fromMap(
      json['pagination'] is Map ? JsonParse.map(json['pagination']) : json,
    );
    return PaginatedPosts(
      posts: posts,
      page: meta.page,
      contentLimit: meta.contentLimit,
      totalContent: meta.totalContent,
      totalPages: meta.totalPages,
      hasNextOverride: meta.hasNextOverride,
      hasPreviousOverride: meta.hasPreviousOverride,
      cursor: meta.cursor,
      nextCursor: meta.nextCursor,
    );
  }
}
