import 'dart:convert';

import 'package:like_test_server/server.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late TestApiServer application;
  late Handler handler;

  setUp(() {
    application = TestApiServer.inMemory();
    handler = application.handler;
  });

  tearDown(() {
    application.close();
  });

  test('protected APIs reject requests without an access token', () async {
    final response = await _send(handler, 'GET', '/api/posts');

    expect(response.statusCode, 401);
    expect(await _json(response), {'error': 'Bearer access token is required'});
  });

  test('complete register, authenticated API, refresh, and logout flow',
      () async {
    final registration = await _send(
      handler,
      'POST',
      '/api/auth/register',
      body: {
        'name': 'Test User',
        'email': 'test@example.com',
        'password': 'password123',
      },
    );
    expect(registration.statusCode, 201);
    final registrationJson = await _json(registration);
    final firstSession = registrationJson['data']! as Map<String, dynamic>;
    final firstAccess = firstSession['accessToken']! as String;
    final firstRefresh = firstSession['refreshToken']! as String;

    final me = await _send(
      handler,
      'GET',
      '/api/auth/me',
      accessToken: firstAccess,
    );
    expect(me.statusCode, 200);
    expect(
      ((await _json(me))['data']! as Map<String, dynamic>)['email'],
      'test@example.com',
    );

    final posts = await _send(
      handler,
      'GET',
      '/api/posts?page=1&limit=2',
      accessToken: firstAccess,
    );
    expect(posts.statusCode, 200);
    expect(((await _json(posts))['data']! as List<dynamic>).length, 2);

    final refresh = await _send(
      handler,
      'POST',
      '/api/auth/refresh',
      body: {'refreshToken': firstRefresh},
    );
    expect(refresh.statusCode, 200);
    final secondSession =
        (await _json(refresh))['data']! as Map<String, dynamic>;
    final secondAccess = secondSession['accessToken']! as String;
    final secondRefresh = secondSession['refreshToken']! as String;
    expect(secondRefresh, isNot(firstRefresh));

    final reusedRefresh = await _send(
      handler,
      'POST',
      '/api/auth/refresh',
      body: {'refreshToken': firstRefresh},
    );
    expect(reusedRefresh.statusCode, 401);

    final logout = await _send(
      handler,
      'POST',
      '/api/auth/logout',
      accessToken: secondAccess,
      body: {'refreshToken': secondRefresh},
    );
    expect(logout.statusCode, 200);

    final refreshAfterLogout = await _send(
      handler,
      'POST',
      '/api/auth/refresh',
      body: {'refreshToken': secondRefresh},
    );
    expect(refreshAfterLogout.statusCode, 401);
  });

  test('login succeeds and duplicate registration is rejected', () async {
    const credentials = {
      'name': 'Login User',
      'email': 'login@example.com',
      'password': 'password123',
    };
    expect(
      (await _send(handler, 'POST', '/api/auth/register', body: credentials))
          .statusCode,
      201,
    );
    expect(
      (await _send(handler, 'POST', '/api/auth/register', body: credentials))
          .statusCode,
      409,
    );

    final login = await _send(
      handler,
      'POST',
      '/api/auth/login',
      body: {
        'email': credentials['email'],
        'password': credentials['password'],
      },
    );
    expect(login.statusCode, 200);
    expect(
      ((await _json(login))['data']! as Map<String, dynamic>)['accessToken'],
      isA<String>().having((value) => value.isNotEmpty, 'is not empty', true),
    );
  });
}

Future<Response> _send(
  Handler handler,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? accessToken,
}) {
  final headers = <String, String>{};
  if (body != null) headers['content-type'] = 'application/json';
  if (accessToken != null) headers['authorization'] = 'Bearer $accessToken';
  return Future<Response>.value(handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    ),
  ));
}

Future<Map<String, dynamic>> _json(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;
