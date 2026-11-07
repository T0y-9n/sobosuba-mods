# Preparing a mod ZIP

The manager reads package information before installing. Selecting an installed mod shows its description, author and README in the details pane. The README is stored with the manager's installation record so it remains readable after the original ZIP has been moved.

Use the example for your game's version. Replace the author placeholder and check every path against your own ZIP. The examples describe the existing Special Sobos and Prime Sobos packages.

## For sobosuba 1.3.10 and 1.3.11

Put `mod-package.json` at the top level of the ZIP, alongside your payload folder and bootstrap file. `mod-package.example.json` shows the existing Special Sobos package layout. Rename your edited copy to `mod-package.json`.

| Field | What to write |
| --- | --- |
| `format_version` | `1` |
| `id` | A stable identifier such as `special_sobo`. Use a lowercase letter first, then lowercase letters, digits or underscores. Keep this ID when releasing updates. |
| `name` | The display name, up to 120 characters. |
| `version` | The mod's version, up to 80 characters. This must contain a value. |
| `game_versions` | The versions checked by the author, such as `["1.3.11"]`. |
| `install_layout` | `user-data-styles` for the supported beta layouts. |
| `payload_root` | The folder containing the mod, such as `special_mod`. |
| `entry` | The main `.gd` script relative to that folder, such as `special_sobo.gd`. |
| `autoload` | The name used by the mod's existing bootstrap, such as `SpecialSobo`. |
| `bootstrap` | Its existing loading file, such as `styles/special_bootstrap.tres`. |
| `files` | Every file the manager should install, including the main script, its required files and the bootstrap. Paths are relative to the ZIP root. |

Keep the package definition at the ZIP root. An extra wrapping folder prevents the manager from finding it. The bootstrap and entry point must already work with the game's supported loading mechanism.

## For sobosuba 1.2.3

Put `mod.json` inside `mods/<id>/`, together with the mod's scripts. `mod.example.json` shows the Prime Sobos fields. Rename it to `mod.json`.

This layout requires `id`, `name`, `version`, `game_version`, `autoload` and `entry`. Set `game_version` to `1.2.3`. The `entry` path is relative to `mods/<id>/`. The manager reads the payload from that directory and manages the matching entry in `override.cfg`.

## Description and author

Both definitions accept these fields. Include them in new packages so users can identify the mod before installing it.

| Field | What to write |
| --- | --- |
| `description` | A JSON object containing a plain-text overview for each language, such as `{"en":"Adds special ball effects.","ja":"特別な性質のソボを追加します。"}`. Use up to 22 language entries and up to 4,000 characters per entry. |
| `author` | The author's display name, up to 120 characters. |
| `readme` | The path of a UTF-8 `.md` or `.txt` explanation file inside the ZIP. Paths are relative to the ZIP root in both layouts. |

The manager selects the description for the interface language, then a matching base language, then English. If English is absent, it uses the first available language code in alphabetical order. The displayed language is shown above the description. Use language codes such as `en`, `ja`, `de`, `es_MX`, `pt_BR`, `zh_CN` or `zh_TW`. A single plain-text description from an older package remains readable.

If `readme` is omitted, the manager looks for `README-en.md`, `README.md`, `README-en.txt`, then `README.txt` at the ZIP root. The file must be no larger than 64 KiB. Its contents are displayed as plain text, including Markdown headings when present. An explicitly named file must exist and meet these limits. If an automatically found README cannot be displayed, the mod can still be installed and the manager shows a message to open the original ZIP.

Existing packages may omit these three fields. Their names, versions and supported game versions remain visible. Existing installation records gain the new text when the mod is installed or updated from a ZIP containing it.

## Required mods

Both definitions accept a `dependencies` array. Use an empty array when the mod has no prerequisites. Each requirement contains an `id`, an exact `version` and, optionally, the required archive's `sha256`.

For a 1.2.3 mod that requires the published Prime Sobos build, the dependency field would be:

```json
"dependencies": [
  {
    "id": "prime_sobo",
    "version": "1.2.3-1.0.2",
    "sha256": "7a7130cf61b2e494d6208446c149cf96b1379e85f0cc6b84dfb2eaacc3115df0"
  }
]
```

The required mod must support the same game version as the parent. A prerequisite's own prerequisites are resolved too. Version strings match exactly, including date suffixes. A mod's stable ID identifies it across updates.

Installed matching prerequisites are reused. Missing ones are located in ZIPs beside the selected package or in the manager's cache. The manager then checks its configured catalog for the same ID and version. A catalog entry provides an HTTPS `zip` URL and should include `sha256`. The dependency's hash is used if the catalog omits one. A download needs at least one of these hashes and must also pass the package ID, version, game-version and ZIP checks.

Publish each prerequisite ZIP and its catalog entry before distributing a package that requires it, or distribute the prerequisite ZIPs alongside the parent. The manager shows the whole group before applying changes. Cycles, conflicting requirements and unavailable prerequisites stop installation before any game files are changed. One operation supports up to 32 mods and 1,024 file changes.

The normal Prime Sobos and Special Sobos example definitions use empty dependency lists. Add entries for the prerequisites your mod actually uses.

## Files to include for the person installing

- A README with the mod's purpose, supported game version, how to use it, known issues and how to remove it.
- A LICENSE describing the terms for your mod and any included third-party files.
- A changelog when you publish an update.
- The package definition and all of its required payload files.

The README and LICENSE can stay at the ZIP root. For 1.2.3, a `.md` or `.txt` document inside the mod folder is also treated as documentation and left out of the installed code files. For 1.3.10, list only files that belong in the game's mod location under `files`. The manager reads the README directly from the ZIP and stores the text in its own record.

Close sobosuba before installing, updating or removing mods. Test the ZIP in a separate game copy before distribution, including the loading file, settings and save preservation. Installing with the manager checks the package structure and file operations; gameplay still needs to be tried in the game.
