import copy
import json
import unittest
from pathlib import Path
from generate import generate

class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.spec = json.loads(Path(__file__).with_name('fixture.json').read_text())
    def test_deterministic_typed_contract(self):
        result = generate(self.spec)
        self.assertEqual(result, generate(copy.deepcopy(self.spec)))
        self.assertIn('Future<ApiResult<FixtureItem>> getItem', result)
        self.assertIn('cacheTags:', result)
        self.assertIn('Uri.encodeComponent', result)
    def test_refuses_implicit_cache_policy(self):
        del self.spec['paths']['/items/{id}']['get']['x-like-policy']
        with self.assertRaises(ValueError): generate(self.spec)
    def test_refuses_unsupported_union(self):
        self.spec['components']['schemas']['FixtureItem']['properties']['title'] = {'oneOf': [{'type':'string'},{'type':'integer'}]}
        with self.assertRaises(ValueError): generate(self.spec)
    def test_refuses_external_reference(self):
        self.spec['paths']['/items/{id}']['get']['responses']['200']['content']['application/json']['schema'] = {'$ref':'https://example.invalid/schema.json'}
        with self.assertRaises(ValueError): generate(self.spec)
    def test_refuses_invalid_identifier(self):
        self.spec['paths']['/items/{id}']['get']['operationId'] = 'class'
        with self.assertRaises(ValueError): generate(self.spec)
if __name__ == '__main__': unittest.main()
