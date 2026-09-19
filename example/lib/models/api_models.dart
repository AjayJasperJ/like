final class ApiUser {
  const ApiUser({
    required this.id,
    required this.name,
    required this.email,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final DateTime createdAt;

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
        id: json['id'] as int,
        name: json['name'] as String,
        email: json['email'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

final class AuthSession {
  const AuthSession({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.expiresIn,
    required this.refreshExpiresIn,
  });

  final ApiUser user;
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final int expiresIn;
  final int refreshExpiresIn;

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
        user: ApiUser.fromJson(_jsonMap(json['user'])),
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        tokenType: json['tokenType'] as String,
        expiresIn: json['expiresIn'] as int,
        refreshExpiresIn: json['refreshExpiresIn'] as int,
      );
}

final class ApiPost {
  const ApiPost({
    required this.id,
    required this.title,
    required this.body,
    required this.published,
    required this.userId,
    required this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String title;
  final String body;
  final bool published;
  final int userId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory ApiPost.fromJson(Map<String, dynamic> json) => ApiPost(
        id: json['id'] as int,
        title: json['title'] as String,
        body: json['body'] as String,
        published: json['published'] as bool,
        userId: json['userId'] as int,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.parse(json['updatedAt'] as String),
      );
}

final class Pagination {
  const Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
    required this.hasNext,
    required this.hasPrevious,
  });

  final int page;
  final int limit;
  final int total;
  final int totalPages;
  final bool hasNext;
  final bool hasPrevious;

  factory Pagination.fromJson(Map<String, dynamic> json) => Pagination(
        page: json['page'] as int,
        limit: json['limit'] as int,
        total: json['total'] as int,
        totalPages: json['totalPages'] as int,
        hasNext: json['hasNext'] as bool,
        hasPrevious: json['hasPrevious'] as bool,
      );
}

final class PaginatedPosts {
  const PaginatedPosts({required this.posts, required this.pagination});

  final List<ApiPost> posts;
  final Pagination pagination;

  factory PaginatedPosts.fromJson(Map<String, dynamic> json) => PaginatedPosts(
        posts: (json['data'] as List<dynamic>)
            .map((item) => ApiPost.fromJson(_jsonMap(item)))
            .toList(growable: false),
        pagination: Pagination.fromJson(_jsonMap(json['pagination'])),
      );
}

Map<String, dynamic> jsonMap(Object? value) => _jsonMap(value);

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw const FormatException('Expected a JSON object');
}
