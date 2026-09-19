import '../core/api_exception.dart';
import '../database/app_database.dart';

final class PostRepository {
  PostRepository(this._database) {
    if (_count == 0) reset();
  }

  final AppDatabase _database;

  int get _count => _database.connection
      .select('SELECT COUNT(*) AS count FROM posts')
      .first['count'] as int;

  List<Map<String, Object?>> get all => _database.connection
      .select('SELECT * FROM posts ORDER BY id')
      .map(_toPost)
      .toList(growable: false);

  Map<String, Object?> findById(int id) {
    final rows =
        _database.connection.select('SELECT * FROM posts WHERE id = ?', [id]);
    if (rows.isEmpty) throw ApiException(404, 'Post $id not found');
    return _toPost(rows.first);
  }

  Map<String, Object?> create(Map<String, Object?> values) {
    final createdAt = DateTime.now().toUtc().toIso8601String();
    _database.connection.execute(
      'INSERT INTO posts (title, body, published, user_id, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        values['title'],
        values['body'],
        _boolToInt(values['published'] as bool),
        values['userId'],
        createdAt,
      ],
    );
    return findById(_database.connection.lastInsertRowId);
  }

  Map<String, Object?> replace(
    Map<String, Object?> existing,
    Map<String, Object?> values,
  ) {
    final id = existing['id']! as int;
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    _database.connection.execute(
      'UPDATE posts SET title = ?, body = ?, published = ?, user_id = ?, '
      'updated_at = ? WHERE id = ?',
      [
        values['title'],
        values['body'],
        _boolToInt(values['published'] as bool),
        values['userId'],
        updatedAt,
        id,
      ],
    );
    return findById(id);
  }

  Map<String, Object?> update(
    Map<String, Object?> existing,
    Map<String, Object?> values,
  ) {
    final merged = {...existing, ...values};
    return replace(existing, merged);
  }

  void delete(Map<String, Object?> post) => _database.connection.execute(
        'DELETE FROM posts WHERE id = ?',
        [post['id']],
      );

  void reset() {
    final database = _database.connection;
    database.execute('BEGIN');
    try {
      database
        ..execute('DELETE FROM posts')
        ..execute("DELETE FROM sqlite_sequence WHERE name = 'posts'");
      final statement = database.prepare(
        'INSERT INTO posts '
        '(id, title, body, published, user_id, created_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      try {
        for (var index = 0; index < 35; index++) {
          final id = index + 1;
          statement.execute([
            id,
            'Test post $id',
            'This is the body of test post $id.',
            id.isEven ? 1 : 0,
            (index % 5) + 1,
            DateTime.utc(2026, 1, 1)
                .add(Duration(hours: index))
                .toIso8601String(),
          ]);
        }
      } finally {
        statement.dispose();
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  Map<String, Object?> _toPost(Map<String, Object?> row) => {
        'id': row['id'],
        'title': row['title'],
        'body': row['body'],
        'published': row['published'] == 1,
        'userId': row['user_id'],
        'createdAt': row['created_at'],
        if (row['updated_at'] != null) 'updatedAt': row['updated_at'],
      };

  int _boolToInt(bool value) => value ? 1 : 0;
}
