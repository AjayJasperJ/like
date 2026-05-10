# 🚀 LIKE (Link Intelligent Kernel Engine)

![LIKE Banner](https://raw.githubusercontent.com/AjayJasperJ/like/refs/heads/main/assets/banner.png)


[![GitHub](https://img.shields.io/badge/GitHub-AjayJasperJ-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/AjayJasperJ)
[![LinkedIn](https://img.shields.io/badge/LinkedIn-Ajay_Jasper_J-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://in.linkedin.com/in/ajay-jasper-j-8563852b4)
[![Instagram](https://img.shields.io/badge/Instagram-@ajayjasper.j-E4405F?style=for-the-badge&logo=instagram&logoColor=white)](https://www.instagram.com/ajayjasper.j)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)

A **production-grade, 3-tier caching networking ecosystem** for Flutter. LIKE is a high-level orchestration engine built on top of Dio, designed to automate every complex network behavior—from SWR revalidation to offline synchronization—so you can stop writing boilerplate and start building features.

---


## ✨ Key Features

- **🛡️ Resilience Engine**: Built-in deduplication, request suppression, and automatic retry logic.
- **💎 3-Tier Caching**: RAM (L1), Persistent Disk (L2), and Stale-While-Revalidate (L3).
- **📶 Offline-First**: Background synchronization and mutation queueing for flaky connections.
- **🔔 Notification Engine**: Contextless high-fidelity toasts with custom animations and swipe logic.
- **🧵 Performance Optimized**: Heavy JSON parsing is automatically offloaded to background isolates.
- **🔗 Reactive State**: Event-driven UI updates via `LikePipeline` and `LikeStateResponse`.

---

## 🚀 4 Steps to Production-Ready Networking

### 1. Global Initialization

Initialize the engine in your `main.dart`. This sets up persistent storage and global interceptors.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize the LIKE engine with a configuration object.
  // This sets up storage, connectivity, and background services.
  await LikeService.init(
    config: LikeConfig(
      baseUrl: 'https://api.yourdomain.com',
      enableLogging: kDebugMode,
      offlineSyncEnabled: true,
    ),
  );

  runApp(const Like(child: MyApp()));
}
```

### 2. Define a Service

Encapsulate your API calls. Use `LikeARS` to control cache and revalidation behavior per request.

```dart
class ProfileService {
  final _client = LikeClient();

  Future<LikeApiResult<User>> getProfile(String id, {LikeARS? ars}) async {
    return await _client.get(
      '/v1/profile/$id',
      ars: ars ?? const LikeARS(
        staleWhileRevalidate: true,
        deduplicate: true,
      ),
    ).mapAsync((json) => User.fromJson(json));
  }
}
```

### 3. Provider Layer (Advanced Pattern)

Providers manage the `LikeStateResponse` and use `LikeARS` to control the loading experience (e.g., preventing flickers during background refreshes).

```dart
class ProfileProvider extends ChangeNotifier {
  final _service = ProfileService();
  LikeStateResponse<User> userState = LikeStateResponse.idle();

  /// Fetches the profile with optional [ars] for cache control.
  Future<LikeStateResponse<User>> loadProfile({String? id, LikeARS? ars}) async {
    try {
      final effectiveArs = ars ?? const LikeARS();

      // 1. Strategic Loading: Don't show spinner if it's just a background refresh
      if (!effectiveArs.refresh) {
        userState = LikeStateResponse.loading();
        notifyListeners();
      }

      // 2. Pre-flight Validation
      if (id == null) {
        return userState = LikeStateResponse.missingData("ID is required");
      }
    
      // 3. Service Call (Pass ARS to the engine)
      final result = await _service.getProfile(id, ars: effectiveArs);
    
      // 4. Map Result to State
      
      // Option A: Automatic (Recommended)
      return userState = result.toStateResponse();

      // Option B: Manual (When you need to transform data)
      /*
      return userState = result.when(
        onSuccess: (user) => LikeStateResponse.success(user),
        onFailure: (error) => LikeStateResponse.error(error),
      );
      */
    } catch (e) {
      return userState = LikeStateResponse.exception(e.toString());
    } finally {
      notifyListeners();
    }
  }
}
```

### 4. Build Reactive UI

Use `LikeBuilder` to handle all states (Loading, Success, SWR Refreshing, Error) declaratively.

```dart
Widget build(BuildContext context) {
  return LikeBuilder<User>(
    observe: () => provider.userState, // A LikeStateResponse<User>
    onLoading: () => const Shimmer(),
    onSuccess: (user, isRefreshing, isFromSWR) {
      return Column(
        children: [
          if (isFromSWR) const Text("Using cached data..."),
          Text("Welcome, ${user.name}"),
          if (isRefreshing) const CircularProgressIndicator(),
        ],
      );
    },
    onError: (error) => ErrorView(error.message),
  );
}
```

---

## ⚡ Handling Actions (Mutations)

LIKE provides two distinct patterns for handling side-effects.

### 1. The "Full" Pattern (`updateNotifier`)
Automatically handles **haptics**, **toasts**, and **callbacks**. Ideal for primary actions.

```dart
void _onSavePressed() async {
  final result = await provider.saveProfile(id: '123');

  updateNotifier<User>(
    response: result,
    onSuccess: (user) => Navigator.pop(context),
    // Precision control over toasts
    disableSuccessToast: false,
    disableErrorToast: false,
  );
}
```

### 2. The "Empty" Pattern (`likeWhenNotifier`)
A raw state mapper with **NO automatic toasts or haptics**. Use for full manual control.

```dart
void _onSilentAction() async {
  final result = await provider.sync();

  likeWhenNotifier<Data>(
    response: result,
    onSuccess: (data) => print("Data synced: $data"),
    onError: (err) => print("Sync failed: ${err.message}"),
  );
}
```

---

## 🔔 Notification Engine

Trigger beautiful, contextless feedback from your services or logic classes.

### Extension Patterns (Recommended)

```dart
extension MyProjectToasts on LikeToastType {
  void showSuccess(String msg) {
    LikeToastManager.showCustomToast(
      child: MySuccessWidget(msg),
      animationType: LikeToastAnimation.slide,
      alignment: Alignment.topCenter,
      slideInOffset: const Offset(0, -1), // Slide down from top
    );
  }
}

// Usage in Logic:
LikeToastType.success.showSuccess("Profile Updated!");
```

---

## 🛠️ Advanced Request Settings (ARS)

| Property | Default | Description |
| :--- | :--- | :--- |
| `staleWhileRevalidate` | `true` | UI shows disk data immediately, while background refresh updates it. |
| `deduplicate` | `true` | Combines 100 concurrent calls into 1 network request. |
| `sessionStale` | `false` | Prefers RAM (L1) cache for the current app session. |
| `offlineSync` | `true` | Mutations (POST/PUT/DELETE) are queued and synced when online. |
| `suppressErrors` | `false` | Prevents the engine from showing global error toasts. |

---

## ⚙️ Global Configuration (`LikeConfig`)

The engine can be fine-tuned via `LikeConfig`. See the class documentation for over 80+ customization options including:

- **Timeouts**: Connect, Receive, Send, and Init.
- **Caching**: L1 limits, TTL (days), and ETag verification.
- **Logging**: Compact mode, silent console, and file logging.
- **Security**: SSL Pinning (SHA256) and Sensitive Header masking.

---
