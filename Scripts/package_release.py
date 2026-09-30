#!/usr/bin/env python3
"""Package an unsigned device build for iPhone sideloading; leave the build intact."""
import argparse
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, default=Path('build/ReleaseDerivedData/Build/Products/Release-iphoneos/Ritme.app'))
parser.add_argument('--output-dir', type=Path, default=Path('build/releases'))
args = parser.parse_args()
app = args.app.resolve()
info = plistlib.loads((app / 'Info.plist').read_bytes())
if info.get('DTPlatformName') != 'iphoneos':
    raise SystemExit('Only device builds can be packaged. Build for generic/platform=iOS first.')
platform = subprocess.check_output(['xcrun', 'vtool', '-show-build', str(app / info['CFBundleExecutable'])], text=True)
if 'platform IOS\n' not in platform:
    raise SystemExit('The executable is not an iOS device binary.')
if (app / 'embedded.mobileprovision').exists() or (app / '_CodeSignature').exists():
    raise SystemExit('Build with CODE_SIGNING_ALLOWED=NO; this script accepts unsigned builds only.')
args.output_dir.mkdir(parents=True, exist_ok=True)
output = args.output_dir.resolve() / f"Ritme-v{info['CFBundleShortVersionString']}.ipa"
with tempfile.TemporaryDirectory(prefix='ritme-release-') as temporary:
    payload = Path(temporary) / 'Payload'
    package = payload / 'Ritme.app'
    shutil.copytree(app, package)
    # Watch signing/installation through sideloaders is not validated. The source
    # project retains the companion for signed Xcode builds and physical testing.
    shutil.rmtree(package / 'Watch', ignore_errors=True)
    with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for file in sorted(package.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(temporary))
print(output)
print(f'{output.stat().st_size} bytes; iPhone only; unsigned')
