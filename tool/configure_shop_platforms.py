"""Apply app-owned release network permission to Flutter-generated wrappers."""
import sys
from pathlib import Path
app = Path(sys.argv[1])
manifest = app / 'android/app/src/main/AndroidManifest.xml'
text = manifest.read_text()
if 'android.permission.INTERNET' not in text:
    text = text.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
manifest.write_text(text)
