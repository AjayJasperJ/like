# LIKE Interceptor Pipeline Documentation

The **Link Intelligent Kernel Engine (LIKE)** network stack relies on a multi-tiered, ordered pipeline of **Dio Interceptors**. Each interceptor owns a single, well-defined responsibility—ranging from preflight fast-failing network connectivity to token refresh rotation, ETag revalidation, offline mutation queueing, and developer logging.

---

## Architecture & Execution Order

When a request is initiated via `LikeClient` or `LikeService`, it flows sequentially through the interceptor pipeline in the following order:

```
Outgoing Request
   │
   ├─► 1. LikePerformanceInterceptor    (Starts duration timer)
   ├─► 2. LikeThrottlingInterceptor     (Applies dev latency simulation)
   ├─► 3. LikeMockInterceptor           (Intercepts & resolves mock rules)
   ├─► 4. LikeConnectivityInterceptor   (Preflight check & fast-fail offline)
   ├─► 5. LikeAuthInterceptor           (Injects Bearer token & x-api-key; rate-limit delays)
   ├─► 6. LikeEtagInterceptor           (Attaches If-None-Match header)
   ├─► 7. LikeRetryInterceptor          (Manages request-local transport retries)
   ├─► 8. LikeOfflineSyncInterceptor    (Prepares offline mutation metadata)
   ├─► 9. LikeCacheInterceptor          (Saves GET responses to Hive L2 cache)
   ├─► 10. LikePipelineInterceptor      (Emits GET responses to LikePipeline)
   ├─► 11. LikeLoggerInterceptor        (Prints compact / expanded log output)
   │
   ▼
Network Transmission (Dio HttpClientAdapter)
```

---

## Detailed Interceptor Breakdown

### 1. `LikeConnectivityInterceptor`
- **File**: [`like_connectivity_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_connectivity_interceptor.dart)
- **Role**: Preflight connection check & fast-fail mechanism.
- **Key Behaviors**:
  - `onRequest`: Checks device connectivity via `LikeConnectivityManager()`. If marked offline, it triggers an instant reachability probe. If the probe confirms offline state, it immediately rejects the request with `DioExceptionType.connectionError` (0ms delay), preventing long timeout waits.
  - `onResponse` / `onError`: Proves server reachability for HTTP responses (including 4xx/5xx) and marks origin as available. Triggers automatic background reachability check for transport failures.

---

### 2. `LikeAuthInterceptor`
- **File**: [`like_auth_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_auth_interceptor.dart)
- **Role**: Access token injection, HTTP 401 token refresh queue, and HTTP 429 rate-limiting.
- **Key Behaviors**:
  - **Token Injection**: Injects `Authorization: Bearer <token>` and `x-api-key: <key>` headers automatically unless `withAuth: false` is configured in `options.extra`.
  - **Single-Flight Token Refresh (401)**: When a 401 Unauthorized occurs, it locks outgoing requests via a `Completer<String?>`. It executes `refreshToken()`, updates the access token, and replays all paused requests cleanly. On refresh failure, it triggers `onLogout()`.
  - **Origin Rate Limiting (429)**: Respects `Retry-After` HTTP headers or exponential backoff per canonical origin (`scheme://host:port`), delaying subsequent requests to that origin automatically.

---

### 3. `LikeOfflineSyncInterceptor`
- **File**: [`like_offline_sync_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_offline_sync_interceptor.dart)
- **Role**: Persistent offline queue for `POST`, `PUT`, `DELETE`, and `PATCH` mutations.
- **Key Behaviors**:
  - `onError`: When an eligible mutation request fails due to an ambiguous transport error, the payload, headers, endpoint, and query parameters are serialized to a Hive box with a unique SHA-256 stable ID.
  - Returns synthetic error `OFFLINE_QUEUED` and displays an offline toast notification.
  - Works with `LikeOfflineSyncManager` to automatically replay queued mutations sequentially upon connection recovery.

---

### 4. `LikeCacheInterceptor`
- **File**: [`like_cache_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_cache_interceptor.dart)
- **Role**: Persists successful GET responses to the Hive L2 disk cache.
- **Key Behaviors**:
  - `onResponse`: Awaits saving HTTP 200 `GET` responses into Hive before proceeding, ensuring the L2 cache is immediately ready for 304 validation.
  - **Pruning**: Provides `pruneCache()` method to prune expired entries based on global `cacheTTL` or per-entry `storageDurationMs`.

---

### 5. `LikeEtagInterceptor`
- **File**: [`like_etag_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_etag_interceptor.dart)
- **Role**: HTTP ETag conditional request validation (HTTP 304 Not Modified).
- **Key Behaviors**:
  - `onRequest`: Attaches `If-None-Match: <etag>` header if an ETag is saved in `LikeService` for the target request key.
  - `onResponse`: Saves returned `ETag` header values for HTTP 200 responses.
  - `onError`: Intercepts HTTP 304 Not Modified (delivered as a Dio non-2xx error) and resolves the request directly with the cached L2 response data, setting `isFromCache: true` and `isFrom304: true`.

---

### 6. `LikePipelineInterceptor`
- **File**: [`like_pipeline_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_pipeline_interceptor.dart)
- **Role**: Broadcasts successful `GET` responses to `LikePipeline`.
- **Key Behaviors**:
  - `onResponse`: Re-wraps HTTP 200 responses and emits them to `LikePipeline().emit(key, response)`, automatically updating all active UI `LikeNotifierState` listeners observing that endpoint path.

---

### 7. `LikeRetryInterceptor`
- **File**: [`like_retry_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_retry_interceptor.dart)
- **Role**: Bounded request-local retries for idempotent transport failures (`GET`, `HEAD`, `OPTIONS`).
- **Key Behaviors**:
  - Only retries safe read methods on connection errors, timeouts, or socket failures.
  - Respects request-level `maxAutoRetries` and `retryDelays` configurations with cancellable backoff delays (`CancelToken`).

---

### 8. `LikeLoggerInterceptor`
- **File**: [`like_logger_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_logger_interceptor.dart)
- **Role**: Request and response developer console logging.
- **Key Behaviors**:
  - Generates request UUIDs (`requestId`) and logs query parameters, headers, and multipart form fields.
  - Automatically masks sensitive headers (such as `Authorization`).
  - Supports **Compact API Logs** (`compactApiLogs: true`) to output clean, single-line HTTP 2xx summaries (`[10:15:30][api] /api/posts [200] : SUCCESS`) while printing detailed diagnostic tracebacks on errors.

---

### 9. `LikeMockInterceptor`
- **File**: [`like_mock_interceptor.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_mock_interceptor.dart)
- **Role**: Dev/staging network mocking engine.
- **Key Behaviors**:
  - `onRequest`: Evaluates enabled `MockRule`s against request method, URL pattern, regex, query parameters, headers, and request body.
  - Resolves matching requests immediately with synthetic `Response(data: mockData, statusCode: rule.statusCode, statusMessage: 'OK (MOCKED)')`.

---

### 10. `LikePerformanceInterceptor` & `LikeThrottlingInterceptor`
- **File**: [`like_perf_interceptors.dart`](file:///home/ja5p3r/Projects/packages/like/lib/src/interceptors/like_perf_interceptors.dart)
- **Role**: Performance timing & simulated network latency.
- **Key Behaviors**:
  - **`LikePerformanceInterceptor`**: Tracks start time in `options.extra['startTime']` and logs total roundtrip execution duration in milliseconds (`options.extra['durationMs']`).
  - **`LikeThrottlingInterceptor`**: Delays request/response handling when `simulatedLatencyMs` is passed in `options.extra`, simulating 2G/3G network conditions in development builds.

---

## Interceptor Controls via `options.extra`

You can control interceptor behaviors per request using `options.extra`:

| Key | Type | Interceptor Affected | Description |
|---|---|---|---|
| `withAuth` | `bool` | `LikeAuthInterceptor` | Set to `false` to skip authorization header injection. |
| `disableCache` | `bool` | `LikeCacheInterceptor`, `LikeEtagInterceptor` | Bypasses L2 Hive cache and ETag headers. |
| `offlineSync` | `bool` | `LikeOfflineSyncInterceptor` | Enables persistent offline queuing for mutations. |
| `disableLogger` | `bool` | `LikeLoggerInterceptor` | Suppresses console logging for this request. |
| `maxAutoRetries` | `int` | `LikeRetryInterceptor` | Overrides max transport retry attempts. |
| `retryDelays` | `List<int>` | `LikeRetryInterceptor` | Overrides retry delay intervals (in seconds). |
| `simulatedLatencyMs` | `int` | `LikeThrottlingInterceptor` | Simulates network latency in milliseconds. |
