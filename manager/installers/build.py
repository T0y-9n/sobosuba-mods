"""Build setup files on Linux using NSIS 3 and Python 3."""
import argparse
import hashlib
import os
import re
from pathlib import Path
import subprocess
import zipfile
from languages import generate

parser = argparse.ArgumentParser()
parser.add_argument('--payload', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--makensis', type=Path, required=True)
parser.add_argument('--nsisdir', type=Path, required=True)
args = parser.parse_args()
here = Path(__file__).resolve().parent
version = re.search(r'^config/version="([^"]+)"', (here.parent/'project.godot').read_text(), re.M).group(1)
args.output.mkdir(parents=True, exist_ok=True)
windows = args.output/f'Sobosuba-Mod-Manager-Setup-Windows-v{version}.exe'
language_include = generate(args.nsisdir, args.output/'setup-languages')
subprocess.run([
    str(args.makensis), '-V2', f'-DVERSION={version}',
    f'-DPAYLOAD={args.payload / "SobosubaModManager.exe"}',
    f'-DICON={here.parent / "assets/sobosuba-mod-manager.ico"}',
    f'-DBACKEND={here / "windows.ps1"}', f'-DLANGUAGES={language_include}', f'-DOUTPUT={windows}', str(here/'windows.nsi'),
], env=dict(os.environ, NSISDIR=str(args.nsisdir)), check=True)

linux = args.output/f'Sobosuba-Mod-Manager-Setup-Linux-x86_64-v{version}.run'
bootstrap = '''#!/bin/sh
exec python3 -I - "$0" "$@" <<'SOBOSUBA_SETUP_PY'
import os, pathlib, subprocess, sys, tempfile, zipfile
with tempfile.TemporaryDirectory(prefix='sobosuba-setup-') as temp:
    directory = pathlib.Path(temp)
    with zipfile.ZipFile(sys.argv[1]) as archive:
        names = ['SobosubaModManager.x86_64', 'sobosuba-mod-manager.png', 'linux.py']
        if sorted(archive.namelist()) != sorted(names):
            raise SystemExit('The setup archive is invalid.')
        for name in names:
            with archive.open(name) as source, (directory/name).open('wb') as dest:
                import shutil
                shutil.copyfileobj(source, dest)
    result = subprocess.run([sys.executable, '-I', str(directory/'linux.py'), '--source', str(directory), *sys.argv[2:]])
    raise SystemExit(result.returncode)
SOBOSUBA_SETUP_PY
'''
linux.write_bytes(bootstrap.encode())
with zipfile.ZipFile(linux, 'a', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for source, name in [(args.payload/'SobosubaModManager.x86_64', 'SobosubaModManager.x86_64'),
                         (here.parent/'assets/sobosuba-mod-manager.png', 'sobosuba-mod-manager.png'),
                         (here/'linux.py', 'linux.py')]:
        archive.write(source, name)
linux.chmod(0o755)
for path in (windows, linux):
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    path.with_suffix(path.suffix+'.sha256').write_text(f'{sha}  {path.name}\n')
    print(path.name, path.stat().st_size, sha, flush=True)
