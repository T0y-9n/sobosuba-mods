"""Per-user Linux installation. Uses only Python's standard library."""
import argparse
import contextlib
import fcntl
import json
import os
from pathlib import Path
import shlex
import shutil
import sys
import tempfile

APP_ID = 'sobosuba-mod-manager'
EXE = 'SobosubaModManager.x86_64'
ICON = 'sobosuba-mod-manager.png'
MARKER = '.sobosuba-manager-install.json'
FILES = (EXE, ICON, 'installer.py', 'uninstall.sh', MARKER)


def check_path(path):
    for part in (path, *path.parents):
        if part.is_symlink():
            raise ValueError(f'Symbolic links are not supported in the install path: {part}')


def desktop_text(prefix):
    # Desktop Entry escaping is separate from shell quoting.
    escaped = str(prefix).replace('\\', '\\\\').replace('"', '\\"').replace('`', '\\`').replace('$', '\\$').replace('%', '%%')
    escaped = escaped.replace('\\', '\\\\')
    icon = str(prefix/ICON).replace('\\', '\\\\')
    return ('[Desktop Entry]\nType=Application\nName=Sobosuba Mod Manager\n'
            'Comment=Install and manage mods for Sobosuba\n'
            f'Exec="{escaped}/{EXE}"\nIcon={icon}\n'
            'Terminal=false\nCategories=Game;Utility;\nStartupNotify=true\n')


def apply_changes(changes):
    """Prepare all writes first, then replace. Restore previous files on error."""
    staged = []
    backups = []
    keep_backups = set()
    try:
        for target, source, mode in changes:
            check_path(target)
            if target.exists() and not target.is_file():
                raise ValueError(f'Expected a regular file: {target}')
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = None
            if source is not None:
                fd, name = tempfile.mkstemp(prefix='.sobosuba-new-', dir=target.parent)
                temporary = Path(name)
                staged.append((target, temporary))
                with os.fdopen(fd, 'wb') as output:
                    if isinstance(source, Path):
                        with source.open('rb') as stream:
                            shutil.copyfileobj(stream, output)
                    else:
                        output.write(source.encode('utf-8'))
                    output.flush()
                    os.fsync(output.fileno())
                temporary.chmod(mode)
            else:
                staged.append((target, temporary))
        for target, temporary in staged:
            backup = None
            if target.exists():
                fd, name = tempfile.mkstemp(prefix='.sobosuba-old-', dir=target.parent)
                os.close(fd)
                backup = Path(name)
                shutil.copy2(target, backup)
            backups.append((target, backup))
            if temporary is None:
                target.unlink(missing_ok=True)
            else:
                os.replace(temporary, target)
    except BaseException:
        for target, backup in reversed(backups):
            try:
                if backup is None:
                    target.unlink(missing_ok=True)
                else:
                    os.replace(backup, target)
            except OSError:
                if backup is not None:
                    keep_backups.add(backup)
                    print(f'Recovery copy kept at {backup}', file=sys.stderr)
        raise
    finally:
        for _, path in staged + backups:
            if path is not None and path not in keep_backups:
                path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description='Install Sobosuba Mod Manager for the current user.')
    parser.add_argument('--prefix', type=Path, default=Path.home()/'.local/opt'/APP_ID)
    parser.add_argument('--source', type=Path, default=Path(__file__).absolute().parent)
    parser.add_argument('--uninstall', action='store_true')
    args = parser.parse_args()
    prefix = args.prefix.absolute()
    if prefix == Path(prefix.anchor) or prefix == Path.home():
        raise ValueError('Choose a dedicated application directory.')
    if any(c in str(prefix) for c in '\r\n\t'):
        raise ValueError('The install path must not contain line breaks or tabs.')
    check_path(prefix)
    prefix.parent.mkdir(parents=True, exist_ok=True)
    data = Path(os.environ.get('XDG_DATA_HOME') or Path.home()/'.local/share').absolute()
    check_path(data)
    data.mkdir(parents=True, exist_ok=True)
    lock = data/'.sobosuba-manager-setup.lock'
    check_path(lock)
    with lock.open('a') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        marker = prefix/MARKER
        check_path(marker)
        owned = marker.is_file() and json.loads(marker.read_text()) == {'application': APP_ID}
        if not owned and any((prefix/name).exists() or (prefix/name).is_symlink() for name in FILES):
            raise ValueError('The destination contains files from another installation. Choose an empty folder.')
        desktop = data/'applications'/f'{APP_ID}.desktop'
        text = desktop_text(prefix)
        check_path(desktop)
        if args.uninstall:
            if not owned:
                raise ValueError('No managed installation was found at this path.')
            changes = [(prefix/name, None, 0) for name in FILES]
            if desktop.is_file() and desktop.read_text() == text:
                changes.append((desktop, None, 0))
            apply_changes(changes)
            with contextlib.suppress(OSError):
                prefix.rmdir()
            print('Sobosuba Mod Manager was removed. Settings, mods and other files were kept.')
            return
        if desktop.exists() and desktop.read_text() != text:
            raise ValueError('An existing application shortcut would be replaced. Keep it or remove it first.')
        uninstall = ('#!/bin/sh\nset -eu\nexec python3 -I '+shlex.quote(str(prefix/'installer.py'))+
                     ' --uninstall --prefix '+shlex.quote(str(prefix))+' "$@"\n')
        apply_changes([
            (prefix/ICON, args.source/ICON, 0o644),
            (prefix/'installer.py', Path(__file__).absolute(), 0o644),
            (prefix/'uninstall.sh', uninstall, 0o755),
            (marker, json.dumps({'application': APP_ID})+'\n', 0o644),
            (desktop, text, 0o644),
            (prefix/EXE, args.source/EXE, 0o755),
        ])
        print(f'Installed Sobosuba Mod Manager in {prefix}\nOpen it from your application menu.\nTo remove it, run {prefix}/uninstall.sh')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        print(f'Setup stopped: {error}', file=sys.stderr)
        sys.exit(1)
