import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/like.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = LikeConnectivityManager();

  setUp(() async {
    LikeConstants.reset();
    await manager.reset();
  });

  tearDown(() async {
    LikeConstants.reset();
    await manager.reset();
  });

  test('is a singleton', () {
    expect(identical(manager, LikeConnectivityManager()), isTrue);
  });

  test('manual check returns structured canonical origin result', () async {
    final now = DateTime.utc(2026, 1, 2, 3, 4, 5);
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (host, port, _) async {
        expect(host, 'example.com');
        expect(port, 443);
        return true;
      },
      clock: () => now,
      isWeb: false,
    );

    final result = await manager.checkConnectivity(
      serverUrl: 'HTTPS://User:pass@Example.COM/path?q=1#fragment',
      force: true,
    );

    expect(result.reason, LikeConnectivityCheckReason.manual);
    expect(result.hasNetworkInterface, isTrue);
    expect(result.isInternetReachable, isTrue);
    expect(result.isServerAvailable, isTrue);
    expect(result.origin, 'https://example.com:443');
    expect(result.timestamp, now);
    expect(result.hasConnection, isTrue);
    expect(result.isOnline, isTrue);
  });

  test('force starts fresh interface and server probe flights', () async {
    final interfaceCompleter = Completer<List<ConnectivityResult>>();
    final serverCompleter = Completer<bool?>();
    var interfaceCalls = 0;
    var serverCalls = 0;
    manager.debugConfigure(
      interfaceCheck: () {
        interfaceCalls++;
        return interfaceCompleter.future;
      },
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) {
        serverCalls++;
        return serverCompleter.future;
      },
      isWeb: false,
    );

    final first = manager.checkConnectivity(serverUrl: 'https://example.com');
    final second = manager.checkConnectivity(
      serverUrl: 'https://EXAMPLE.com:443/other',
      force: true,
    );
    expect(interfaceCalls, 2);

    interfaceCompleter.complete(<ConnectivityResult>[ConnectivityResult.wifi]);
    await Future<void>.delayed(Duration.zero);
    expect(serverCalls, 2);

    serverCompleter.complete(true);
    final results = await Future.wait(<Future<LikeConnectivityCheckResult>>[
      first,
      second,
    ]);
    expect(results.every((result) => result.isServerAvailable == true), isTrue);
  });

  test('automatic checks obey per-origin cooldown', () async {
    var now = DateTime.utc(2026);
    var serverCalls = 0;
    LikeConstants.apply(
      LikeConfig(
        projectName: 'test',
        automaticFailureCheckCooldown: const Duration(seconds: 3),
      ),
    );
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) async {
        serverCalls++;
        return false;
      },
      clock: () => now,
      isWeb: false,
    );

    manager.checkAfterApiFailure('https://one.example/a');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    manager.checkAfterApiFailure('https://one.example/b');
    manager.checkAfterApiFailure('https://two.example/a');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(serverCalls, 2);

    now = now.add(const Duration(seconds: 3));
    manager.checkAfterApiFailure('https://one.example/c');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(serverCalls, 3);
  });

  test('automatic checks can be disabled', () async {
    var interfaceCalls = 0;
    LikeConstants.apply(
      LikeConfig(
        projectName: 'test',
        automaticConnectivityChecksEnabled: false,
      ),
    );
    manager.debugConfigure(
      interfaceCheck: () async {
        interfaceCalls++;
        return <ConnectivityResult>[ConnectivityResult.wifi];
      },
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) async => false,
      isWeb: false,
    );

    manager.checkAfterApiFailure('https://example.com');
    await Future<void>.delayed(Duration.zero);

    expect(interfaceCalls, 0);
  });

  test('background check failures are contained', () async {
    manager.debugConfigure(
      interfaceCheck: () async => throw StateError('plugin unavailable'),
      isWeb: false,
    );

    manager.checkAfterApiFailure('https://example.com');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  });

  test('scoped origin state cannot poison primary server state', () async {
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (host, _, __) async => host == 'primary.example',
      isWeb: false,
    );
    await manager.init(serverUrl: 'https://primary.example');
    expect(manager.isServerAvailable, isTrue);

    final scoped = await manager.checkServerReachability(
      'https://scoped.example/path',
      force: true,
    );
    expect(scoped.isServerAvailable, isFalse);
    expect(manager.serverAvailabilityFor('https://scoped.example'), isFalse);
    expect(manager.isServerAvailable, isTrue);
  });

  test('new HTTP evidence prevents stale failed probe from winning', () async {
    final probe = Completer<bool?>();
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async => true,
      serverCheck: (_, __, ___) => probe.future,
      isWeb: false,
    );

    final check = manager.checkServerReachability('https://example.com');
    await Future<void>.delayed(Duration.zero);
    manager.markServerAvailable(serverUrl: 'https://example.com/response');
    probe.complete(false);
    final result = await check;

    expect(result.isServerAvailable, isFalse);
    expect(manager.serverAvailabilityFor('https://example.com'), isTrue);
  });

  test('web checks avoid DNS and socket and leave server unknown', () async {
    var internetCalls = 0;
    var serverCalls = 0;
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.wifi],
      internetCheck: (_, __) async {
        internetCalls++;
        return false;
      },
      serverCheck: (_, __, ___) async {
        serverCalls++;
        return false;
      },
      isWeb: true,
    );

    final result = await manager.checkConnectivity(
      serverUrl: 'https://example.com',
    );
    expect(result.isInternetReachable, isTrue);
    expect(result.isServerAvailable, isNull);
    expect(internetCalls, 0);
    expect(serverCalls, 0);
  });

  test('origin transitions suppress duplicate observations', () async {
    final transitions = <LikeConnectivityTransition>[];
    final subscription = manager.originTransitions.listen(transitions.add);

    manager.markServerUnavailable(serverUrl: 'HTTPS://EXAMPLE.com/path');
    manager.markServerUnavailable(serverUrl: 'https://example.com:443/other');
    manager.markServerAvailable(serverUrl: 'https://example.com');
    await Future<void>.delayed(Duration.zero);

    expect(transitions, hasLength(2));
    expect(transitions.first.origin, 'https://example.com:443');
    expect(transitions.first.previousAvailability, isNull);
    expect(transitions.first.availability, isFalse);
    expect(transitions.last.previousAvailability, isFalse);
    expect(transitions.last.availability, isTrue);
    await subscription.cancel();
  });

  test('restorations contain only exact false-to-true transitions', () async {
    final restorations = <LikeConnectivityTransition>[];
    final subscription = manager.originRestorations.listen(restorations.add);

    // Unknown-to-available is a transition, but not restoration evidence.
    manager.markServerAvailable(serverUrl: 'https://unknown.example');
    manager.markServerUnavailable(serverUrl: 'https://restored.example/path');
    manager.markServerAvailable(serverUrl: 'https://restored.example/other');
    manager.markServerAvailable(
        serverUrl: 'https://restored.example/duplicate');
    await Future<void>.delayed(Duration.zero);

    expect(restorations, hasLength(1));
    expect(restorations.single.origin, 'https://restored.example:443');
    expect(restorations.single.isRestoration, isTrue);
    await subscription.cancel();
  });

  test('origin availability isolates origins and controls unknown evidence',
      () {
    manager.debugSetStatus(internet: true);
    manager.markServerUnavailable(serverUrl: 'https://offline.example');
    manager.markServerAvailable(serverUrl: 'https://online.example');

    expect(manager.isOriginAvailable('https://offline.example/path'), isFalse);
    expect(manager.isOriginAvailable('https://online.example/path'), isTrue);
    expect(manager.isOriginAvailable('https://unknown.example/path'), isTrue);
    expect(
      manager.isOriginAvailable(
        'https://unknown.example/path',
        allowUnknown: false,
      ),
      isFalse,
    );

    manager.debugSetStatus(internet: false);
    expect(manager.isOriginAvailable('https://online.example/path'), isFalse);
  });

  test('forceCheck remains a backward-compatible wrapper', () async {
    manager.debugConfigure(
      interfaceCheck: () async => <ConnectivityResult>[ConnectivityResult.none],
      isWeb: false,
    );
    await manager.forceCheck();
    expect(manager.isInternetConnected, isFalse);
  });
}
