import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:like/src/core/like_auth_config.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/diagnostics/like_redaction.dart';
import 'package:like/src/interceptors/like_auth_interceptor.dart';
import 'package:synchronized/synchronized.dart';
import 'package:universal_io/io.dart';
import 'package:like/src/services/like_pipeline.dart';

class _WsLifecycleObserver with WidgetsBindingObserver {
  _WsLifecycleObserver(this.onState);
  final ValueChanged<AppLifecycleState> onState;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onState(state);
}

/// Managed WebSocket client for the LIKE package.
///
/// Features auto-reconnect with exponential backoff and jitter, lifecycle pause/resume,
/// token synchronization, ping-pong heartbeats, and automatic dispatch of incoming
/// events to the [LikePipeline].
class LikeWebSocketClient {
  final String url;
  final FutureOr<String?> Function()? getToken;

  /// Optional supplier for a short-lived one-time WebSocket ticket instead of
  /// placing long-lived bearer tokens in query parameters.
  final FutureOr<String?> Function()? authTicketSupplier;

  /// Optional callback invoked right after the socket connects so callers can
  /// send an in-band auth frame rather than passing credentials in the URL.
  final FutureOr<void> Function(LikeWebSocketClient client, String token)?
      onConnectedAuth;

  /// Whether to append the resolved token to `?token=...` on the WebSocket URL.
  ///
  /// Prefer `useQueryToken: false` with [onConnectedAuth] or [authTicketSupplier]
  /// so bearer credentials do not appear in proxy/server URL logs.
  final bool useQueryToken;

  final LikeAuthConfig? authConfig;
  final Duration reconnectInterval;
  final Duration maxReconnectInterval;
  final int? maxReconnectAttempts;
  final Duration pingInterval;
  final String pingPayload;
  final bool pauseWhenBackgrounded;

  WebSocket? _socket;
  bool _isDisposed = false;
  bool _isPaused = false;
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  _WsLifecycleObserver? _lifecycleObserver;
  final Random _random = Random();

  final Lock _lock = Lock();
  final _connectionController = StreamController<bool>.broadcast();

  /// Connection transitions; subscribers never receive tokens or message data.
  Stream<bool> get connectionChanges => _connectionController.stream;

  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();

  LikeWebSocketClient({
    required this.url,
    this.getToken,
    this.authTicketSupplier,
    this.onConnectedAuth,
    this.useQueryToken = true,
    this.authConfig,
    this.reconnectInterval = const Duration(seconds: 5),
    this.maxReconnectInterval = const Duration(seconds: 60),
    this.maxReconnectAttempts,
    this.pingInterval = const Duration(seconds: 30),
    this.pingPayload = '{"type":"ping"}',
    this.pauseWhenBackgrounded = true,
  }) {
    if (pauseWhenBackgrounded) {
      try {
        _lifecycleObserver = _WsLifecycleObserver(_handleAppLifecycle);
        WidgetsBinding.instance.addObserver(_lifecycleObserver!);
      } catch (_) {
        // WidgetsBinding may be uninitialized in pure Dart VM tests.
      }
    }
  }

  void _handleAppLifecycle(AppLifecycleState state) {
    if (_isDisposed) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      pause();
    } else if (state == AppLifecycleState.resumed && _isPaused) {
      resume();
    }
  }

  /// Pauses automatic reconnects while the app/tab is backgrounded.
  void pause() {
    _isPaused = true;
    _reconnectTimer?.cancel();
  }

  /// Resumes reconnects and connects immediately if not already connected.
  void resume() {
    if (_isDisposed) return;
    _isPaused = false;
    _reconnectAttempts = 0;
    if (!isConnected && !_isConnecting) {
      unawaited(connect());
    }
  }

  /// Stream of decoded JSON/string messages received from the server.
  Stream<dynamic> get messages => _messageController.stream;

  /// Returns true if the WebSocket is currently open.
  bool get isConnected =>
      _socket != null && _socket!.readyState == WebSocket.open;

  /// Connects to the WebSocket server sequentially.
  Future<void> connect() async {
    await _lock.synchronized(() async {
      if (_isDisposed || _isPaused || _isConnecting || isConnected) return;
      _isConnecting = true;

      try {
        var connectionUrl = url;
        final tokenSupplier = authConfig?.getToken ??
            getToken ??
            LikeConstants.current.authConfig?.getToken ??
            LikeAuthInterceptor.getToken;

        String? resolvedToken;
        if (authTicketSupplier != null) {
          final ticket = await authTicketSupplier!();
          if (ticket != null && ticket.isNotEmpty) {
            final uri = Uri.parse(url);
            final params = Map<String, dynamic>.from(uri.queryParameters);
            params['ticket'] = ticket;
            connectionUrl = uri.replace(queryParameters: params).toString();
          }
        } else if (tokenSupplier != null) {
          resolvedToken = await tokenSupplier();
          if (useQueryToken && resolvedToken != null && resolvedToken.isNotEmpty) {
            final uri = Uri.parse(url);
            final params = Map<String, dynamic>.from(uri.queryParameters);
            params['token'] = resolvedToken;
            connectionUrl = uri.replace(queryParameters: params).toString();
          }
        }

        final safeUrl = LikeRedaction.endpoint(connectionUrl);
        debugPrint('[LIKE WebSocket] Connecting to $safeUrl...');
        final socket = await WebSocket.connect(connectionUrl);
        _socket = socket;
        _isConnecting = false;
        _reconnectAttempts = 0;

        _onConnected(socket);
        if (onConnectedAuth != null &&
            resolvedToken != null &&
            resolvedToken.isNotEmpty) {
          await onConnectedAuth!(this, resolvedToken);
        }
      } catch (_) {
        _isConnecting = false;
        debugPrint('[LIKE WebSocket] Connection failed.');
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
        final socket = _socket!;
        _socket = null;
        await socket.close();
        _connectionController.add(false);
      }
    });
  }

  void _onConnected(WebSocket socket) {
    debugPrint('[LIKE WebSocket] Connected successfully.');
    _connectionController.add(true);
    _startHeartbeat();

    socket.listen(
      (rawData) {
        _handleIncomingMessage(rawData);
      },
      onError: (err) {
        debugPrint('[LIKE WebSocket] Socket error occurred.');
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
        _connectionController.add(false);
        _scheduleReconnect();
      }
    });
  }

  void _scheduleReconnect() {
    if (_isDisposed || _isPaused) return;
    if (maxReconnectAttempts != null &&
        _reconnectAttempts >= maxReconnectAttempts!) {
      return;
    }
    _reconnectTimer?.cancel();
    final exponent = _reconnectAttempts.clamp(0, 5);
    _reconnectAttempts++;
    final baseMs = reconnectInterval.inMilliseconds * (1 << exponent);
    final cappedMs = min(baseMs, maxReconnectInterval.inMilliseconds);
    final jitterMs = cappedMs > 0 ? _random.nextInt((cappedMs * 0.2).round() + 1) : 0;
    _reconnectTimer = Timer(Duration(milliseconds: cappedMs + jitterMs), () {
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
      if (_lifecycleObserver != null) {
        try {
          WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
        } catch (_) {}
        _lifecycleObserver = null;
      }
      _reconnectTimer?.cancel();
      _pingTimer?.cancel();
      if (_socket != null) {
        final socket = _socket!;
        _socket = null;
        await socket.close();
        _connectionController.add(false);
      }
      await _messageController.close();
      await _connectionController.close();
      debugPrint('[LIKE WebSocket] Disposed client.');
    });
  }
}
