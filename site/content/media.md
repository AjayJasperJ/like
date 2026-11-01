# Uploads, images & WebSockets

## Browser-compatible multipart

`LikeClient.multipart` accepts `fields`, byte files, headers, cancellation and
progress callbacks. `filePaths` is native-only. The current main entry point does
not re-export `MultipartBytesFile`, so import its defining library explicitly:

```dart
import 'dart:typed_data';
import 'package:like/like.dart';
import 'package:like/src/core/like_multipart_file.dart';

Future<LikeApiResult<Response>> upload(Uint8List bytes, CancelToken token) =>
    LikeClient().multipart('/upload',
      fields: {'caption': 'Example'},
      files: [MultipartBytesFile(field: 'file', bytes: bytes, filename: 'photo.jpg')],
      cancelToken: token,
    );
```

That source import is a current API surface limitation; pin/review it across
upgrades. Do not imply every public method parameter type is available through
`like.dart`. Enable durable upload replay only after reviewing [Offline queue](offline/).

## Image cache

`LikeCacheImage` supports URL, dimensions, fit, placeholder and error widgets.
`AppCacheManager` stores downloaded bytes unchanged, tracks access and supports
pruning/clearing. Source defaults are 500 MB maximum, 400 MB target, 5,000 entries
and a 90-day stale period. Platform lifecycle may evict temporary files.

The `_universalImageCache_v2` namespace isolates older formats. This is not
application-wide encrypted storage. Review image URL normalization before using
account-sensitive signed image URLs; URL normalization is not an authorization policy.

## WebSocket lifecycle

```dart
import 'package:like/like.dart';

final socket = LikeWebSocketClient(url: 'wss://your-server.example/ws');
final subscription = socket.messages.listen((message) {
  // Validate and map your server's message contract.
});
await socket.connect();
await socket.send({'type': 'subscribe', 'channel': 'catalog'});
// When the feature closes:
await subscription.cancel();
await socket.dispose();
```

Lifecycle operations are serialized, with reconnect/heartbeat/auth support and
connection changes. Deliberate disconnect must not schedule accidental reconnect.
Structured path/data messages can integrate with the pipeline; validate your
server contract. Browser WebSocket handshake/header restrictions still apply.
