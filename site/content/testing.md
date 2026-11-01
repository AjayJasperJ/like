# Testing & CI

## Pick the right level

| Level | What it establishes |
| --- | --- |
| Unit/controlled adapter | Mapping, policies, cancellation, races and storage migration behavior |
| Host widget/VM | State ownership and deterministic UI flows |
| Chrome | Browser-compatible HTTP/storage/widget behavior |
| Native compile | Platform integration compiles; not runtime proof |
| Android emulator / iOS simulator | Actual app flow and native plugin execution |
| Live public contract | External API behavior/availability at test time |

Chrome coverage does not establish Safari/Firefox parity. Simulator success does
not prove every physical device or OS version is supported.

## Local checks

```sh
flutter pub get
flutter test --coverage
cd server && dart pub get && dart test && cd ..
cd example && flutter pub get && flutter test && cd ..
flutter analyze
```

For the complete browser HTTP suite, start `python3 tool/browser_test_server.py`
then run the browser commands from `.github/workflows/ci.yml`. Stop your fixture
process afterward. App commands belong inside each example app directory.

Import `package:like/testing.dart` for exposed cache/registry/queue/pipeline and
adapter boundaries. Inject `LikeHttpClient` fakes in service tests without booting
global storage/network; use controlled adapters for real transport-policy tests.

## Workflow controls and runner budget

Heavy Flutter/package/minimum-SDK/native/device workflows are manual-only. They
do not run on ordinary pushes or pull requests. Use Actions → the workflow →
Run workflow when you need that validation. Example APK builds also run for
explicit `apps-v*` release tags. Package publishing remains gated by `v*` tags.
The documentation workflow is the only routine automatic build, filtered to docs
and API-source changes, with cancellation of superseded runs.

## Available workflows

- **Package checks:** generator/release metadata, unit/server/example suites, browser tests, analysis, format, publication dry-run.
- **Minimum Flutter compatibility:** independent minimum SDK resolution and checks.
- **Native platform checks:** Linux/macOS/Windows host suites and platform builds.
- **Public API shop apps:** three host/browser flows, shared tests, release web/APK and live contract.
- **Device flow tests:** Android complete flows and isolated iOS UI/live repository flows.
- **Documentation site:** content/link/build tests; deploys only approved main/manual source through Pages.

Device startup recovery is bounded and only applies before tests connect; test
assertion failures are not silently retried. Temporary SDKs/caches are cleaned
at job completion, with one-hour job bounds and disposable hosted runners.

Read actual workflow results before claiming a commit passed. Cancelled superseded
runs are not test failures. See [CI reference](ci-history/).
