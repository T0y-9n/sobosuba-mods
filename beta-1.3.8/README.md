# Prime Sobos for the beta game

The folder name is historical. The current package targets **sobosuba beta
1.3.11**, build 26465074. See [PRIME-SOBOS-en.md](PRIME-SOBOS-en.md) for installation,
verification results and known issues.

Build the ZIP from the repository root with:

```sh
python beta-1.3.8/package_prime.py --output /your/build/folder
```

This beta uses `user://styles/prime_bootstrap.tres` and `user://prime_mod/`.
The stable 1.2.3 mod remains under `mods/` and uses its separate release package.
No game files are included.
