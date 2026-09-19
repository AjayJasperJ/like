import '../database/app_database.dart';
import '../models/refresh_session.dart';

final class RefreshSessionRepository {
  const RefreshSessionRepository(this._database);

  final AppDatabase _database;

  void save(String tokenHash, RefreshSession session) {
    _database.connection.execute(
      'INSERT OR REPLACE INTO refresh_sessions '
      '(token_hash, user_id, expires_at) VALUES (?, ?, ?)',
      [tokenHash, session.userId, session.expiresAt.toIso8601String()],
    );
  }

  RefreshSession? consume(String tokenHash) {
    final database = _database.connection;
    database.execute('BEGIN IMMEDIATE');
    try {
      final rows = database.select(
        'SELECT user_id, expires_at FROM refresh_sessions '
        'WHERE token_hash = ?',
        [tokenHash],
      );
      database.execute(
        'DELETE FROM refresh_sessions WHERE token_hash = ?',
        [tokenHash],
      );
      database.execute('COMMIT');
      if (rows.isEmpty) return null;
      final row = rows.first;
      return RefreshSession(
        userId: row['user_id'] as int,
        expiresAt: DateTime.parse(row['expires_at'] as String),
      );
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  RefreshSession? find(String tokenHash) {
    final rows = _database.connection.select(
      'SELECT user_id, expires_at FROM refresh_sessions WHERE token_hash = ?',
      [tokenHash],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RefreshSession(
      userId: row['user_id'] as int,
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
  }

  void delete(String tokenHash) => _database.connection.execute(
        'DELETE FROM refresh_sessions WHERE token_hash = ?',
        [tokenHash],
      );
}
