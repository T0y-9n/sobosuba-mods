"""Build the Special Sobos package for sobosuba 1.3.11."""
import argparse
import datetime
import hashlib
import json
import re
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--tested', type=Path, required=True, help='TESTED-en.md for this release')
args = parser.parse_args()
source = Path(__file__).resolve().parent
version = re.search(r'^const MOD_VERSION\s*:?=\s*"([^"]+)"',
                    (source / 'special_mod/special_diagnostics.gd').read_text(encoding='utf-8'), re.MULTILINE).group(1)
payload = {f'special_mod/{path.name}': path.read_bytes()
           for path in sorted((source / 'special_mod').iterdir())
           if path.suffix == '.gd' and 'selftest' not in path.name}
payload['special_mod/game_mode_scope.gd'] = (source.parent / 'mods/prime_sobo/game_mode_scope.gd').read_bytes()
bootstrap = 'styles/special_bootstrap.tres'
payload[bootstrap] = (source / bootstrap).read_bytes()
metadata = {
    'id': 'special_sobo', 'name': 'Special Sobos', 'version': version,
    'payload_root': 'special_mod', 'entry': 'special_sobo.gd', 'autoload': 'SpecialSobo',
    'bootstrap': bootstrap,
    'description': {
        'en': 'Small, puffy, magnet, throwing, tornado, liquid and dark matter sobos, with numeric tuning settings.',
        'ja': '小さい・ふわふわ・磁石・投げ飛ばす・トルネード・液体・ダークマターのソボと数値の設定。',
    },
    'format_version': 1, 'game_versions': ['1.3.11'], 'install_layout': 'user-data-styles',
    'dependencies': [], 'readme': 'README-en.md', 'files': sorted(payload),
    'author': 'T0y-9n', 'created_at': datetime.date.today().isoformat(), 'languages': ['en', 'ja'],
    'game_credit': {'text': 'sobosuba by keepee', 'store_url': 'https://store.steampowered.com/app/1946560/sobosuba'},
}
args.output.mkdir(parents=True, exist_ok=True)
path = args.output / f'Special-Sobos-{version}.zip'
changelog = (source.parent / 'CHANGELOG.md').read_bytes()
with zipfile.ZipFile(path, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in payload.items():
        archive.writestr(name, data)
    archive.writestr('mod-package.json', json.dumps(metadata, indent=2, ensure_ascii=False))
    archive.writestr('README-en.md', (source / 'SPECIAL-SOBOS-en.md').read_bytes())
    archive.writestr('CHANGELOG.md', changelog)
    archive.writestr('CHANGELOG-en.md', changelog)
    archive.writestr('TESTED-en.md', args.tested.read_bytes())
digest = hashlib.sha256(path.read_bytes()).hexdigest()
path.with_name(path.name + '.sha256').write_text(f'{digest}  {path.name}\n', encoding='utf-8')
print(path, path.stat().st_size, digest)
