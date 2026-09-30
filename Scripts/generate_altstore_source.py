#!/usr/bin/env python3
"""Generate the AltStore feed from the packaged IPA's real version and permissions."""
import argparse
import datetime
import json
import plistlib
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('ipa', type=Path)
parser.add_argument('--date', default=datetime.date.today().isoformat())
parser.add_argument('--release-notes', default='Native trip dashboard, route previews, colored purposes, schedules, exports and guided Shortcuts setup. Local storage; iPhone-only unsigned sideload package.')
args = parser.parse_args()
datetime.date.fromisoformat(args.date)
with zipfile.ZipFile(args.ipa) as archive:
    info = plistlib.loads(archive.read('Payload/Ritme.app/Info.plist'))
    if any('/Watch/' in name for name in archive.namelist()):
        raise SystemExit('This source distributes the iPhone-only package.')
raw = 'https://raw.githubusercontent.com/MiranoVerhoef/Ritme/main'
version = info['CFBundleShortVersionString']
release = f'https://github.com/MiranoVerhoef/Ritme/releases/download/v{version}'
source = {
    'name': 'Ritme', 'identifier': 'nl.verhoef.ritme.source',
    'subtitle': 'A personal mileage log for iPhone',
    'description': 'Development builds of Ritme. Record trips, classify Work or Private, and export mileage reports. Requires iOS 26 or later.',
    'iconURL': f'{raw}/Distribution/Ritme-Icon.png',
    'website': 'https://github.com/MiranoVerhoef/Ritme', 'tintColor': '#007AFF',
    'featuredApps': [info['CFBundleIdentifier']],
    'apps': [{
        'name': 'Ritme', 'bundleIdentifier': info['CFBundleIdentifier'],
        'developerName': 'Mirano Verhoef', 'subtitle': 'Trip recording and mileage reports',
        'localizedDescription': 'An early native iPhone beta with GPS trip recording, saved places, Work/Private classification, schedules, holiday mode, and CSV/PDF/GPX exports. CarPlay and Bluetooth setup is guided through Shortcuts. This build stores data locally; iCloud sync is not active. The sideload package does not include the Watch companion. Physical driving and paired-Watch testing are still required.',
        'iconURL': f'{raw}/Distribution/Ritme-Icon.png', 'tintColor': '#007AFF',
        'category': 'utilities',
        'screenshots': [{'imageURL': f'{raw}/Preview/{name}.png', 'width': 1206, 'height': 2622} for name in ['trips', 'places', 'reports', 'settings']],
        'versions': [{
            'version': version, 'buildVersion': info['CFBundleVersion'], 'date': args.date,
            'localizedDescription': args.release_notes,
            'downloadURL': f'{release}/{args.ipa.name}', 'size': args.ipa.stat().st_size,
            'minOSVersion': info['MinimumOSVersion']
        }],
        'appPermissions': {
            'entitlements': [],
            'privacy': {key: value for key, value in info.items() if key.startswith('NS') and key.endswith('UsageDescription')}
        }
    }], 'news': []
}
feed_path = Path('altstore-source.json')
if feed_path.exists():
    previous = json.loads(feed_path.read_text())
    previous_app = next((app for app in previous.get('apps', []) if app.get('bundleIdentifier') == info['CFBundleIdentifier']), {})
    source['apps'][0]['versions'].extend(entry for entry in previous_app.get('versions', []) if entry.get('version') != version)
Path('altstore-source.json').write_text(json.dumps(source, indent=2) + '\n')
print('Generated altstore-source.json from', args.ipa)
