# Prime Sobos for sobosuba 1.3.11

The folder name is historical. The current package targets **sobosuba 1.3.11**,
build 26465074. See [PRIME-SOBOS-en.md](PRIME-SOBOS-en.md) for installation,
verification results and known issues.

Build the ZIP from the repository root.

```sh
python beta-1.3.8/package_prime.py --output /your/build/folder
```

Self-tests need game_mode_scope.gd next to the scripts, the same way the packager adds it.

This version uses `user://styles/prime_bootstrap.tres` and `user://prime_mod/`.
The older 1.2.3 mod remains under `mods/` and uses its separate release package.
No game files are included.
