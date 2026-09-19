final class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    required this.salt,
    required this.createdAt,
  });

  final int id;
  final String name;
  final String email;
  final String passwordHash;
  final String salt;
  final DateTime createdAt;

  Map<String, Object?> toPublicJson() => {
        'id': id,
        'name': name,
        'email': email,
        'createdAt': createdAt.toIso8601String(),
      };
}
