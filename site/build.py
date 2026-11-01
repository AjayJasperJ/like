"""Build static human/agent documentation from repository-owned Markdown."""
import argparse
import html
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from urllib.parse import urlsplit, quote

import markdown

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site'
REPO = 'https://github.com/AjayJasperJ/like'
PAGES = json.loads((SITE / 'pages.json').read_text())
SLUGS = {p[0] for p in PAGES}
SOURCES = {p[3]: p[0] for p in PAGES if not p[3].startswith('@')}


def source_ref():
    return os.environ.get('DOCS_SOURCE_REF') or subprocess.check_output(
        ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def api_index(ref):
    lines = ['# Public API source index', '',
             'This index is derived from the exports in `lib/like.dart` and `lib/testing.dart`.',
             'It links to exact source contracts; it is **not** generated Dartdoc or a promise',
             'that every symbol in a library is exported (check `show`/`hide` clauses).', '']
    for entry in ['lib/like.dart', 'lib/testing.dart']:
        lines += ['## ' + entry, '']
        for rel in re.findall(r"^export '([^']+)'[^;]*;", (ROOT / entry).read_text(), re.M):
            if rel.startswith('package:'):
                continue
            path = (Path(entry).parent / rel).as_posix()
            source = ROOT / path
            if not source.is_file():
                raise ValueError('Export target missing: ' + path)
            text = source.read_text()
            symbols = re.findall(r'^(?:(?:abstract|final|base|sealed|interface)\s+)*(?:class|enum|mixin|typedef|extension)\s+([A-Za-z]\w*)', text, re.M)
            lines += ['### ' + ('LikeConfig' if path == 'lib/src/core/like_config.dart' else (symbols[0] if symbols else source.stem)), '',
                      f'[{path}]({REPO}/blob/{ref}/{path})', '',
                      'Declared types: ' + (', '.join('`' + x + '`' for x in symbols) or 'See source') + '.', '']
            if path == 'lib/src/core/like_config.dart':
                begin = text.index('  LikeConfig({')
                end = text.index('  })', begin)
                lines += ['Constructor defaults for the full configuration surface:', '', '```dart', text[begin:end] + '  });', '```', '']
    lines += ['## Complete injectable HTTP contract', '', 'The following contract is copied from the source for this build. Concrete client helpers are linked above.', '', '```dart', (ROOT / 'lib/src/client/like_http_client.dart').read_text(), '```', '']
    return '\n'.join(lines)


def resolve_link(value, source, base, ref):
    parsed = urlsplit(value)
    if parsed.scheme or parsed.netloc or value.startswith(('#', 'mailto:')):
        return value
    path, frag = parsed.path, ('#' + parsed.fragment if parsed.fragment else '')
    if not path:
        return value
    if path.startswith(base):
        return value
    route = path.strip('/')
    if route in SLUGS:
        return base + ('' if route == 'overview' else route + '/') + frag
    if route.startswith('assets/') or route in ['llms.txt', 'llms-full.txt', 'manifest.json', 'search.json', 'sitemap.xml']:
        return base + route + frag
    if path.startswith('../assets/'):
        return base + path.removeprefix('../')
    target = (ROOT / source).parent.joinpath(path).resolve()
    if not target.is_relative_to(ROOT):
        raise ValueError('Link escapes source repository: ' + value)
    relative = target.relative_to(ROOT).as_posix()
    if relative in SOURCES:
        slug = SOURCES[relative]
        return base + ('' if slug == 'overview' else slug + '/') + frag
    if target.exists():
        kind = 'tree' if target.is_dir() else 'blob'
        return f'{REPO}/{kind}/{ref}/{quote(relative)}' + frag
    # Assets in authored HTML are relative to the rendered page, not source Markdown.
    if path.startswith('../assets/'):
        return base + path.removeprefix('../')
    raise ValueError(f'Broken content link in {source}: {value}')


class LinkRewriter(HTMLParser):
    def __init__(self, source, base, ref):
        super().__init__(convert_charrefs=False)
        self.source, self.base, self.ref, self.parts = source, base, ref, []

    def handle_starttag(self, tag, attrs):
        out = []
        for key, value in attrs:
            if value is not None and key in ('href', 'src'):
                value = resolve_link(value, self.source, self.base, self.ref)
            out.append(key if value is None else f'{key}="{html.escape(value, quote=True)}"')
        self.parts.append('<' + tag + (' ' + ' '.join(out) if out else '') + '>')

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.parts.append('</' + tag + '>')

    def handle_data(self, data):
        self.parts.append(data)

    def handle_entityref(self, name):
        self.parts.append('&' + name + ';')

    def handle_charref(self, name):
        self.parts.append('&#' + name + ';')


def build(output, base='/like/', origin='https://ajayjasperj.github.io'):
    if not base.startswith('/') or not base.endswith('/'):
        raise ValueError('Base must start and end with /')
    ref = source_ref()
    version = re.search(r'^version:\s*(\S+)', (ROOT / 'pubspec.yaml').read_text(), re.M)[1]
    output = Path(output).resolve()
    if output in (ROOT, SITE) or ROOT.is_relative_to(output):
        raise ValueError('Unsafe output directory')
    output.mkdir(parents=True, exist_ok=True)
    shutil.copytree(SITE / 'assets', output / 'assets', dirs_exist_ok=True)
    (output / 'markdown').mkdir(exist_ok=True)
    records, full = [], []
    for index, (slug, title, group, source) in enumerate(PAGES):
        text = api_index(ref) if source == '@api' else (ROOT / source).read_text()
        if text.count('```') % 2:
            raise ValueError('Unbalanced fences in ' + source)
        effective_source = source if source != '@api' else 'site/content/api.md'
        md = markdown.Markdown(extensions=['fenced_code', 'tables', 'toc', 'sane_lists'])
        body = md.convert(text)
        rewrite = LinkRewriter(effective_source, base, ref)
        rewrite.feed(body)
        body = ''.join(rewrite.parts)
        route = '' if slug == 'overview' else slug + '/'
        canonical = origin + base + route
        raw = re.sub(r'\]\(([^)]+)\)', lambda m: '](' + resolve_link(m[1], effective_source, base, ref).replace(base, origin + base, 1) + ')' if not urlsplit(m[1]).scheme and not m[1].startswith('#') else m[0], text)
        (output / 'markdown' / (slug + '.md')).write_text(raw)
        full.append(f'\n\n---\nPage: {title}\nURL: {canonical}\nSource: {source}\n\n' + raw)
        plain = re.sub(r'<[^>]+>', ' ', body)
        plain = html.unescape(re.sub(r'\s+', ' ', plain)).strip()
        records.append({'slug': slug, 'title': title, 'group': group, 'url': base + route,
                        'markdown': base + 'markdown/' + slug + '.md', 'source': source, 'text': plain})
        nav, last = [], None
        for nav_slug, label, section, _ in PAGES:
            if section != last:
                nav.append('<p class="nav-group">' + html.escape(section) + '</p>')
                last = section
            href = base + ('' if nav_slug == 'overview' else nav_slug + '/')
            nav.append(f'<a href="{href}"' + (' aria-current="page"' if nav_slug == slug else '') + '>' + html.escape(label) + '</a>')
        previous = PAGES[index - 1] if index else None
        following = PAGES[index + 1] if index + 1 < len(PAGES) else None
        pager = ''
        for entry, label in [(previous, 'Previous'), (following, 'Next')]:
            if entry:
                target = base + ('' if entry[0] == 'overview' else entry[0] + '/')
                pager += f'<a href="{target}"><span>{label}</span><strong>{html.escape(entry[1])}</strong></a>'
        src = 'lib/like.dart' if source == '@api' else source
        description = plain[:165]
        page = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)} · LIKE Docs</title><meta name="description" content="{html.escape(description, quote=True)}">
<link rel="canonical" href="{canonical}"><meta name="color-scheme" content="light dark">
<link rel="icon" href="{base}assets/favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="{base}assets/style.css"><script defer src="{base}assets/app.js"></script>
<link rel="alternate" type="text/markdown" href="{base}markdown/{slug}.md" title="Markdown source">
</head><body data-base="{base}"><a class="skip" href="#main">Skip to content</a>
<header><a class="brand" href="{base}"><span class="logo">L<span>↗</span></span><strong>LIKE<span> / docs</span></strong></a>
<span class="version">v{version}</span><button class="search-open" aria-label="Search documentation">Search documentation <kbd>⌘ K</kbd></button>
<a class="header-link" href="{base}agents/">For agents ↗</a><a class="header-link" href="{REPO}">GitHub ↗</a>
<button id="theme" aria-label="Switch color theme">◐</button><button id="menu" aria-controls="sidebar" aria-expanded="false">Menu</button></header>
<button id="nav-backdrop" aria-label="Close navigation" tabindex="-1" hidden></button>
<div class="layout"><nav id="sidebar" aria-label="Documentation"><button id="nav-close" type="button">Close menu</button>{''.join(nav)}<div class="nav-bottom">Built for Flutter.<br>Readable by people and agents.</div></nav>
<main id="main"><div class="eyebrow">{html.escape(group)} <span> / {index + 1:02d}</span></div>
<div class="page-tools"><a href="{base}markdown/{slug}.md">View Markdown</a><button id="copy-page" data-url="{base}markdown/{slug}.md">Copy page</button></div>
<article>{body}</article><div class="pager">{pager}</div><footer>LIKE {version} · <a href="{REPO}/blob/{ref}/{src}">Source {ref[:7]}</a> · <a href="{base}llms.txt">llms.txt</a><br>This page describes source behavior; publication and CI status are separate.</footer></main>
<aside class="on-this-page"><p>ON THIS PAGE</p>{md.toc}<a class="agent-box" href="{base}agents/">Working with an agent?<br><strong>Get the source context ↗</strong></a></aside></div>
<dialog id="search"><div class="search-head"><label for="search-input">Search LIKE</label><button id="search-close" aria-label="Close search">Esc</button></div><input id="search-input" type="search" placeholder="Try: slow internet, offline queue, Riverpod" autocomplete="off"><p id="search-status" role="status">Search guides, APIs and examples.</p><ul id="search-results"></ul></dialog>
<div id="notice" role="status" aria-live="polite"></div></body></html>'''
        folder = output / route
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'index.html').write_text(page)
    (output / 'search.json').write_text(json.dumps(records, ensure_ascii=False))
    (output / 'manifest.json').write_text(json.dumps({'package': 'like', 'version': version,
        'source_revision': ref, 'canonical_base': origin + base,
        'pages': [{k: v for k, v in x.items() if k != 'text'} for x in records]}, indent=2))
    llms = f'# LIKE documentation\n\n> Flutter networking, caching, offline replay and state coordination.\n\nSource version: {version}; revision: {ref}.\n\nRequires Flutter >=3.44.1 and Dart >=3.12.\nSource presence does not imply pub.dev publication.\n\n## Read first\n\n- Inject LikeHttpClient into services; repositories depend on contracts.\n- Set stable session scope after login; propagate cancellation and dispose owned resources.\n- Auth and durable replay require explicit request flags. Queued is not acknowledged.\n- Diagnostic redaction does not encrypt caches or secure a compromised device.\n- This is not a browser engine; CORS and platform restrictions apply.\n\n## Guides\n\n'
    llms += '\n'.join(f'- [{x["title"]}]({origin}{x["markdown"]}): {x["group"]}' for x in records)
    llms += f'\n\nFull context: {origin}{base}llms-full.txt\nBuild manifest: {origin}{base}manifest.json\n'
    (output / 'llms.txt').write_text(llms)
    (output / 'llms-full.txt').write_text(llms + ''.join(full))
    (output / 'sitemap.xml').write_text('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">' + ''.join('<url><loc>' + html.escape(origin + x['url']) + '</loc></url>' for x in records) + '</urlset>')
    (output / 'robots.txt').write_text('User-agent: *\nAllow: /\nSitemap: ' + origin + base + 'sitemap.xml\n')
    (output / '.nojekyll').write_text('')
    print(f'Built {len(records)} pages, Markdown, search, llms and sitemap in {output}')
    return records


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default=str(SITE / '_build'))
    parser.add_argument('--base', default='/like/')
    args = parser.parse_args()
    build(args.output, args.base)
