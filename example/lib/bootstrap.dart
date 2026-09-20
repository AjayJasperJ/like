import 'package:flutter/material.dart';
import 'package:like/like.dart';

import 'app.dart';
import 'core/constants/api_urls.dart';
import 'core/constants/app_constants.dart';

/// Bootstraps the application by initializing Flutter bindings, the LIKE engine,
/// and running the main widget tree.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LikeService.init(
    config: LikeConfig(
      projectName: AppConstants.projectName,
      baseUrl: ApiUrls.baseUrl,
      supportWeb: true,
      withAuthByDefault: false,
      cacheEnabled: false,
      enableLogging: true,
      compactApiLogs: true,
      receiveTimeout: AppConstants.requestTimeout,
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

  runApp(const LikeServerApp());
}
