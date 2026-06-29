import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';
import 'package:like/src/models/like_state_response.dart';
import 'package:like/src/models/like_error.dart';
import 'package:like/src/services/like_toast_delegate.dart';
import 'package:like/src/services/like_toast_manager.dart';

class FakeLikeToastDelegate implements LikeToastDelegate {
  bool connectivityCalled = false;
  bool? isOnlineVal;
  bool responseCalled = false;
  LikeStateResponse? responseVal;
  bool toastCalled = false;
  String? toastMessage;
  bool customCalled = false;
  Widget? customChild;
  bool loadingCalled = false;
  String? loadingTitle;
  bool syncCalled = false;
  double? syncProgress;
  bool dismissCalled = false;

  @override
  void showConnectivityToast(BuildContext context, bool isOnline) {
    connectivityCalled = true;
    isOnlineVal = isOnline;
  }

  @override
  void showResponseToast(
      BuildContext context, LikeStateResponse<dynamic> response) {
    responseCalled = true;
    responseVal = response;
  }

  @override
  void showToast(
    BuildContext context, {
    required String message,
    String? submessage,
    required ToastificationType type,
    Duration? autoCloseDuration,
  }) {
    toastCalled = true;
    toastMessage = message;
  }

  @override
  void showCustomToast(
    BuildContext context, {
    required Widget child,
    LikeToastAnimation animationType = LikeToastAnimation.slide,
    LikeToastAnimation? exitAnimationType,
    DismissDirection dismissDirection = DismissDirection.horizontal,
    Duration? autoCloseDuration = const Duration(seconds: 3),
    bool isDismissible = true,
    Alignment alignment = Alignment.topCenter,
    EdgeInsetsGeometry? margin,
    VoidCallback? onTap,
    Duration entryDuration = const Duration(milliseconds: 600),
    Duration? exitDuration,
    Offset? slideInOffset,
    Offset? slideOutOffset,
  }) {
    customCalled = true;
    customChild = child;
    if (onTap != null) {
      onTap();
    }
  }

  @override
  void showLoadingToast(
    BuildContext context, {
    required String title,
    String? message,
  }) {
    loadingCalled = true;
    loadingTitle = title;
  }

  @override
  void showSyncProgressToast(
    BuildContext context, {
    required String title,
    required String message,
    required double progress,
  }) {
    syncCalled = true;
    syncProgress = progress;
  }

  @override
  void dismiss(BuildContext context, {bool showRemoveAnimation = false}) {
    dismissCalled = true;
  }
}

void main() {
  group('LikeToastManager - Delegation', () {
    late FakeLikeToastDelegate fakeDelegate;

    setUp(() {
      fakeDelegate = FakeLikeToastDelegate();
      LikeToastManager.setDelegate(fakeDelegate);
      LikeToastManager.onlineWidget = null;
      LikeToastManager.offlineWidget = null;
      LikeToastManager.onOnline = null;
      LikeToastManager.onOffline = null;
    });

    testWidgets('showConnectivityToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showConnectivityToast(true);
      expect(fakeDelegate.connectivityCalled, isTrue);
      expect(fakeDelegate.isOnlineVal, isTrue);
    });

    testWidgets('showResponseToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      final response = LikeStateResponse.success('data');
      LikeToastManager.showResponseToast(response);
      expect(fakeDelegate.responseCalled, isTrue);
      expect(fakeDelegate.responseVal, equals(response));
    });

    testWidgets('showToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showToast(
          message: 'Hello', type: ToastificationType.info);
      expect(fakeDelegate.toastCalled, isTrue);
      expect(fakeDelegate.toastMessage, equals('Hello'));
    });

    testWidgets('showCustomToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      bool tapped = false;
      LikeToastManager.showCustomToast(
        child: const Text('Custom'),
        onTap: () => tapped = true,
      );
      expect(fakeDelegate.customCalled, isTrue);
      expect(fakeDelegate.customChild, isA<Text>());
      expect(tapped, isTrue);
    });

    testWidgets('showLoadingToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showLoadingToast(title: 'Loading');
      expect(fakeDelegate.loadingCalled, isTrue);
      expect(fakeDelegate.loadingTitle, equals('Loading'));
    });

    testWidgets('showSyncProgressToast delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showSyncProgressToast(
          title: 'Sync', message: 'Syncing', progress: 0.5);
      expect(fakeDelegate.syncCalled, isTrue);
      expect(fakeDelegate.syncProgress, equals(0.5));
    });

    testWidgets('dismiss delegates correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.dismiss();
      expect(fakeDelegate.dismissCalled, isTrue);
    });

    testWidgets('registerContext registers context and uses it',
        (tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      LikeToastManager.registerContext(capturedContext);
      // Use a new delegate that does not use navigatorKey but relies on _context
      LikeToastManager.showConnectivityToast(false, context: null);
      expect(fakeDelegate.connectivityCalled, isTrue);
      expect(fakeDelegate.isOnlineVal, isFalse);
    });

    testWidgets('LikeConnectivityActions triggers actions correctly',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // 1. Without overrides
      LikeToast.online();
      expect(fakeDelegate.connectivityCalled, isTrue);
      expect(fakeDelegate.isOnlineVal, isTrue);

      fakeDelegate.connectivityCalled = false;
      LikeToast.offline();
      expect(fakeDelegate.connectivityCalled, isTrue);
      expect(fakeDelegate.isOnlineVal, isFalse);

      // 2. With overrides
      bool onOnlineCalled = false;
      bool onOfflineCalled = false;
      LikeToastManager.onOnline = () => onOnlineCalled = true;
      LikeToastManager.onOffline = () => onOfflineCalled = true;

      fakeDelegate.connectivityCalled = false;
      LikeToast.online();
      expect(onOnlineCalled, isTrue);
      expect(fakeDelegate.connectivityCalled, isFalse);

      LikeToast.offline();
      expect(onOfflineCalled, isTrue);
      expect(fakeDelegate.connectivityCalled, isFalse);
    });
  });

  group('DefaultLikeToastDelegate - UI Tests', () {
    late DefaultLikeToastDelegate delegate;

    setUp(() {
      delegate = DefaultLikeToastDelegate();
      LikeToastManager.setDelegate(delegate);
      LikeToastManager.onlineWidget = null;
      LikeToastManager.offlineWidget = null;
    });

    testWidgets('showConnectivityToast uses standard toast without overrides',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showConnectivityToast(true);
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Back Online'), findsOneWidget);
      expect(find.text('Internet connection restored.'), findsOneWidget);

      LikeToastManager.showConnectivityToast(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('No Connection'), findsOneWidget);
      expect(find.text('Please check your network.'), findsOneWidget);
    });

    testWidgets(
        'showConnectivityToast uses custom online/offline widgets when set',
        (tester) async {
      LikeToastManager.onlineWidget = const Text('Custom Online Widget');
      LikeToastManager.offlineWidget = const Text('Custom Offline Widget');

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showConnectivityToast(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Custom Online Widget'), findsOneWidget);

      LikeToastManager.showConnectivityToast(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Custom Offline Widget'), findsOneWidget);
    });

    testWidgets('showResponseToast displays correct statuses', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // Idle response should do nothing
      LikeToastManager.showResponseToast(LikeStateResponse.idle());
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      // Success response
      LikeToastManager.showResponseToast(
          LikeStateResponse.success('Good', message: 'Success Message'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Success Message'), findsOneWidget);

      // Warning/Error response
      LikeToastManager.showResponseToast(LikeStateResponse.error(
          LikeError(message: 'Error Message', type: LikeApiErrorType.server)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Error Message'), findsOneWidget);
    });

    testWidgets('showLoadingToast displays progress bar and title',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showLoadingToast(
          title: 'Syncing details', message: 'Please wait');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Syncing details'), findsOneWidget);
      expect(find.text('Please wait'), findsOneWidget);
    });

    testWidgets('showSyncProgressToast builds custom UI and custom builder',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // 1. Default progress UI
      LikeToastManager.showSyncProgressToast(
          title: 'Sync', message: 'Downloading files', progress: 0.75);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Downloading files'), findsOneWidget);
      expect(find.text('75%'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 2. Custom builder progress UI
      final customDelegate = DefaultLikeToastDelegate(
        syncProgressBuilder: (title, message, progress) =>
            Text('Custom Progress: $progress'),
      );
      LikeToastManager.setDelegate(customDelegate);

      LikeToastManager.showSyncProgressToast(
          title: 'Sync', message: 'Downloading files', progress: 0.9);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Custom Progress: 0.9'), findsOneWidget);
    });

    testWidgets(
        'showCustomToast supports different animations, dismiss, and mouse actions',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // Test FadeAnimation
      LikeToastManager.showCustomToast(
        child: const Text('Fade Toast'),
        animationType: LikeToastAnimation.fade,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Fade Toast'), findsOneWidget);
      expect(find.byType(FadeTransition), findsWidgets);

      // Test ScaleAnimation
      LikeToastManager.showCustomToast(
        child: const Text('Scale Toast'),
        animationType: LikeToastAnimation.scale,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Scale Toast'), findsOneWidget);
      expect(find.byType(ScaleTransition), findsWidgets);

      // Test SlideAnimation with offsets
      LikeToastManager.showCustomToast(
        child: const Text('Slide Toast'),
        animationType: LikeToastAnimation.slide,
        slideInOffset: const Offset(1, 0),
        slideOutOffset: const Offset(0, 1),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Slide Toast'), findsOneWidget);
      expect(find.byType(SlideTransition), findsWidgets);

      // Dismiss gesture check
      await tester.drag(find.text('Slide Toast'), const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(find.text('Slide Toast'), findsNothing);
    });

    testWidgets('dismiss removes current toast with or without animation',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: LikeToastManager.navigatorKey,
          builder: (context, child) =>
              ToastificationWrapper(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      LikeToastManager.showToast(
          message: 'Toast to remove', type: ToastificationType.success);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Toast to remove'), findsOneWidget);

      LikeToastManager.dismiss(showRemoveAnimation: true);
      await tester.pumpAndSettle();
      expect(find.text('Toast to remove'), findsNothing);
    });
  });
}
