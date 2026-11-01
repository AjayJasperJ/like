# Quick start

## Requirements

The current source requires **Flutter 3.44.1 / Dart 3.12 or newer**. The minimum-SDK
workflow checks this separately from current stable. Android needs Internet
permission in its release manifest. Browser APIs must permit your app through CORS.

## Install

For the latest published package:

```sh
flutter pub add like
```

Check the installed version: a repository version does not establish publication.
To use repository changes before publication, pin a reviewed commit rather than a
moving branch:

```yaml
dependencies:
  like:
    git:
      url: https://github.com/AjayJasperJ/like.git
      ref: REPLACE_WITH_REVIEWED_COMMIT_SHA
```

The placeholder above must be replaced. See the source revision in the page footer
or `manifest.json`; do not assume it is the newest commit when reading an older deployment.

## Initialize once

```dart
import 'package:flutter/material.dart';
import 'package:like/like.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LikeService.init(
    config: LikeConfig(
      projectName: 'my_shop',
      baseUrl: 'https://dummyjson.com',
      verifySSL: true,
    ),
  );
  runApp(
    const Like(
      showConnectivityToasts: false,
      showSlowInternetToasts: false,
      child: MaterialApp(home: Scaffold(body: Text('Ready'))),
    ),
  );
}
```

`LikeService.init` opens the engine's storage and initializes network services.
Await it before using the default real client. `Like` is an optional root wrapper
for notification subscriptions and a developer-tool wrapper. Disabling the root's
notifications does not disable request measurements.

## Make a typed request

```dart
import 'package:like/like.dart';

class Product {
  final int id;
  final String title;
  const Product(this.id, this.title);
  factory Product.fromJson(dynamic value) =>
      Product(value['id'] as int, value['title'] as String);
}

Future<LikeApiResult<Product>> loadProduct(CancelToken token) =>
    LikeClient().get('/products/1', cancelToken: token).mapSync(Product.fromJson);
```

Expected failures are returned as `LikeApiResult` values. Inspect `isSuccess`,
`data` and `error`; do not assume a failed result throws. Cancel the token when the
owning screen/query is replaced or disposed.

## Next steps

Move the request behind a [service and repository](architecture/), add your
[state owner](state/), and run one of the [complete examples](examples/).
