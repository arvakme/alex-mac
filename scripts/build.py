#!/usr/bin/env python3
"""Build the universal application bundle; never install or change system settings.

Signs with the single local Apple Development identity when there is one, else ad-hoc;
ALEX_SIGN_IDENTITY overrides (`-` forces ad-hoc, as the release does)."""
from pathlib import Path
import hashlib
import os
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)
SWIFT_BUILD = ['xcrun', 'swift', 'build', '-c', 'release', '--arch', 'arm64', '--arch', 'x86_64']
subprocess.run(SWIFT_BUILD, check=True)
bin_path = subprocess.check_output([*SWIFT_BUILD, '--show-bin-path'], text=True).strip()
bundle = ROOT / 'build/Alex.app'
if bundle.exists():
    shutil.rmtree(bundle)
contents = bundle / 'Contents'
for directory in ['MacOS', 'Resources']:
    (contents / directory).mkdir(parents=True, exist_ok=True)
shutil.copy2(Path(bin_path) / 'alex', contents / 'MacOS/alex')
for source in (ROOT / 'Resources').iterdir():
    if source.is_file():
        shutil.copy2(source, contents / 'Resources' / source.name)
fingerprint = hashlib.sha256()
for source in sorted((ROOT / 'Sources').rglob('*.swift')):
    fingerprint.update(source.relative_to(ROOT).as_posix().encode())
    fingerprint.update(source.read_bytes())
revision = fingerprint.hexdigest()[:12]
info = {
    'CFBundleExecutable': 'alex', 'CFBundleIdentifier': 'com.kazelis.alex',
    'CFBundleName': 'Alex', 'CFBundleDisplayName': 'Alex', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '1',
    'AlexRevision': revision, 'LSMinimumSystemVersion': '26.0', 'LSUIElement': True,
    'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True,
    'CFBundleIconFile': 'AppIcon',
    'NSAccessibilityUsageDescription': 'alex 仅在划词时读取选中文字及可验证的所在句子。',
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
identity = os.environ.get('ALEX_SIGN_IDENTITY')
if not identity:
    identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
    developers = re.findall(r'([A-F0-9]{40}) "Apple Development:', identities)
    identity = developers[0] if len(developers) == 1 else '-'
subprocess.run(['codesign', '--force', '--sign', identity, '--identifier', 'com.kazelis.alex', str(bundle)], check=True)
print('Signing: Apple Development' if identity != '-' else 'Signing: ad-hoc (Keychain may require re-entry after rebuilding)')
subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
print(f'Built {bundle}\nSource revision: {revision}')
