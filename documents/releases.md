# Release and compatibility automation

Dependabot proposes weekly Dart and GitHub Actions updates. Compatible minor and
patch changes are grouped; breaking upgrades need review. Heavy core/browser/native/device checks are manual-only to conserve runner
minutes. The documentation workflow remains automatic for relevant changes.
Example APKs build on explicit manual runs or `apps-v*` tags.

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

The proposed minimum is Flutter 3.44.1 / Dart 3.12; a dedicated workflow resolves
and tests that SDK independently of current stable. Treat this support claim as
unvalidated until the minimum-SDK job passes. The prior 3.16/Dart 3.0 constraint
was incompatible with dependency requirements. The minimum-SDK probe confirmed
that path_provider 2.1.6 requires Dart 3.10; it cannot resolve on Dart 3.8.

The same probe confirmed synchronized 3.4.1 requires Dart 3.12. The minimum
workflow therefore targets Flutter 3.44.1 and the package declares Dart 3.12;
current stable remains independently tested.
