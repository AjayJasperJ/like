# LIKE: Link Intelligent Kernel Engine 🚀

**LIKE** is a high-performance, 4-tier networking engine for Flutter designed for **Offline-First**, **Resilient**, and **Reactive** applications. It provides enterprise-grade request control, caching, and state management.

---

## 🛠 1. Initialization

Call `Like.init` before `runApp` to set up global configurations, cache boxes, and background sync.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Like.init(
    config: LikeConfig(
      baseUrl: 'https://api.example.com',
      unpacker: const DefaultLikeUnpacker(), // Unpacks {"status": 200, "data": {...}}
      cacheEnabled: true,
      offlineSyncEnabled: true,
    ),
  );

  runApp(const MyApp());
}
```

### 📦 The Root Wrapper
Wrap your `MaterialApp` with `LikeRootWrapper` to enable global toast notifications and connectivity monitoring.

```dart
LikeRootWrapper(
  child: MaterialApp(
    home: const HomeScreen(),
  ),
)
```

---

## 🏗 2. The 4-Tier Pattern

### 📡 Tier 1: Service Layer (`LikeApiResult`)
Services return `LikeApiResult<T>`. This is a pure data wrapper that captures result metadata (cache, 304, success/error) without UI state.

```dart
class UserService {
  Future<LikeApiResult<User>> getUser(String id) async {
    return await LikeClient().get('/users/$id').mapAsync(User.fromJson);
  }
}
```

### 🧠 Tier 2: Provider Layer (`LikeStateResponse`)
Providers convert `LikeApiResult` into `LikeStateResponse`. This is a **UI-aware** state wrapper containing a `LikeState` (loading, success, error, etc.) and **Sticky Data**.

```dart
class UserNotifier extends ChangeNotifier with LikeAutoReconnectMixin {
  LikeStateResponse<User> state = LikeStateResponse.idle();
  CancelToken? _ct;

  Future<void> fetchUser(String id) async {
    await fetcher<User>(
      ct: _ct,
      onRotate: (next) => _ct = next,
      onUpdate: (s) => state = s,
      action: (ct, ars) => UserService().getUser(id).toStateResponse(),
    );
  }
}
```

---

## ⚡ 3. Advanced Developer Patterns

### 🔄 `fetcher`
**Use in**: Providers/Notifiers.
**Why**: Automates the boilerplate of rotating `CancelToken`s, setting loading states (but only when appropriate), and handling silent Dio cancellations.

### 🔗 `syncWith`
**Use in**: Provider `initAutoReconnect`.
**Why**: Declaratively refreshes data when a specific endpoint updates globally.
```dart
syncWith<User>(
  endpoint: '/users/profile',
  action: () => fetchUser(),
  state: () => state,
  cancelToken: () => _ct,
);
```

### 📥 `loadOrFetch`
**Use in**: UI or Actions.
**Why**: "Get me the data now if you have it, otherwise fetch it and return it."
```dart
final user = await loadOrFetch(state, () => fetchUser());
```

---

## 🎨 4. Reactive UI Widgets

### `LikeBuilder`
The primary widget for consuming `LikeStateResponse`. It provides a clean API for handling every state in the lifecycle.

```dart
LikeBuilder<User>(
  state: userNotifier.state,
  onSuccess: (data) => UserProfile(user: data),
  onLoading: () => const ShimmerLoader(),
  onRefreshing: (data) => Stack(children: [UserProfile(user: data), LinearProgressIndicator()]),
  onError: (error) => ErrorView(message: error.message),
);
```

### `LikeStateResponse` State Machine
- **`isIdle`**: Initial state.
- **`isLoading`**: First-time fetch (no data yet).
- **`isRefreshing`**: Explicit refresh (data is visible/sticky).
- **`isSWR`**: Background update (cached data is visible).
- **`isSuccess`**: Request completed with data.
- **`isError`**: API error (e.g., 500).
- **`isException`**: Client-side failure (e.g., No Internet).

---

## 🧪 5. Customizing Response Unpacking
By default, LIKE expects a flat response. Use `DefaultLikeUnpacker` if your API wraps data in a standard envelope:

```dart
// Handles: { "status": 200, "data": { "id": 1 }, "message": "Success" }
LikeConfig(
  unpacker: const DefaultLikeUnpacker(
    dataKey: 'data',
    messageKey: 'message',
    statusKey: 'status',
  ),
)
```

---
*Created with ❤️ by Ajay Jasper J.*
