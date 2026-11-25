# LIKE 2.4.1 Audit

Audit date: 2026-11-25  
Application: Noah Flutter app  
Package inspected: `like 2.4.1`  
Package source: `/home/ajay-jasper/.pub-cache/hosted/pub.dev/like-2.4.1`

This document is a task backlog and verification report. It does not modify the
LIKE package. Findings are classified as **Confirmed**, **Likely**, or **Needs
runtime verification** so fixes can be prioritized accurately.

## Executive summary

### Confirmed blocker

`like 2.4.1` is not WASM-safe with the current Hive backend. The package opens
Hive boxes unconditionally during startup, even when the app passes
`cacheEnabled: false` on web. The current browser evidence shows:

```text
UnimplementedError
BackendManager.open -> Hive.openBox
```

This can prevent the release WASM app from starting and explains the white
screen. The fix belongs in LIKE or in a WASM-compatible storage adapter; changing
only the app's `cacheEnabled` flag is insufficient.

### Confirmed deployment limitation

Skwasm multithreading cannot be enabled from the current plain HTTP LAN URL
(`http://192.168.2.190:8080`). The browser ignores COOP on that untrusted origin,
so Skwasm falls back to single-threaded mode. This is a deployment/performance
limitation, not the WASM startup exception. Use HTTPS with COOP/COEP headers, or
accept single-threaded Skwasm.

## Findings

### LIKE-001 — Hive initialization ignores the cache flag

- **Severity:** Critical
- **Status:** Confirmed
- **Source:** `lib/src/services/like_service.dart:58-72`
- **Evidence:** `LikeService.init()` always calls `Hive.initFlutter()` and opens
  `boxApiCache`, `boxCacheMetadata`, `boxEtags`, and `boxOfflineQueue`.
- **Why it matters:** `cacheEnabled: false` only affects later cache behavior;
  it does not skip storage initialization. Hive's current web/WASM backend throws
  `UnimplementedError` in the app's release WASM build.
- **Task:** Make storage capability-aware. If persistent Hive is unavailable,
  either skip all Hive initialization and use a web-safe adapter, or fail with a
  controlled diagnostic and continue without persistence. `cacheEnabled: false`
  must mean no cache storage is opened.
- **Acceptance test:** `LikeService.init(config: cacheEnabled: false)` succeeds
  in Chrome release WASM and no `Hive.openBox` call occurs.

### LIKE-002 — Startup failure can become a white screen

- **Severity:** High
- **Status:** Confirmed by app behavior; package recovery needs testing
- **Sources:** `like_service.dart:58-98`, app bootstrap, `like_root.dart:82-132`
- **Evidence:** initialization is awaited before the app becomes usable, and the
  Hive exception is unhandled at the browser boundary.
- **Why it matters:** a storage backend failure blocks the first usable frame
  instead of degrading to network-only mode.
- **Task:** Add a non-fatal startup path for optional storage. Surface a compact
  diagnostic in debug builds, preserve network access, and ensure the app still
  renders when cache/offline storage is unavailable.
- **Acceptance test:** corrupt/unavailable storage does not produce a blank app;
  requests still work and the failure is reported once.

### LIKE-003 — `initTimeout` is documented but not enforced around Hive startup

- **Severity:** High
- **Status:** Likely; verify with a delayed/failing backend
- **Source:** `like_config.dart:88-98` documents `initTimeout`; `like_service.dart`
  directly awaits Hive initialization/opening.
- **Why it matters:** a slow storage backend can hold startup indefinitely or
  longer than the configured timeout.
- **Task:** Wrap storage initialization in the configured timeout and distinguish
  timeout from permanent backend incompatibility.
- **Acceptance test:** delayed storage fails over within `initTimeout` and app
  startup continues when storage is optional.

### LIKE-004 — Global initialization is not safely reconfigurable

- **Severity:** Medium
- **Status:** Confirmed by source; behavior needs an integration test
- **Source:** `like_service.dart:18-49`
- **Evidence:** `_initialized` is global. Subsequent `init()` calls apply config
  and reconnect, but do not reopen, migrate, or clear boxes when project name,
  storage capability, cache policy, or environment changes.
- **Why it matters:** tests, logout/login transitions, hot restart scenarios, or
  switching API environments can retain storage created under an earlier config.
- **Task:** Define an explicit lifecycle: idempotent same-config init, controlled
  reconfiguration, and test reset/dispose behavior.
- **Acceptance test:** two different configurations in one process cannot mix
  cache, ETags, or offline queue data.

### LIKE-005 — Offline sync is initialized as a global background service

- **Severity:** Medium
- **Status:** Confirmed by source; impact depends on app configuration
- **Source:** `like_service.dart:80-91`, `services/like_offline_sync_manager.dart`
- **Evidence:** `LikeOfflineSyncManager().init()` is called for every successful
  service initialization. It subscribes to connectivity restoration and may start
  durable sync when a connection exists.
- **Why it matters:** this creates background work at startup and can trigger
  network activity or queue processing even when the current feature does not
  need offline mutations. It also depends on the Hive queue being available.
- **Task:** Gate offline-sync startup on both storage capability and
  `offlineSyncEnabled`; provide an explicit dispose/reset for tests and logout.
- **Acceptance test:** web network-only mode starts with no durable sync listener
  and no Hive queue access.

### LIKE-006 — Route visibility does not detect all IndexedStack changes

- **Severity:** Medium
- **Status:** Likely; reproduce in the app
- **Source:** `mixins/like_visibility_mixin.dart:35-92`
- **Evidence:** route callbacks update `_isVisible`, while
  `isCurrentlyVisible` checks `TickerMode`, render size, and `Offstage`. An
  IndexedStack tab switch does not necessarily produce a route callback or an
  `onVisibilityChanged` callback.
- **Why it matters:** screens kept alive in an IndexedStack can remain logically
  visible to the mixin or fail to receive a visibility transition, causing missed
  refetches or unnecessary refreshes.
- **Task:** Add an explicit tab/visibility signal or a supported visibility
  detector path and document that route observation alone is insufficient for
  IndexedStack.
- **Acceptance test:** switching tabs produces exactly one false/true transition
  for the affected screen and does not refetch inactive screens.

### LIKE-007 — Visibility restoration can trigger duplicate work

- **Severity:** Medium
- **Status:** Likely; reproduce with a bound engine and `onRecover`
- **Source:** `like_visibility_mixin.dart:56-70`, `:82-92`
- **Evidence:** on connectivity restoration, the mixin calls `onRecover()` and
  `triggerFocusRefetch()` for every engine. Becoming visible also triggers
  `triggerFocusRefetch()`.
- **Why it matters:** a screen becoming visible during network restoration can
  issue duplicate requests.
- **Task:** Coalesce recovery and focus-refetch signals by endpoint/state and
  enforce one in-flight refresh per state.
- **Acceptance test:** a restoration plus tab activation produces one request per
  endpoint, not two or more.

### LIKE-008 — Provider pipeline bindings can broaden updates by path

- **Severity:** Medium
- **Status:** Confirmed behavior; impact depends on provider registration
- **Source:** `mixins/like_state_mixin.dart:103-150`
- **Evidence:** pipeline matching first compares cleaned paths and then uses
  non-exact query overlap by default. An event with a subset of matching query
  keys can update multiple registered states.
- **Why it matters:** different feed modes, pages, filters, or circle scopes can
  receive a response intended for another state if their active query maps are
  incomplete.
- **Task:** Require explicit query identity for paginated/feed states, especially
  mode, cursor/page, limit, and circle ID. Use exact matching where replacement
  would be unsafe.
- **Acceptance test:** a response for one feed mode/page never mutates another
  mode/page state.

### LIKE-009 — Pagination identity and cursor semantics need contract tests

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Source:** `models/like_paged_query.dart:40-125`
- **Evidence:** pages are deduplicated by `identity`, while cursor mode is
  inferred from response flags or cursor values. A repeated cursor is stopped,
  but malformed responses and cursor reset behavior are not rejected explicitly.
- **Task:** Add tests for repeated cursors, null/empty cursors, page plus cursor
  responses, duplicate IDs across pages, refresh during load, and stale response
  suppression.
- **Acceptance test:** server order is preserved, duplicate IDs do not move an
  existing item, and stale pages cannot overwrite a refreshed session.

### LIKE-010 — Auth refresh and request replay need race/session tests

- **Severity:** High
- **Status:** Needs runtime verification
- **Source:** `interceptors/like_auth_interceptor.dart:42-78`, `:176-220`,
  `:278-307`
- **Evidence:** refreshes are coalesced by session scope and requests are rejected
  when their session identity is stale. Replay also clones `FormData` and adds
  `isRetry`.
- **Task:** Test concurrent 401s, refresh failure, logout during refresh, session
  change during refresh, cancellation during refresh, and replay of JSON and
  multipart bodies.
- **Acceptance test:** one refresh per session scope; no request from the old
  session is replayed with the new token; no request hangs after refresh failure.

### LIKE-011 — Retry behavior is safe-method-only, but needs API contract checks

- **Severity:** Medium
- **Status:** Confirmed design; needs verification against app expectations
- **Source:** `interceptors/like_retry_interceptor.dart:69-101`
- **Evidence:** transport retries only apply to GET/HEAD/OPTIONS and no HTTP
  response is retried. 429 is handled separately by the auth interceptor.
- **Task:** Confirm every app GET can be safely replayed, verify cancellation of
  backoff timers, and test retry count when another interceptor replays a request.
- **Acceptance test:** no mutation is duplicated; retry stops on cancellation and
  respects the configured maximum.

### LIKE-012 — ETag/304 handling depends on persistent cache availability

- **Severity:** High on WASM, Medium elsewhere
- **Status:** Confirmed dependency; runtime behavior needs testing
- **Sources:** `interceptors/like_etag_interceptor.dart:12-66`,
  `services/like_service.dart:120-183`
- **Evidence:** a 304 response is resolved only if the matching Hive response is
  available. Without that cache, the interceptor forwards the 304 error after
  deleting the ETag.
- **Task:** Disable ETag headers whenever persistent response cache is unavailable,
  or implement a safe 304 fallback that performs an unconditional request.
- **Acceptance test:** cache-disabled/WASM mode never sends an unusable ETag and a
  304 cannot become a user-facing error.

### LIKE-013 — Web image path does not enforce decode-size limits

- **Severity:** Medium
- **Status:** Confirmed by source; impact depends on call sites
- **Source:** `widgets/like_cache_image.dart:98-117`
- **Evidence:** the web path uses `Image.network` and does not pass
  `cacheWidth`/`cacheHeight`; the exposed `memCacheWidth` and `memCacheHeight`
  fields are used only by the native `CachedNetworkImage` path.
- **Why it matters:** large feed/profile images can be decoded at source
  resolution on mobile Safari/Chrome, increasing memory, heat, and jank.
- **Task:** Use bounded web decode dimensions or backend thumbnail URLs for feed,
  avatar, and list contexts. Keep full-resolution loading only for detail views.
- **Acceptance test:** image decode dimensions are bounded for list cards and
  memory/frame timings are measured on mobile Safari.

### LIKE-014 — Full-image loading policy is caller-dependent

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Source:** `widgets/like_cache_image.dart` and app call sites
- **Evidence:** the widget accepts dimensions but does not derive a safe decode
  size from layout constraints. A caller can omit both dimensions and request a
  full-size image.
- **Task:** audit all call sites, require explicit sizing for list contexts, and
  add debug assertions/telemetry for unbounded remote images.

### LIKE-015 — Global singleton managers require explicit test cleanup

- **Severity:** Medium
- **Status:** Confirmed by source; test impact needs verification
- **Sources:** `like_service.dart`, `like_offline_sync_manager.dart`,
  `like_sync_manager.dart`, `like_connectivity_manager.dart`,
  `like_client.dart`
- **Evidence:** multiple singleton managers keep streams, timers, registries, and
  global callbacks. Individual providers dispose their own subscriptions, but
  the global lifecycle is not automatically reset between app/test sessions.
- **Task:** expose a documented test reset or scoped instance lifecycle and verify
  that all timers/subscriptions/controllers are closed.
- **Acceptance test:** repeated test setup/teardown does not retain listeners,
  requests, queued work, or stale auth callbacks.

### LIKE-016 — Builder widgets rebuild their complete subtree on state changes

- **Severity:** Low/Medium
- **Status:** Confirmed design; performance impact needs profiling
- **Sources:** `widgets/like_builder.dart:118-151`,
  `widgets/like_sliver_builder.dart:95-127`
- **Evidence:** each state notification calls `setState` on the builder, rebuilding
  the complete callback result. The package does not provide granular row-level
  rebuilds.
- **Task:** keep builders at the smallest practical scope and use keyed/lazy list
  children in the app. Consider selectors only if profiling proves this is a
  bottleneck.
- **Acceptance test:** state changes for a reaction or footer do not rebuild the
  whole feed unnecessarily.

## WASM and LAN verification matrix

| Scenario | Result | Notes |
|---|---|---|
| `like 2.4.1` package source audit | Passed | 78 Dart files found under package `lib/`; key storage, client, state, visibility, retry, auth, sync, and image files inspected. |
| App release WASM startup on LAN HTTP | Failed | `Hive.openBox` throws `UnimplementedError`; white screen. |
| Skwasm multithreading on LAN HTTP | Not available | Browser ignores COOP on untrusted HTTP origin; falls back to single-threaded mode. |
| Standard Flutter web release build | Not run here | Flutter executable is unavailable in this environment. |
| WASM Flutter build | Not run here | Flutter executable is unavailable in this environment. |
| Flutter analyze/tests | Not run here | Flutter/Dart executables are unavailable in this environment. |
| Mobile Safari frame/memory profiling | Not run here | Requires a connected physical device/browser profile. |

## Recommended fix order

1. Fix `LIKE-001` and `LIKE-002`: make storage optional/capability-aware and
   prevent startup white screens.
2. Fix `LIKE-012`: disable or safely degrade ETag behavior without persistent
   cache.
3. Add `LIKE-003`, `LIKE-004`, and `LIKE-015` lifecycle/timeout tests.
4. Add auth/session and pagination contract tests (`LIKE-009`, `LIKE-010`).
5. Verify IndexedStack visibility and coalesce recovery refreshes (`LIKE-006`,
   `LIKE-007`).
6. Optimize and measure web image decode size (`LIKE-013`, `LIKE-014`).
7. Profile builder rebuild scope before changing architecture (`LIKE-016`).

## Ready-to-paste future task

> Fix the confirmed LIKE 2.4.1 storage/WASM defects without changing app API
> contracts. Make `LikeService.init` capability-aware: `cacheEnabled: false`
> must skip Hive initialization, and unavailable web/WASM storage must degrade to
> network-only mode instead of throwing. Enforce `initTimeout`; make ETag/304
> behavior safe when persistent cache is unavailable; gate offline sync on both
> storage capability and `offlineSyncEnabled`. Add tests for WASM startup,
> storage failure, repeated initialization, ETag cache miss, auth refresh races,
> pagination cursor/stale responses, IndexedStack visibility, and manager
> cleanup. Then audit web image decode sizes and profile mobile Safari. Do not
> modify unrelated app modules.

## Expanded package-wide pass

The package contains 78 Dart library files and 54 Dart test files. The expanded
review covered the public configuration, client factory, client lifecycle,
interceptors, cache and ETag paths, auth/retry paths, offline replay, pagination,
visibility, builders, image loading, WebSocket support, diagnostics, and the
browser-oriented tests.

### LIKE-017 — Client factory still requires the Hive offline queue

- **Severity:** Critical for web/WASM
- **Status:** Confirmed by source
- **Source:** `client/like_client_factory.dart:124-132`
- **Evidence:** when `LikeConstants.offlineSyncEnabled` is true, the factory
  constructs `LikeOfflineSyncInterceptor` with
  `LikeService.boxOfflineQueue`. That getter throws if the box is unavailable.
- **Why it matters:** skipping Hive during web/WASM startup without also gating
  interceptor construction simply moves the crash from initialization to the
  first client creation.
- **Task:** Make offline-sync interceptor registration conditional on a durable
  storage capability, not only the feature flag. If storage is unavailable,
  disable durable replay and keep normal HTTP requests working.
- **Acceptance test:** web/WASM with `cacheEnabled: false` and default
  `offlineSyncEnabled: true` can create a client and perform GET/POST requests
  without accessing `LikeService.boxOfflineQueue`.

### LIKE-018 — `supportWeb` is a presentation flag, not a complete platform gate

- **Severity:** High
- **Status:** Confirmed by source
- **Sources:** `core/like_config.dart:365-375`,
  `widgets/like_cache_image.dart:98-117`, `services/like_service.dart`
- **Evidence:** `supportWeb` changes the image widget path, but does not control
  Hive initialization, the offline queue, ETag storage, or client construction.
  It defaults to `false`.
- **Why it matters:** consumers can reasonably assume `supportWeb: true` enables
  web support, while the networking engine can still fail before rendering.
- **Task:** either rename the flag to reflect its narrow image behavior or make
  it a real platform capability mode with explicit storage and interceptor
  decisions. Prefer automatic platform capability detection plus explicit
  opt-in for persistence.
- **Acceptance test:** enabling web mode consistently affects all storage,
  cache, offline, image, and transport paths.

### LIKE-019 — Package README overstates WASM verification

- **Severity:** High
- **Status:** Confirmed documentation gap
- **Source:** package `README.md` platform support table and workflow claims
- **Evidence:** README states browser storage tests and release web compilation,
  but package tests contain no `wasm`, `skwasm`, or WASM build target. The
  browser test manually initializes Hive and is not evidence that the app's
  release WASM startup path works.
- **Task:** add an actual Flutter WASM build/test job, or explicitly state that
  only standard browser/Dart2JS coverage is supported. Do not advertise WASM
  support until Hive/storage and startup tests pass on the target toolchain.
- **Acceptance test:** CI runs `flutter build web --release --wasm` and a browser
  smoke test that calls `LikeService.init` through the real public API.

### LIKE-020 — Browser test setup bypasses the failing public startup path

- **Severity:** High
- **Status:** Confirmed test coverage gap
- **Source:** `test/portable/browser_http_test.dart:52-66`
- **Evidence:** the browser ETag test calls `LikeConstants.apply`,
  `Hive.initFlutter`, and `Hive.openBox` directly. It does not call
  `LikeService.init` or construct the normal `LikeClientFactory` stack.
- **Why it matters:** the exact failure in the app—package startup opening Hive
  under release WASM—is not exercised by this test.
- **Task:** add a public-API browser smoke test using the same bootstrap sequence
  as consumers, both with persistence enabled and with persistence unavailable.

### LIKE-021 — Durable offline replay is not a web-safe default

- **Severity:** High
- **Status:** Confirmed design problem for unsupported storage
- **Sources:** `core/like_config.dart:430-447`,
  `client/like_client_factory.dart:124-132`,
  `interceptors/like_offline_sync_interceptor.dart`
- **Evidence:** `offlineSyncEnabled` and `backgroundSyncEnabled` default to true,
  while web/WASM storage may be unavailable. The queue is durable Hive state and
  is installed by default when the client is built.
- **Task:** default durable offline replay off when storage capability is absent;
  require an explicit supported adapter for browser persistence. Keep ordinary
  requests available in network-only mode.
- **Acceptance test:** an unsupported browser never silently queues a mutation or
  reports it as queued when it could not persist the body.

### LIKE-022 — Browser image persistence is intentionally non-persistent, but the
  public behavior is not explicit

- **Severity:** Medium
- **Status:** Confirmed behavior/documentation gap
- **Source:** `services/app_cache_manager.dart:25-39, 54-56`
- **Evidence:** web uses `NonStoringObjectProvider`, so image cache entries do not
  persist across sessions. The package still exposes image cache configuration
  such as stale period and maximum cache item count.
- **Task:** document that web image caching is browser-memory/network-cache
  dependent, or provide a supported browser storage implementation. Do not imply
  native disk-cache parity on web.

### LIKE-023 — WebSocket implementation needs explicit browser and security tests

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Source:** `client/like_websocket_client.dart:1-220`
- **Evidence:** auth tokens are appended to the WebSocket URL query string, and
  reconnect/heartbeat timers run independently of app visibility. The source uses
  `universal_io` and has no package-level WASM/Safari test.
- **Risks:** tokens can appear in proxy/server URL logs; background mobile browser
  suspension can cause reconnect loops; `ws://` from an HTTPS page is blocked as
  mixed content.
- **Task:** prefer a browser-compatible auth handshake/header strategy where
  possible, redact/avoid query tokens, pause reconnect while backgrounded, and
  test HTTPS/WSS, Safari suspension, disposal, and repeated reconnects.

### LIKE-024 — Large response parsing can still block or behave differently on web

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Sources:** `client/like_client.dart:750-767`,
  `models/like_api_result.dart:120-137`,
  `client/internal/like_mapper.dart`
- **Evidence:** large JSON/model work uses `compute`. Browser/WASM isolate
  behavior and transfer cost differ from native platforms; the package has a
  configurable threshold but no measured mobile Safari/WASM benchmark in the
  inspected tests.
- **Task:** benchmark parsing on Chrome, Safari, standard web release, and WASM;
  avoid copying huge object graphs unnecessarily and expose a safe threshold.

### LIKE-025 — HTTP error mapping is broad but does not implement recovery policy

- **Severity:** Medium
- **Status:** Confirmed design boundary; needs integration verification
- **Source:** `client/like_error_handler.dart:145-375`
- **Evidence:** 410 and 503 are converted to typed errors, but the error handler
  itself does not renew a session, reset pagination, or retry 503. Those policies
  must be implemented by callers/interceptors.
- **Task:** document ownership of 410 session renewal, 400 cursor reset, and 503
  retry. Add end-to-end tests proving the app does not treat typed conversion as
  recovery.

### LIKE-026 — Offline replay rejects permanent 4xx but needs mutation policy tests

- **Severity:** Medium
- **Status:** Confirmed behavior; needs product verification
- **Source:** `interceptors/like_offline_sync_interceptor.dart:515-558`
- **Evidence:** most 4xx responses become terminal failures, with exceptions for
  408 and 429. A 410, 422, or 409 mutation will not automatically retry.
- **Task:** verify each mutation type's policy for 409/410/422/429 and whether the
  UI must reconcile or roll back an optimistic update after replay failure.

### LIKE-027 — Sensitive WebSocket credentials can leak through URL infrastructure

- **Severity:** High
- **Status:** Confirmed security risk by design
- **Source:** `client/like_websocket_client.dart:65-78`
- **Evidence:** the access token is placed in `queryParameters['token']` before
  `WebSocket.connect`.
- **Task:** replace URL-token auth with a protocol-supported safer mechanism or a
  short-lived one-time ticket. Verify browser history, reverse-proxy logs, error
  telemetry, and reconnect URLs do not retain bearer credentials.

## Coverage conclusions

### What the package tests cover

- Core model/config/error/pagination behavior.
- Native-style client, cache, ETag, retry, auth, offline replay, WebSocket, and
  widget tests.
- A browser HTTP test and browser Hive/ETag test.
- Several lifecycle and race-condition tests.

### What remains unproven

- The real public `LikeService.init` path in release WASM.
- WASM/Skwasm compilation and startup.
- Flutter Web on iOS Safari and Android Chrome with the real app bootstrap.
- Web storage quota exhaustion, blocked IndexedDB, private browsing, and storage
  eviction.
- Network-only mode with Hive unavailable.
- Offline mutation behavior when persistence cannot be opened.
- WebSocket behavior in browser background/suspension and WSS deployments.
- Memory/frame impact of large images and large JSON payloads.
- Cross-origin deployment with actual CORS, COOP/COEP, HTTPS, and API uploads.

## Updated release gate for web support

Do not mark LIKE as web/WASM-supported until all of the following pass:

- `flutter build web --release`.
- `flutter build web --release --wasm`.
- Public bootstrap with persistence enabled on supported browser storage.
- Public bootstrap with persistence disabled/unavailable.
- Client creation when offline sync is enabled but durable storage is absent.
- GET, POST, multipart-bytes upload, auth refresh, 410/503 error handling, and
  cancellation in Chrome and Safari.
- ETag disabled/degraded safely when no persistent response cache exists.
- IndexedStack visibility and recovery request-count tests.
- Mobile browser memory and frame profiling for image-heavy feed screens.
- Documentation and pub.dev platform claims match the tested matrix.

## Additional holes found in the second pass

### LIKE-028 — 401/429 replay can replay mutations without an idempotency contract

- **Severity:** High
- **Status:** Confirmed by control flow; backend semantics need verification
- **Source:** `interceptors/like_auth_interceptor.dart:198-257, 278-307`
- **Evidence:** after a 401 or eligible 429, the interceptor calls `dio.fetch`
  again using the original request. This applies to POST/PUT/PATCH/DELETE as
  well as GET. A request that reached the server but received an ambiguous
  response can be processed twice.
- **Task:** restrict automatic replay to safe methods, or require a stable
  server-supported idempotency key for mutations. Ensure the key survives auth
  and rate-limit replay.
- **Acceptance test:** a mutation receiving 401/429 is never duplicated; with an
  idempotency key, replay produces one server-side operation.

### LIKE-029 — Successful cache writes delay the response path

- **Severity:** Medium
- **Status:** Confirmed by source; quantify on web/native
- **Source:** `interceptors/like_cache_interceptor.dart:10-23`
- **Evidence:** every cacheable successful GET awaits `saveResponseToCache`
  before passing the response to the next interceptor. On IndexedDB or slower
  devices this adds storage latency to the foreground request and may delay UI
  state updates.
- **Task:** measure the tradeoff and consider scheduling cache persistence after
  the response is delivered, with cancellation/error handling and a bounded
  write queue.
- **Acceptance test:** foreground response latency is not dominated by cache
  writes; a failed cache write does not fail a successful network request.

### LIKE-030 — ETag persistence is fire-and-forget

- **Severity:** Low/Medium
- **Status:** Confirmed by source
- **Source:** `interceptors/like_etag_interceptor.dart:24-35`
- **Evidence:** `LikeService.putEtag` returns a `Future`, but `onResponse` does
  not await or catch it. A rapid follow-up request can miss the ETag, and a
  storage failure can become an unobserved asynchronous error.
- **Task:** make persistence explicitly awaited or queued, and handle storage
  errors without affecting the network response.

### LIKE-031 — HTTP cache policy is not automatically safe for every GET

- **Severity:** High
- **Status:** Needs endpoint-level verification
- **Sources:** `client/like_client.dart:535-585`,
  `interceptors/like_cache_interceptor.dart`
- **Evidence:** the generic client can cache GET responses, while endpoint
  privacy and volatility are controlled through request extras/configuration.
  A caller that forgets `disableCache` or a correct session scope can retain
  private or rapidly changing data.
- **Task:** default private/authenticated GETs to a verified session scope and
  require explicit cache opt-in for sensitive or volatile endpoints. Add tests
  for profile, feed, reactions, logout/login, and user switching.

### LIKE-032 — Cache invalidation and in-flight responses can race

- **Severity:** Medium
- **Status:** Likely; reproduce with concurrent mutation + GET
- **Sources:** `services/like_service.dart:15, 217-241`,
  `client/like_request_registry.dart`
- **Evidence:** invalidation marks/deletes persistent entries while in-flight
  requests and L1 entries are managed separately. A response started before an
  invalidation can be promoted back into memory/cache after the mutation.
- **Task:** add generation/version checks around invalidation and response
  promotion, especially for optimistic reactions, follow state, and feeds.
- **Acceptance test:** a stale GET completing after a mutation cannot overwrite
  the authoritative updated state.

### LIKE-033 — `compute` thresholds need browser memory and serialization limits

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Sources:** `client/like_client.dart:750-767`,
  `models/like_api_result.dart:120-137`
- **Evidence:** large payloads are moved through `compute`, which can duplicate
  input/output memory. This is especially relevant to feed pages and image-rich
  JSON on mobile web.
- **Task:** benchmark peak memory, add payload-size telemetry, and avoid parsing
  or mapping entire unbounded responses where pagination is available.

### LIKE-034 — WebSocket reconnect is not lifecycle-aware

- **Severity:** Medium
- **Status:** Confirmed by source; device behavior needs testing
- **Source:** `client/like_websocket_client.dart:167-187`
- **Evidence:** disconnect schedules a timer regardless of app visibility or
  browser lifecycle. Mobile browsers may suspend timers, then reconnect in bursts
  when resumed.
- **Task:** expose pause/resume hooks, add exponential backoff with jitter, cap
  reconnect attempts, and test app background/foreground transitions.

### LIKE-035 — Public API behavior differs when assertions are disabled

- **Severity:** Medium
- **Status:** Confirmed by source; needs release test
- **Source:** `client/like_client.dart:1108-1128`
- **Evidence:** web `filePaths` rejection is an `assert`. Assertions are removed
  in release builds, after which the unsupported path is silently ignored and a
  multipart request may be sent without its file.
- **Task:** replace platform-critical assertions with a runtime error/result.
- **Acceptance test:** release web rejects `filePaths` deterministically and
  instructs callers to use `MultipartBytesFile`.

### LIKE-036 — Browser CORS/opaque network failures are not fully distinguishable

- **Severity:** Medium
- **Status:** Needs runtime verification
- **Source:** `client/like_error_handler.dart:92-123`
- **Evidence:** web unknown errors without a response are broadly classified as
  network errors. Browser CORS, mixed-content, TLS, DNS, and server-unreachable
  conditions can collapse into the same user message.
- **Task:** preserve a machine-readable transport reason where available and
  document that browser security policies can hide the real HTTP status.
  Verify CORS preflight, HTTPS API, LAN HTTP, and mixed-content cases.

### LIKE-037 — Debug logging can still be expensive and expose request metadata

- **Severity:** Medium
- **Status:** Confirmed design; security behavior needs review
- **Sources:** `interceptors/like_logger_interceptor.dart:14-47, 55-130`,
  `services/like_logger.dart:75-170`
- **Evidence:** request/response headers, fields, queries, and payloads are
  assembled before redaction. Redaction is present, but debug logging runs in the
  request interceptor and can serialize large FormData/response objects.
- **Task:** make sensitive logging opt-in, redact before expensive serialization,
  cap payload sizes, and verify authorization, cookies, upload fields, tokens,
  and personally identifying data never reach console/file logs.

### LIKE-038 — Diagnostics retain a process-wide history

- **Severity:** Low/Medium
- **Status:** Confirmed by source
- **Source:** `diagnostics/like_request_trace.dart:63-79`
- **Evidence:** `LikeDiagnostics` retains up to 400 trace objects globally. This is
  bounded, but it survives screen disposal and can retain diagnostic activity for
  the entire process.
- **Task:** make retention configurable, disable it in release by default, and
  clear it on logout/session changes when traces could reveal account activity.

### LIKE-039 — The package has no explicit browser storage failure contract

- **Severity:** High
- **Status:** Confirmed documentation/API gap
- **Evidence:** browser storage tests assume Hive can be initialized and opened;
  no public capability/result describes blocked IndexedDB, private browsing,
  quota exhaustion, or WASM backend failure.
- **Task:** expose storage capability status and a documented network-only mode.
  Applications must be able to show degraded mode without catching an opaque
  `UnimplementedError`.

