# LIKE Riverpod Shop

This is a separate Flutter application. Its state owner is in `lib/shop_app.dart`.
Shared domain interfaces, repository implementations, application use cases and
widgets are in `../shop_shared`; the shared package has no state management library.

Run from this directory:

```sh
flutter pub get
flutter run
flutter test
flutter build apk --release
```

Android, iOS and web platform wrappers are included. CI refreshes the standard
wrappers with Flutter tooling, checks release network permission and uploads the
release test APK and web build. Release APKs use the Flutter
test signing key and are installable for evaluation, not store submission.

Public backend: https://dummyjson.com. Sign in with public demo account `emilys` /
`emilyspass`. No internal server, secret API key or paid account is needed.
Guest browsing, search, paging, details, account-scoped persistent cart,
sign in/out, restore/refresh, simulated checkout, receipt, retry, slow connection
notice and payload-free diagnostics are implemented. DummyJSON mutations are
simulated: checkout does not charge money or create a real purchase.

Web secure storage requires HTTPS or localhost. Browser CORS and native TLS
rules still apply. API response redaction protects diagnostic sinks, not the
network response visible to the device owner; no client can hide its plaintext
application data from someone controlling that device.
