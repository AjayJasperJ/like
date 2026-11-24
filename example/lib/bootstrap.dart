import 'package:flutter/material.dart';
import 'package:like/like.dart';
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
      compactApiLogs: false,
      receiveTimeout: AppConstants.requestTimeout,
      toastConfig: LikeToastConfig(
        connected: (message) {},
        disconnected: (message) {},
        resync: (message, progress) {},
        cacheUse: (message) {},
        slowInternet: (message) {},
        actionQueued: (message) {},
        swrUse: (message) {},
      ),
    ),
  );
}
