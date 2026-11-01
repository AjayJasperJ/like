"""Print direct dependency lower-bound SDK requirements for CI diagnosis.

The actual minimum-SDK pub get/test job remains the compatibility gate. This
metadata report also shows every lower bound instead of stopping at the first
solver conflict. Reads only the simple hosted declarations in this pubspec.
"""
import json
import re
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

active = False
for line in Path('pubspec.yaml').read_text().splitlines():
    if line and not line.startswith(' '):
        active = line in ('dependencies:', 'dev_dependencies:')
        continue
    if not active:
        continue
    match = re.match(r'^  ([a-z_][a-z_0-9]*):\s*(.+)$', line)
    if not match:
        continue
    name, constraint = match.groups()
    version = re.search(r'\d+\.\d+\.\d+(?:\+[0-9]+)?', constraint)
    if not version:
        continue
    url = 'https://pub.dev/api/packages/' + name + '/versions/' + quote(version[0], safe='')
    try:
        request = Request(url, headers={'User-Agent': 'Mozilla/5.0 LIKE-CI/1.0'})
        with urlopen(request, timeout=10) as response:
            package = json.load(response)
        environment = package['pubspec'].get('environment', {})
        print(name + ' ' + version[0] + ': ' + json.dumps(environment, sort_keys=True))
    except Exception as error:
        print(name + ': metadata unavailable (' + type(error).__name__ + ')')
