# Why a workflow is red

GitHub Actions does not require this repository's code to be on main. Pull requests
run the proposed changes; main push runs test the merged version. Check the failed
**step and first error**, rather than treating every red job as runner failure.

Verified failures from the 31 October 2026 runs:

| Run | Actual cause | Correction |
| --- | --- | --- |
| 41227822995 / 41227822986 | Cache resource indexing called Uri.origin on relative `/test` during the auth fallback test. The same test failed on Ubuntu, macOS and Windows. | Index only absolute origins; retain support for relative URLs in injected test clients. |
| 41227823020, Riverpod | A disposal callback used ref.read after Riverpod entered disposal. | Capture the repository while building the notifier; cleanup uses the captured instance. |
| 41225480711, main | Strict analysis rejected three missing-brace diagnostics. | Add braces; retain strict analysis. |
| Older PR runs | Changed Dart formatting gate rejected unformatted source. | Format and commit changed files; main must apply the same gate. |

Provider and BLoC jobs in run 41227823020 succeeded, including release APK
builds. Several earlier branch native runs also passed. A cancellation after a
new push is expected: concurrency.cancel-in-progress replaces outdated runs.

Current workflow triggers use pull_request for branches with an open PR, push
for main, and workflow_dispatch for manual runs. A feature branch without an
open PR does not automatically run this matrix on every push.

A passing main run from an older commit is not validation of newer branch code.
Do not merge a draft while its fixes and checks are still in progress.
