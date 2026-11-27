import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:like/testing.dart';

class _ScreenHost extends StatefulWidget {
  final List<String> events;

  const _ScreenHost({required this.events});

  @override
  State<_ScreenHost> createState() => _ScreenHostState();
}

class _ScreenHostState extends State<_ScreenHost>
    with LikeScreenMixin<_ScreenHost> {
  @override
  bool get rebuildOnConnectivityChange => true;

  @override
  void onVisibilityChanged(bool visible) {
    widget.events.add('visible:$visible');
  }

  @override
  void onConnectivityChanged(bool isOnline) {
    widget.events.add('online:$isOnline');
  }

  @override
  Future<void> onConnectivityRestored(
    LikeConnectivityTransition transition,
  ) async {
    widget.events.add('restored:${transition.origin}');
  }

  @override
  Future<void> onRecover() async {
    widget.events.add('recover');
  }

  @override
  void onVisibleRestored(bool restored) {
    widget.events.add('visibleRestored:$restored');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(isOnline ? 'screen-online' : 'screen-offline'),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('second-route')),
              ),
            );
          },
          child: const Text('push'),
        ),
      ],
    );
  }
}

void main() {
  setUp(() async {
    await LikeConnectivityManager().reset();
    LikeConnectivityManager().debugConfigure(
      interfaceCheck: () async => [ConnectivityResult.wifi],
      internetCheck: (host, timeout) async => true,
      serverCheck: (host, port, timeout) async => true,
    );
    await LikeConnectivityManager().init(serverUrl: 'https://api.example.com');
  });

  tearDown(() async {
    await LikeConnectivityManager().reset();
  });

  testWidgets(
    'LikeScreenMixin combines visibility + connectivity and defers recovery until visible',
    (tester) async {
      final events = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [likeRouteObserver],
          home: Scaffold(body: _ScreenHost(events: events)),
        ),
      );
      await tester.pumpAndSettle();
      expect(events, contains('visible:true'));
      expect(events, isNot(contains('visibleRestored:false')));
      expect(events, isNot(contains('visibleRestored:true')));
      expect(find.text('screen-online'), findsOneWidget);

      // Push another route so the screen is covered (invisible).
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      expect(events, contains('visible:false'));

      // Drop & restore connectivity while hidden: recovery should be deferred.
      events.clear();
      LikeConnectivityManager().markServerUnavailable(
        serverUrl: 'https://api.example.com',
      );
      await tester.pumpAndSettle();
      LikeConnectivityManager().markServerAvailable(
        serverUrl: 'https://api.example.com',
      );
      await tester.pumpAndSettle();

      expect(events, containsAllInOrder(['online:false', 'online:true']));
      expect(events, isNot(contains('recover')));
      expect(events, isNot(contains('restored:https://api.example.com:443')));

      // Pop back to the screen: deferred recovery runs onVisibleRestored(true)
      // WITHOUT also firing onVisibilityChanged(true).
      events.clear();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(events, contains('restored:https://api.example.com:443'));
      expect(events, contains('recover'));
      expect(events, contains('visibleRestored:true'));
      expect(events, isNot(contains('visible:true')));

      // Drop & restore connectivity while already visible: runs onVisibleRestored(true)
      // WITHOUT firing onVisibilityChanged(true).
      events.clear();
      LikeConnectivityManager().markServerUnavailable(
        serverUrl: 'https://api.example.com',
      );
      await tester.pumpAndSettle();
      LikeConnectivityManager().markServerAvailable(
        serverUrl: 'https://api.example.com',
      );
      await tester.pumpAndSettle();

      expect(events, contains('visibleRestored:true'));
      expect(events, isNot(contains('visible:true')));
    },
  );
}
