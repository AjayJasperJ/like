import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_io/io.dart';
import 'package:like/like.dart';
import 'package:like/src/models/like_event.dart';
import 'package:like/src/services/like_pipeline.dart';

void main() {
  late HttpServer server;
  late String wsUrl;
  final List<WebSocket> activeServerSockets = [];

  setUp(() async {
    // Spin up a local mock WebSocket server
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    wsUrl = 'ws://${server.address.address}:${server.port}';

    server.transform(WebSocketTransformer()).listen((WebSocket clientSocket) {
      activeServerSockets.add(clientSocket);
      clientSocket.listen((message) {
        if (message is String) {
          try {
            final decoded = jsonDecode(message);
            if (decoded['type'] == 'ping') {
              clientSocket.add(jsonEncode({'type': 'pong'}));
              return;
            }
          } catch (_) {}
        }
        // Echo back other messages
        clientSocket.add(message);
      });
    });
  });

  tearDown(() async {
    for (final socket in activeServerSockets) {
      await socket.close();
    }
    activeServerSockets.clear();
    await server.close(force: true);
  });

  group('LikeWebSocketClient - Basic Functionality', () {
    test('connects and receives echo messages', () async {
      final client = LikeWebSocketClient(url: wsUrl);

      await client.connect();
      expect(client.isConnected, isTrue);

      final received = [];
      final subscription = client.messages.listen((msg) {
        received.add(msg);
      });

      await client.send(jsonEncode({'hello': 'world'}));

      // Wait for echo
      await Future.delayed(const Duration(milliseconds: 200));

      expect(received.length, equals(1));
      expect(received.first['hello'], equals('world'));

      await subscription.cancel();
      await client.dispose();
    });

    test('reconnects automatically when connection is lost', () async {
      final client = LikeWebSocketClient(
        url: wsUrl,
        reconnectInterval: const Duration(milliseconds: 100),
      );

      await client.connect();
      expect(client.isConnected, isTrue);

      // Force-close all server sockets to trigger a disconnect
      for (final socket in activeServerSockets) {
        await socket.close();
      }
      activeServerSockets.clear();

      await Future.delayed(const Duration(milliseconds: 50));
      expect(client.isConnected, isFalse);

      // Wait for reconnect interval to run
      await Future.delayed(const Duration(milliseconds: 200));
      expect(client.isConnected, isTrue);

      await client.dispose();
    });

    test('token injection updates the URL query parameters', () async {
      String? capturedUrl;
      final tokenServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      tokenServer.listen((HttpRequest request) async {
        capturedUrl = request.uri.toString();
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          activeServerSockets.add(socket);
        }
      });

      final client = LikeWebSocketClient(
        url: 'ws://${tokenServer.address.address}:${tokenServer.port}/ws',
        getToken: () async => 'super-secret-token',
      );

      await client.connect();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(capturedUrl, contains('token=super-secret-token'));

      await client.dispose();
      await tokenServer.close(force: true);
    });

    test('broadcasts pipeline events when JSON contains path and data keys',
        () async {
      final client = LikeWebSocketClient(url: wsUrl);
      await client.connect();

      final events = <LikeEvent>[];
      final subscription = LikePipeline().stream.listen((event) {
        events.add(event);
      });

      // Send payload with path and data keys, which server will echo
      final payload = {
        'path': '/user/profile',
        'data': {'id': '10', 'name': 'John'},
      };
      await client.send(jsonEncode(payload));

      await Future.delayed(const Duration(milliseconds: 200));

      expect(events.length, equals(1));
      expect(events.first.key, equals('/user/profile'));
      expect(events.first.data['name'], equals('John'));

      await subscription.cancel();
      await client.dispose();
    });

    test('sequential calls to connect/disconnect do not cause race conditions',
        () async {
      final client = LikeWebSocketClient(url: wsUrl);

      // Run multiple connects and disconnects in parallel.
      // Since they are guarded by a Lock, they will execute sequentially and safely.
      final futures = <Future>[];
      futures.add(client.connect());
      futures.add(client.disconnect());
      futures.add(client.connect());
      futures.add(client.disconnect());
      futures.add(client.connect());

      await Future.wait(futures);

      expect(client.isConnected, isTrue);

      await client.dispose();
    });
  });
}
