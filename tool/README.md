# Test tools

- `browser_test_server.py`: deterministic loopback fixture for browser CORS, cache,
  ETag, timeout and cancellation tests. It is not required by the public API apps.
- `configure_shop_platforms.py APP_DIRECTORY`: adds Android release network
  permission to the standard Flutter platform wrapper.
- `public_api_smoke.py`: live DummyJSON contract checks for the complete public API
  flow. Prints pass/fail metadata, never response payloads or tokens.

CI SDKs and Pub caches are isolated in runner temporary directories. Every job
has a 60-minute timeout and an always-run cleanup step. Hosted runners are
removed after completion/cancellation; this is not a guarantee that cleanup can
run after a runner itself loses power. No SDK is retained as an artifact.
