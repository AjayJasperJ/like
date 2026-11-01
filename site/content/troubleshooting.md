# Troubleshooting

## Initialization or storage fails

Call `WidgetsFlutterBinding.ensureInitialized()` and await `LikeService.init`
before using the real singleton. Keep a stable `projectName`. Tests with injected
fakes do not need to initialize the full engine. Do not delete arbitrary app/temp
directories to fix a storage error; target owned stores and migrations.

## Protected request has no token

Configure `LikeAuthConfig` at the correct client boundary and pass `withAuth: true`.
Confirm the token supplier returns current credentials. Do not log raw tokens to
diagnose this. Set/reset `LikeSessionScope` consistently after login/logout.

## Cache does not return data offline

Fallback is not enabled by default. Check `cacheOnOffline`, freshness, `ARS`,
request flags, origin and account scope. Protected anonymous calls intentionally
do not persist. An ETag is not a cached response body.

## Mutation is queued or blocked

Inspect queue state and ownership. A queued action is not successful server
completion. Another account's or legacy ownerless action must not auto-replay.
Check durable payload availability, attempt bounds and server idempotency support.

## Slow toast is missing

The default needs two consecutive slow requests to the same origin; cached data
and cancelled work do not count. Mount `Like`, keep `showSlowInternetToasts` true
and provide `LikeToastConfig.slowInternet`. If using the default snackbar, place
`Like` beneath a ScaffoldMessenger. An injected custom monitor does not feed the
shared root hook. A single slow sample reports unknown.

## Browser requests fail while native works

Check HTTPS/mixed-content policy and API CORS headers/preflight/exposed headers.
Browser no-response errors do not establish global Internet loss. Native file
paths and raw socket/DNS diagnostics are not available in web builds. A package
cannot bypass browser security or certificate rules.

## Riverpod throws during disposal

Capture resources before `ref.onDispose`; close the captured query/client rather
than looking up dependencies through a disposed ref. Dispose only what you own.

## Documentation page or version looks stale

Check `manifest.json` and the source commit footer. Merge the documentation PR,
then check the Documentation site deployment. Before first deployment, enable
GitHub Pages with the **GitHub Actions** source in repository settings. A successful
build artifact does not imply a published URL. The `llms-full.txt` file always
comes from the same build's guide sources.
