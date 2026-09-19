import 'dart:io';

import 'package:shelf/shelf.dart';

import '../core/api_exception.dart';
import '../http/http_utils.dart';
import '../services/auth_service.dart';

Middleware corsMiddleware() => (innerHandler) => (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await innerHandler(request);
      return response.change(headers: {...response.headers, ..._corsHeaders});
    };

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'access-control-allow-headers': 'Origin, Content-Type, Authorization',
};

Middleware errorMiddleware() => (innerHandler) => (request) async {
      try {
        return await innerHandler(request);
      } on ApiException catch (error) {
        return jsonResponse({'error': error.message}, status: error.statusCode);
      } catch (error, stackTrace) {
        stderr
          ..writeln('Unhandled request error: $error')
          ..writeln(stackTrace);
        return jsonResponse(
          {'error': 'Internal server error'},
          status: HttpStatus.internalServerError,
        );
      }
    };

Middleware authenticationMiddleware(AuthService authService) =>
    (innerHandler) => (request) {
          const publicPaths = {
            '',
            'health',
            'api/auth/register',
            'api/auth/login',
            'api/auth/refresh',
          };
          if (request.method == 'OPTIONS' ||
              publicPaths.contains(request.url.path)) {
            return innerHandler(request);
          }

          final authorization =
              request.headers[HttpHeaders.authorizationHeader];
          if (authorization == null || !authorization.startsWith('Bearer ')) {
            throw const ApiException(401, 'Bearer access token is required');
          }
          final token = authorization.substring(7).trim();
          if (token.isEmpty) {
            throw const ApiException(401, 'Bearer access token is required');
          }
          final userId = authService.verifyAccessToken(token);
          return innerHandler(request.change(context: {'userId': userId}));
        };
