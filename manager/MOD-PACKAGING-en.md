# Prepare a mod ZIP

1. Add a package definition to your mod's files.
2. ZIP the files with the layout below.
3. Install the ZIP with Sobosuba Mod Manager and try it in the game.

## 1. Add the package definition

### 1.3.10 and 1.3.11

Copy [mod-package.example.json](../docs/mod-packaging/mod-package.example.json),
rename it to `mod-package.json`, and put it at the ZIP root. The example matches
Special Sobos 1.3.11-0.5.0. Replace its details and file list with your own.

| Field | What it describes |
| --- | --- |
| `format_version` | Use `1` for this package format. |
| `id` | A permanent lowercase ID, such as `my_mod`. Keep it for updates. |
| `name`, `version` | The mod's display name and release version. |
| `game_versions` | Game versions you have checked, such as `["1.3.11"]`. |
| `install_layout` | `user-data-styles` for these versions. |
| `payload_root` | Your code folder, such as `my_mod`. |
| `entry` | Your main Node script relative to that folder, such as `main.gd`. |
| `autoload` | The Node name used by your loader, such as `MyMod`. |
| `bootstrap` | Your loading resource, such as `styles/my_mod_bootstrap.tres`. |
| `files` | Every installed code file and the bootstrap, relative to the ZIP root. |
| `description` | Plain-text descriptions keyed by language, such as `{"en":"Adds a new ball effect."}`. |
| `author`, `readme` | Your name and the path to your UTF-8 README inside the ZIP. |
| `dependencies` | Required mods, or `[]` if your mod works on its own. |

These versions load resources from `user://styles/` at startup. Save this UTF-8 file
as `styles/my_mod_bootstrap.tres`. Change the two strings `MyMod` and
`user://my_mod/main.gd` to match `autoload`, `payload_root` and `entry` in your
definition. The entry script must extend `Node`.

```ini
[gd_resource type="Resource" load_steps=2 format=3]

[sub_resource type="GDScript" id="1"]
script/source = "extends Resource

func _init() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var autoload_name := \"MyMod\"
	var entry := \"user://my_mod/main.gd\"
	if tree.root.get_node_or_null(autoload_name) != null:
		return
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(entry)
	script.take_over_path(entry)
	if script.reload() != OK:
		return
	var node: Node = script.new()
	node.name = autoload_name
	tree.root.add_child.call_deferred(node)
"

[resource]
script = SubResource("1")
```

This uses the loading sequence from Special Sobos' `special_bootstrap.tres`.
The template was checked on Windows 1.3.11, build 26465074.
The manager copies the files to the game's user-data folder. For a manual check,
put `my_mod/main.gd` and `styles/my_mod_bootstrap.tres` under that folder yourself.

| System | Game user-data folder |
| --- | --- |
| Windows | `%APPDATA%\Godot\app_userdata\sobosuba\` |
| Linux | `~/.local/share/godot/app_userdata/sobosuba/` |

### Older 1.2.3

Copy [mod.example.json](../docs/mod-packaging/mod.example.json), rename it to
`mod.json`, and put it inside `mods/<id>/`. Set `id`, `name`, `version`,
`game_version`, `autoload` and `entry`. Use `game_version: "1.2.3"` and an entry
path relative to `mods/<id>/`. The example uses Prime Sobos 1.2.3-1.0.2.
The manager writes the matching autoload entry into `override.cfg`.

## 2. Make the ZIP

For 1.3.x, select these files and folders and ZIP them together. Keep
`mod-package.json` at the top level.

```text
mod-package.json
README-en.md
LICENSE
my_mod/
  main.gd
styles/
  my_mod_bootstrap.tres
```

List `my_mod/main.gd`, its required files and `styles/my_mod_bootstrap.tres` in
`files`. Keep the README and license at the ZIP root. For 1.2.3, use
`mods/<id>/mod.json` and `mods/<id>/<entry>` instead. Include your changelog when
releasing an update.

## 3. Install and check

Close sobosuba. In the manager, select a separate game copy and the matching game
version. Choose **Install from ZIP**, select your ZIP and confirm. Check the
description and author, then start the game and try the mod. Check settings and
saved runs as well as the new behavior. Close the game again and check disabling,
enabling and uninstalling through the manager.

## Publish automatic updates

Publish your ZIP at a permanent HTTPS download URL. Calculate its SHA256 after
building the final ZIP, for example with PowerShell.

```powershell
(Get-FileHash ./my-mod.zip -Algorithm SHA256).Hash.ToLowerInvariant()
```

Submit a pull request to `T0y-9n/sobosuba-mods`, editing `catalog.json` on `main`.
For help preparing it, open an issue with the ZIP URL, supported game version,
package ID, version and SHA256.
[Pull requests](https://github.com/T0y-9n/sobosuba-mods/pulls) ·
[New issue](https://github.com/T0y-9n/sobosuba-mods/issues/new)

The file contains a `mods` array. This entry uses the published Prime Sobos ZIP
for the older game version 1.2.3. Replace all six fields with your mod's details.

```json
{
  "mods": [
    {
      "id": "prime_sobo",
      "name": "Prime sobos",
      "version": "1.2.3-1.0.2",
      "summary": "Prime-numbered sobos that only merge when the sum is a power of two.",
      "zip": "https://github.com/T0y-9n/sobosuba-mods/releases/download/1.2.3-1.0.2/sobosuba-prime-balls-1.2.3-1.0.2.zip",
      "sha256": "7a7130cf61b2e494d6208446c149cf96b1379e85f0cc6b84dfb2eaacc3115df0"
    }
  ]
}
```

Add your entry to the existing array. For a later release, update your entry's
version, URL and hash in another pull request. The catalog accepts one entry per
ID. The package's ID and version must match the entry, and its declared game
version must match the player's selection. After the maintainer merges the
change, the manager reads it from the repository's `main` branch. Players who
select **Auto-update this mod** receive newer compatible releases when the game
is closed. The manager checks on startup, every 30 minutes, or when the player
presses **Check for updates**.

## Required mods

Both package definitions accept exact-version prerequisites.

```json
"dependencies": [
  {
    "id": "prime_sobo",
    "version": "1.2.3-1.0.2",
    "sha256": "7a7130cf61b2e494d6208446c149cf96b1379e85f0cc6b84dfb2eaacc3115df0"
  }
]
```

Each prerequisite must support the same game version. The manager reuses an
installed matching version, then searches ZIPs beside your package, its cache
and the configured catalog. Publish prerequisites and their catalog entries
first, or supply their ZIPs beside yours. The player confirms the whole group
before installation. A downloaded prerequisite needs a SHA256 in its dependency
or catalog entry.

## Reference and limits

- IDs start with a lowercase letter and use lowercase letters, digits and
  underscores, up to 64 characters. Autoload names use letters, digits and
  underscores, starting with a letter or underscore, up to 64 characters.
- Names and author names have a 120-character limit. Version strings have an
  80-character limit. Prerequisite versions match exactly.
- Descriptions accept up to 22 language entries, each up to 4,000 characters.
  Use language codes such as `en`, `de`, `es_MX`, `pt_BR`, `zh_CN` or `zh_TW`.
  The manager tries the interface language, its base language, English, then the
  first available language code alphabetically. It shows the selected language.
- A README must be UTF-8, use `.md` or `.txt`, and fit within 64 KiB. It is shown
  as plain text. With no `readme` field, the manager looks for `README-en.md`,
  `README.md`, `README-en.txt`, then `README.txt` at the ZIP root. An explicitly
  named README must exist and be readable. The manager keeps its text in the
  installation record.
- An operation supports up to 32 mods and 1,024 file changes. Missing
  prerequisites, cycles and conflicting requirements stop installation.
- In 1.2.3 packages, `.md` and `.txt` files inside the mod folder are treated as
  documentation. In 1.3.x packages, `files` lists the files installed into the
  game's user-data folder.
