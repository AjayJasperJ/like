import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../core/api_exception.dart';
import '../http/http_utils.dart';
import '../repositories/post_repository.dart';

final class SystemController {
  const SystemController(this._posts);

  final PostRepository _posts;

  Response index(Request request) => jsonResponse({
        'name': 'Like test API',
        'version': '1.0.0',
        'documentation': '/README.md',
        'authentication': 'Use Authorization: Bearer <accessToken>',
        'endpoints': [
          'GET /health (public)',
          'POST /api/auth/register (public)',
          'POST /api/auth/login (public)',
          'POST /api/auth/refresh (public)',
          'POST /api/auth/logout',
          'GET /api/auth/me',
          'GET /api/posts?page=1&limit=10&search=&published=',
          'GET /api/posts/:id',
          'POST /api/posts',
          'PUT /api/posts/:id',
          'PATCH /api/posts/:id',
          'DELETE /api/posts/:id',
          'POST /api/reset',
          'GET /api/status/:code',
          'GET /api/delay/:milliseconds',
        ],
      });

  Response health(Request request) => jsonResponse({
        'status': 'ok',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

  Response reset(Request request) {
    _posts.reset();
    return jsonResponse(
        {'message': 'Test data reset', 'count': _posts.all.length});
  }

  Response status(Request request, String code) {
    final value = int.tryParse(code);
    if (value == null || value < 100 || value > 599) {
      throw ApiException(400, 'Status code must be between 100 and 599');
    }
    return jsonResponse(
      {'status': value, 'message': 'Intentional test response'},
      status: value,
    );
  }

  Future<Response> delay(Request request, String milliseconds) async {
    final value = int.tryParse(milliseconds);
    if (value == null || value < 0 || value > 30000) {
      throw ApiException(400, 'Delay must be between 0 and 30000 ms');
    }
    await Future<void>.delayed(Duration(milliseconds: value));
    return jsonResponse({'delayedByMs': value});
  }

  Response notFound(Request request, String ignored) => jsonResponse(
        {'error': 'Route not found', 'path': request.requestedUri.path},
        status: HttpStatus.notFound,
      );
}
