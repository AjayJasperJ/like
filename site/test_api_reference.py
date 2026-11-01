import json
from pathlib import Path
import tempfile
import unittest

from api_reference import parse_library, exported_api, render_reference

ROOT = Path(__file__).resolve().parents[1]


class ApiReferenceTest(unittest.TestCase):
    def test_signatures_parameters_callbacks_and_defaults(self):
        source = '''
/// A widget contract.
class Card<T> extends StatelessWidget {
  /// Receives data and an optional count.
  final void Function(T data, {int count})? callback;
  final bool enabled;
  final Map<String, List<int>> values;
  const Card({super.key, required this.callback, this.enabled = true,
    this.values = const {'a': [1, 2]}});
  Card._private();
  Future<List<T>> load(int page, {required String query, Duration? timeout,
    void Function(T, int)? onItem}) async { throw UnimplementedError(); }
  static String label([String value = 'a,b']) => value;
  bool get isEnabled => enabled;
  void _hidden() {}
}
'''
        card = parse_library(source, 'lib/card.dart')[0]
        self.assertTrue(card['widget'])
        methods = {m['name']: m for m in card['members']}
        self.assertNotIn('Card._private', methods)
        self.assertNotIn('_hidden', methods)
        self.assertNotIn('throw', methods['load']['signature'])
        params = {p['name']: p for p in methods['Card']['parameters']}
        self.assertTrue(params['callback']['required'])
        self.assertIn('Function(T data, {int count})?', params['callback']['type'])
        self.assertEqual(params['enabled']['default'], 'true')
        self.assertEqual(params['values']['default'], "const {'a': [1, 2]}")
        self.assertEqual(params['key']['type'], 'inherited; see superclass')
        load = {p['name']: p for p in methods['load']['parameters']}
        self.assertEqual(load['page']['kind'], 'positional')
        self.assertTrue(load['query']['required'])
        self.assertFalse(load['timeout']['required'])
        self.assertEqual(load['onItem']['type'], 'void Function(T, int)?')
        self.assertEqual(methods['label']['parameters'][0]['default'], "'a,b'")
        self.assertFalse(methods['label']['parameters'][0]['required'])
        self.assertIn('static String label', methods['label']['signature'])

    def test_private_initializing_formals_use_public_call_names(self):
        source = 'class Store { final String _key; Store({required this._key}); }'
        store = parse_library(source, 'lib/store.dart')[0]
        self.assertNotIn('_key', [m['name'] for m in store['members']])
        param = store['members'][0]['parameters'][0]
        self.assertEqual(param['name'], 'key')
        self.assertEqual(param['type'], 'String')

    def test_export_show_hide_transitive_and_testing_only(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'lib').mkdir()
            (root / 'lib/like.dart').write_text("export 'types.dart' show Visible; export 'more.dart' hide Hidden;")
            (root / 'lib/testing.dart').write_text("export 'like.dart'; export 'test.dart';")
            (root / 'lib/types.dart').write_text('class Visible {} class NotExported {} class _Private {}')
            (root / 'lib/more.dart').write_text('class Other {} class Hidden {}')
            (root / 'lib/test.dart').write_text('class TestOnly {}')
            symbols = {s['name']: s for s in exported_api(root)['symbols']}
            self.assertEqual(set(symbols), {'Visible', 'Other', 'TestOnly'})
            self.assertEqual(symbols['TestOnly']['entrypoints'], ['package:like/testing.dart'])

    def test_repository_widgets_and_core_signatures_are_complete(self):
        api = exported_api(ROOT)
        symbols = {s['name']: s for s in api['symbols']}
        self.assertIn('LikeBuilder', symbols)
        self.assertIn('LikeStateResponseBuilderSliver', symbols)
        self.assertIn('LikeCacheImage', symbols)
        self.assertNotIn('LikeSyncTask', symbols)  # Only LikeSyncPriority is exported.
        self.assertIn('LikeSyncPriority', symbols)
        self.assertNotIn('_LikeState', symbols)
        self.assertNotIn('LikeSelector', symbols)  # Do not invent absent widgets.
        client = symbols['LikeClient']
        names = [m['name'] for m in client['members']]
        self.assertEqual(names.count('LikeClient'), 1)
        self.assertIn('LikeClient.scoped', names)
        self.assertFalse(any('_internal' in x for x in names))
        get = next(m for m in client['members'] if m['name'] == 'get')
        self.assertTrue({'path', 'cancelToken', 'requestConfig', 'staleWhileRevalidate'}.issubset({p['name'] for p in get['parameters']}))
        ctor = next(m for m in symbols['LikeConfig']['members'] if m['name'] == 'LikeConfig')
        params = {p['name']: p for p in ctor['parameters']}
        self.assertTrue(params['projectName']['required'])
        self.assertEqual(params['maxAutoRetries']['default'], '3')
        self.assertEqual(params['cacheTTL']['default'], '7')
        self.assertEqual(next(m for m in symbols['LikeToastConfig']['members'] if m['name']=='slowInternet')['type'], 'void Function(String message)?')

    def test_reference_contains_signatures_tables_and_structured_data(self):
        markdown, api = render_reference(ROOT, 'abc', 'https://github.com/AjayJasperJ/like')
        self.assertIn('## Widgets', markdown)
        self.assertIn('### LikeBuilder', markdown)
        self.assertIn('Required | Explicit default', markdown)
        self.assertIn('required this.onSuccess', markdown)
        self.assertIn('Future<LikeApiResult<Response>> get(', markdown)
        self.assertIn('id="api-filter"', markdown)
        self.assertIn('/blob/abc/', markdown)
        self.assertGreater(len(api['symbols']), 90)
        json.dumps(api)

    def test_implicit_constructor_is_labelled_and_private_only_is_not_exposed(self):
        items = parse_library('class Implicit {} class PrivateOnly { PrivateOnly._(); }', 'lib/test.dart')
        self.assertTrue(items[0]['members'][0]['implicit'])
        self.assertEqual(items[1]['members'], [])

    def test_syntax_errors_fail_instead_of_silently_omitting_members(self):
        with self.assertRaises(ValueError):
            parse_library('class Broken { void method( {', 'broken.dart')


if __name__ == '__main__':
    unittest.main()
