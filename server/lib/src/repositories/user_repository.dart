import 'package:sqlite3/sqlite3.dart';

import '../database/app_database.dart';
import '../models/user.dart';

final class UserRepository {
  const UserRepository(this._database);

  final AppDatabase _database;

  User create({
    required String name,
    required String email,
    required String passwordHash,
    required String salt,
  }) {
    final createdAt = DateTime.now().toUtc();
    _database.connection.execute(
      'INSERT INTO users (name, email, password_hash, salt, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [name, email, passwordHash, salt, createdAt.toIso8601String()],
    );
    return User(
      id: _database.connection.lastInsertRowId,
      name: name,
      email: email,
      passwordHash: passwordHash,
      salt: salt,
      createdAt: createdAt,
    );
  }

  User? findById(int id) => _firstUser(
        _database.connection.select('SELECT * FROM users WHERE id = ?', [id]),
      );

  User? findByEmail(String email) => _firstUser(
        _database.connection.select(
          'SELECT * FROM users WHERE email = ? COLLATE NOCASE',
          [email],
        ),
      );

  bool exists(int id) => _database.connection.select(
        'SELECT 1 FROM users WHERE id = ? LIMIT 1',
        [id],
      ).isNotEmpty;

  User? _firstUser(ResultSet rows) => rows.isEmpty ? null : _toUser(rows.first);

  User _toUser(Row row) => User(
        id: row['id'] as int,
        name: row['name'] as String,
        email: row['email'] as String,
        passwordHash: row['password_hash'] as String,
        salt: row['salt'] as String,
        createdAt: DateTime.parse(row['created_at'] as String),
      );
}
