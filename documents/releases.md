# Release and compatibility automation

Dependabot proposes weekly Dart and GitHub Actions updates. Compatible minor and
patch changes are grouped; breaking upgrades need review. Normal PR workflows
validate core behavior, browsers, native builds and three public API app builds.

`Publish package release` runs only for `v<pubspec-version>` tag pushes. It checks
the changelog/tag, reruns tests, analysis and publication dry-run, then publishes
with pub.dev's GitHub OIDC identity. The `pub-dev` GitHub environment can require
reviewers before the final publication step. No publishing token is committed.

Before first use, the package owner must configure **pub.dev → Admin → Automated
publishing** with `AjayJasperJ/like` and tag pattern `v{{version}}`. This is an
external account setting; adding the workflow does not configure that setting.
Create a matching changelog section before creating an approved release tag.
No release tag or package publication is performed just by opening the PR.

`apps-v*` tags and manual runs build the three example release APKs as workflow
artifacts. These are test-signed APKs for evaluation. Production signing keys
belong in protected environment secrets and must never be committed.

The SDK and Pub cache are temporary, uncached and removed at job completion.
Every job has a one-hour timeout. APK artifacts are retained for seven days;
coverage and generated-source review artifacts for one day.

The proposed minimum is Flutter 3.38.1 / Dart 3.10; a dedicated workflow resolves
and tests that SDK independently of current stable. Treat this support claim as
unvalidated until the minimum-SDK job passes. The prior 3.16/Dart 3.0 constraint
was incompatible with dependency requirements. The minimum-SDK probe confirmed
that path_provider 2.1.6 requires Dart 3.10; it cannot resolve on Dart 3.8.
