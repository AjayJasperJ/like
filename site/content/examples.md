# Three complete apps

The repository includes three independent Flutter applications, all backed by
DummyJSON and a shared domain/data/application/presentation package.

| Project | State owner | Shared implementation |
| --- | --- | --- |
| `examples/provider_app` | ChangeNotifier / Provider | `examples/shop_shared` |
| `examples/riverpod_app` | Riverpod Notifier | `examples/shop_shared` |
| `examples/bloc_app` | Cubit / BlocBuilder | `examples/shop_shared` |

## Complete flow

Guest browse → search/paging → product detail → sign in → account-scoped cart →
quantity updates → simulated checkout → receipt → sign out.

The public demo account is **emilys / emilyspass**. No internal server, secret API
key or payment card is required. These are intentionally public demo credentials.
DummyJSON mutations simulate writes: checkout is not a purchase and does not
charge money. Tokens use secure storage; Hive carts are separated by account/guest.

## Run one

```sh
cd examples/provider_app
flutter pub get
flutter run
flutter run -d chrome
flutter test
flutter build web --release
flutter build apk --release
```

Replace `provider_app` with `riverpod_app` or `bloc_app`. Android/iOS/web wrappers
are included. Web secure storage needs HTTPS or localhost; CORS/TLS still apply.

## Download APKs

Open a successful **Public API shop apps** Actions run and download
`like-provider-release-apk`, `like-riverpod-release-apk` or
`like-bloc-release-apk`. These artifacts last seven days. They are release-mode
but test-signed evaluation builds, not store-ready production signing. An older
installation may need removal when the test signing key changes.

`apps-v*` tags attach three distinct APK assets to a GitHub release after checks.
Merging source alone does not create a tagged release or publish to pub.dev.
The legacy `example/` and `server/` are additional demonstrations, not prerequisites
for these public API shops.
