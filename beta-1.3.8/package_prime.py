"""Build the Prime Sobos package for sobosuba beta 1.3.11."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parent
version = re.search(r'^const MOD_VERSION\s*:?=\s*"([^"]+)"',
                    (source / 'prime_mod/prime_diagnostics.gd').read_text(encoding='utf-8'), re.MULTILINE).group(1)
payload = {f'prime_mod/{path.name}': path.read_bytes()
           for path in sorted((source / 'prime_mod').iterdir())
           if path.suffix in {'.gd', '.cfg'}}
bootstrap = 'styles/prime_bootstrap.tres'
payload[bootstrap] = (source / bootstrap).read_bytes()
payload['prime_mod/game_mode_scope.gd'] = (source.parent / 'mods/prime_sobo/game_mode_scope.gd').read_bytes()
metadata = {
    'format_version': 1, 'id': 'prime_sobo', 'name': 'Prime Sobos',
    'version': version, 'game_versions': ['1.3.11'],
    'install_layout': 'user-data-styles', 'payload_root': 'prime_mod',
    'entry': 'prime_sobo.gd', 'autoload': 'PrimeSobo',
    'bootstrap': bootstrap, 'dependencies': [], 'files': sorted(payload),
    'description': {'en': 'Adds prime-numbered sobos. Pairs merge when their sum is a power of two.'},
    'author': 'T0y-9n', 'readme': 'README-en.md',
    'game_credit': {'text': 'sobosuba by keepee', 'store_url': 'https://store.steampowered.com/app/1946560/sobosuba'},
}
args.output.mkdir(parents=True, exist_ok=True)
path = args.output / f'sobosuba-prime-balls-{version}.zip'
with zipfile.ZipFile(path, 'x', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in payload.items():
        archive.writestr(name, data)
    archive.writestr('mod-package.json', json.dumps(metadata, indent=2))
    archive.writestr('README-en.md', (source / 'PRIME-SOBOS-en.md').read_bytes())
    archive.writestr('LICENSE', (source.parent / 'LICENSE').read_bytes())
    archive.writestr('CHANGELOG.md', (source.parent / 'CHANGELOG.md').read_bytes())
digest = hashlib.sha256(path.read_bytes()).hexdigest()
path.with_suffix('.zip.sha256').write_text(f'{digest}  {path.name}\n', encoding='ascii')
print(path.name, path.stat().st_size, digest)
