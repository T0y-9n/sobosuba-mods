# Prime Sobos for sobosuba 1.3.11

Mod version 1.3.11-1.0.2. Requires sobosuba 1.3.11, the current regular release.
For the older game version 1.2.3, download mod version 1.2.3-1.0.4.
https://github.com/T0y-9n/sobosuba-mods/releases/tag/1.2.3-1.0.4

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
Save screenshots, directly below send scores in desktop and mobile settings,
is off by default, including for existing settings. Enable it to save future
game-over screens to your Steam screenshots.

Finish a saved prime run before disabling or removing the mod. Saved runs
containing prime sobos may need the mod to resume.

## Checked and remaining issues

On Windows, the installed 1.3.11 executable, build 26465074, loaded the
mod through the custom-style bootstrap. Sixteen focused checks had no failures,
covering settings switches, spawning, 3 + 5 = 8, two 3s staying separate,
achievement and official leaderboard suppression, and rendered screens.
The spawn check used a forced rate. Normal spawn probabilities were not measured.

Smartphone layout support in 1.3.11-1.0.1: settings use the native mobile page,
the level label follows the visible layout, and the initial guide fits the
available screen. Mod ranking controls follow the native mobile visibility.
The old 1280 x 900 level-label clipping is also addressed.

The final Windows phone-size rendered check reported 41 checks, no failures;
seven images at 375 x 667, 393 x 852, 360 x 780 and landscape were inspected.
Related static checks reported 13 checks, no failures. This was a PC test,
not a real mobile-device test. Real-device touch, safe areas and software
keyboards remain unverified. Windows orientation and shutdown texture-release
warnings remain.
Long play sessions and the native Linux game have not been checked for this
release. Loading a PCK was not part of the verification.

This is an unofficial mod. sobosuba and its game content belong to keepeetron.
