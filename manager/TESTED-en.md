# Sobosuba Mod Manager 0.3.0-alpha.15

Checked on Windows with dedicated test game and user-data folders.

- Version: from the start, the window title and the heading at the top both show "Sobosuba Mod Manager 0.3.0-alpha.15". 4 checks, 0 failures. Before the change the same test had 2 failures.
- Log: installs, updates, refused installs and disabling write timed lines to `manager.log`, and the screen has "Open log" and "Copy diagnostics". Above 1 MB the log keeps one older file, `manager.log.1`. The home folder is written as `~`, so the account name is not in the log. When the log cannot be written, disabling still goes ahead. 22 checks, 0 failures. Before the change the same test had 8 failures.
- Keep this version: a pinned mod is not offered the newer catalog version and stays on its version with automatic updates on. Unpinning offers the newer version again. Installing a mod that needs a newer version of a pinned mod stops and leaves the pinned files unchanged. 20 checks, 0 failures. Before the change the same test had 8 failures.
- Light and Dark screens were captured with the Pinned label, "Open log" and "Copy diagnostics" in place.

The checks below were run for 0.3.0-alpha.14.

- Appearance: System follows a dark OS and a light OS, Light and Dark stay fixed, an unknown choice is light, dark ink on paper is 15.38 to 1 and dark muted on paper is 8.91 to 1, the light colors match the previous Cobalt set, and a real manager.json stores dark and reads an unknown value back as system. 14 checks, 0 failures. Before the choice existed the same test had 2 failures.

- Load order: moving a mod earlier or later saves `mod_load_order.json`, the list follows the saved order, the selected mod stays selected, and the first and last mods cannot move further. 10 checks, 0 failures. The same test failed before the feature was added.
- With a saved order, the game loaded the mods in that order. Without one, the game kept the order it finds the mods in.
- Updating to a release whose files were already copied in by hand now succeeds, and the list and receipt show the new version. A managed file edited by the user still stops the update and is left in place. 8 checks, 0 failures. The same test failed before the fix.
- Prime Sobos 1.3.11-1.0.7, Special Sobos 1.3.11-0.6.2 and Sobo Crash Fix 1.3.11-1.0.0 were installed together through the manager's backend, and the game loaded all three with no errors.

- Each installed mod shows a drag handle. Dragging rows with real mouse events saved the new load order and the list followed it, and drops that would put a mod before a mod it requires were refused. Drops on the lower half of a row were checked by calling the drop handlers directly, because the headless test cannot place the pointer there. 30 checks, 0 failures. The checks failed before the change.
- The load order screen check was run again for this version. 15 checks, 0 failures.

The checks below were run for 0.3.0-alpha.12. The code they cover has not changed since.

- Started with the hidden window style that 0.3.0-alpha.10 and earlier use for "Update and restart", the manager shows its window. The 0.3.0-alpha.11 build, started the same way, showed no window. 2 checks, 0 failures.
- When another running program holds the old manager file, the Setup cleanup keeps its temporary folder instead of failing, and a later setup removes the folder once the file is free. 9 checks, 0 failures. Before the fix the cleanup failed with access denied.
- With a second copy of the manager running from the same executable, the notice says another copy is running. With one copy it says nothing. 6 checks, 0 failures.

The checks below were run for 0.3.0-alpha.11. The code they cover has not changed since.

- The manager installs bootstraps in `mod_bootstraps/` and one loader in `styles/`, and moves bootstraps left in `styles/` by an earlier manager when their hash matches the receipt. 33 checks, 0 failures. The same test failed 16 checks before the change.
- A mod cannot be moved before a mod it requires, and saving the order keeps required mods first. Moving a mod earlier or later saves `mod_load_order.json` and the list follows it. 15 checks, 0 failures. The two dependency checks failed before the fix.
- With five released mods installed through the manager's backend, the game loaded them in the saved order, forward and reversed. With the 0.3.0-alpha.10 backend, the reversed order was ignored and the game loaded them by file name.
- "Update and restart" now starts the manager with its window visible. Started with the earlier hidden start style, the 0.3.0-alpha.10 manager ran with no visible window.
- Updating to a release whose files were already copied in by hand succeeds, and a managed file edited by the user still stops the update. 8 checks, 0 failures.

Linux desktop behavior, the full Setup path with its administrator prompt, gameplay with a screen, smartphone hardware, long sessions and every MOD combination remain unverified. Export and packaged startup are checked separately before publication.
