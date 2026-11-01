# Network quality, diagnostic privacy and platform verification

## Slow API-path detection

LikeClientFactory installs LikeNetworkQualityInterceptor. Subscribe to
LikeNetworkQualityMonitor.shared.stream, or inject a separate monitor into a custom
interceptor/client stack. Use sample.origin, elapsed, quality and the nullable
estimatedBytesPerSecond value. Dispose subscriptions owned by a screen; do not
dispose the shared monitor when a screen closes. An injected monitor is caller-owned.

The default slow threshold is two consecutive requests taking at least two seconds,
or large responses averaging below 32 KiB/s. The first slow sample reports unknown;
a normal sample resets the streak. Thresholds are configurable through an injected
monitor. State is isolated per origin and limited to 100 origins.

Measurements use Stopwatch, work on browser and native targets, and never launch
extra speed-test downloads. Small/missing content lengths have no throughput estimate.
Content-Length might be unavailable under CORS or compression. The rate includes
server latency and is not a calibrated bandwidth measurement. Slow servers, proxies
and authentication delays can affect results. Cached/304 responses, cancellations
and local mapping failures are excluded. Timeouts can contribute slow evidence.

This does not replace connectivity state: a slow API path can still be online.
The feature reports quality; it does not silently change timeouts or replay mutations.

### Slow-internet notification hook

Use the same toast configuration as connectivity and synchronization:

```dart
LikeConfig(
  toastConfig: LikeToastConfig(
    connected: (message) => showAppToast(message),
    disconnected: (message) => showAppToast(message),
    slowInternet: (message) => showAppToast(message),
    resync: (message, progress) => showSyncProgress(message, progress),
  ),
);
```

The `Like` root listens to the shared passive quality monitor. Each origin fires
once on entering slow quality; normal measurements rearm its notification.
A custom `slowInternet` callback replaces the default warning toast. The default
requires `Like` beneath a `ScaffoldMessenger` (for example inside a MaterialApp
Scaffold); when wrapping MaterialApp, supply a callback using your app toast or
messenger key. Without a messenger or callback, no notification is shown. Set
`Like(showSlowInternetToasts: false, child: app)` to disable slow notifications
without disabling measurements or connectivity notifications. Custom monitors
remain caller-owned and do not feed this shared root notification hook.

## Redaction before diagnostic publication

LikeLogger sanitizes diagnostic details before console, file and log-stream output.
Application response objects remain intact. Nested maps/lists and JSON strings are
handled without modifying the source object. Built-in secret/PII keys and configured
sensitiveHeaders are matched without case or punctuation differences.

Safe defaults omit opaque strings and arbitrary object stringification, even in
debug. Release API response/request bodies are omitted. URI query/fragment/userinfo
are removed from API endpoint logs; generic messages also scrub URL queries and
Bearer values. Existing request correlation strings are omitted with other detail
strings under this conservative policy.

This protects the logger's output, not network traffic from an authorized device
owner, arbitrary application logs, crash-reporting SDKs or existing stored log files.
Apps must avoid placing secrets in URL paths or unstructured messages. The raw
LikePipeline is an application data bus, not a sanitized diagnostic stream. DevTool now consumes payload-free LikeDiagnostics traces; log and storage
previews apply redaction before display/copy. Historical unversioned log entries
are excluded by LikeLogger.readLogs; this does not erase old plaintext files. Do not promise that redaction prevents
hacking or secures a compromised device. Use HTTPS and server-side authorization.

## Request identity

Deduplication uses the effective absolute URI, matching L1/L2 keys. ETags use the
same absolute request URI instead of a shared relative path. Old path-based ETags
are ignored and refreshed by new successful requests. LikeSessionScope adds an environment/account hash to protected cache and queue
identities. Switching scopes cancels old work and blocks replay owned by another
account. Explicitly set the scope after login and reset it on logout; unscoped
protected operations do not cache or queue.

## Web support and test coverage

Web filesystem guards no longer depend on supportWeb being enabled. The logger and
image pruning avoid native filesystem operations whenever kIsWeb is true. Hive can
use browser storage; managed image metadata does not persist as native disk storage.
Browser TLS, CORS, exposed headers and storage quotas still apply.

CI runs browser-compatible core/model/widget tests in headless Chrome, plus real
browser HTTP tests against a loopback CORS fixture covering preflight, JSON,
HTTP errors, cancellation, receive timeout and a LIKE request. No external API
or credentials are needed. Browser execution is separate from web compilation.

The native workflow runs VM tests on Linux, macOS and Windows and compiles the
example for Linux/Android, macOS/iOS simulator and Windows. Missing platform
scaffolding is generated only inside CI. SDK/dependency downloads are temporary,
uncached and removed at completion, with a one-hour limit per job.

These are distinct levels of evidence: VM tests are not real-device plugin tests;
native builds are not Android/iOS runtime or simulator interaction tests. Device
integration, additional browsers, web persistence/quota cases and complete platform
parity remain pending until their tests have been implemented and passed.


## Complete public API applications

The Provider, Riverpod and Cubit shops run against DummyJSON without a local
server. A live contract job verifies public catalog/search/details, login,
profile, refresh and simulated checkout. A browser-compatible User-Agent is
needed by the public probe; the initial Python default was rejected with 403.
This live availability check is separate from deterministic fixture-based tests.

Three app host/browser flow jobs and release-mode web/APK builds are included.
Android emulator and iOS simulator jobs execute the same complete UI flow via
integration_test. Read the actual run results before claiming device coverage;
a compiled binary alone is not a device-runtime test.
