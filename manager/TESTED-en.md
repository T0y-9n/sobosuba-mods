# Sobosuba Mod Manager 0.3.0-alpha.10

Checked on Windows with dedicated test game and user-data folders.

- Load order: moving a mod earlier or later saves `mod_load_order.json`, the list follows the saved order, the selected mod stays selected, and the first and last mods cannot move further. 10 checks, 0 failures. The same test failed before the feature was added.
- With a saved order, the game loaded the mods in that order. Without one, the game kept the order it finds the mods in.
- Updating to a release whose files were already copied in by hand now succeeds, and the list and receipt show the new version. A managed file edited by the user still stops the update and is left in place. 8 checks, 0 failures. The same test failed before the fix.
- Prime Sobos 1.3.11-1.0.7, Special Sobos 1.3.11-0.6.2 and Sobo Crash Fix 1.3.11-1.0.0 were installed together through the manager's backend, and the game loaded all three with no errors.

Linux desktop behavior, gameplay, smartphone hardware, long sessions and every MOD combination remain unverified. Export and packaged startup are checked separately before publication.
