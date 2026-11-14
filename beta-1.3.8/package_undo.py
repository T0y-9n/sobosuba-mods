"""Build the Undo package for sobosuba 1.3.11."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parent
version = re.search(
    r'^const MOD_VERSION := "([^"]+)"',
    (source / "undo_mod" / "undo_sobo.gd").read_text(encoding="utf-8"),
    re.MULTILINE,
).group(1)
payload = {
    f"undo_mod/{path.name}": path.read_bytes()
    for path in sorted((source / "undo_mod").iterdir())
    if path.suffix == ".gd" and path.name != "undo_selftest.gd"
}
bootstrap = "styles/undo_bootstrap.tres"
payload[bootstrap] = (source / bootstrap).read_bytes()
metadata = {
    "format_version": 1,
    "id": "undo_sobo",
    "name": "Undo",
    "version": version,
    "game_versions": ["1.3.11"],
    "install_layout": "user-data-styles",
    "payload_root": "undo_mod",
    "entry": "undo_sobo.gd",
    "autoload": "UndoSobo",
    "bootstrap": bootstrap,
    "dependencies": [],
    "files": sorted(payload),
    "description": {
        "en": "Restores the board from before a launch, up to five times. While undo is on, no run is sent to a leaderboard."
    },
    "author": "T0y-9n",
    "readme": "README-en.md",
    "game_credit": {
        "text": "sobosuba by keepee",
        "store_url": "https://store.steampowered.com/app/1946560/sobosuba",
    },
}
args.output.mkdir(parents=True, exist_ok=True)
path = args.output / f"sobosuba-undo-{version}.zip"
with zipfile.ZipFile(path, "x", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name, data in payload.items():
        archive.writestr(name, data)
    archive.writestr("mod-package.json", json.dumps(metadata, indent=2) + "\n")
    archive.writestr("README-en.md", (source / "UNDO-en.md").read_bytes())
    archive.writestr("LICENSE", (source.parent / "LICENSE").read_bytes())
digest = hashlib.sha256(path.read_bytes()).hexdigest()
path.with_suffix(".zip.sha256").write_text(f"{digest}  {path.name}\n", encoding="ascii")
print(path.name, path.stat().st_size, digest)
