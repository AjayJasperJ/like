![LIKE Banner](https://raw.githubusercontent.com/AjayJasperJ/like_docs/refs/heads/main/assets/banner.png)

# Contributing to LIKE 🚀

Thank you for contributing to the **Link Intelligent Kernel Engine (LIKE)**. To maintain the high architectural standards, reliability, and extreme performance of this enterprise-grade, offline-first networking package, please follow these guidelines.

---

## 🏗️ Design Philosophy

1.  **Strict 4-Tier Separation**:
    *   **UI Layer**: Presentation only (`LikeBuilder`, `LikeSelector`, etc.).
    *   **Provider Layer**: State holding and asynchronous orchestration (`ChangeNotifier` + `LikeNotifierState`).
    *   **Repository Layer**: Business mapping, query building, and thin forwarding.
    *   **Service Layer**: Network client orchestration (`LikeClient`, raw HTTP, intercepts).
2.  **Context-Agnostic Core**: Keep core engine logic fully decoupled from Flutter's `BuildContext` to guarantee pure unit-testability. Use managers and static delegates (like `LikeToastManager`) for UI-level side effects.
3.  **L1 · L2 · SWR Caching**: Every fetch must respect the multi-tier caching system (L1 RAM -> L2 Hive Box -> background SWR revalidation -> ETag/304 negotiation) to maximize responsiveness and minimize cellular bandwidth.
4.  **No Main-Thread Jank**: Always delegate payload parsing to background isolates using `.mapAsync()` for payloads larger than 100 KB.
5.  **Reactive State Contracts**: Never expose raw domain models directly from providers to the UI. Always wrap state in a `LikeNotifierState` or `LikeStateResponse` to handle `loading`, `refreshing`, `success`, `error`, and `staleWhileRevalidate` states out-of-the-box.
6.  **Offline-Resiliency**: All mutable endpoints (`POST`/`PUT`/`DELETE`) must support persistence in the offline mutation queue, complete with auto-replay and auth-aware token rotation on reconnect.
7.  **Web Compatibility & Platform Isolation**: Maintain full compatibility across Web and native. Do not import `dart:io` or native-only APIs directly in shared code. Use conditional compilation/exports or runtime guards (`kIsWeb`) to isolate native APIs (like certificate overrides or direct file caching) from browser execution environments.

---

## 📐 Architectural Contracts & Coding Standards

### 1. The Tiered Flow
*   **Service**: Returns a raw `LikeApiResult<T>`.
*   **Repository**: Performs JSON mappings using background parsing:
    ```dart
    Future<LikeApiResult<User>> getUser(String id) =>
        _service.getUser(id).mapAsync(User.fromJson);
    ```
*   **Provider**: Inherits from `ChangeNotifier` with `LikeAutoReconnectMixin` and updates a `LikeNotifierState<T>`.
*   **UI**: Observes state using highly localized `LikeBuilder<T>`, `LikeSelector<N, T>`, or `LikeMultiBuilder` widgets.

### 2. The Gold Standard Notifier (Provider)
New state notifiers must follow this zero-boilerplate pattern:

```dart
class UserNotifier extends ChangeNotifier with LikeAutoReconnectMixin {
  final _repo = UserRepository();

  // 1. Reactive state with auto-pipeline serialization mapper
  final userState = LikeNotifierState<User>(
    mapper: (json) => User.fromJson(json as Map<String, dynamic>),
  );

  Future<void> fetchUser(String id, {ARS? ars}) async {
    // 2. Fetch handles loading, SWR, token rotation, and pipeline sync
    await fetch<User>(
      state:      userState,
      ars:        ars,
      autoResync: true,
      action:     (ct, actionArs) => _repo.getUser(id, ars: actionArs),
    );
  }

  @override
  void dispose() {
    super.dispose(); // 3. MUST call super.dispose() to cancel active tokens & pipeline listeners
  }
}
```

### 3. Reactive UI Widgets
Do not introduce custom stateful builder bindings. Always leverage LIKE's optimized widget suite:
*   `LikeBuilder<T>`: Subscribes directly to states.
*   `LikeSliverBuilder<T>`: For CustomScrollViews.
*   `LikeSelector<N, T>`: For rebuilding a widget only when a selected property of a state changes.
*   `LikeMultiBuilder`: For combining multiple concurrent states.
*   `LikeWhen<T>`: Pattern-matching shorthand.

---

## 🛠️ Development Standards

### 1. Code Style & Formatting
*   Adhere to the [Official Effective Dart Style Guide](https://dart.dev/guides/language/effective-dart/style).
*   Run `dart format .` before creating any commits.
*   Run `dart analyze` to ensure zero warnings, hints, or lints are present in the project.

### 2. Strict API Documentation
*   All public-facing API signatures (classes, mixins, constructors, methods, extension functions) **MUST** have complete, clear DartDoc comments (`///`).
*   Config options must be added to `LikeConfig` with default values and detailed documentation.

### 3. Testing Requirements
*   All new features and core bugs must be validated with tests inside the `test/` directory.
*   Cover both success cases ("happy path") and error paths (offline simulation, HTTP timeout, 401 token refresh failures, 500 status envelopes).
*   Mock requests using `mocktail` or the built-in `MockController` system.

---

## 🚀 Contribution Workflow

1.  **Sync**: Pull the latest code from `main`.
2.  **Branch**: Create a descriptive feature branch:
    ```bash
    git checkout -b feat/add-lru-cache-pruning
    ```
3.  **Build & Code**: Code your improvements and check for lints:
    ```bash
    dart analyze
    ```
4.  **Test**: Ensure all tests pass with no regressions:
    ```bash
    dart test
    ```
5.  **Submit PR**: Open a Pull Request on GitHub. Detail the **What**, **Why**, and **How** of your changes.

---

## 🤝 Connect & Contribute

Support the project or reach out for collaboration:

*   📦 **pub.dev**: [pub.dev/packages/like](https://pub.dev/packages/like)
*   📖 **Docs / Wiki**: [github.com/AjayJasperJ/like_docs](https://github.com/AjayJasperJ/like_docs)
*   🐛 **Issues**: [github.com/AjayJasperJ/like_docs/issues](https://github.com/AjayJasperJ/like_docs/issues)
*   💻 **GitHub**: [@AjayJasperJ](https://github.com/AjayJasperJ)
*   💼 **LinkedIn**: [Ajay Jasper J](https://in.linkedin.com/in/ajay-jasper-j-8563852b4)
*   📸 **Instagram**: [@ajayjasper.j](https://www.instagram.com/ajayjasper.j)
*   ✉️ **Email**: [ajayjasperj@outlook.com](mailto:ajayjasperj@outlook.com)

*Created with ❤️ by Ajay Jasper J. and contributors.*
