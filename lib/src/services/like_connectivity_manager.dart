import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:like/src/core/like_constants.dart';
import 'package:like/src/models/like_connectivity_check_result.dart';
import 'package:like/src/models/like_connectivity_transition.dart';
import 'package:like/src/services/like_logger.dart';
import 'package:universal_io/io.dart';

/// Injectable connectivity interface check used by tests and embedders.
typedef LikeInterfaceCheck = Future<List<ConnectivityResult>> Function();

/// Injectable internet reachability check.
typedef LikeInternetCheck = Future<bool> Function(
    String host, Duration timeout);

/// Injectable origin reachability check.
typedef LikeServerCheck = Future<bool?> Function(
  String host,
  int port,
  Duration timeout,
);

/// Service that monitors interface, internet, and origin-aware server reachability.
class LikeConnectivityManager {
  static final LikeConnectivityManager _instance =
      LikeConnectivityManager._internal();

  factory LikeConnectivityManager() => _instance;

  LikeConnectivityManager._internal();

  final Connectivity _connectivity = Connectivity();
  StreamController<bool> _connectionChangeController =
      StreamController<bool>.broadcast();
  StreamController<LikeConnectivityTransition> _originTransitionController =
      StreamController<LikeConnectivityTransition>.broadcast();
  final ValueNotifier<bool> _isInternetConnectedNotifier = ValueNotifier(true);
  final ValueNotifier<bool> _isServerAvailableNotifier = ValueNotifier(true);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
  bool _isInitialized = false;
  List<ConnectivityResult>? _lastResults;
  String? _serverUrl;
  String? _primaryOrigin;

  Future<_InterfaceResult>? _interfaceFlight;
  final Map<String, Future<bool?>> _serverFlights = {};
  final Map<String, DateTime> _lastAutomaticChecks = {};
  final Map<String, int> _originEpochs = {};
  final Map<String, bool?> _originAvailability = {};

  LikeInterfaceCheck? _interfaceCheckOverride;
  LikeInternetCheck? _internetCheckOverride;
  LikeServerCheck? _serverCheckOverride;
  DateTime Function() _clock = DateTime.now;
  bool? _isWebOverride;

  /// Whether the device has a usable interface and internet reachability.
  bool get isInternetConnected => _isInternetConnectedNotifier.value;

  /// Legacy primary-origin server status.
  bool get isServerAvailable => _isServerAvailableNotifier.value;

  ValueListenable<bool> get isInternetConnectedListenable =>
      _isInternetConnectedNotifier;
  ValueListenable<bool> get isServerAvailableListenable =>
      _isServerAvailableNotifier;

  /// Legacy combined status for the configured primary origin.
  bool get hasConnection => isInternetConnected && isServerAvailable;

  /// Alias for [hasConnection].
  bool get isOnline => hasConnection;

  /// Emits legacy primary-origin combined status changes.
  Stream<bool> get connectionChange => _connectionChangeController.stream;

  /// Alias for [connectionChange].
  Stream<bool> get statusStream => connectionChange;

  /// Emits meaningful reachability transitions independently for each origin.
  ///
  /// Repeated observations of the same value are suppressed. A restoration is
  /// represented only by an event whose previous value is `false` and whose
  /// new value is `true`.
  Stream<LikeConnectivityTransition> get originTransitions =>
      _originTransitionController.stream;

  /// Convenience stream containing exact unavailable-to-available transitions.
  Stream<LikeConnectivityTransition> get originRestorations =>
      originTransitions.where((event) => event.isRestoration);

  /// Returns a canonical `scheme://host:effectivePort` origin.
  static String? canonicalOrigin(String? serverUrl) {
    if (serverUrl == null || serverUrl.trim().isEmpty) return null;
    final uri = Uri.tryParse(serverUrl.trim());
    if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    return '$scheme://$host:$port';
  }

  /// Initializes monitoring and performs an initial check.
  ///
  /// Repeated calls safely update the primary origin without adding duplicate
  /// subscriptions.
  Future<void> init({String? serverUrl}) async {
    if (_connectionChangeController.isClosed) {
      _connectionChangeController = StreamController<bool>.broadcast();
    }
    if (_originTransitionController.isClosed) {
      _originTransitionController =
          StreamController<LikeConnectivityTransition>.broadcast();
    }
    if (serverUrl != null) {
      _serverUrl = serverUrl;
      _primaryOrigin = canonicalOrigin(serverUrl);
    }
    if (!_isInitialized) {
      _isInitialized = true;
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
    }
    await checkConnectivity(serverUrl: _serverUrl, force: true);
  }

  /// Checks interface/internet state and optionally an origin's reachability.
  Future<LikeConnectivityCheckResult> checkConnectivity({
    String? serverUrl,
    bool force = false,
  }) {
    // Manual calls intentionally bypass the automatic-failure cooldown. The
    // force flag remains part of the public API for backward compatibility;
    // equivalent in-flight work is always joined, including forced calls.
    return _checkConnectivity(
      serverUrl: serverUrl ?? _serverUrl,
      reason: LikeConnectivityCheckReason.manual,
      forceNewFlight: force,
    );
  }

  /// Checks connectivity and reachability for [serverUrl].
  Future<LikeConnectivityCheckResult> checkServerReachability(
    String serverUrl, {
    bool force = false,
  }) {
    return _checkConnectivity(
      serverUrl: serverUrl,
      reason: LikeConnectivityCheckReason.manualServer,
      forceNewFlight: force,
    );
  }

  /// Backward-compatible forced check wrapper.
  Future<void> forceCheck() async {
    await checkConnectivity(force: true);
  }

  /// Starts a non-blocking check after an eligible API failure.
  void checkAfterApiFailure(String serverUrl, {bool force = false}) {
    if (!LikeConstants.automaticConnectivityChecksEnabled) return;
    final origin = canonicalOrigin(serverUrl);
    if (origin == null) return;
    final now = _clock();
    final last = _lastAutomaticChecks[origin];
    if (!force &&
        last != null &&
        now.difference(last) < LikeConstants.automaticFailureCheckCooldown) {
      return;
    }
    _lastAutomaticChecks[origin] = now;
    unawaited(
      _runBackgroundCheck(
        serverUrl: serverUrl,
        reason: LikeConnectivityCheckReason.apiFailure,
        forceNewFlight: force,
      ),
    );
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (listEquals(results, _lastResults)) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      Duration(milliseconds: LikeConstants.connDebounceMs),
      () => unawaited(
        _runBackgroundCheck(
          serverUrl: _serverUrl,
          reason: LikeConnectivityCheckReason.connectivityChange,
          knownResults: results,
        ),
      ),
    );
  }

  Future<void> _runBackgroundCheck({
    required String? serverUrl,
    required LikeConnectivityCheckReason reason,
    List<ConnectivityResult>? knownResults,
    bool forceNewFlight = false,
  }) async {
    try {
      await _checkConnectivity(
        serverUrl: serverUrl,
        reason: reason,
        knownResults: knownResults,
        forceNewFlight: forceNewFlight,
      );
    } catch (_) {
      // Background diagnostics must never surface an unhandled asynchronous
      // error or interfere with delivery of the original request failure.
    }
  }

  Future<LikeConnectivityCheckResult> _checkConnectivity({
    required String? serverUrl,
    required LikeConnectivityCheckReason reason,
    List<ConnectivityResult>? knownResults,
    bool forceNewFlight = false,
  }) async {
    final origin = canonicalOrigin(serverUrl);
    final epochAtStart = origin == null ? 0 : (_originEpochs[origin] ?? 0);
    final stopwatch = Stopwatch()..start();
    
    // If the OS just told us the network changed (knownResults != null),
    // we MUST force a new flight to avoid piggybacking on a stale offline check.
    final bool requiresNewFlight = forceNewFlight || knownResults != null;
    
    if (!LikeConstants.silentSyncLogs) {
      LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'connectivity',
        message: '[LIKE Connectivity] Check started ($reason) for $origin | force=$requiresNewFlight',
      );
    }
    
    final interface = await _interfaceAndInternet(
      knownResults: knownResults,
      forceNewFlight: requiresNewFlight,
    );

    bool? serverAvailable;
    if (!interface.hasNetworkInterface) {
      serverAvailable = origin == null ? null : false;
    } else if (origin != null) {
      serverAvailable = await _serverReachability(origin, forceNewFlight: requiresNewFlight);
    }

    stopwatch.stop();
    final timestamp = _clock();
    _applyInternetState(interface.internetReachable);
    if (origin != null && (_originEpochs[origin] ?? 0) == epochAtStart) {
      _applyOriginState(origin, serverAvailable);
    }

    if (!LikeConstants.silentSyncLogs) {
      LikeLogger.log(
        level: LikeLogLevel.info,
        category: 'connectivity',
        message: '[LIKE Connectivity] Check completed in ${stopwatch.elapsedMilliseconds}ms ($reason) -> interface=${interface.hasNetworkInterface}, internet=${interface.internetReachable}, server=$serverAvailable ($origin)',
      );
    }

    return LikeConnectivityCheckResult(
      reason: reason,
      hasNetworkInterface: interface.hasNetworkInterface,
      isInternetReachable: interface.internetReachable,
      isServerAvailable: serverAvailable,
      origin: origin,
      timestamp: timestamp,
    );
  }

  Future<_InterfaceResult> _interfaceAndInternet({
    List<ConnectivityResult>? knownResults,
    bool forceNewFlight = false,
  }) {
    final active = _interfaceFlight;
    if (active != null && !forceNewFlight) return active;
    final future = _runInterfaceAndInternet(knownResults);
    _interfaceFlight = future;
    future.then<void>(
      (_) {
        if (identical(_interfaceFlight, future)) _interfaceFlight = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_interfaceFlight, future)) _interfaceFlight = null;
      },
    );
    return future;
  }

  Future<_InterfaceResult> _runInterfaceAndInternet(
    List<ConnectivityResult>? knownResults,
  ) async {
    final results = knownResults ??
        await (_interfaceCheckOverride?.call() ??
            _connectivity.checkConnectivity());
    _lastResults = results;
    final hasInterface = results.any((r) => r != ConnectivityResult.none);
    if (!hasInterface) return const _InterfaceResult(false, false);
    if (_isWeb) {
      return const _InterfaceResult(true, true);
    }
    final reachable = await (_internetCheckOverride?.call(
          LikeConstants.connCheckHost,
          Duration(seconds: LikeConstants.connTimeout),
        ) ??
        _lookupHost(
          LikeConstants.connCheckHost,
          Duration(seconds: LikeConstants.connTimeout),
        ));
    return _InterfaceResult(true, reachable);
  }

  Future<bool?> _serverReachability(String origin, {bool forceNewFlight = false}) {
    final active = _serverFlights[origin];
    if (active != null && !forceNewFlight) return active;
    final future = _runServerReachability(origin);
    _serverFlights[origin] = future;
    future.then<void>(
      (_) {
        if (identical(_serverFlights[origin], future)) {
          _serverFlights.remove(origin);
        }
      },
      onError: (Object _, StackTrace __) {
        if (identical(_serverFlights[origin], future)) {
          _serverFlights.remove(origin);
        }
      },
    );
    return future;
  }

  Future<bool?> _runServerReachability(String origin) async {
    if (_isWeb) return null;
    final uri = Uri.parse(origin);
    if (_serverCheckOverride != null) {
      return _serverCheckOverride!(
        uri.host,
        uri.port,
        Duration(seconds: LikeConstants.connTimeout),
      );
    }
    
    // HTTP/HTTPS origins should be probed with an HTTP HEAD request to avoid
    // leaving raw TCP sockets open on HTTP servers (like Shelf).
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      try {
        final client = HttpClient()
          ..connectionTimeout = Duration(seconds: LikeConstants.connTimeout);
        final request = await client.openUrl('HEAD', uri);
        request.followRedirects = false;
        final response = await request.close();
        client.close(force: true);
        return response.statusCode < 500 || response.statusCode == 503;
      } catch (_) {
        // Fall back to TCP socket if HTTP HEAD fails unexpectedly
        return _connectSocket(
          uri.host,
          uri.port,
          Duration(seconds: LikeConstants.connTimeout),
        );
      }
    }

    return _connectSocket(
      uri.host,
      uri.port,
      Duration(seconds: LikeConstants.connTimeout),
    );
  }

  bool get _isWeb => _isWebOverride ?? kIsWeb;

  static Future<bool> _lookupHost(String host, Duration timeout) async {
    if (host.isEmpty) return false;
    try {
      final result = await InternetAddress.lookup(host).timeout(timeout);
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool?> _connectSocket(
    String host,
    int port,
    Duration timeout,
  ) async {
    try {
      final socket = await Socket.connect(host, port, timeout: timeout);
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _applyInternetState(bool available) {
    final previous = hasConnection;
    _isInternetConnectedNotifier.value = available;
    _emitIfChanged(previous);
  }

  void _applyOriginState(String origin, bool? available) {
    final previousAvailability = _originAvailability[origin];
    _originAvailability[origin] = available;
    if (previousAvailability != available &&
        !_originTransitionController.isClosed) {
      _originTransitionController.add(
        LikeConnectivityTransition(
          origin: origin,
          previousAvailability: previousAvailability,
          availability: available,
          timestamp: _clock(),
        ),
      );
    }
    if (origin != _primaryOrigin || available == null) return;
    final previous = hasConnection;
    _isServerAvailableNotifier.value = available;
    _emitIfChanged(previous);
  }

  void _emitIfChanged(bool previous) {
    if (previous != hasConnection && !_connectionChangeController.isClosed) {
      _connectionChangeController.add(hasConnection);
    }
  }

  /// Records an actual HTTP response as newer success evidence for its origin.
  void markServerAvailable({String? serverUrl}) {
    final origin = canonicalOrigin(serverUrl ?? _serverUrl);
    if (origin == null) return;
    _originEpochs[origin] = (_originEpochs[origin] ?? 0) + 1;
    _applyOriginState(origin, true);
  }

  /// Legacy explicit mutation, scoped to [serverUrl] or the primary origin.
  void markServerUnavailable({String? serverUrl}) {
    final origin = canonicalOrigin(serverUrl ?? _serverUrl);
    if (origin == null) return;
    _originEpochs[origin] = (_originEpochs[origin] ?? 0) + 1;
    _applyOriginState(origin, false);
  }

  /// Returns the last known reachability for [serverUrl].
  bool? serverAvailabilityFor(String serverUrl) =>
      _originAvailability[canonicalOrigin(serverUrl)];

  /// Returns whether network evidence permits contacting [serverUrl].
  ///
  /// Unknown origin reachability is allowed by default, which preserves web's
  /// browser-safe unknown-server semantics. Set [allowUnknown] to `false` when
  /// a caller requires explicit positive origin evidence.
  bool isOriginAvailable(String serverUrl, {bool allowUnknown = true}) {
    if (!isInternetConnected) return false;
    final availability = serverAvailabilityFor(serverUrl);
    return availability ?? allowUnknown;
  }

  /// Manual override retained for existing tests and diagnostics.
  void debugSetStatus({bool? internet, bool? server}) {
    if (internet != null) _isInternetConnectedNotifier.value = internet;
    if (server != null) _isServerAvailableNotifier.value = server;
  }

  /// Installs deterministic platform and probe seams for tests.
  @visibleForTesting
  void debugConfigure({
    LikeInterfaceCheck? interfaceCheck,
    LikeInternetCheck? internetCheck,
    LikeServerCheck? serverCheck,
    DateTime Function()? clock,
    bool? isWeb,
  }) {
    _interfaceCheckOverride = interfaceCheck;
    _internetCheckOverride = internetCheck;
    _serverCheckOverride = serverCheck;
    if (clock != null) _clock = clock;
    _isWebOverride = isWeb;
  }

  /// Resets subscriptions, flights, state, and test seams without closing the
  /// singleton permanently.
  @visibleForTesting
  Future<void> reset() async {
    _debounceTimer?.cancel();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _isInitialized = false;
    _lastResults = null;
    _serverUrl = null;
    _primaryOrigin = null;
    _interfaceFlight = null;
    _serverFlights.clear();
    _lastAutomaticChecks.clear();
    _originEpochs.clear();
    _originAvailability.clear();
    _interfaceCheckOverride = null;
    _internetCheckOverride = null;
    _serverCheckOverride = null;
    _clock = DateTime.now;
    _isWebOverride = null;
    _isInternetConnectedNotifier.value = true;
    _isServerAvailableNotifier.value = true;
    if (_connectionChangeController.isClosed) {
      _connectionChangeController = StreamController<bool>.broadcast();
    }
    if (_originTransitionController.isClosed) {
      _originTransitionController =
          StreamController<LikeConnectivityTransition>.broadcast();
    }
  }

  /// Stops monitoring. A later [init] remains safe.
  void dispose() {
    _debounceTimer?.cancel();
    unawaited(_connectivitySubscription?.cancel());
    _connectivitySubscription = null;
    _isInitialized = false;
    if (!_connectionChangeController.isClosed) {
      unawaited(_connectionChangeController.close());
    }
    if (!_originTransitionController.isClosed) {
      unawaited(_originTransitionController.close());
    }
  }
}

class _InterfaceResult {
  final bool hasNetworkInterface;
  final bool internetReachable;

  const _InterfaceResult(this.hasNetworkInterface, this.internetReachable);
}
