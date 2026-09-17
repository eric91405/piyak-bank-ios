#!/usr/bin/env python3
"""Validate release resources using only Python's standard library."""
import json
import plistlib
import re
import struct
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'PiyakBank/Shared/Economy.swift').read_text()
ids = re.findall(r'\.init\(id: "([A-Za-z]+\.[a-z_]+)"', source)
assert len(ids) == len(set(ids)) == 81, 'Catalog IDs changed; review migration and screenshots.'
generated = json.loads((ROOT / 'scripts/generated_assets.json').read_text())
assert generated['catalogIds'] == sorted(ids), 'Regenerate previews after changing the catalog.'
for path, digest in generated['sources'].items():
    assert hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == digest, f'{path} changed; regenerate matching previews.'
for item_id in ids:
    folder = ROOT / 'PiyakBank/Assets.xcassets' / ('thumb_' + item_id.replace('.', '_') + '.imageset')
    images = json.loads((folder / 'Contents.json').read_text())['images']
    assert all((folder / image['filename']).is_file() for image in images)
for target in ('PiyakBank', 'PiyakWatch Watch App'):
    folder = ROOT / target / 'Assets.xcassets/AppIcon.appiconset'
    image = json.loads((folder / 'Contents.json').read_text())['images'][0]
    data = (folder / image['filename']).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', data[16:24]) == (1024, 1024)
    assert data[25] == 2, 'App icon must be RGB without alpha.'
for target in ('PiyakBank', 'PiyakWatch Watch App', 'PiyakWidget'):
    manifest = plistlib.loads((ROOT / target / 'PrivacyInfo.xcprivacy').read_bytes())
    assert manifest['NSPrivacyTracking'] is False
    assert not manifest['NSPrivacyCollectedDataTypes']
    reasons = manifest['NSPrivacyAccessedAPITypes'][0]['NSPrivacyAccessedAPITypeReasons']
    assert set(reasons) == {'CA92.1', '1C8F.1'}
    if target == 'PiyakBank':
        APIs = {entry['NSPrivacyAccessedAPIType']: entry['NSPrivacyAccessedAPITypeReasons']
                for entry in manifest['NSPrivacyAccessedAPITypes']}
        assert APIs.get('NSPrivacyAccessedAPICategorySystemBootTime') == ['35F9.1'], 'Declare elapsed-time measurement for rewards and interactions.'
info = plistlib.loads((ROOT / 'PiyakBank/Info.plist').read_bytes())
assert 'piyakbank' in info['CFBundleURLTypes'][0]['CFBundleURLSchemes']
assert not (ROOT / 'PiyakBank/Services/Products.storekit').exists()
print('81 item previews, both opaque icons, three privacy manifests and URL scheme: OK')
