# Sobo Mod Manager for Windows

Manage mods for sobosuba **1.2.3** and **1.3.10**. The game is required.

1. Extract the ZIP and open `SoboModManager.exe`.
2. Check the game folder. Use **Change** if it is wrong.
3. Select the installed game version. Steam build 26393791 is detected as 1.3.10. Other installations require you to check the version shown in the game; the manager labels your choice as unverified.
4. Choose **Install from ZIP**, select a mod ZIP and check its name, version and install location before confirming.
5. Use **Enable**, **Disable** or **Uninstall** on each installed mod. Close the game before making changes.

Choose your language at the top right. The first launch uses the Windows locale. File pickers use the Windows display language.

**Disable** stops loading the mod and keeps its files. **Uninstall** removes only the files recorded as belonging to that mod. Settings, saves and other files are kept. A saved run that uses a mod may still need that mod to resume.

Files installed manually are marked separately. To bring them under management, select the matching ZIP and confirm **Manage matching files already installed**. Different or locally edited code is left untouched. Keep your original ZIP if you want to install it again later.

If a file operation is interrupted, choose **Restore interrupted changes** before continuing. If the files have changed again since the interruption, the manager stops and keeps the recovery record instead of overwriting them.

The catalog is optional. It is checked only when you press **Check catalog**. ZIP installation does not require a network connection. Installing a ZIP does not execute its mod code; only install mods from authors you trust, as the game will execute them later.

## Supported packages

- Existing public 1.2.3 packages with `mods/<id>/mod.json` and `game_version: "1.2.3"`.
- The previously distributed Prime Sobos 1.2.3-1.0.2 ZIP, recognized by its SHA256.
- The previously distributed Special Sobos 1.3.10 alpha and magnet-tuning ZIPs, recognized by SHA256.
- The Prime Sobos and Special Sobos native UI ZIPs for 1.3.10, with `mod-package.json`.

A package's declared game version must match the selected version. Unknown game versions are rejected rather than guessed. Public builds use `mods` and the game's `override.cfg`; 1.3.10 uses the user's `prime_mod` or `special_mod` and its own `styles/*_bootstrap.tres`. The manager will not enable a mod for another game version. Turn off mods for an earlier version before switching installation layouts.

The app uses Windows PowerShell 5.1, standard .NET ZIP support and the Windows tar utility. It does not require a separately installed Godot engine. The helper scripts are embedded in the EXE and unpacked into the manager's own application data. A ZIP is checked for CRC errors before installation. Windows 10 version 1803 or later, or Windows 11, is required for the built-in tar utility. If Windows policy blocks PowerShell, the operation stops; do not weaken your system policy to use this app.

## Languages and checks

The interface has the same 22 locales as sobosuba 1.3.10. All message keys and arguments are checked. Japanese, German, Simplified Chinese, Korean and Russian screens have been visually checked. Native-speaker proofreading outside Japanese and English is still needed.

Storage checks use real release ZIPs and a QA copy of the actual game executable. They cover both installation layouts, independent mod toggles, settings preservation, version mismatch, ZIP paths, changed files, interrupted updates and rollback. The game is not launched in these manager checks. These checks do not certify gameplay with every combination of mods.

## Build from source

Use Godot 4.7.2 with its matching Windows export templates. Set `GODOT_BIN` to the console executable for your Godot installation.

From the repository root, run these commands in PowerShell.

```powershell
New-Item -ItemType Directory -Force dist
& $env:GODOT_BIN --headless --editor --path manager --quit
& $env:GODOT_BIN --headless --path manager --export-release 'Windows Desktop' (Join-Path (Get-Location) 'dist/SoboModManager.exe')
```

The output is `dist/SoboModManager.exe`. ZIP inspection and file operations use the embedded PowerShell helpers. Read `backend.ps1`, `package.ps1` and `transaction.ps1` for those operations. The interface is built by `main.gd`, and its translations are in `locales.json`.

The published alpha's checks and known limitations are in `TESTED-en.md` inside the Windows download.
