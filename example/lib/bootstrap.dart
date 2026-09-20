import 'package:flutter/material.dart';
import 'package:like/like.dart';

import 'app.dart';
import 'urls/api_urls.dart';

/// Bootstraps the application by initializing Flutter bindings, the LIKE engine,
/// and running the main widget tree.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize LikeService engine and Hive storage FIRST
  await LikeService.init(
    config: LikeConfig(
      projectName: 'like_real_app_example',
      baseUrl: ApiUrls.baseUrl,
      supportWeb: true,
      withAuthByDefault: false,
      cacheEnabled: false,
      enableLogging: true,
      compactApiLogs: true,
      receiveTimeout: const Duration(seconds: 10),
      toastConfig: LikeToastConfig(
        connected: (message) {
          debugPrint('CUSTOM CONNECTED HANDLER: $message');
        },
        disconnected: (message) {
          debugPrint('CUSTOM DISCONNECTED HANDLER: $message');
        },
        resync: (message, progress) {
          debugPrint('CUSTOM RESYNC HANDLER: $message ($progress)');
        },
      ),
    ),
  );

  // 2. Launch main application widget tree
  runApp(const LikeServerApp());
}
