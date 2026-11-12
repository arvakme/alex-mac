#!/usr/bin/env python3
"""Build the universal application bundle; never install or change system settings.

Development (default): build/Alex.app as com.kazelis.alex, signed with the single local Apple Development
identity when there is one, else ad-hoc; ALEX_SIGN_IDENTITY overrides.
Release (--release): dist/app/Alex.app as com.kazelis.alex.release, signed with the Developer ID Application
certificate of team WK58796PBF from the login keychain, with the hardened runtime and a secure timestamp so it
can be notarized.

macOS keeps Accessibility grants per bundle id and designated requirement. An ad-hoc requirement names one exact
build, so every update would lose the grant; a Developer ID requirement names the bundle id and the team, so it
stays the same across versions and certificate renewals, and the in-app updater installs only builds that satisfy it. Development and release never share an id or a path,
because a copy signed differently under the development id invalidates the development grant on the same Mac.
"""
from pathlib import Path
import argparse
import hashlib
import os
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
VARIANTS = {
    'development': (ROOT / 'build/Alex.app', 'com.kazelis.alex'),
    'release': (ROOT / 'dist/app/Alex.app', 'com.kazelis.alex.release'),
}
VERSION = '0.1.4'
# Users' Accessibility grants and the updater trust this team: never sign a release with another.
RELEASE_IDENTITY = 'Developer ID Application: zhijie ma (WK58796PBF)'
SWIFT_BUILD = ['xcrun', 'swift', 'build', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64']


def development_identity():
    if identity := os.environ.get('ALEX_SIGN_IDENTITY'):
        return identity
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    developers = re.findall(r'([A-F0-9]{40}) "Apple Development:', identities)
    return developers[0] if len(developers) == 1 else '-'


def sign(bundle, identifier, identity, *options):
    subprocess.run(['codesign', '--force', *options, '--sign', identity, '--identifier', identifier, str(bundle)], check=True)


def revision():
    fingerprint = hashlib.sha256()
    for source in sorted((ROOT / 'Sources').rglob('*.swift')):
        fingerprint.update(source.relative_to(ROOT).as_posix().encode())
        fingerprint.update(source.read_bytes())
    return fingerprint.hexdigest()[:12]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--release', action='store_true', help='Developer ID signed copy for the DMG and updater, under its own bundle id')
    release = parser.parse_args().release
    bundle, identifier = VARIANTS['release' if release else 'development']
    os.chdir(ROOT)
    subprocess.run(SWIFT_BUILD, check=True)
    bin_path = subprocess.check_output([*SWIFT_BUILD, '--show-bin-path'], text=True).strip()
    if bundle.exists():
        shutil.rmtree(bundle)
    contents = bundle / 'Contents'
    for directory in ['MacOS', 'Resources']:
        (contents / directory).mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(bin_path) / 'alex', contents / 'MacOS/alex')
    for source in (ROOT / 'Resources').iterdir():
        if source.is_file():
            shutil.copy2(source, contents / 'Resources' / source.name)
    source_revision = revision()
    info = {
        'CFBundleExecutable': 'alex', 'CFBundleIdentifier': identifier,
        'CFBundleName': 'Alex', 'CFBundleDisplayName': 'Alex', 'CFBundlePackageType': 'APPL',
        'CFBundleShortVersionString': VERSION, 'CFBundleVersion': VERSION,
        'AlexRevision': source_revision, 'LSMinimumSystemVersion': '26.0', 'LSUIElement': True,
        'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True,
        'CFBundleIconFile': 'AppIcon',
        'NSAccessibilityUsageDescription': 'alex 仅在划词时读取选中文字及可验证的所在句子。',
    }
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    if release:
        sign(bundle, identifier, RELEASE_IDENTITY, '--options', 'runtime', '--timestamp')
        print('Signing: Developer ID')
    else:
        identity = development_identity()
        sign(bundle, identifier, identity, '--timestamp=none')
        print('Signing: Apple Development' if identity != '-' else 'Signing: ad-hoc (Keychain may require re-entry after rebuilding)')
    subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
    print(f'Built {bundle} ({identifier})\nSource revision: {source_revision}')


if __name__ == '__main__':
    main()
