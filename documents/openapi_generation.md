# Optional typed OpenAPI generation

The runtime never requires a generator or a schema server. For the supported
OpenAPI 3.0 **JSON subset**, run:

```sh
python3 tool/openapi/generate.py api.json lib/data/generated_api.dart
dart format lib/data/generated_api.dart
```

Generation emits immutable named DTOs with `fromJson`/`toJson` and a typed service
that depends on `LikeHttpClient`. Inject it into a repository; presentation code
continues to depend on the repository interface. CancelToken propagates through
generated operations and failure mapping preserves LIKE result metadata.

Supported: named plain object DTOs; primitive/local-reference/array fields;
required and nullable fields; GET/POST/PUT/PATCH/DELETE; primitive path/query
parameters; one JSON success response; required JSON request bodies. Every
operation must explicitly set `x-like-policy.withAuth` and either `cacheTags`
(GET) or `invalidates` (mutations), including an empty tag list when deliberate.
Path parameter values are URI-encoded.

This is not a complete OpenAPI implementation. External references, unions,
compositions, arbitrary map schemas, enums, multipart schema generation,
optional request bodies and multiple success schemas fail with an error. Write
these services by hand or use a dedicated full OpenAPI tool. Schema constraints
such as string length or numeric ranges still require domain validation.

`tool/openapi/fixture.json`, Python generator rejection tests and
`test/generated_api_test.dart` verify deterministic output, malformed-spec
rejection, typed parsing and actual generated HTTP policy/cancellation wiring.
`--check` accepts formatter whitespace and trailing-comma changes.
