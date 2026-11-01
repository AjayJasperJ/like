# LIKE documentation site

Static HTML, local search and agent-readable context are generated from a single
page manifest. Existing guides in `documents/` are included directly rather than
maintaining a second copy. No runtime CDN, framework, analytics or server is needed.

## Build and verify

```sh
python3 -m venv /tmp/like-docs-venv
/tmp/like-docs-venv/bin/pip install -r site/requirements.txt
/tmp/like-docs-venv/bin/python -m unittest discover -s site -p 'test_*.py'
/tmp/like-docs-venv/bin/python site/build.py
node --check site/assets/app.js
```

For a local preview with no repository base path:

```sh
/tmp/like-docs-venv/bin/python site/build.py --base / --output /tmp/like-docs-preview
python3 -m http.server 8000 --directory /tmp/like-docs-preview
```

Open http://localhost:8000. Stop the server after review. Build outputs are ignored.
Do not add secrets to documentation sources: the website, Markdown and indexes
are public. The raw Markdown/full-context files are produced by the same build.

## GitHub Pages deployment

The Documentation site workflow builds/checks PRs and uploads a review artifact.
Only main/manual main builds deploy. It uses the standard GitHub Pages artifact
and OIDC deployment actions; no personal access token is required.

For first deployment, enable repository **Settings → Pages → Build and deployment
→ Source: GitHub Actions**. The owner may need to permit the `github-pages`
environment to deploy from main. A PR does not publish the site. After merge,
check the deployment action's returned URL before reporting that it is live.
Expected project URL: https://ajayjasperj.github.io/like/.

## Content maintenance

- Add/edit authored guides in `site/content/` and register them in `site/pages.json`.
- Existing deep guides are imported from `documents/`; edit their original source.
- Relative guide links are rewritten to site routes; code links point to the build's commit.
- Public API reference uses pinned tree-sitter Dart grammar to extract exported declarations,
  constructor/method signatures, fields, callback types and parameter metadata. It respects
  show/hide rules, excludes private names, and fails on syntax extraction errors.
  It is not full Dartdoc and does not duplicate inherited Flutter APIs.
- `api-reference.json` is generated alongside the HTML and agent Markdown.
- Keep `tokenStore`, repository and toast-handler placeholders explicitly identified.
- Run build tests: they check internal destinations/fragments, agent/search parity,
  raw Markdown, source revision metadata and root/subpath behavior.
- Review mobile navigation, search (Ctrl/Cmd+K or /), keyboard focus, theme switching,
  code/page copy and raw Markdown links before release.

The current site describes the source version/revision in its manifest and footer;
it does not assert that every platform/API combination has passed CI or shipped
on pub.dev. Existing implementation/pending reports are historical evidence, not
site navigation or a live build-status database.
