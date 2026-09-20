import 'package:flutter/widgets.dart';
import 'package:like_example/app.dart';

import 'bootstrap.dart';

Future<void> main() async {
  await bootstrap();
  runApp(const LikeServerApp());
}
