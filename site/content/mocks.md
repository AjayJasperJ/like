# Mocks & DevTool

## Reproduce failures without a mock server

`MockController` and `MockRule` persist development rules. Rules can match paths,
methods and request data, then apply synthetic responses, delays, failure modes,
headers and bounded uses. Use synthetic data only.

```dart
import 'package:like/like.dart';

await LikeMockScenario.failureThenSuccess('/products', status: 429).install();
```

`LikeMockScenario.exportSafe()` strips credential matchers/opaque data for sharing;
`fromJson` validates versioned scenario input. Do not place real secrets in route
paths or metadata. Scenario installation is disabled in release builds.

## Optional DevTool companion

The private `AjayJasperJ/like_devtool` companion is separate from core. Access and
compatible dependency setup are required; it is not installed by `flutter pub add like`.
It supports safe request inspection, source/timing/retry metadata, log/storage
previews, queue recovery and synthetic latency/401/429/outage controls.

Use an app-owned client when inspecting that client's queue. The developer overlay
does not take ownership of the client. Do not assume core and companion can be
upgraded independently without their compatibility check.

## Privacy boundary

DevTool reads payload-free diagnostics and sanitizes previews before display/copy.
It does not make raw app data confidential from a device owner. For export and
release logging guarantees, read [Privacy & platform behavior](privacy/).
