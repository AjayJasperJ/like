# Complete public API examples

| Project | State owner | Public API |
| --- | --- | --- |
| provider_app | ChangeNotifier / Provider | DummyJSON |
| riverpod_app | Riverpod Notifier | DummyJSON |
| bloc_app | Cubit / BlocBuilder | DummyJSON |

Each project has its own entry point, dependency manifest, theme and flow tests.
`shop_shared` contains domain interfaces, HTTP service, concrete repository,
application use cases and widgets. Dependencies point inward: widgets call use
cases, use cases depend on `ShopRepository`, and infrastructure implements that
interface using injectable `LikeHttpClient`, secure token storage and Hive carts.
The three adapters publish immutable snapshots through their own state library.

See each project README for run and release APK commands. The **Public API shop
apps** action builds all three installable APKs on explicit manual
runs and `apps-v*` tags; ordinary pushes/PRs no longer start these expensive builds. Download `like-provider-release-apk`,
`like-riverpod-release-apk`, or `like-bloc-release-apk` from the successful run.
These are test-signed release builds. Configure a private production keystore
before submitting an app to an app store.

The package is a networking/data/state toolkit, not an HTML/CSS/JavaScript browser
engine. These apps render Flutter widgets from API data. To render arbitrary
websites, embed a maintained platform WebView; browser CORS/security restrictions
cannot be bypassed by the networking package.
