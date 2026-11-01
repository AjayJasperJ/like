# Connectivity & toast hooks

## Connectivity is more than a Wi-Fi icon

An interface can exist while the Internet or a particular API is unreachable.
`LikeConnectivityManager` tracks interface/internet/origin evidence. Call
`client.checkServerReachability(force: true)` for an explicit client-origin check.
An HTTP response, including a 4xx/5xx response, establishes server reachability.

Automatic no-response diagnostics do not turn cancelled, cached, queued or local
mapping failures into outage claims. Browser failures can be ambiguous because of
CORS and browser security; server availability can remain unknown.

## Configure notifications

Initialize the engine with the following configuration; functions here are your
application's toast/progress handlers:

```dart
import 'package:like/like.dart';

final config = LikeConfig(
  projectName: 'my_app',
  baseUrl: 'https://dummyjson.com',
  toastConfig: LikeToastConfig(
    connected: (message) => showAppToast(message),
    disconnected: (message) => showAppToast(message),
    slowInternet: (message) => showAppToast(message),
    resync: (message, progress) => showSyncProgress(message, progress),
    actionQueued: (message) => showAppToast(message),
    cacheUse: (message) => showAppToast(message),
    swrUse: (message) => showAppToast(message),
  ),
);
```

Wrap the application in `Like` for the root's connectivity/slow-quality listeners.
A custom event callback replaces default feedback. When wrapping MaterialApp,
use a callback connected to your app messenger key/toast service. The built-in
slow warning needs a ScaffoldMessenger ancestor; without it or a callback it is
silent rather than throwing.

## Slow-internet trigger

The shared passive monitor records real HTTP attempts. Defaults require two
consecutive slow samples per origin. A sample is slow if it takes at least two
seconds, times out, or a sufficiently large response averages below 32 KiB/s.
Cached responses and cancellations do not count.

The root fires `slowInternet('Slow Internet Connection')` once when an origin
enters slow quality. More slow samples are suppressed. A normal sample rearms
that origin, so a later slow episode can notify again. Origins are independent.
The listener is cancelled when the root is disposed.

Set `Like(showSlowInternetToasts: false, child: app)` to disable just this feedback.
Measurements still run. `showConnectivityToasts` controls connectivity feedback
separately. No speed-test download is started: server latency is included, so this
is an API-path quality hint, not calibrated Internet bandwidth.

For custom thresholds inject `LikeNetworkQualityMonitor` into a custom
`LikeNetworkQualityInterceptor`. Custom monitors are caller-owned and do not feed
the root's shared-monitor hook. See [Privacy & platform behavior](privacy/).
