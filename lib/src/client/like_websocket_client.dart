import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart';
import 'package:like/src/services/like_pipeline.dart';

/// Managed WebSocket client for the LIKE package.
///
/// Features auto-reconnect, token synchronization, ping-pong heartbeats,
/// and automatic dispatch of incoming events to the [LikePipeline].
/// State changes and connection handshakes are synchronized sequentially to prevent races.
class LikeWebSocketClient {
  final String url;
  final Future<String?> Function()? getToken;
  final Duration reconnectInterval;
  final Duration pingInterval;
  final String pingPayload;

  WebSocket? _socket;
  bool _isDisposed = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;

  final Lock _lock = Lock();
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();

  LikeWebSocketClient({
    required this.url,
    this.getToken,
    this.reconnectInterval = const Duration(seconds: 5),
    this.pingInterval = const Duration(seconds: 30),
    this.pingPayload = '{"type":"ping"}',
  });

  /// Stream of decoded JSON/string messages received from the server.
  Stream<dynamic> get messages => _messageController.stream;

  /// Returns true if the WebSocket is currently open.
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  /// Connects to the WebSocket server sequentially.
  Future<void> connect() async {
    await _lock.synchronized(() async {
      if (_isDisposed || _isConnecting || isConnected) return;
      _isConnecting = true;

      try {
        var connectionUrl = url;
        if (getToken != null) {
          final token = await getToken!();
          if (token != null && token.isNotEmpty) {
            final uri = Uri.parse(url);
            final params = Map<String, dynamic>.from(uri.queryParameters);
            params['token'] = token;
            connectionUrl = uri.replace(queryParameters: params).toString();
          }
        }

        debugPrint('[LIKE WebSocket] Connecting to $connectionUrl...');
        final socket = await WebSocket.connect(connectionUrl);
        _socket = socket;
        _isConnecting = false;

        _onConnected(socket);
      } catch (e) {
        _isConnecting = false;
        debugPrint('[LIKE WebSocket] Connection failed: $e');
        _scheduleReconnect();
      }
    });
  }

  /// Disconnects from the WebSocket server sequentially.
  Future<void> disconnect() async {
    await _lock.synchronized(() async {
      _pingTimer?.cancel();
      _reconnectTimer?.cancel();
      if (_socket != null) {
        debugPrint('[LIKE WebSocket] Closing connection...');
        await _socket!.close();
        _socket = null;
      }
    });
  }

  void _onConnected(WebSocket socket) {
    debugPrint('[LIKE WebSocket] Connected successfully.');
    _startHeartbeat();

    socket.listen(
      (rawData) {
        _handleIncomingMessage(rawData);
      },
      onError: (err) {
        debugPrint('[LIKE WebSocket] Socket error occurred: $err');
        _handleDisconnect(socket);
      },
      onDone: () {
        debugPrint('[LIKE WebSocket] Socket closed by remote host.');
        _handleDisconnect(socket);
      },
    );
  }

  void _handleIncomingMessage(dynamic rawData) {
    try {
      final decoded = jsonDecode(rawData.toString());
      _messageController.add(decoded);

      // Extract endpoint path and data to publish to the LikePipeline
      if (decoded is Map<String, dynamic>) {
        final String? path = decoded['path'] as String?;
        final dynamic data = decoded['data'];

        if (path != null && data != null) {
          // Emit a simulated HTTP response to the LikePipeline
          LikePipeline().emit(
            path,
            Response(
              requestOptions: RequestOptions(path: path),
              data: data,
              statusCode: 200,
            ),
          );
        }
      }
    } catch (e) {
      // If it's not JSON, broadcast raw data
      _messageController.add(rawData);
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (timer) {
      if (isConnected) {
        _socket!.add(pingPayload);
      }
    });
  }

  void _handleDisconnect(WebSocket socket) {
    _lock.synchronized(() async {
      if (_socket == socket) {
        _socket = null;
        _pingTimer?.cancel();
        _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(reconnectInterval, () {
      connect();
    });
  }

  /// Sends a message down the socket channel sequentially.
  Future<void> send(dynamic message) async {
    await _lock.synchronized(() async {
      if (!isConnected) {
        debugPrint('[LIKE WebSocket] Cannot send message: client is offline.');
        return;
      }
      final payload = message is String ? message : jsonEncode(message);
      _socket!.add(payload);
    });
  }

  /// Disposes of the client and cleans up resources sequentially.
  Future<void> dispose() async {
    await _lock.synchronized(() async {
      _isDisposed = true;
      _reconnectTimer?.cancel();
      _pingTimer?.cancel();
      if (_socket != null) {
        await _socket!.close();
        _socket = null;
      }
      await _messageController.close();
      debugPrint('[LIKE WebSocket] Disposed client.');
    });
  }
}
