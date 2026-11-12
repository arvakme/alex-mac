#!/usr/bin/env python3
"""Package the release build (dist/app/Alex.app, com.kazelis.alex.release) into dist/Alex-<version>.dmg with a
drag-to-Applications window, plus dist/Alex-<version>.zip for the in-app updater. build/ is never touched.

The app is notarized and stapled before it goes into either file, and the DMG is signed, notarized and stapled
too, so Gatekeeper opens both without a network check. Notarization reads the App Store Connect credentials
stored in the login keychain as the notarytool profile alex-notary.

Finder writes the window layout, so this needs a logged-in Mac session where Finder automation is allowed."""
from pathlib import Path
import hashlib
import os
import plistlib
import subprocess
import tempfile

from build import RELEASE_IDENTITY

ROOT = Path(__file__).resolve().parent.parent
VOLUME = 'Alex'
WINDOW = (640, 400)  # matches packaging/dmg-background.tiff
LAYOUT = f'''
tell application "Finder"
    tell disk "{VOLUME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        set the bounds of container window to {{200, 120, {200 + WINDOW[0]}, {120 + WINDOW[1] + 28}}}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "Alex.app" of container window to {{160, 190}}
        set position of item "Applications" of container window to {{480, 190}}
        update without registering applications
        delay 1
        close
    end tell
end tell
'''


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def notarize(path):
    """Submits to Apple, waits for the verdict, and staples the ticket so the first launch needs no network."""
    run('xcrun', 'notarytool', 'submit', str(path), '--keychain-profile', 'alex-notary', '--wait')
    target = path.with_suffix('.app') if path.suffix == '.zip' else path
    run('xcrun', 'stapler', 'staple', str(target))


def main():
    os.chdir(ROOT)
    run('python3', 'scripts/build.py', '--release')
    app = ROOT / 'dist/app/Alex.app'
    version = plistlib.loads((app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    mount = Path('/Volumes') / VOLUME
    if mount.exists():
        raise SystemExit(f'{mount} is already mounted; eject it first')
    dist = ROOT / 'dist'
    dist.mkdir(exist_ok=True)
    submission = app.with_suffix('.zip')
    run('ditto', '-c', '-k', '--keepParent', str(app), str(submission))
    try:
        notarize(submission)
    finally:
        submission.unlink(missing_ok=True)
    dmg = dist / f'Alex-{version}.dmg'
    with tempfile.TemporaryDirectory() as tmp:
        stage, rw = Path(tmp) / 'stage', Path(tmp) / 'rw.dmg'
        run('ditto', str(app), str(stage / 'Alex.app'))
        (stage / 'Applications').symlink_to('/Applications')
        run('ditto', str(ROOT / 'packaging/dmg-background.tiff'), str(stage / '.background/background.tiff'))
        run('chflags', 'hidden', str(stage / '.background'))
        # Room for the .DS_Store Finder writes on top of the copied files.
        size = int(subprocess.check_output(['du', '-sm', str(stage)], text=True).split()[0]) + 20
        run('hdiutil', 'create', '-quiet', '-srcfolder', str(stage), '-volname', VOLUME, '-fs', 'HFS+',
            '-format', 'UDRW', '-size', f'{size}m', str(rw))
        run('hdiutil', 'attach', '-quiet', '-readwrite', '-noverify', '-noautoopen', str(rw))
        try:
            run('osascript', '-e', LAYOUT)
            run('rm', '-rf', str(mount / '.fseventsd'))
            run('chmod', '-Rf', 'go-w', str(mount))
            run('sync')
        finally:
            run('hdiutil', 'detach', '-quiet', str(mount))
        dmg.unlink(missing_ok=True)
        run('hdiutil', 'convert', '-quiet', str(rw), '-format', 'UDZO', '-imagekey', 'zlib-level=9', '-o', str(dmg))
    run('codesign', '--sign', RELEASE_IDENTITY, '--timestamp', str(dmg))
    notarize(dmg)
    archive = dist / f'Alex-{version}.zip'
    archive.unlink(missing_ok=True)
    run('ditto', '-c', '-k', '--keepParent', str(app), str(archive))
    for artifact in (dmg, archive):
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        (dist / f'{artifact.name}.sha256').write_text(f'{digest}  {artifact.name}\n')
        print(f'{artifact}\nsize: {artifact.stat().st_size} bytes\nsha256: {digest}')


if __name__ == '__main__':
    main()
