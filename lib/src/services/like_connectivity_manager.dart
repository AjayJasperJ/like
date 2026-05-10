import 'dart:async';
import 'package:universal_io/io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_constants.dart';

/// Service to monitor network connectivity and server availability.
/// Matches the exact logic and contract of enterprise's ConnectivityService.
class LikeConnectivityManager {
  static final LikeConnectivityManager _instance =
      LikeConnectivityManager._internal();
  factory LikeConnectivityManager() => _instance;
  LikeConnectivityManager._internal();

  final Connectivity _connectivity = Connectivity();
  final StreamController<bool> _connectionChangeController =
      StreamController<bool>.broadcast();

  final ValueNotifier<bool> _isInternetConnectedNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _isServerAvailableNotifier = ValueNotifier(true);

  /// Whether the device has a valid network interface with internet reachability.
  bool get isInternetConnected => _isInternetConnectedNotifier.value;

  /// Whether the specific API server is reachable via a socket connection.
  bool get isServerAvailable => _isServerAvailableNotifier.value;

  ValueListenable<bool> get isInternetConnectedListenable =>
      _isInternetConnectedNotifier;
  ValueListenable<bool> get isServerAvailableListenable =>
      _isServerAvailableNotifier;

  /// Combined status: returns true if the device is currently online.
  /// We prioritize internet reachability for reconnection events.
  bool get hasConnection => isInternetConnected;

  /// Alias for [hasConnection] to match enterprise resiliency naming.
  bool get isOnline => hasConnection;

  /// A stream that emits the connectivity status whenever it changes.
  Stream<bool> get connectionChange => _connectionChangeController.stream;

  /// Alias for [connectionChange].
  Stream<bool> get statusStream => connectionChange;

  bool _isInitialized = false;
  List<ConnectivityResult>? _lastResults;
  bool _isChecking = false;
  Timer? _debounceTimer;
  String? _serverUrl;

  /// Initializes the connectivity monitoring service.
  ///
  /// [serverUrl] is the base URL of the API to check socket reachability.
  /// If provided, the manager will periodically verify if the server is up.
  Future<void> init({String? serverUrl}) async {
    if (_isInitialized) return;
    _isInitialized = true;
    _serverUrl = serverUrl;

    _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);

    // Initial check
    final results = await _connectivity.checkConnectivity();
    await _performCheck(results);
  }

  /// Forces an immediate manual connectivity and server reachability check.
  Future<void> forceCheck() async {
    final results = await _connectivity.checkConnectivity();
    await _performCheck(results, ignoreResultsCache: true);
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (listEquals(results, _lastResults)) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: LikeConstants.connDebounceMs),
      () => _performCheck(results),
    );
  }

  Future<void> _performCheck(
    List<ConnectivityResult> results, {
    bool ignoreResultsCache = false,
  }) async {
    if (_isChecking) return;
    if (!ignoreResultsCache && listEquals(results, _lastResults)) return;

    _isChecking = true;
    _lastResults = results;

    try {
      final bool previousConnection = hasConnection;
      final bool hasNetworkInterface = results.any(
        (r) => r != ConnectivityResult.none,
      );

      if (hasNetworkInterface) {
        // Run both checks concurrently
        final checks = await Future.wait([
          _lookupHost(LikeConstants.connCheckHost),
          if (_serverUrl != null)
            _checkServerReachability(_serverUrl!)
          else
            Future.value(true),
        ]);

        _isInternetConnectedNotifier.value = checks[0];
        _isServerAvailableNotifier.value = checks[1];
      } else {
        _isInternetConnectedNotifier.value = false;
        _isServerAvailableNotifier.value = false;
      }

      final bool currentConnection = hasConnection;
      _logStatus(currentConnection);

      if (previousConnection != currentConnection) {
        _connectionChangeController.add(currentConnection);
      }
    } finally {
      _isChecking = false;
    }
  }

  static Future<bool> _lookupHost(String host) async {
    if (host.isEmpty) return false;
    try {
      final result = await InternetAddress.lookup(
        host,
      ).timeout(Duration(seconds: LikeConstants.connTimeout));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _checkServerReachability(String url) async {
    try {
      final uri = Uri.parse(url);
      final host = uri.host;
      if (host.isEmpty) return false;

      final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      final socket = await Socket.connect(
        host,
        port,
        timeout: Duration(seconds: LikeConstants.connTimeout),
      );

      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _logStatus(bool status) {
    if (kDebugMode && !LikeConstants.silentConsole) {
      debugPrint(
        'LikeConnectivity: [Internet: ${isInternetConnected ? "ONLINE" : "OFFLINE"}, '
        'Server: ${isServerAvailable ? "ONLINE" : "OFFLINE"}] -> hasConnection: $status',
      );
    }
  }

  /// Manual override for testing purposes.
  void debugSetStatus({bool? internet, bool? server}) {
    if (internet != null) _isInternetConnectedNotifier.value = internet;
    if (server != null) _isServerAvailableNotifier.value = server;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _connectionChangeController.close();
    _isInternetConnectedNotifier.dispose();
    _isServerAvailableNotifier.dispose();
  }
}
