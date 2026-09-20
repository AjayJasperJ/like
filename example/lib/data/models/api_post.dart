import 'package:like/like.dart';

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
        id: JsonParse.integer(json['id']),
        title: JsonParse.string(json['title']),
        body: JsonParse.string(json['body']),
        published: JsonParse.boolean(json['published']),
        userId: JsonParse.integer(json['userId']),
        createdAt: JsonParse.dateTime(json['createdAt']),
        updatedAt: JsonParse.nullableDateTime(json['updatedAt']),
      );
}
