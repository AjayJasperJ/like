import 'package:path_provider/path_provider.dart';

/// Returns the temporary directory path on `dart:io` platforms.
Future<String?> getTempDirPath() async => (await getTemporaryDirectory()).path;

/// Returns the application documents directory path on `dart:io` platforms.
Future<String?> getDocsDirPath() async =>
    (await getApplicationDocumentsDirectory()).path;
