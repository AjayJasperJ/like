import 'dart:io';

import 'package:like_test_server/server.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main(List<String> arguments) async {
  final address = Platform.environment['HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final jwtSecret =
      Platform.environment['JWT_SECRET'] ?? 'like-test-server-change-me';
  final databasePath =
      Platform.environment['DATABASE_PATH'] ?? 'like_test_server.db';
  final application = TestApiServer(
    jwtSecret: jwtSecret,
    databasePath: databasePath,
  );
  final server = await shelf_io.serve(application.handler, address, port);
  server.autoCompress = true;

  stdout
    ..writeln(
      'Like test API running at http://${server.address.host}:${server.port}',
    )
    ..writeln('Health: http://localhost:${server.port}/health')
    ..writeln('Posts:  http://localhost:${server.port}/api/posts')
    ..writeln('Database: $databasePath');
}
