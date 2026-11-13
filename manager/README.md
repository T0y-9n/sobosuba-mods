# Sobosuba Mod Manager

sobosuba by keepee. This manager requires the original game.
[Get sobosuba on Steam](https://store.steampowered.com/app/1946560/sobosuba).

Manage mods for sobosuba **1.2.3**, **1.3.10** and **1.3.11**. The game is required.

Supported mods include [Prime Sobos](https://github.com/T0y-9n/sobosuba-mods/releases/tag/1.3.11-1.0.5)
and [Special Sobos 0.5.5 (beta)](https://github.com/T0y-9n/sobosuba-mods/releases/tag/special-1.3.11-0.5.5).

1. Extract the common setup ZIP. On Windows, open the setup EXE in `Windows`. On Linux x86_64, open a terminal in `Linux` and run `sh Sobosuba-Mod-Manager-Setup-Linux-x86_64-v0.3.0-alpha.10.run`. Then open **Sobosuba Mod Manager** from the Start menu or application menu. See `INSTALL-en.md` for locations and removal. Portable downloads can still run their manager executable directly.

2. Check the game folder. Use **Choose folder** if it is wrong or missing.

3. Check the selected game version. On startup and when choosing a folder, Steam builds 26393791 and 26465074 select 1.3.10 and 1.3.11 automatically. Other installations require you to check the version shown in the game. The manager labels your choice as unverified.

4. Choose **Install from ZIP**, or drop one mod ZIP into the window. Check its name, version and install location before confirming.

5. If required mods are listed, review the whole group before confirming. The manager installs and enables the prerequisites along with the selected mod.

6. Select a mod in the list. Use **Enable**, **Disable** or **Uninstall** at the bottom of its details. Close the game before making changes.

Search by name or ID, or filter the list by **Enabled**, **Disabled** or **Manually installed**. **Clear filters** resets the search and status filters. The count next to **Installed mods** is the total installed, including mods hidden by your filters. Mod details and actions always refer to the selected row. The result of each operation stays at the bottom of the window.

The catalog initially shows mods that list your selected game version. Use the checkbox beside **Game version** to include mods made for earlier versions. Earlier 1.3 mods can be installed on a newer 1.3 game, with a warning in the row and after installation. For a 1.3 game, 1.2.3 mods appear with a disabled install button and a tooltip explaining their different loading method. Select game version 1.2.3 to install those mods.

From alpha.7, one catalog ID can offer separate releases for different game versions. Prime Sobos offers its original 1.2.3 and 1.3.11 ZIPs. Selecting the game version chooses the matching ZIP and SHA256. The 1.2.3 package stays in the game folder; the 1.3.11 package stays in the game's user data folder. Their receipts and automatic update settings remain separate. Disable mods for the other game family before installing or enabling mods for the selected game.

Select a mod to read its overview, author and included README in the details pane. JSON descriptions can be supplied in several languages. The manager chooses the interface language when available and shows which language is being displayed. The manager keeps this text with its installation record. Older installations show the information they already contain. Installing or updating from a ZIP with a README adds it to the record.

Mod authors can use **MOD-PACKAGING-en.md** and the two JSON examples included with this app to prepare a package. Use the example for your game version.

Required mods are matched by ID and exact version. The manager first checks installed mods, then ZIPs beside the package and its own cache, then the configured catalog. Catalog downloads must have a SHA256 in the catalog or dependency definition. An unavailable or mismatched dependency stops the operation before game files are changed.

Enabling a mod also prepares its prerequisites. A prerequisite used by an enabled mod is protected from disabling, removal and an incompatible update. Disable the dependent mod first. Updating a disabled mod preserves its disabled state. Changes in one group are recovered together if writing fails.

Choose your language at the top right. The first launch uses your system language. File pickers use the desktop language.

**Disable** stops loading the mod and keeps its files. **Uninstall** removes only the files recorded as belonging to that mod. Settings, saves and other files are kept. A saved run that uses a mod may still need that mod to resume.

Files installed manually are marked separately. To bring them under management, select the matching ZIP and confirm **Manage matching files already installed**. Different or locally edited code is left untouched. Keep your original ZIP if you want to install it again later.

If a file operation is interrupted, choose **Restore interrupted changes** before continuing. If the files have changed again since the interruption, the manager stops and keeps the recovery record instead of overwriting them.

Use **Auto-update this mod** in a managed mod's details to allow automatic updates. This is off until you select it for that mod. The manager checks on startup and every 30 minutes; **Check for updates** checks immediately. A newer compatible version is downloaded and verified before it is applied. Disabled mods stay disabled. The game must be closed. Checks wait while a file picker, confirmation or another operation is open. Updates do not adopt manually installed files or downgrade a prerequisite.

**Auto-update manager** is on by default. A new manager release is downloaded from this project's GitHub Releases. Windows installations in Program Files use the newer setup and ask for administrator approval when you close the app. Setup checks the expected version and tests startup in separate application data before keeping the new files. Portable Windows and Linux copies use a helper to replace the executable and restore it if startup fails. You can also choose **Update and restart**. Settings, game files and saves are kept. A failed package is not retried automatically. Keep the previous executable backup until you have used the new version.

The catalog is also checked when a prerequisite cannot be found locally. Installing ZIPs with all prerequisites already present works offline. Installing a ZIP does not execute its mod code; only install mods from authors you trust, as the game will execute them later.

## Original-game credit and author releases

From alpha.9, details and installation confirmations show `sobosuba by keepee` and the [original game's purchase link](https://store.steampowered.com/app/1946560/sobosuba). A package with missing or incorrect `game_credit` shows a warning. You can confirm installation, including required mods, and opted-in automatic updates continue. Existing installations without credit also show the warning.

The catalog can name an author's GitHub repository, tag prefix and ZIP filename pattern in `source`. On startup and **Check for updates**, the manager checks those repositories for newer releases. It verifies the release asset's SHA256 digest and the ZIP's ID, version, game versions before offering an update. Missing package credit or unverified GitHub README credit produces a warning. Catalog contribution checks continue to require both credits. A per-mod automatic update setting controls installation. Prereleases require explicit permission in that catalog source. Prime's 1.2.3 and 1.3.11 release series stay separate.

When an author release cannot be checked or accepted, the row shows a reason and the catalog version stays available. The last check result and time remain available offline. The catalog's pinned version, URL and SHA256 remain the baseline for earlier managers.

## Supported packages

- Existing public 1.2.3 packages with `mods/<id>/mod.json` and `game_version: "1.2.3"`.

- The previously distributed Prime Sobos 1.2.3-1.0.2 ZIP, recognized by its SHA256.

- The previously distributed Special Sobos 1.3.10 alpha and magnet-tuning ZIPs, recognized by SHA256.

- The Prime Sobos and Special Sobos native UI ZIPs for 1.3.10, with `mod-package.json`.

A package for an earlier 1.3 game version can be installed on a newer 1.3 game. If your selected version is absent from the package's list, the manager warns that it has not been checked on that version. If the game behaves incorrectly, disable that mod first. Version 1.2.3 uses `mods` and the game's `override.cfg`. Versions 1.3.10 and 1.3.11 use the user's data directory and `styles/*_bootstrap.tres`. Keep mods for these two loading methods separate when switching game versions.

Windows uses the built-in PowerShell 5.1 and tar utility. Linux x86_64 includes the official PowerShell 7.4 LTS runtime inside the app and requires the system Python 3 and tar commands. The runtime is checked against its pinned SHA256 and extracted into the manager's application data on first use. Linux ZIP checks use Python's standard library in isolated mode. Ubuntu 22.04 or later is supported by the bundled runtime. Ubuntu 24.04 under WSL is used for checks. It does not require a separately installed Godot engine. The helper scripts are embedded in the executable and unpacked into the manager's own application data. A ZIP is checked for CRC errors before installation. Windows 10 version 1803 or later, or Windows 11, is required for the Windows tar utility. If Windows policy blocks PowerShell, the operation stops; do not weaken your system policy to use this app.

## Languages and checks

The interface has the same 22 locales as sobosuba 1.3.10. All message keys and arguments are checked. Japanese, English, German, Simplified Chinese, Korean and Russian screens have been visually checked. Native-speaker proofreading outside Japanese and English is still needed.

Storage checks use real release ZIPs and a QA copy of the actual game executable. They cover both installation layouts, independent mod toggles, settings preservation, version mismatch, ZIP paths, changed files, interrupted updates and rollback. The game is not launched in these manager checks. These checks do not certify gameplay with every combination of mods.

## Build and test from source

Use isolated APPDATA and LOCALAPPDATA on Windows. On Linux, isolate HOME, XDG_DATA_HOME, XDG_CONFIG_HOME and XDG_CACHE_HOME. The Linux runtime build input is `manager/runtime/powershell-linux-x64.tar.gz`; its source URL and pinned digest are in `manager/runtime/linux.json`. Obtain that exact archive before exporting the Linux preset. Obtain Godot 4.7.2 and its matching Windows export templates from the official distribution.

```powershell

& $env:GODOT_BIN --headless --editor --path manager --quit

& $env:GODOT_BIN --headless --path manager --export-release 'Windows Desktop' "$env:SOBOSUBA_BUILD_ROOT/SobosubaModManager.exe"

node --test server/test/manager.test.mjs

```

Tests require `GODOT_BIN`, `SOBOSUBA_QA_ROOT` and `SOBOSUBA_GAME_COPY`. `SOBOSUBA_GAME_COPY` must point to a QA copy of the real `sobosuba.exe`. No dummy game or invented mod is used. The ZIP paths are listed in `server/test/manager_versions.ps1`. Exported release builds do not run the external SceneTree test script through `--script`; use the source runner, then check the exported window and embedded backend separately.

## Publishing manager updates

The main download is one common ZIP named `Sobosuba-Mod-Manager-Setup-v<version>.zip`, containing the Windows setup EXE, Linux x86_64 setup script and one set of instructions. Automatic updates use the matching OS asset described below.

Manager update tags use `manager-v<version>`, for example `manager-v0.3.0-alpha.1`. Attach `Sobosuba-Mod-Manager-Windows-v0.3.0-alpha.1.zip` with `SobosubaModManager.exe` and a root-level `VERSION.txt` containing only `0.3.0-alpha.1`. For Linux, attach `Sobosuba-Mod-Manager-Linux-x86_64-v0.3.0-alpha.1.zip` with `SobosubaModManager.x86_64` and the same `VERSION.txt`. The Linux runtime is embedded in its executable and is updated with it. GitHub must provide a `sha256:` asset digest. The update check accepts that exact repository, tag, asset name and download URL. The earlier date-only alpha tag is not treated as a newer semantic version.

Stable releases only update to newer stable releases. Alpha builds can also receive newer prereleases in the same version series. Unknown version formats and unordered prerelease labels are skipped. MOD catalog entries must include the ZIP URL and SHA256; the downloaded metadata must match the listed ID, version, game version and install layout.

The source update checks use `server/test/manager_updates.gd` with a separate QA directory. Self-update checks use `server/test/manager_self_update.py --root <QA> --old <old manager EXE> --new <new manager EXE>`. Both EXEs must be actual exports of this manager. These tests never start the game.

The first launch under the Sobosuba name imports saved manager settings from the earlier Sobo name when no new settings exist.
