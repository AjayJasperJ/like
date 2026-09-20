import 'json_parse.dart';

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
        id: JsonParse.integer(json['id']),
        name: JsonParse.string(json['name']),
        email: JsonParse.string(json['email']),
        createdAt: JsonParse.dateTime(json['createdAt']),
      );
}
