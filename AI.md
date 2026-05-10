# LIKE: Agent Intelligence Guide 🧠

Welcome, Agent. This file is the primary source of truth for the **Link Intelligent Kernel Engine (LIKE)**.

---

## 🏗 1. The 4-Tier Architecture
1.  **Client (`LikeClient`)**: Execution engine. Handles `ARS` settings.
2.  **Service Layer**: Returns `LikeApiResult<T>`. Use `mapAsync` for background parsing.
3.  **Provider Layer**: Uses `LikeAutoReconnectMixin`. Converts results to `LikeStateResponse<T>`.
4.  **UI Layer**: Uses `LikeBuilder` to consume state.

---

## 🗺 2. Master Developer Capability Map

### ⚙️ Core Layer (`lib/src/core`)
- **`like_config.dart`**: Add global flags, timeouts, or design tokens.
- **`like_ars.dart`**: Add request-level controls (e.g., `priority`, `retryCount`).
- **`like_data_unpacker.dart`**: Implement logic for legacy API JSON envelopes.
- **`like_constants.dart`**: Define internal keys for Hive/Notifications.
- **`like_helpers.dart`**: Add shared pure utility functions.

### 📡 Client Layer (`lib/src/client`)
- **`like_client.dart`**: Add new HTTP methods or global decorators.
- **`like_request_registry.dart`**: Customize request keying for deduplication.
- **`like_error_handler.dart`**: Map new status codes or error signatures.
- **`like_client_factory.dart`**: Modify interceptor order or inject custom adapters.
- **`like_pipeline.dart`**: Transform request/response data flow.
- **`internal/`**: Handle hashing (`like_hash`), mapping (`like_mapper`), and registry implementation.

### 📦 Model Layer (`lib/src/models`)
- **`like_api_result.dart`**: Add metadata fields (e.g., `responseTime`).
- **`like_state_response.dart`**: Add convenience state getters.
- **`like_error.dart`**: Define new error categories (e.g., `validation_error`).
- **`like_event.dart` / `like_sync_task.dart`**: Define system events and sync task shapes.

### 🛠 Service Layer (`lib/src/services`)
- **`like_service.dart`**: Add new persistence adapters (e.g., SQLite).
- **`like_sync_manager.dart`**: Customize priority queue logic.
- **`like_connectivity_manager.dart`**: Add custom reachability checks.
- **`like_offline_sync_manager.dart`**: Resolve offline mutation conflicts.
- **`like_background_sync_service.dart`**: Define platform-specific background rules.
- **`like_toast_manager.dart`**: Add new notification types (Toasts, Banners).
- **`like_logger.dart`**: Implement remote logging (Sentry/Crashlytics).

### 🧩 Interceptor Layer (`lib/src/interceptors`)
- **`like_cache_interceptor.dart`**: Fine-tune TTL and disk-cache rules.
- **`like_auth_interceptor.dart`**: **Auth Hook**: Code JWT refresh logic here.
- **`like_retry_interceptor.dart`**: Implement exponential backoff algorithms.
- **`like_perf_interceptors.dart`**: Track network performance metrics.

### 🎨 Widget Layer (`lib/src/widgets`)
- **`like_root_wrapper.dart`**: Inject global providers or custom overlays.
- **`like_builder.dart`**: Add custom state transition animations.
- **`like_sliver_builder.dart`**: Implement specialized scroll behavior.
- **`like_selector.dart`**: Optimize rebuilds for nested data.
- **`like_when.dart`**: Add declarative branching patterns.

### 🧠 Mixin Layer (`lib/src/mixins`)
- **`like_auto_reconnect_mixin.dart`**: Add reactive helpers like `debouncedFetch`.
- **`like_pipeline_mixin.dart`**: Code multi-step "Wizard" API flows.

---

## 🛠 3. Standard Implementation Templates

### A. The Service Pattern
```dart
class MyService {
  Future<LikeApiResult<T>> getData() async {
    return await LikeClient().get('/path').mapAsync(T.fromJson);
  }
}
```

### B. The Provider Pattern
```dart
class MyNotifier extends ChangeNotifier with LikeAutoReconnectMixin {
  LikeStateResponse<T> state = LikeStateResponse.idle();
  CancelToken? _ct;

  Future<void> load() async {
    await fetcher<T>(
      ct: _ct,
      onRotate: (n) => _ct = n,
      onUpdate: (s) => state = s,
      action: (ct, ars) => MyService().getData().then((r) => r.toStateResponse()),
    );
  }
}
```

### C. The UI Pattern
```dart
LikeBuilder<T>(
  state: notifier.state,
  onSuccess: (data) => DataView(data),
  onRefreshing: (old) => Stack(children: [DataView(old), Loader()]),
  onError: (err) => ErrorView(err.message),
);
```

---

## 🌩️ 4. Advanced Sync & Persistence
- **Offline Mutations**: Use `offlineSync: true` in `ARS` to persist failing POSTs to Hive.
- **Global Refresh**: Call `LikeClient().notifyRefresh('/path')` to trigger all `syncWith` listeners.

---

## 🧬 6. Core Engine Deep-Dive (Code Anatomy)

### A. The Heart: `LikeClient._execute`
- **Location**: `lib/src/client/like_client.dart` (Starts L75)
- **Logic**: 
  - **L80-90**: Checks if `deduplicate` is enabled; if so, returns existing `Future` from `LikeRequestRegistry`.
  - **L100-110**: Handles `staleWhileRevalidate`. Triggers a "Cache-First" response immediately while spawning a background network fetch.
  - **L120+**: Wraps the Dio call in a retry/error handler pipeline.

### B. The Brain: `LikeAutoReconnectMixin.fetcher`
- **Location**: `lib/src/mixins/like_auto_reconnect_mixin.dart` (Starts L135)
- **Lifecycle**:
  - **L146**: `newCT(ct)` - Cancels the previous request before starting a new one.
  - **L151**: Checks `ars.refresh` - Only shows `loading` state if it's NOT a background refresh.
  - **L157**: Executes the `action` and maps the `LikeApiResult` to a `LikeStateResponse`.
  - **L170**: `finally { notifyListeners() }` - Ensures the UI always updates regardless of success or failure.

### C. Persistence: `LikeCacheInterceptor`
- **Location**: `lib/src/interceptors/like_cache_interceptor.dart`
- **Logic**:
  - Intercepts `onRequest` to see if a valid Hive cache exists.
  - If `staleWhileRevalidate` is on, it completes the request with cached data but lets the Dio pipeline continue for the "real" fetch.

### D. The Consumer: `LikeBuilder.build`
- **Location**: `lib/src/widgets/like_builder.dart`
- **Logic**:
  - Uses a `switch` on `state.state` (the enum).
  - **Success**: Returns `onSuccess(state.data!)`.
  - **Refreshing/SWR**: Returns `onRefreshing(state.data!)` if provided, otherwise defaults to `onSuccess`. This is the secret to "Sticky Data."

---

## 🚫 7. Maintenance Rules for Agents
1.  **Isolate Parsing**: Always use `mapAsync` for complex model mapping.
2.  **Sticky UI**: Never set state to `loading` if `data` is present (use `refreshing`).
3.  **Cancellation**: Every request MUST have a `CancelToken`.
4.  **No `dart:io`**: Use `universal_io` for Web/Wasm compatibility.

---
*Created by Antigravity (Google DeepMind) for the LIKE Open Source Project.*
