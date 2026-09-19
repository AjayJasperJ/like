import 'package:sqlite3/sqlite3.dart';

final class AppDatabase {
  AppDatabase(String path) : connection = sqlite3.open(path) {
    _migrate();
  }

  AppDatabase.inMemory() : connection = sqlite3.openInMemory() {
    _migrate();
  }

  final Database connection;

  void close() => connection.dispose();

  void _migrate() {
    connection
      ..execute('PRAGMA foreign_keys = ON;')
      ..execute('''
        CREATE TABLE IF NOT EXISTS users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT NOT NULL UNIQUE COLLATE NOCASE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          created_at TEXT NOT NULL
        );
      ''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS posts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          published INTEGER NOT NULL DEFAULT 0,
          user_id INTEGER NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT
        );
      ''')
      ..execute('''
        CREATE TABLE IF NOT EXISTS refresh_sessions (
          token_hash TEXT PRIMARY KEY,
          user_id INTEGER NOT NULL,
          expires_at TEXT NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        );
      ''')
      ..execute(
        'CREATE INDEX IF NOT EXISTS refresh_sessions_user_id_idx '
        'ON refresh_sessions (user_id);',
      );
  }
}
