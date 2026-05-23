# Changelog

All notable changes to this project will be documented in this file.

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
