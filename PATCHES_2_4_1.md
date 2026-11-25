# LIKE 2.4.1 Patch Log

Date: 2026-11-25  
Base tag: `v2.4.1` (`4117ffe`)

This document records all patches applied against `LIKE_2_4_1_AUDIT.md`, including files modified, symbols added/updated, and verification results.

## Summary of patches

### 1. Storage capability, startup resilience, timeout, and reconfiguration
- **Audit IDs:** `LIKE-001`, `LIKE-002`, `LIKE-003`, `LIKE-004`, `LIKE-005`, `LIKE-017`, `LIKE-021`, `LIKE-039`
- **Files:**
  - `lib/src/services/like_service.dart`
  - `lib/src/client/like_client_factory.dart`
  - `lib/src/services/like_offline_sync_manager.dart`
  - `lib/src/interceptors/like_cache_interceptor.dart`
  - `lib/src/core/like_config.dart`
- **Changes:**
  - Added `LikeStorageStatus` (`uninitialized`, `available`, `disabled`, `timedOut`, `unavailable`), `LikeService.storageAvailable`, `LikeService.storageStatus`, and `LikeService.storageError`.
  - `LikeService.init()` now skips Hive initialization and `AppCacheManager().pruneCacheIfExceedsSize()` when `cacheEnabled: false`.
  - Wrapped `Hive.initFlutter(...)` and `Future.wait([Hive.openBox(...)])` in `.timeout(config.initTimeout)` with `TimeoutException` vs general storage error handling, degrading cleanly to network-only mode instead of throwing.
  - Updated re-initialization (`_initialized == true`) to re-evaluate `_configureStorage`, update `LikeClient().updateBaseUrl(config.baseUrl)`, and start or dispose `LikeOfflineSyncManager` based on `_storageAvailable && config.offlineSyncEnabled`.
  - Gated `LikeOfflineSyncInterceptor` registration in `LikeClientFactory._setupInterceptors` on `LikeConstants.offlineSyncEnabled && LikeService.storageAvailable && _isOfflineQueueOpen`.
  - Guarded `LikeCacheInterceptor.pruneCache()` with `Hive.isBoxOpen(LikeConstants.boxApiCache)` and wrapped `saveResponseToCache` in `try/catch` (`LIKE-029`) so failed cache writes do not fail successful network responses.
  - Added `LikeService.reset({bool closeBoxes = false})` for deterministic test/logout cleanup (`LIKE-015`).

### 2. ETag / 304 safety and persistence
- **Audit IDs:** `LIKE-012`, `LIKE-030`
- **Files:**
  - `lib/src/interceptors/like_etag_interceptor.dart`
  - `lib/src/client/like_client_factory.dart`
- **Changes:**
  - Gated `onRequest` and `onResponse` in `LikeEtagInterceptor` on `LikeConstants.cacheEnabled && (LikeService.storageAvailable || Hive.isBoxOpen(LikeConstants.boxEtags))`.
  - Awaited `LikeService.putEtag(key, etag)` in `onResponse` inside `try/catch` instead of fire-and-forget.
  - Added optional `Dio? dio` to `LikeEtagInterceptor` (wired by `LikeClientFactory`), performing a single unconditional fallback `dio.fetch` without `If-None-Match` when a 304 cache miss occurs.

### 3. Global singleton reset hooks & diagnostics retention
- **Audit IDs:** `LIKE-015`, `LIKE-038`
- **Files:**
  - `lib/src/services/like_sync_manager.dart`
  - `lib/src/interceptors/like_auth_interceptor.dart`
  - `lib/src/diagnostics/like_request_trace.dart`
  - `lib/src/client/like_client.dart`
- **Changes:**
  - Added `LikeSyncManager().reset()` and `LikeAuthInterceptor.resetGlobalState()` (`@visibleForTesting`).
  - Added `LikeDiagnostics.enabled` (defaults to `!kReleaseMode`) and configurable `LikeDiagnostics.maxHistory` (default `400`).
  - Cleared `LikeDiagnostics.shared.clear()` in `LikeClient.setSessionScope` on account/scope transitions.

### 4. Cache invalidation generation guard
- **Audit IDs:** `LIKE-032`
- **Files:**
  - `lib/src/services/like_service.dart`
  - `lib/src/client/like_client.dart`
- **Changes:**
  - Added per-key invalidation generation tracking (`LikeService.generationForKey`, `LikeService.markKeysInvalidated`).
  - `LikeClient._executeRequest` records `like.cacheGeneration` at request start; `LikeService.saveResponseToCache` and `LikeClient._handleSuccess` skip L2/L1 promotion if the key was invalidated while the GET was in flight.

### 5. Auth replay safety & session checks
- **Audit IDs:** `LIKE-010`, `LIKE-028`
- **Files:**
  - `lib/src/interceptors/like_auth_interceptor.dart`
- **Changes:**
  - Propagated `extra['idempotencyKey']` as `Idempotency-Key` header in `onRequest`.
  - Gated automatic 401 replay via `_isReplayEligible` (safe methods `GET`/`HEAD`/`OPTIONS`, or requests carrying `Idempotency-Key` / `idempotencyKey` / `allowUnsafeReplay: true`).
  - Preserved 429 `Retry-After` retry for existing package contract (`like_auth_interceptor_rate_limit_test.dart`) while supporting opt-in `requireIdempotencyKey: true` and adding `LikeSessionIdentity.isCurrent(options)` check after the 429 delay before replaying.

### 6. Pipeline query matching & visibility coalescing
- **Audit IDs:** `LIKE-006`, `LIKE-007`, `LIKE-008`
- **Files:**
  - `lib/src/mixins/like_visibility_mixin.dart`
  - `lib/src/mixins/like_state_mixin.dart`
  - `lib/src/engine/like_engine.dart`
- **Changes:**
  - Added `notifyVisibility(bool visible)` to `LikeVisibilityMixin` for `IndexedStack`/`TabBarView` containers, and coalesced `onRecover` / `triggerFocusRefetch` calls per microtask.
  - Added optional `bool exactQueryMatch = false` to `LikeStateMixin.fetch`, `LikeEngine.fetch`, and `LikeEngine.fetchResult` so paginated/mode-scoped states can require exact query matching.

### 7. Web image decode bounds, release multipart safety, transport error reason, and compute threshold
- **Audit IDs:** `LIKE-013`, `LIKE-014`, `LIKE-024`, `LIKE-033`, `LIKE-035`, `LIKE-036`
- **Files:**
  - `lib/src/widgets/like_cache_image.dart`
  - `lib/src/client/like_client.dart`
  - `lib/src/models/like_error.dart`
  - `lib/src/client/like_error_handler.dart`
  - `lib/src/client/internal/like_mapper.dart`
- **Changes:**
  - Passed `cacheWidth`/`cacheHeight` to `Image.network` on web in `LikeCacheImage` (from `memCacheWidth`/`memCacheHeight` or finite `width`/`height * devicePixelRatio`).
  - Replaced `assert(!kIsWeb, ...)` in `LikeClient.multipart` with a deterministic runtime `LikeApiResult.error` so release web builds also reject `filePaths`.
  - Added `LikeError.transportReason` and populated it in `LikeErrorHandler` (e.g. `web_opaque_network_error`, `web_connection_error`).
  - Enforced `thresholdKB` in `LikeMapper.map` using a bounded size estimator before calling `compute`.

### 8. WebSocket lifecycle & auth options, logger release gating, and documentation
- **Audit IDs:** `LIKE-018`, `LIKE-019`, `LIKE-022`, `LIKE-023`, `LIKE-027`, `LIKE-034`, `LIKE-037`
- **Files:**
  - `lib/src/client/like_websocket_client.dart`
  - `lib/src/interceptors/like_logger_interceptor.dart`
  - `lib/src/core/like_config.dart`
  - `README.md`
- **Changes:**
  - Added `authTicketSupplier`, `onConnectedAuth`, `useQueryToken`, `pause()`, `resume()`, `pauseWhenBackgrounded`, `maxReconnectAttempts`, and exponential backoff with jitter to `LikeWebSocketClient`.
  - Skipped assembling `FormData.fields` and header/query maps in `LikeLoggerInterceptor` when `kReleaseMode` or logging is disabled.
  - Updated `LikeConfig` docstrings (`initTimeout`, `imageStalePeriod`, `supportWeb`) and `README.md` platform table to distinguish Dart2JS vs WASM network-only support and non-persistent web image caching.

## Tests added
- `test/audit_patches_test.dart`: covers `cacheEnabled: false` startup, `LikeStorageStatus`, `LikeEtagInterceptor` 304 cache-miss retry, `LikeCacheInterceptor.pruneCache` with closed box, `LikeAuthInterceptor` unsafe mutation replay guard + `Idempotency-Key` preservation, `LikeEngine` `exactQueryMatch`, invalidation generation guard, `LikeMapper` threshold, `LikeDiagnostics` session-change clearing, `LikePagedQuery` repeated cursor & refresh cancellation (`LIKE-009`), and `cacheAuthenticatedGets: false` (`LIKE-031`).
- `test/portable/browser_http_test.dart`: added public `LikeService.init(cacheEnabled: false)` + `LikeClient` browser smoke test (`LIKE-020`).
- `.github/workflows/ci.yml`: updated `example/` web build to `flutter build web --release`. Note: running `flutter build web --release --wasm` in `example/` showed `like` itself compiles cleanly under `dart2wasm`, while `example/`'s `flutter_secure_storage_web: 1.2.1` dependency fails `dart2wasm` due to legacy `dart:html` / `dart:js_util` imports.

