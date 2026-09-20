# Changelog

All notable changes to this project will be documented in this file.

## [2.2.6] - 2026-09-20

### Added
- **Multi-SDK & Multi-Platform Compatibility**: Ensured broad compatibility with Dart SDK `>=3.0.0 <4.0.0` and Flutter `>=3.16.0`.
- **Safe JSON Parsing Extensions & Utilities**: Standardized `JsonParse` static methods (`JsonParse.string`, `JsonParse.integer`, `JsonParse.decimal`, `JsonParse.boolean`, `JsonParse.dateTime`, `JsonParse.map`, `JsonParse.list`) for crash-proof model deserialization.
- **Pagination & Load-More Framework**: Comprehensive support for page-based and cursor-based pagination with `PaginationTool<T>` and `PaginatedNotifierState<T>`.

### Changed
- **Model Layer Standardization**: Standardized `PaginatedPosts`, `ApiPost`, `ApiUser`, and `AuthSession` model factories with robust null-safety defaults.
- **Ignore Rules**: Updated `.gitignore` and `.pubignore` to exclude internal `usage/` and `documents/` directories.

### Fixed
- **UI & Widget Test Suite**: Expanded full test coverage for `LikeBuilder`, `LikeWhen`, `LikeSliverBuilder`, `LikeCacheImage`, and `Like` root configuration widget.

### Fixed
- **Pana Static Analysis**: Added missing `await` on internal request retry inside the `try` block in `LikeAuthInterceptor` (`like_auth_interceptor.dart`).
- **Dependencies**: Removed unused dependencies `dio_smart_retry` and `path`.
- **Dependency Compatibility**: Expanded `cached_network_image` version constraint to `">=3.4.1 <5.0.0"` to support cached_network_image 4.x.
- **Ignore Files**: Updated `.gitignore` and `.pubignore` to exclude `.roomodes`, `example/.agent/`, `coverage/`, and `build/`.

### Improved
- **Example App Architecture & UI**: Refactored `posts_page.dart` into modular stateless widgets (`PostListItem`, `PostErrorView`, `PostPaginationFooter`), extracted auxiliary screens, and updated the theme to modern Material 3 styling.

## [Unreleased]

### Added

- **Origin-Aware Connectivity Diagnostics**: Added structured manual connectivity checks through `LikeConnectivityManager` and each `LikeClient`, reporting interface availability, internet reachability, nullable server availability, canonical origin, reason, timestamp, and legacy-compatible combined online status.
- **Terminal Failure Observation**: Added non-blocking diagnostics after retry exhaustion for ambiguous no-response connection, timeout, and socket-backed failures, with global/per-origin single-flight work, per-origin cooldown, and stale-probe protection.
- **Connectivity Configuration**: Added `automaticConnectivityChecksEnabled` (default `true`) and `automaticFailureCheckCooldown` (default three seconds).

### Changed

- **Breaking — Image Cache Storage**: Removed image-cache encryption and decryption. `AppCacheManager` now stores downloaded bytes unchanged through `flutter_cache_manager`, while retaining URL normalization, access-time updates, LRU pruning, clearing, logging, and web behavior.
- **Image Cache Migration**: Bumped the cache namespace to `_universalImageCache_v2`, isolating legacy cache entries so bytes written in the former format are never served as images. The old temporary namespace is left to normal platform cleanup.
- **Breaking — Configuration/API Removal**: Removed `LikeConfig.encryptionKey`, `AppCacheSecurity`, `EncryptedHttpFileService`, `EncryptedFileServiceResponse`, decrypted temporary-file handling, and `clearDecryptedCache`.
- **Dependencies**: Removed the image-cache-only `encrypt` and `shared_preferences` dependencies. Retained `crypto` because SSL certificate SHA-256 pinning still uses it.
- Every real HTTP response now records positive reachability evidence for its canonical request origin. HTTP errors, cancellation (including take-latest), certificate failures, local transformations, preflight-offline failures, and `OFFLINE_QUEUED` results do not start automatic probes.
- Flutter Web connectivity diagnostics avoid DNS and raw sockets; no-response browser failures do not establish global internet loss, and server availability may remain unknown.

## [2.2.4] - 2026-06-30

### Fixed

- **Static Analysis**: Enclosed single-line if statements in blocks to fix `curly_braces_in_flow_control_structures` lints.
- **Dependency Constraints**: Tightened dependencies to prevent downgrade analysis failure on pub.dev due to missing `transformTimeout` in older `dio` versions.

## [2.2.3] - 2026-06-29

### Fixed

- **Static Analysis & Platform Support**: Fixed a static analysis compilation failure on pub.dev by ensuring `DioExceptionType.transformTimeout` is exhaustively matched in `LikeErrorHandler`.
- **Analyzer Warnings**: Removed unused imports, added missing `const` constructors in models, and stripped `print()` debug diagnostic blocks from toast tests to achieve a perfect 100% clean analyzer score.
- **Dependency Requirements**: Bumped the minimum `dio` dependency constraint to `5.5.0` to guarantee the availability of the `transformTimeout` enum value.

## [2.2.2] - 2026-06-21

### Added

- **Thread-Safe WebSocket Support (`LikeWebSocketClient`)**:
  - Implemented a modern, platform-agnostic WebSocket client for real-time bi-directional streaming.
  - Designed with sequential state-machine logic using `synchronized` locks to prevent race conditions during parallel connect, disconnect, dispose, and send operations.
  - Automatically routes incoming events into the `LikePipeline` for zero-boilerplate, real-time UI synchronization.
  - Supports authorization token retrieval on connection handshake, heartbeats (ping/pong), auto-reconnect with backing-off strategy, and customized event callbacks.
  - Covered with comprehensive integration tests validating connection lifecycle, token parameters, pipeline broadcasts, and concurrent calls.

### Changed

- **Comprehensive `LikeLogger` Testing & Coverage**:
  - Achieved **100% test coverage** for the `LikeLogger` service.
  - Hardened unit tests covering global error handlers (`FlutterError.onError`, `PlatformDispatcher.instance.onError`), log rotation thresholds, compact vs full API log formatting, and file systems fallback paths.

## [2.2.1] - 2026-06-14

### Fixed

- **Silent Request Cancellation — Continuous UI State**: `LikeAutoReconnectMixin.fetcher` no longer surfaces a cancellation as a state regression. When a request is cancelled by a newer `fetch` call (via `newCT`):
  - If prior success data exists, the state is immediately restored to `success(data)` so the UI remains continuous and the user sees no disruption.
  - If no prior data exists (initial load), the state is explicitly set to `loading()` so the spinner persists until the new in-flight request resolves.
  - In both cases the cancelled state is fully absorbed — the new in-flight request owns the final state update.

- **Deduplication Block — Cancel Exception Swallowing New Request**: `LikeClient._execute` deduplication now correctly handles cancelled in-flight entries:
  - Added a pre-check: if the stored in-flight `CancelToken` is already cancelled, deduplication is skipped entirely and the caller proceeds to make a fresh independent network request.
  - Added a cancel-aware catch: if the shared in-flight future resolves with a cancellation while a waiter is awaiting it, the waiter falls through to step 4 (Start Network Request) instead of returning an error — fixing the root cause of "new request missing" after a `newCT` rotation.

- **`ARS` Default — `staleWhileRevalidate` Opt-In**: Changed the default value of `staleWhileRevalidate` from `true` to `false` in both the `LikeARS` constructor and `LikeARS.fromJson`. SWR is now opt-in, consistent with `LikeClient.get()` defaults, preventing unintended stale cache renders on endpoints that require real-time accuracy.

## [2.1.2] - 2026-06-04

### Changed

- **Dynamic Request Header & Timeout Configuration**:
  1. Refactored `Content-Type` header injection to be dynamic: automatically appends `Content-Type` if a request has a body (`data != null`) and no override is present, and cleans it up from the request headers if no body exists.
  1. Configured default `sendTimeout` in `LikeClientFactory` to fallback to `null` under Flutter Web (`kIsWeb`) to prevent web-specific adapter execution issues.

## [2.1.1] - 2026-06-04

### Fixed

- **Options connectTimeout Deprecation and Lower-bound Resolution**:
  - Resolved a compatibility compilation error that occurred during package downgrades due to `connectTimeout` not being defined as a parameter in `Options.copyWith`.
  - Re-routed the request-specific connection timeout via the request `extra` option and dynamically applied it inside `LikeConnectivityInterceptor.onRequest`.

## [2.1.0] - 2026-06-04

### Added

- **Full Flutter Web Platform Support**:
  - Achieved complete platform-agnostic architecture by isolating native `dart:io` compiler imports.
  - Introduced conditional exports (`like_ssl_io.dart` / `like_ssl_stub.dart`) to support certificate pinning/verification safely on native platforms while cleanly stubbing it out on Web.
  - Implemented runtime platform guards (`kIsWeb`) to safely bypass filesystem mutations and avoid multipart file extraction errors in browser environments.
  - Integrated `NonStoringObjectProvider` fallback for the caching layer on Web to bypass native SQLite / filesystem dependencies.
  - Added dynamic `sendTimeout` handling to suppress Dio web adapter errors when dispatching requests without a body.
- **Robust Multi-Category Error Mapping**:
  - Expanded `LikeApiErrorType` enum to include `methodNotAllowed`, `conflict`, `gone`, and `payloadTooLarge` for granular client handling.
  - Configured `LikeErrorHandler.parseResponse` to systematically decode dozens of HTTP status codes (3xx redirections, 4xx client issues, 5xx server issues).
  - Extended `LikeErrorHandler.handle` to intercept low-level Dart network and runtime failures, converting `SocketException`, `TimeoutException`, `HttpException`, `TypeError` (decoding mismatches), and `AssertionError` to unified, user-friendly `LikeError` formats.
- **Thorough Platform Test Harness**:
  - Added rigorous unit tests in `test/client/like_error_handler_test.dart` to verify mapping accuracy, connectivity states, and custom exception handling.

## [2.0.0] - 2026-05-31

### Added

- **Stable Major Milestone Release**: Officially declared the stable, fully-hardened production release of the **Link Intelligent Kernel Engine (LIKE)**.
- **Unified Engine Capabilities**:
  - **Zero-Config Pipeline Synchronization**: Streamlined event-driven state sync updates across viewmodels without boilerplate.
  - **Deduplicated Toast Notification Manager**: Fully contextless, queue-safe toast alerts to protect the UI.
  - **Advanced Offline Resilience**: Automatic request queuing, smart exponential retries (via `dio_smart_retry`), and circuit-breaker failure guards.
  - **Highly Reactive UI Builders**: Integrated `LikeBuilder`, `LikeSliverBuilder`, `LikeWhen`, `LikeSelector`, and `LikeSelectorSliver` for flawless frame-efficient state updates.
  - **Secure Cryptographic Caching**: Multi-tiered cache structure (L1/L2) with automatic AES-CBC 256-bit encryption.
  - **Perfect Code Health**: Zero static analysis warnings, 100% lint compliance, and 100% test coverage with all 87 test assertions passing cleanly.

## [1.2.7] - 2026-05-31

### Added

- **Unified SSL Support in Deserialization**: Added `verifySSL` configuration handling to `LikeARS.fromJson` to guarantee complete serialization/deserialization parity.

### Fixed

- **Toast Notification Duplicate Elimination**: Implemented strict, stateful deduplication inside `DefaultLikeToastDelegate` to prevent duplicate or overlapping toast prompts during concurrent operations (e.g. logouts).
- **Static Lint Warning Purge**: Restructured and backtick-escaped all generic widget and class doc comment headers (such as `LikeBuilder<T>`, `LikeSliverBuilder<T>`, `LikeWhen<T>`) to fully resolve `unintended_html_in_doc_comment` static analysis hints.
- **Unused Import Removal**: Cleaned up the `like_error_handler.dart` package structure by pruning redundant imports.
- **Improved Barrel Exports Naming**: Fixed duplicate export comment labels in the main barrel file `like.dart` for cleaner modularization.

## [1.2.6] - 2026-05-30

### Added

- **`LikeWhen<T>` Pattern-Matching Widget**: Implemented the promised declarative pattern-matching widget for inline `build()` rendering of `LikeStateResponse<T>` states (idle, loading, success, error, exception), fully verified with a comprehensive widget test suite.
- **Enterprise-Grade Network Circuit Breaker**: Introduced consecutive failure detection (`maxConsecutiveFailures = 3`) in `LikeSyncManager` to protect backend servers and client devices during outages. Automatically trips and transitions to offline-mode when thresholds are breached.

### Fixed

- **One-Fetch-Behind State Lag**: Moved provider notification logic out of the asynchronous `finally` blocks in `LikeAutoReconnectMixin` to fire immediately after individual state transitions. Fixed stale data rendering on sequential cached/SWR requests.
- **Systematic Widget Layer Loophole Mitigation**: Resolved 13 critical reactivity and safety issues:
  - Enabled active listener subscriptions in `LikeMultiBuilder` and `LikeMultiSliverBuilder` for full dynamic reactivity.
  - Implemented custom `operator ==` and `hashCode` in `LikeStateResponse` to eliminate recursive notification loops.
  - Upgraded generic cast assertions with detailed debug-mode diagnostics.
  - Integrated standard sliver progress indicators when custom builders are omitted.
  - Added dual-stage `context.mounted` verification (pre- and post-await) to prevent race conditions during widget disposal.
  - Corrected raw package exports in `like.dart` to expose `widgets/like.dart` properly.
- **Null-Payload & Envelope Verification**: Upgraded `DefaultLikeUnpacker` to use explicit key presence checks (`containsKey('data')`) rather than null-coalescing fallbacks. Safely preserves explicitly null payloads and implements priority-based success/failure boolean parsing.
- **Selector Debug Assertions**: Relaxed strict debug-time assertions in `LikeBuilder` and `LikeSliverBuilder` to permit direct `LikeStateResponse` value observation without throwing runtime assertion failures.
- **SWR Refresh Rebuilding**: Enhanced multi-builder sticky data state validation to aggregate `success`, `refreshing`, and `staleWhileRevalidate` states, eliminating loading flashes during background cache updates.
- **Recursive Queue Protection**: Wrapped dynamic queue process triggers in a micro-task throttle (`Future.delayed`) to shield the Flutter call-stack from recursive overflows during prolonged server outages.

## [1.2.5] - 2026-05-24

### Added

- **`LikeSuggestions` Diagnostic Engine**: Introduced a dedicated development-mode developer suggestions engine (`like_suggestions.dart`) that scans request profiles, identifies bad patterns (e.g. janky payloads parsed on UI thread, missing cache keys, redundant rebuilds), and outputs beautiful console advice.
- **Pruning Floor Safeguards**: Added silent cache capacity audits and automatic safety limits to `AppCacheManager` to prevent storage leaks.

### Fixed

- **Toastification Reliability / Release Build Support**: Overhauled `LikeRootWrapper` and `LikeToastManager` to fully resolve instances where toast alerts failed to display in release builds. Secured context lookup routines in `ToastificationWrapper` and mitigated context-loss crashes.
- **Resync Strategy Tuning**: Refined `LikeAutoReconnectMixin` and `LikeClient` query-overlap parsing logic to avoid redundant resync cascades on network recovery.

### Removed

- **Legacy Documentation Bloat**: Pruned unmaintained local wiki markdown files (`api_flow_implementation.md`, `toast_manupulation.md`, `auth_token_manupulation.md`, etc.) from the package root, pointing developers instead to the unified `like_docs` wiki repository to maintain a lightweight package profile (< 1MB).

## [1.2.4] - 2026-05-23

### Changed

- **Synchronized Release**: Bumped version to `1.2.4` to maintain version alignment with `like_devtool`.

## [1.2.2] - 2026-05-22

### Documentation

- **README Restructured — Clean Architecture Flow**: Replaced the "4-Tier" naming with an explicit, named layer breakdown: Reactive UI → Provider → Repository → Service → Cache layers. The architecture diagram now reflects a clean, reader-friendly ASCII flow with clearly labelled cache lanes (L1 RAM · L2 Hive · SWR · ETag/304).
- **Cache Layer Naming Clarified**: Renamed `L3 (SWR)` to **SWR** to avoid implying a third physical store. The four cache strategies are now documented as distinct columns: L1 (in-memory), L2 (Hive disk), SWR (stale-while-revalidate background revalidation), and ETag/304 (HTTP conditional requests).
- **Repository Layer Section Added**: Explicit section showing thin repository call-sites that forward to the service layer and own query-building logic — previously implied but never documented.
- **`LikeWhen<T>` Expanded**: Clarified the widget is intended for inline `build()` use when a `LikeStateResponse<T>` snapshot is already in scope, not as a live listener.
- **`updateNotifier` Fully Documented**: Added complete parameter reference — all five toast-control flags (`disableLoadingToast`, `disableSuccessToast`, `disableErrorToast`, `disableExceptionToast`, `disableCancelledToast`), `enableHaptics`, `messageOverrides`, and all lifecycle callbacks (`onInit`, `onSuccess`, `onError`, `onException`). Includes a state-by-state behaviour table (toast type + haptic weight + callback fired).
- **`likeWhenNotifier` Documented**: Added dedicated section for the raw, side-effect-free state handler — no automatic toasts or haptics. Includes real-world usage patterns (overlay hiding, custom bottom sheets, analytics) and a side-by-side comparison table against `updateNotifier`.
- **Connect & Contribute Section Improved**: Reformatted as a table with pub.dev, Docs/Wiki, Issues tracker, GitHub, LinkedIn, Instagram, and email — all in one scannable block.

## [1.2.1] - 2026-05-22

### Fixed

- **`LikeBuilder` / `LikeSliverBuilder` Sticky Data Leak**: When the state transitioned to `LikeState.loading` (primary loading), both builders checked `_lastSuccessfulData != null` and — if true — bypassed `onLoading` entirely, rendering stale data instead. `_lastSuccessfulData` is now reset to `null` on `LikeState.loading` transitions, and `onLoading` is always rendered when the state is `loading`, regardless of prior data.
- **Incorrect Initial-State Transition in `LikeAutoReconnectMixin.fetcher`**: The orchestration method did not differentiate between a background refresh (`ars.refresh == true`) and a clean/initial load. It now reads the active `LikeNotifierState` via a Zone-bound lookup: if `ars.refresh == true` and current data exists, the state transitions immediately to `LikeStateResponse.refreshing(currentData)`; otherwise it transitions cleanly to `LikeStateResponse.loading()` before the request fires.
- **Inaccurate SWR Cache State Mapping in `LikeApiResult.toStateResponse`**: When `isFromStaleWhileRevalidate == true`, the converter was returning a generic `LikeState.success` response with only a boolean flag, preventing downstream listeners from detecting the `LikeState.staleWhileRevalidate` state. It now returns `LikeStateResponse.staleWhileRevalidate(data, message: 'Serving from cache...')` explicitly.
- **`LikeNotifierState` Reactivity / `.clear()` Not Updating UI**: `LikeNotifierState` now extends `ChangeNotifier` and uses a backing-field getter/setter that calls `notifyListeners()` on every mutation. `LikeBuilder` and `LikeSliverBuilder` subscribe to the observed object as a `Listenable` (if applicable), rebuild on every notification, and cancel the subscription in `dispose()`. Calling `.clear()` now instantly drives the UI to `onIdle`/`onLoading` without requiring an external `notifyListeners()` call.

## [1.2.0] - 2026-05-20

### Added

- **Zero-Config Pipeline Synchronization**: Introduced a `mapper` field on `LikeNotifierState<T>`. When defined, `fetch()` automatically registers the state as a live pipeline listener — any response for the same endpoint+query broadcast on the `LikePipeline` updates the state instantly across all screens, with no extra parameters at the call site.
- **`LikePipelineMixin.bindPipeline`**: New zero-argument declarative method. Reads the `mapper` from the `LikeNotifierState` and registers the binding automatically. No endpoint string or mapper lambda needed at bind time.
- **`LikeAutoReconnectMixin` Pipeline Integration**: `fetch()` now auto-wires a pipeline binding if `state.mapper` is set. Background `autoResync` refresh cycles preserve the binding without re-declaring it.
- **Automatic Path & Query Verification**: Pipeline matching extracts `endpointPath` and `activeQuery` directly from the live HTTP request via `Zone`-based injection in `LikeClient`. Both path (with prefix-matching) and query parameters are verified automatically before dispatching a pipeline update.
- **In-Flight Race Guard**: Pipeline `processAndAssign` is suppressed while a state is actively loading or refreshing (`isLoading || isRefreshing`), preventing concurrent writers from corrupting the state.

### Changed

- **Wide SDK Support**: Lowered minimum Dart SDK constraint to `>=3.0.0 <4.0.0` and Flutter SDK to `>=3.16.0` to support older, existing, and modern projects.
- **Dependency Flexibility**: Widened dependency constraints (such as `dio`, `hive`, `connectivity_plus`, `toastification`, etc.) to use flexible ranges instead of high/pinned versions. This prevents dependency resolution conflicts in client projects.
- **`LikeUiConfig` Extraction Reverted**: `minSplashDuration` and `authRedirectDelay` were removed entirely from `LikeConfig` and `LikeConstants`. A network package has no business knowing what a splash screen is.
- **`LikePipelineMixin` Refactored**: Internal listener management unified into a single `_startPipelineListener()` method. `registerPipelineListener` and `unregisterPipelineListener` no longer restart the stream subscription unnecessarily. When all registrations are removed, the subscription is cancelled and nulled instead of being restarted empty.
- **`AppCacheSecurity` — Complete Encryption Redesign**: Replaced the hardcoded 32-character AES key (`LikeSecureEncryptionCacheKey1234`) and static IV (`LikeSecureIV1234`) with a proper async lifecycle. A fresh cryptographically random 16-byte IV is generated per file and prepended to the ciphertext (`[16-byte IV][AES-CBC ciphertext]`). `AppCacheSecurity.init()` reads `LikeConfig.encryptionKey` (SHA-256 derived to 32 bytes) or generates a per-device key persisted in `SharedPreferences` under `like_cache_encryption_key_v2`. Added `AppCacheSecurity.reset()` (`@visibleForTesting`).
- **`LikeService.init()` — Encryption First**: `AppCacheSecurity.init()` is now called as step `1a`, before Hive storage initialization, guaranteeing the encrypter is ready before any file cache access occurs.
- **`AppCacheManager.getFileStream` Override**: Stream transform now (a) skips files already in the `decrypted/` subdirectory, (b) calls `_updateAccessTime` on every cache hit to reset the stale-period clock, and (c) auto-deletes corrupted or legacy-format files on decryption failure so they are re-downloaded correctly.
- **`AppCacheManager.clearAll` — Structured Error Logging**: Replaced all silent `catch (_) {}` blocks with categorized `LikeLogger` calls (`error`/`warning`, category `'cache_manager'`).
- **`LikeAutoReconnectMixin` — Embedded Pipeline Listener**: `_pipelineSubscription` and `_pipelineBindings` are now managed directly inside `LikeAutoReconnectMixin`, removing the need for a separate `LikePipelineMixin` on providers that already use this mixin.
- **`LikeAutoReconnectMixin.checkQueryOverlap` — `exact` Parameter**: Now accepts `bool exact = false`. When `true`, query maps must be identical in length and value; `false` (default) uses subset/overlap matching.
- **`LikeLogger` — Null-Safe Map Entry Syntax**: Replaced deprecated null-conditional spread (`?key`) with Dart collection-if syntax (`if (key != null) 'key': key`) in `logHttp`, `logRequest`, and `LikeService._writeToDiskCache`.
- **`LikePipeline` — Internal Only**: Removed from the public `like.dart` barrel export; it is an internal broadcast bus.

### Fixed

- **Duplicate Pipeline Bindings**: `_LikePipelineStateBinding` now implements `==` and `hashCode` via an `identity` key. Repeated calls to `bindPipeline` for the same state object replace the prior binding rather than accumulating duplicates that would fire N times per event.
- **`autoResync` Lost Pipeline Binding**: The `refreshAction` closure stored inside `fetch()` previously called `fetch` without forwarding pipeline configuration, causing the binding to be dropped on background resync. The closure now re-registers the binding correctly.
- **Removed `workmanager` Dependency**: Fully removed the `workmanager` package and `LikeBackgroundSyncService`. The package is now platform-agnostic and runs on Flutter Web, Windows, macOS, and Linux. Offline sync is driven by `LikeConnectivityManager` reacting to foreground connectivity changes.
- **Cryptographic Hardening**: Replaced the hardcoded AES key and static IV in `AppCacheSecurity` with a per-device derived key (SHA-256) and a random IV per-file write. Cached data is now genuinely encrypted.
- **Registry Singleton Removed**: `LikeRequestRegistry` no longer uses a global singleton. Each `LikeClient` instance manages its own registry, preventing state corruption when using multiple clients or running parallel tests.
- **Auth-Aware Offline Replay**: `LikeOfflineSyncInterceptor` now fetches a fresh auth token before replaying queued mutations, fixing 401 errors for long-lived offline sessions.
- **SWR Background Future Bug**: `LikeClient._execute` was not awaiting the SWR background future, silently swallowing errors. This has been corrected.

## [1.1.3] - 2026-05-19

### Added

- **Repository Optimization**: Updated and pointed the package source repository metadata to the dedicated documentation/repository (`https://github.com/AjayJasperJ/like_docs`).
- **Modern SDK Support**: Upgraded the package constraints to target the latest stable Dart SDK (`^3.12.0`) and Flutter SDK (`>=3.44.0`) following system environment upgrades.

## [1.1.2] - 2026-05-18

### Added

- **Multi-Screen UI Demonstration App**: Added a full, robust multi-screen example application within `example/` demonstrating the comprehensive integration of all core package widgets and builders (including `LikeBuilder`, `LikeWhen`, `LikeSelector`, `LikeSelectorSliver`, `LikeMultiBuilder`, `LikeMultiSliverBuilder`, `LikeCacheImage`, `updateNotifier`, and `LikeToast`).
- **Reactive State Selectors**: Supported granular UI rebuilds via `LikeSelector` and `LikeSelectorSliver` to observe and rebuild on precise state slices.
- **Combined State Observers**: Introduced `LikeMultiBuilder` and `LikeMultiSliverBuilder` to elegantly bundle and process multiple concurrent state notifier updates.
- **Background Isolate Parsing**: Standardized `mapAsync` background parsing in repository layers to offload heavy JSON serialization cleanly.

## [1.1.1] - 2026-05-17

### Added

- **Metadata Tuning**: Updated the package description and topics in `pubspec.yaml` to highlight core Dio, Hive, and AES encryption integrations for enhanced discoverability on pub.dev.
- **Engine Optimization**: Consolidated brand-agnostic key transformations and optimized test configurations.

## [1.1.0] - 2026-05-17

### Added

- **Network Mocking Engine**: Integrated persistent Hive-backed mocking (`MockController`) and Dio request interception (`LikeMockInterceptor`) for offline, testing, and staging environment simulation.
- **Secure Image Caching**: Added transparent AES-CBC 256-bit disk encryption (`AppCacheManager`, `EncryptedHttpFileService`) with dynamic stream-based decryption for sensitive assets.
- **Auto LRU Image Pruning**: Implemented automatic Least Recently Used (LRU) pruning targeting size limits (`maxImageCacheMB` and `minImageCacheMB`).
- **`LikeCacheImage` Widget**: Added a robust network image caching widget that removes ephemeral tracking query parameters automatically to maximize cache hits.
- **DevTool Integration**: Added support for debug staging overlays via the new optional `devTool` callback in the root `Like` wrapper.
- **Unified Protocols & Technical Deep Dive**: Fully documented the engine's optimized Dio wrapper foundation, REST/GraphQL protocol support, offline mutation queues, background Isolate parsing, and rate limiting (HTTP 429) controls.

### Fixed

- **Code Hardening & Security Audit**: Audited the entire codebase to purge external branding and variables. Updated deprecated method channel testing APIs and resolved static analysis lints for 100% health.

## [1.0.7] - 2026-05-11

### Added

- **Documentation**: Major update to README with corrected initialization via the `Like` root wrapper widget.
- **4-Tier Roadmap**: Explicitly documented Tiers 1-4 (Service, Repository, Provider, UI) with production-grade examples.
- **Manual Initialization**: Added `addPostFrameCallback` pattern for deferred engine setup.
- **Contribution**: Integrated social links (GitHub, LinkedIn, Instagram) and email for community engagement.
- **Visuals**: Standardized package banners across all documentation using raw GitHub URLs.

## [1.0.6] - 2026-05-11

### Added

- **Background Parsing**: Added isolate-based JSON transformation for background processing.
- **LikeBuilder Updates**:
  - Added support for onLoading, onError, and onSuccess callbacks.
  - Added support for pagination loading states.
  - Created `LikeWhen` widget for pattern matching UI.
- **Reactive UI Components**: Added `LikeToast` for contextless notifications and `LikeNetworkImage` for caching.
- **Connectivity**: Integrated `ConnectivityPlus` for network status monitoring.
- **Haptics**: Added haptic feedback support.
- **Async Utilities**: Added `mapAsync` and `mapSuccessAsync` extensions.

### Fixed

- **Memory Safety**: Added critical documentation on `dispose` patterns to prevent background sync leaks in multi-screen applications.
- **Metadata**: Resolved `pubspec.yaml` topic limit issues for better discoverability.

## [1.0.5] - 2026-05-10

### Added

- **Architecture Roadmap**: Added comprehensive documentation for Clean Architecture integration covering Service, Repository, Provider, and UI layers.
- **Background Parsing**: Standardized `mapAsync` and `mapSuccessAsync` extensions for isolate-based JSON transformation to maintain 120 FPS.
- **Provider Hardening**: Enhanced `LikeAutoReconnectMixin` documentation with "Gold Standard" implementation patterns.
- **Resync Engine**: Formally documented cross-notifier synchronization (`syncWith`) and automated reconnection recovery (`onReconnect`).

### Fixed

- **Memory Safety**: Added critical documentation on `dispose` patterns to prevent background sync leaks in multi-screen applications.
- **Metadata**: Resolved `pubspec.yaml` topic limit issues for better discoverability.

## [1.0.4] - 2026-05-10

### Added

- **Multi-platform Support**: Integrated `universal_io` to enable Web support while maintaining mobile/desktop parity.
- **Dependency Hardening**: Synchronized all core packages to their latest resolvable versions for optimal security and performance.

### Fixed

- **Static Analysis**: Resolved all linter hints (info) across the codebase.
- **Documentation**: Finalized banner rendering paths.

## [1.0.3] - 2026-05-10

### Fixed

- **Documentation**: Finalized correct banner URL path for pub.dev.

## [1.0.2] - 2026-05-10

### Fixed

- **Pub.dev Asset Loading**: Switched to raw GitHub URLs for the banner to ensure correct rendering on pub.dev.
- **Package Size Optimization**: Added `.pubignore` to exclude the `build/` folder and other artifacts, significantly reducing the package size (from 16MB down to <1MB).

## [1.0.1] - 2026-05-10

### Added

- **Visual Identity**: Added a high-fidelity package banner to the README for a more professional presentation on pub.dev.

### Fixed

- **Code Hardening**: Fixed multiple `use_build_context_synchronously` lint issues in `LikeWhen` to ensure UI stability during async gaps.
- **Style Consistency**: Corrected string quoting and applied `dart format` across the entire package (63 files) for 100% lint compliance.

## [1.0.0] - 2026-05-10

### Initial Release

- **Link Intelligent Kernel Engine (LIKE)**: A high-performance, 4-tier caching networking package for Flutter.
- **3-Tier Caching Architecture**:
  - L1: RAM Cache for instantaneous session-level retrieval.
  - L2: Persistent Disk Cache (Hive) for cross-session persistence.
  - L3: Stale-While-Revalidate (SWR) logic for background data freshness.
- **Resilience Engine**:
  - Automated request deduplication.
  - Request suppression and cancellation logic.
  - Built-in smart retry mechanism.
- **Offline-First Synchronization**:
  - Background mutation queueing (POST/PUT/DELETE).
  - Automatic synchronization when connectivity is restored.
- **Notification Engine**:
  - Contextless high-fidelity toast notification system.
  - Custom animations (Slide, Fade, Scale, Bounce).
  - Swipe-to-dismiss and interactive action support.
- **Performance Optimizations**:
  - Automatic offloading of heavy JSON parsing to background isolates.
  - Efficient binary serialization for L2 disk storage.
- **Reactive UI Components**:
  - `LikeBuilder`: Declarative state handling for Loading, Success, SWR, and Error.
  - `LikeWhen`: Streamlined pattern matching for network results.
  - `updateNotifier`: Integrated side-effect handler with haptics and toast support.
- **Security & Configuration**:
  - Support for SSL Pinning (SHA256).
  - Sensitive header masking in logs.
  - Comprehensive `LikeConfig` with over 80+ customization options.
