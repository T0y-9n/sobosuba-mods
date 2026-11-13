# Sobo Crash Fix

sobosuba by keepee. This mod requires the original game.
https://store.steampowered.com/app/1946560/sobosuba

Version 1.3.11-1.0.0 for sobosuba 1.3.11. This package works on its own.

When two sobos overlap, the game keeps a record so it can push them apart.
If one of them is removed while that record is still kept (two sobos merge,
or the run ends), the game can crash on the next physics frame.
This mod drops the record as soon as the sobo is removed.

It changes nothing else. Scores, saves and settings are not touched.
It works with or without other mods. The next Special Sobos release will require it.

The crash is in the game itself, not in a mod. Once the game fixes it,
this mod is no longer needed and can be removed.

## Install

Use the Sobosuba Mod Manager and choose Sobo Crash Fix in the list.

To install by hand, copy `sobo_crash_fix/sobo_crash_fix.gd` and
`styles/sobo_crash_fix_bootstrap.tres` into the game's user data folder,
keeping the two folders.
