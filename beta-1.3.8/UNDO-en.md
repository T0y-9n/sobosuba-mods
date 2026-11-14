# Undo for sobosuba 1.3.11

Restores the board from immediately before a launch. Five launches are kept. The U key restores the newest one.

While the undo switch is on, every mode is kept off the leaderboard, and the base game's score submission switch stays off. The undo switch is on when the mod is installed. Turning it off lets the next run submit again. The run already in progress stays off the leaderboard.

## Install

Copy `undo_mod/` to `user://undo_mod/` and `styles/undo_bootstrap.tres` to `user://styles/undo_bootstrap.tres`.

`user://` is `%APPDATA%\Godot\app_userdata\sobosuba` on Windows.

The switch is on the game settings screen, under show instructions. Its label is "undo", or "一手戻す" when the game language is Japanese.

## Package

```sh
python beta-1.3.8/package_undo.py --output /your/build/folder
```

The self-test script is not part of the zip. It runs only when `undo.flag` sits next to the scripts.
