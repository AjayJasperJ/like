import 'package:like/like.dart';
import 'api_post.dart';

final class PaginatedPosts extends PaginationTool<ApiPost> {
  const PaginatedPosts({
    required this.posts,
    this.pageNumber,
    this.limitNumber,
    this.totalCount,
  }) : super(
          listData: posts,
          page: pageNumber,
          contentLimit: limitNumber,
          totalContent: totalCount,
        );

  final List<ApiPost> posts;
  final int? pageNumber;
  final int? limitNumber;
  final int? totalCount;

  @override
  List<ApiPost> get items => posts;

  @override
  int? get page => pageNumber;

  @override
  int? get contentLimit => limitNumber;

  @override
  int? get totalContent => totalCount;

  factory PaginatedPosts.fromJson(Map<String, dynamic> json) {
    final postsData = JsonParse.list(
      json['data'],
      (item) => ApiPost.fromJson(JsonParse.map(item)),
    );
    final paginationMap = JsonParse.map(json['pagination']);

    return PaginatedPosts(
      posts: postsData,
      pageNumber: JsonParse.integer(paginationMap['page']),
      limitNumber: JsonParse.integer(paginationMap['limit']),
      totalCount: JsonParse.integer(paginationMap['total']),
    );
  }
}
