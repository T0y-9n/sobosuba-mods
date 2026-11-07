# Prime Sobos for sobosuba 1.3.11

Mod version 1.3.11-1.0.0. Requires sobosuba 1.3.11, the current regular release.
For the older game version 1.2.3, download mod version 1.2.3-1.0.2:
https://github.com/T0y-9n/sobosuba-mods/releases/tag/1.2.3-1.0.2

## Install

Close the game. In Sobosuba Mod Manager, check the game folder and select
1.3.11, then choose Install from ZIP and select this ZIP. Review the package
and confirm. Start the game normally. The package has no required mods.

For manual installation, copy prime_mod and styles into the game's user-data
folder. On Windows this is %APPDATA%\Godot\app_userdata\sobosuba.
On Linux it is ~/.local/share/godot/app_userdata/sobosuba.
Keep the folders inside that location. The bootstrap belongs at
styles/prime_bootstrap.tres. No override.cfg is needed for this version.

## Play

Use prime balls in the game's settings to turn the mode on or off for the next
run. Some spawns become 3, 5, 11, 13 or 19. Two prime sobos merge only when
their sum is a power of two, such as 3 + 5 = 8. Two 3s stay separate.
Prime runs disable Steam achievements and the official leaderboard.
Send scores to the mod's separate ranking is off by default.

Finish a saved prime run before disabling or removing the mod. Saved runs
containing prime sobos may need the mod to resume.

## Checked and remaining issues

On Windows, the installed 1.3.11 executable, build 26465074, loaded the
mod through the custom-style bootstrap. Sixteen focused checks had no failures,
covering settings switches, spawning, 3 + 5 = 8, two 3s staying separate,
achievement and official leaderboard suppression, and rendered screens.
The spawn check used a forced rate. Normal spawn probabilities were not measured.

At 1280 x 900, the prime-level text on the right extends beyond the window.
Long play sessions and the native Linux game have not been checked for this
release. Loading a PCK was not part of the verification.

This is an unofficial mod. sobosuba and its game content belong to keepeetron.
