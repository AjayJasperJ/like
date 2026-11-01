"""Require a matching version/tag and versioned release notes before publication."""
import re
import sys
from pathlib import Path
version = re.search(r'^version:\s*(\S+)', Path('pubspec.yaml').read_text(), re.M).group(1)
if len(sys.argv) > 1 and sys.argv[1] != 'v' + version:
    raise SystemExit('Release tag must match pubspec version')
if not re.search(r'^##\s+\[?' + re.escape(version) + r'\]?(?:\s+-[^\n]+)?\s*$', Path('CHANGELOG.md').read_text(), re.M):
    raise SystemExit('Add a CHANGELOG section for the package version')
print('PASS: package version, changelog and optional tag agree')
