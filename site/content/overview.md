# One networking layer. Your state management.

LIKE is a Flutter networking, cache and state-coordination toolkit built on Dio
and Hive. Keep transport policy behind an injectable service/repository boundary,
and use Provider, Riverpod or BLoC/Cubit to own presentation state.

<div class="hero-grid"><a class="feature-card" href="quickstart/">01 / START<br><strong>Your first typed request</strong><span>Install, initialize and map a public API response.</span></a><a class="feature-card" href="examples/">02 / EXPLORE<br><strong>Three working applications</strong><span>Browse, authenticate, manage a cart and check out.</span></a><a class="feature-card" href="agents/">03 / AUTOMATE<br><strong>Context for coding agents</strong><span>Plain Markdown, source contracts and implementation recipes.</span></a></div>

## What is included

| Capability | What you can build |
| --- | --- |
| Injectable HTTP | Services returning typed results with cancellation |
| Scoped identity | Separate account/environment caches and queued operations |
| Cache policies | Memory/Hive, SWR, ETag validation and resource invalidation |
| Offline recovery | Explicitly queued mutations, durable multipart and bounded replay |
| State coordination | Shared queries, optimistic mutations and paginated lists |
| Notifications | Connected/disconnected, sync, queued action, cache and slow-path hooks |
| Safe inspection | Sanitized logs, payload-free traces and development scenarios |
| Media/realtime | Images, multipart uploads and managed WebSockets |

## Choose a route

- **New project:** follow [Quick start](quickstart/), then [Architecture](architecture/).
- **Existing project:** inject `LikeHttpClient` into your service; keep your current state owner.
- **Production integration:** review [Authentication](authentication/), [Offline recovery](offline/) and [Privacy](privacy/).
- **Coding agent:** begin with [Agent guide](agents/), `llms.txt` and the version/source manifest.

## Version and boundaries

These guides describe the repository source version shown in the header. Source
availability is distinct from a published pub.dev release. Installation choices
and minimum SDKs are explained in [Quick start](quickstart/).

LIKE is not an HTML/CSS/JavaScript browser engine. Use a maintained WebView for
arbitrary websites. Redis belongs behind your HTTP API; it is not a bundled
mobile state layer. Browser CORS, storage quotas and certificate policy apply.

The release adds session isolation, durable recovery, reactive query primitives,
slow-path monitoring, conservative diagnostics and three public-API apps. See
[Releases & migration](releases/) for behavior changes and [Public API source index](api/)
for the exact exported source surface.
