#!/usr/bin/env python3
"""Check the actual App Store signatures and entitlements of an exported IPA."""
import argparse
import datetime
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {
    'com.minseo.PiyakBank': ('PiyakBank/PiyakBank.entitlements', '17.0'),
    'com.minseo.PiyakBank.watchkitapp': (
        'PiyakWatch Watch App/PiyakWatch Watch App.entitlements', '10.0'),
    'com.minseo.PiyakBank.PiyakWidget': ('PiyakWidgetExtension.entitlements', '17.0'),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def plist_command(*command):
    result = subprocess.run(command, check=True, capture_output=True)
    return plistlib.loads(result.stdout)


def verify(ipa, team):
    with zipfile.ZipFile(ipa) as package:
        for name in package.namelist():
            path = Path(name)
            require(not path.is_absolute() and '..' not in path.parts,
                    'Unsafe path in IPA')
    with tempfile.TemporaryDirectory(prefix='piyak-ipa-check-') as temporary:
        subprocess.run(['ditto', '-x', '-k', str(ipa), temporary], check=True)
        payload = Path(temporary) / 'Payload'
        bundles = sorted(path for path in payload.rglob('*')
                         if path.is_dir() and path.suffix in ('.app', '.appex'))
        require(len(bundles) == len(TARGETS), 'Expected app, Watch app and widget')
        found, versions, results = set(), set(), []
        for bundle in bundles:
            info = plistlib.loads((bundle / 'Info.plist').read_bytes())
            identifier = info['CFBundleIdentifier']
            require(identifier in TARGETS and identifier not in found,
                    f'Unexpected or duplicate bundle: {identifier}')
            found.add(identifier)
            source_path, minimum_os = TARGETS[identifier]
            source = plistlib.loads((ROOT / source_path).read_bytes())
            subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
            entitlements = plist_command('codesign', '-d', '--entitlements', ':-', str(bundle))
            profile = plist_command('security', 'cms', '-D', '-i',
                                    str(bundle / 'embedded.mobileprovision'))
            allowed = profile['Entitlements']
            app_id = f'{team}.{identifier}'
            require(entitlements.get('application-identifier') == app_id
                    and allowed.get('application-identifier') == app_id,
                    f'{identifier}: application identifier mismatch')
            require(entitlements.get('com.apple.developer.team-identifier') == team
                    and profile.get('TeamIdentifier') == [team],
                    f'{identifier}: team mismatch')
            require(entitlements.get('get-task-allow') is False
                    and allowed.get('get-task-allow') is False,
                    f'{identifier}: debugging entitlement is enabled or missing')
            require(allowed.get('beta-reports-active') is True
                    and 'ProvisionedDevices' not in profile
                    and not profile.get('ProvisionsAllDevices', False),
                    f'{identifier}: not an App Store distribution profile')
            require(profile['ExpirationDate'] > datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
                    f'{identifier}: expired provisioning profile')
            for key, value in source.items():
                require(entitlements.get(key) == value and allowed.get(key) == value,
                        f'{identifier}: source entitlement missing or mismatched: {key}')
            require(info.get('MinimumOSVersion') == minimum_os,
                    f'{identifier}: unexpected minimum OS')
            require((bundle / 'PrivacyInfo.xcprivacy').is_file(),
                    f'{identifier}: privacy manifest missing')
            require((bundle / info['CFBundleExecutable']).is_file(),
                    f'{identifier}: executable missing')
            version = (info['CFBundleShortVersionString'], info['CFBundleVersion'])
            versions.add(version)
            results.append({'bundle': identifier, 'version': version[0], 'build': version[1],
                            'appGroups': entitlements.get('com.apple.security.application-groups'),
                            'profile': profile['Name'], 'verified': True})
        require(found == set(TARGETS), 'Expected target is missing')
        require(len(versions) == 1, 'App, Watch and widget versions do not match')
        return results


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa', type=Path)
    parser.add_argument('--team', required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify(arguments.ipa.resolve(), arguments.team), ensure_ascii=False, indent=2))
