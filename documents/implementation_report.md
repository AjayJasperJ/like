# Implementation and verification report

Final validation is in progress on [core PR #5](https://github.com/AjayJasperJ/like/pull/5)
and [DevTool PR #1](https://github.com/AjayJasperJ/like_devtool/pull/1).
This report distinguishes implemented behavior from external release setup.

## Package updates

| Area | Implementation | Main verification |
| --- | --- | --- |
| Request identity | Effective origin, typed query values and session/environment identity | origin_identity_test, session_scope_test, client tests |
| Session isolation | Cancel stale requests, clear L1 ownership, block another account's queued operations | session_scope_test, offline interceptor tests |
| Offline recovery | Scheduled retries, startup recovery, durable multipart byte snapshots, stable operation IDs | replay_policy_test, offline interceptor tests including close/reopen replay |
| Queue controls | Pending/running/blocked/failed metadata, owner-checked retry/cancel, bounded attempts | offline interceptor tests |
| Authentication | Shared refresh, throwing-hook settlement, multipart reconstruction and scoped auth copies | auth configuration/resilience/rate-limit tests |
| Retry policy | Retry-After seconds/date, bounded positive jitter and cancellation | replay_policy_test, retry/auth interceptor tests |
| Cache invalidation | Scope/origin/resource tags invalidate disk, metadata, ETags and active queries | service tag-isolation test, query_flow_test |
| State lifecycle | Shared LikeQuery snapshot/stream, cancellation, stale-result suppression, reconnect and invalidation | cross-adapter architecture_test, query_flow_test |
| Optimistic updates | Ordered layers, reconciliation and rollback preserve newer successful mutations | query_flow_test |
| Pagination | Per-page backing data, item-ID deduplication, failed-page retry and cursor termination | query_flow_test, pagination_test |
| Network quality | Passive per-origin latency/throughput hints with bounded state | diagnostics_test |
| Privacy | Sanitized diagnostic copies, release payload omission, historical export filtering | diagnostics_test, logger tests, DevTool privacy_test |
| Request explanations | Payload-free source, timing, status, retry counts and auth-replay metadata | scenario_trace_test, DevTool tests |
| Synthetic scenarios | Persist latency/failure rules; safe sharing; 401/429/outage controls; disabled in release | scenario_trace_test, DevTool compatibility build |
| Typed generation | Optional strict OpenAPI 3.0 JSON subset, DTO parsers, explicit read/mutation policies | Python rejection/determinism tests and generated_api_test |
| CI | Core/server/integration, browser, native builds, minimum/current SDK and device flow checks | GitHub Actions workflows |
| Releases | Weekly dependency proposals, changelog/tag gates, OIDC publishing and three APK assets | publication dry-run and APK build workflows |

## Three complete public API applications

Each project has committed Android/iOS/web wrappers, its own entry point and state
owner. Shared domain, data, use-case and presentation code avoids copying business
logic while keeping Provider, Riverpod and Cubit ownership explicit.

| Project | State owner | Flow |
| --- | --- | --- |
| examples/provider_app | ChangeNotifier / Provider | Guest browse → search/paging → details → sign in → cart quantities → simulated checkout/receipt → sign out |
| examples/riverpod_app | Riverpod Notifier | Same flow, with repository captured before disposal callbacks |
| examples/bloc_app | Cubit / BlocBuilder | Same flow, with explicit stream/state ownership and close |

All use https://dummyjson.com and the public demo account shown in the sign-in
dialog. No internal server, secret API key or payment details are required.
Tokens use secure storage; carts are persisted separately for each account and
guest. Public mutations are simulated, so a demo receipt is not a real purchase.
Slow-connection hints, safe request diagnostics and retry UI are included.

Widget tests run on the native host and Chrome. The same flow has an
integration_test entry point executed on Android emulator and iOS simulator.
A separate live job verifies actual public API contracts without logging tokens.
A native integration test also exercises the production repository, real LIKE
HTTPS transport, secure token storage and Hive cart persistence against that API.

The app workflow produces release-mode APKs and web builds. An `apps-v*` tag can
attach `like-provider.apk`, `like-riverpod.apk` and `like-bloc.apk` to a GitHub
release after checks pass. These are evaluation APKs using Flutter test signing.
An older test installation may need removal if its signing key differs.

## Why branch runs were red

The runner was executing correctly. Failures came from relative-URI indexing,
Riverpod disposal, stale test mocks/fixtures, SDK constraints that understated
actual dependencies, and formatting/analyzer checks. Main failed too. Formatting
now applies to both pull requests and main; independent checks report their own
failures instead of hiding later results after the first failed test.

See [CI troubleshooting](ci_troubleshooting.md) for the inspected historical runs.
Cancellations after newer pushes are expected concurrency behavior.

## Boundaries and owner setup

- This package provides Flutter networking/data/state features. It does not
  implement an HTML/CSS/JavaScript browser engine; arbitrary pages need a WebView.
- Browser CORS, TLS, storage quotas and background timer limits still apply.
- Redaction protects diagnostic copies; it cannot hide application data from a
  person controlling the device. Application caches are not encrypted by LIKE.
- Exactly-once mutation behavior requires server support for Idempotency-Key.
- The default durable multipart snapshot limit is 10 MiB; larger uploads need an
  application-provided codec/storage policy.
- Optional OpenAPI generation supports the documented subset and rejects other
  shapes instead of generating incomplete bindings.
- pub.dev automated publishing requires the owner to configure the repository
  and tag identity in pub.dev Admin. No publishing tag has been created here.
- SDK and package caches are temporary, uncached and cleaned at job completion;
  every job has a maximum one-hour timeout. Hosted runners are discarded as well.

See [release setup](releases.md), [state management](state_management.md),
[privacy/platform behavior](network_privacy_platforms.md) and
[the acceptance checklist](pending_tasks.md).
