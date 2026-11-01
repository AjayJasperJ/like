"""Offline checks for real guide routes, agent exports and build contracts."""
from html.parser import HTMLParser
import json
from pathlib import Path
import tempfile
import unittest
from urllib.parse import unquote, urlsplit
from unittest.mock import patch

from build import build, PAGES, resolve_link


class Page(HTMLParser):
    def __init__(self, content):
        super().__init__()
        self.links, self.ids = [], set()
        self.feed(content)

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if 'id' in attrs:
            self.ids.add(attrs['id'])
        for key in ('href', 'src'):
            if attrs.get(key):
                self.links.append(attrs[key])


class DocumentationBuildTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.output = Path(cls.temp.name)
        with patch.dict('os.environ', {'DOCS_SOURCE_REF': 'test-revision'}):
            cls.records = build(cls.output)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_all_internal_targets_and_anchors_exist(self):
        errors = []
        cache = {}
        for file in self.output.rglob('*.html'):
            page = Page(file.read_text())
            for url in page.links:
                parts = urlsplit(url)
                if parts.scheme or parts.netloc:
                    continue
                if url.startswith('#'):
                    target = file
                else:
                    self.assertTrue(parts.path.startswith('/like/'), url)
                    target = self.output / unquote(parts.path.removeprefix('/like/'))
                    if parts.path.endswith('/'):
                        target /= 'index.html'
                if not target.exists():
                    errors.append((str(file.relative_to(self.output)), url))
                elif parts.fragment and target.suffix == '.html':
                    if target not in cache:
                        cache[target] = Page(target.read_text()).ids
                    if unquote(parts.fragment) not in cache[target]:
                        errors.append((str(file.relative_to(self.output)), url))
        self.assertEqual(errors, [])

    def test_agent_and_search_exports_share_same_pages(self):
        manifest = json.loads((self.output / 'manifest.json').read_text())
        search = json.loads((self.output / 'search.json').read_text())
        self.assertEqual(len(search), len(PAGES))
        self.assertEqual(manifest['source_revision'], 'test-revision')
        full = (self.output / 'llms-full.txt').read_text()
        for record in self.records:
            raw = self.output / 'markdown' / (record['slug'] + '.md')
            self.assertTrue(raw.is_file())
            self.assertIn(raw.read_text(), full)
            self.assertIn(record['title'], full)
        self.assertIn('slowInternet', full)
        self.assertIn('showSlowInternetToasts', full)
        self.assertIn('LikeHttpClient', (self.output / 'markdown/api.md').read_text())

    def test_link_rewrite_handles_repo_files_guides_assets_and_queries(self):
        self.assertEqual(resolve_link('../assets/architecture.svg', 'site/content/architecture.md', '/like/', 'abc'), '/like/assets/architecture.svg')
        self.assertEqual(resolve_link('offline/', 'site/content/overview.md', '/like/', 'abc'), '/like/offline/')
        self.assertIn('/abc/ARCHITECTURE.md', resolve_link('../../ARCHITECTURE.md', 'site/content/architecture.md', '/like/', 'abc'))
        with self.assertRaises(ValueError):
            resolve_link('missing.md', 'site/content/overview.md', '/like/', 'abc')
        with self.assertRaises(ValueError):
            resolve_link('../../../../private', 'site/content/overview.md', '/like/', 'abc')

    def test_root_base_preview(self):
        with tempfile.TemporaryDirectory() as folder:
            build(folder, base='/')
            self.assertIn('href="/assets/style.css?v=', (Path(folder) / 'index.html').read_text())

    def test_generated_sitemap_and_accessible_shell(self):
        self.assertEqual((self.output / 'sitemap.xml').read_text().count('<loc>'), len(PAGES))
        page = (self.output / 'index.html').read_text()
        for token in ['Skip to content', 'aria-current="page"', 'aria-controls="sidebar"', 'aria-live="polite"', 'type="text/markdown"', 'rel="canonical"']:
            self.assertIn(token, page)
        self.assertTrue((self.output / '.nojekyll').exists())
        self.assertIn('assets/app.js?v=', page)
        self.assertIn('assets/style.css?v=', page)


if __name__ == '__main__':
    unittest.main()
