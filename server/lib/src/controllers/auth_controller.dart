import 'dart:io';

import 'package:shelf/shelf.dart';

import '../http/http_utils.dart';
import '../services/auth_service.dart';

final class AuthController {
  const AuthController(this._authService);

  final AuthService _authService;

  Future<Response> register(Request request) async {
    final body = await readJsonObject(request);
    final session = _authService.register(
      name: requiredString(body, 'name', minimumLength: 2),
      email: requiredString(body, 'email'),
      password: requiredString(body, 'password', minimumLength: 8),
    );
    return jsonResponse({'data': session}, status: HttpStatus.created);
  }

  Future<Response> login(Request request) async {
    final body = await readJsonObject(request);
    final session = _authService.login(
      email: requiredString(body, 'email'),
      password: requiredString(body, 'password'),
    );
    return jsonResponse({'data': session});
  }

  Future<Response> refresh(Request request) async {
    final body = await readJsonObject(request);
    final session = _authService.refresh(requiredString(body, 'refreshToken'));
    return jsonResponse({'data': session});
  }

  Future<Response> logout(Request request) async {
    final body = await readJsonObject(request);
    _authService.logout(
      userId: authenticatedUserId(request),
      refreshToken: requiredString(body, 'refreshToken'),
    );
    return jsonResponse({'message': 'Logged out successfully'});
  }

  Response me(Request request) => jsonResponse({
        'data':
            _authService.findUser(authenticatedUserId(request)).toPublicJson(),
      });
}
