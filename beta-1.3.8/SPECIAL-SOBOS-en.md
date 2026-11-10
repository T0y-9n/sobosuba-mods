# Special Sobos

sobosuba by keepee. This mod requires the original game.
https://store.steampowered.com/app/1946560/sobosuba

Idea by Hilobo

Version 1.3.11-0.5.6 for sobosuba 1.3.11. This package works on its own.

Special Sobos works only in classic (radix 2). Other modes, including Radix 3, play like the base game again.

| Sobo | What it does |
| --- | --- |
| Small | Uses a smaller shape without changing its number. |
| Puffy | Feels less gravity after leaving the selection bar. |
| Magnet | Attracts nearby ordinary sobos, repels other magnets, and holds non-magnets it touches. It does not launch them. |
| Throwing | Immediately throws a sobo it touches, then waits for its cooldown before throwing the same sobo again. |

## Install

1. Close the game.
2. Open Sobosuba Mod Manager 0.3.0-alpha.5 or later and select **1.3.11**.
3. Choose **Install from ZIP**, select this ZIP and confirm the update or installation.
4. Start the game. Open **Settings → game → special sobos** on desktop, or **Settings → special sobos** on mobile.
5. Turn on the main switch and start a new run. Each kind has its own switch.

Finish an in-progress run with an older Special Sobos release before updating.

For manual installation, copy `special_mod` and `styles` into the game's user-data folder. On Windows, this is `%APPDATA%\Godot\app_userdata\sobosuba`. On Linux, it is `~/.local/share/godot/app_userdata/sobosuba`. Keep the folder structure. No game files are replaced.

## Tune while playing

Press **Settings page** to cycle through Kinds, Spawn chance, Relative frequency,
Small / Puffy, Magnet and Throwing. Type a number and press Enter, or leave the
field, to save it and apply it to the current board. Decimals are allowed except
for counts and shape levels. A value outside the stated range is rejected and
the previous number returns. **Reset tuning to defaults** resets all twenty
numbers together and keeps your kind switches.

| Setting | Range | Initial value |
| --- | --- | --- |
| Spawn chance for stages 1–7 | 0–100% each | 2, 3, 4, 5, 6, 7, 8% |
| Relative frequency of Small, Puffy, Magnet, Throwing | 0–100 each | 3, 3, 2, 1 |
| Small shape levels down | 1–10, whole number | 3 |
| Puffy gravity multiplier | 0–3 | 0.5 |
| Magnet attraction multiplier | 0–20 | 2 |
| Magnet range in radii | 1.1–20 | 3 |
| Magnet field strength | 0–20 | 0.25 |
| Magnet contact hold strength | 0–20 | 2 |
| Maximum held sobos | 0–20, whole number | 3 |
| Throwing launch speed | 0–3000 | 500 |
| Throwing cooldown | 0.05–30 seconds | 2 |

A frequency of zero prevents that kind from being picked. If all frequencies are
zero, no new special sobos appear. Spawn chances and frequencies affect future
spawns. Changes to gravity and magnet force affect sobos already on the board;
Small shape changes apply to existing Small sobos. Throwing speed applies on the next contact. A shorter cooldown also
shortens an existing wait. The attraction multiplier does not change magnet
repulsion; field strength affects both attraction and repulsion.

The previous magnet-only setting is kept. English and Japanese tuning labels are included; other game
languages use English for these new labels.

Special runs keep scores local and block Steam scores, world-ranking submissions
and achievements. Switch changes apply from the next run. Finish a saved special
run before disabling or removing the mod. Settings and saves are kept when the
manager removes the mod.


## Export your settings

Press **Export settings** in the Special Sobos settings screen to save the current
switches, kind choices and numeric values as JSON in your Downloads folder.
The filename includes the mod version and local date and time. Existing exports
are kept. The screen shows the full saved path. If Downloads is unavailable or
unwritable, the file is saved in the game's user-data folder instead. A failure
at both locations is shown on screen and in the game log.

The JSON also includes the mod version and export time. You can share it when
reporting the settings you play with.


## Mobile settings

The settings entry and Back action follow the platform settings page. The settings screen supports portrait and landscape layouts. Numeric tuning and separate package installation use the existing settings. Real-device touch, safe-area and software-keyboard checks are still required.
