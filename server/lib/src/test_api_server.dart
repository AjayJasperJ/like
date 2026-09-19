import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'controllers/auth_controller.dart';
import 'controllers/post_controller.dart';
import 'controllers/system_controller.dart';
import 'database/app_database.dart';
import 'middleware/server_middleware.dart';
import 'repositories/post_repository.dart';
import 'repositories/refresh_session_repository.dart';
import 'repositories/user_repository.dart';
import 'services/auth_service.dart';

final class TestApiServer {
  TestApiServer({
    String jwtSecret = 'like-test-server-change-me',
    String databasePath = 'like_test_server.db',
  }) : this._(AppDatabase(databasePath), jwtSecret);

  TestApiServer.inMemory({String jwtSecret = 'like-test-server-change-me'})
      : this._(AppDatabase.inMemory(), jwtSecret);

  TestApiServer._(this._database, String jwtSecret)
      : _posts = PostRepository(_database),
        _authService = AuthService(
          users: UserRepository(_database),
          refreshSessions: RefreshSessionRepository(_database),
          jwtSecret: jwtSecret,
        );

  final AppDatabase _database;
  final AuthService _authService;
  final PostRepository _posts;

  void close() => _database.close();

  Handler get handler {
    final auth = AuthController(_authService);
    final posts = PostController(_posts);
    final system = SystemController(_posts);
    final router = Router()
      ..get('/', system.index)
      ..get('/health', system.health)
      ..post('/api/auth/register', auth.register)
      ..post('/api/auth/login', auth.login)
      ..post('/api/auth/refresh', auth.refresh)
      ..post('/api/auth/logout', auth.logout)
      ..get('/api/auth/me', auth.me)
      ..get('/api/posts', posts.list)
      ..get('/api/posts/<id>', posts.get)
      ..post('/api/posts', posts.create)
      ..put('/api/posts/<id>', posts.replace)
      ..patch('/api/posts/<id>', posts.update)
      ..delete('/api/posts/<id>', posts.delete)
      ..post('/api/reset', system.reset)
      ..get('/api/status/<code>', system.status)
      ..get('/api/delay/<milliseconds>', system.delay)
      ..all('/<ignored|.*>', system.notFound);

    return const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(corsMiddleware())
        .addMiddleware(errorMiddleware())
        .addMiddleware(authenticationMiddleware(_authService))
        .addHandler(router.call);
  }
}
