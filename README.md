![LIKE Banner](https://raw.githubusercontent.com/AjayJasperJ/like/refs/heads/main/assets/banner.png)

# LIKE: Link Intelligent Kernel Engine 🚀

**LIKE** is a high-performance, 4-tier networking engine for Flutter designed for **Offline-First**, **Resilient**, and **Reactive** applications. It provides enterprise-grade request control, caching, and state management.

---

## 🛠 1. Initialization

Wrap your `MaterialApp` with the `Like` root wrapper. This widget handles the initialization of the engine (Hive, connectivity, sync) and provides global services like authentication hooks and toast notifications.

```dart
void main() {
  runApp(
    Like(
      baseUrl: 'https://api.example.com',
      getToken: () async => 'current_session_token',
      refreshToken: () async => 'new_session_token',
      child: const MyApp(),
    ),
  );
}
```

### ⚙️ Runtime Configuration
The `Like` widget manages the entire lifecycle of the networking engine. It automatically:
- Initializes **Persistent Storage** (Hive).
- Sets up **Connectivity Monitoring**.
- Configures **Authentication Interceptors**.
- Registers **Global Toast** listeners.

### ⏳ Manual or Deferred Initialization
If you need to initialize the engine manually (e.g., inside a splash screen or custom setup flow), you can use the `LikeService` directly. It is recommended to use `addPostFrameCallback` to avoid blocking the initial render:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) async {
  // Required to open Hive cache boxes and setup connectivity
  await LikeService.init(config: LikeConfig());
});
```

---

## 🏗 Tier 1: Service Layer (`LikeApiResult`)
Services return `LikeApiResult<T>`. This is a pure data wrapper that captures result metadata (cache, 304, success/error) without UI state.

```dart
class UserService {
  Future<LikeApiResult<User>> getUser(String id) async {
    return await LikeClient().get('/users/$id').mapAsync(User.fromJson);
  }
}
```

## 🧠 Tier 2: Provider Layer (`LikeStateResponse`)
Providers convert `LikeApiResult` into `LikeStateResponse`. This is a **UI-aware** state wrapper containing a `LikeState` (loading, success, error, etc.) and **Sticky Data**.

```dart
class UserNotifier extends ChangeNotifier with LikeAutoReconnectMixin {
  final _userService = UserService();
  
  LikeStateResponse<User> state = LikeStateResponse.idle();
  CancelToken? _ct;

  UserNotifier() {
    initAutoReconnect(); // Required for syncWith and onReconnect
  }

  Future<void> fetchUser(String id) async {
    await fetcher<User>(
      ct: _ct,
      onRotate: (next) => _ct = next,
      onUpdate: (s) => state = s,
      action: (ct, ars) => _userService.getUser(id),
    );
  }

  @override
  void dispose() {
    super.dispose(); // CRITICAL: Cancels active sync listeners
  }
}
```

---

## ⚡ Tier 3: Advanced Developer Patterns

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

## 🎨 Tier 4: Reactive UI Widgets

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
By default, LIKE expects a flat JSON response. If your API wraps data in a standard envelope (e.g., JSend or similar), use `DefaultLikeUnpacker`. 

> [!IMPORTANT]
> This is critical for **Error Handling**. Without these keys, the engine cannot extract the `message` or `status` from your API's custom envelope, leading to generic "Unknown Error" states.

```dart
// Handles: { "status": 200, "data": { "id": 1 }, "message": "Success" }
LikeConfig(
  unpacker: const DefaultLikeUnpacker(
    dataKey: 'data',        // Where the payload lives
    messageKey: 'message',  // Where the error/success message lives
    statusKey: 'status',    // Where the business status code lives
  ),
)
```

---

## 🤝 Connect & Contribute

Support the project or reach out for collaboration:

- **GitHub**: [@AjayJasperJ](https://github.com/AjayJasperJ)
- **LinkedIn**: [Ajay Jasper J](https://in.linkedin.com/in/ajay-jasper-j-8563852b4)
- **Instagram**: [@ajayjasper.j](https://www.instagram.com/ajayjasper.j)
- **Email**: [ajayjasperj@outlook.com](mailto:ajayjasperj@outlook.com)
