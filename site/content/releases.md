# Releases & migration

## Source, publication and deployment are different

| Event | What it does |
| --- | --- |
| Merge into main | Updates source and starts normal checks |
| `v<pubspec-version>` tag | Runs gated package publication workflow |
| `apps-v*` tag | Builds/checks and attaches three demo APKs to a release |
| Documentation site workflow | Builds docs and deploys main through GitHub Pages |

Before first package publication, the owner configures pub.dev Admin automated
publishing for `AjayJasperJ/like` and the intended tag identity. Do not assume a
workflow configures that external setting. Production app signing needs protected
keys; demo APKs use evaluation signing.

## Migrating to 2.4.0 source

- Upgrade to Flutter 3.44.1 / Dart 3.12 or newer.
- Replace obsolete root-level token arguments with `LikeAuthConfig`.
- Pass explicit `withAuth` and opt-in `offlineSync` flags at request boundaries.
- Set account/environment scope after login and reset it on logout.
- Review legacy ownerless queued entries; they stay blocked until explicitly resolved.
- Use resource tags/shared queries when cross-screen invalidation is required.
- Do not expect diagnostic payloads to appear in release logs; use typed traces.
- Image bytes/current caches are not encrypted by LIKE; remove stale encryption assumptions.

See the repository CHANGELOG and `documents/releases.md` for release gates and
compatibility details. The generated [API index](api/) and source revision footer
identify the implementation behind this documentation build.
