# Sobosuba Mod Manager 0.3.0-alpha.5

The storage checks used copies of the game executable and separate game-data
folders. They did not start the game.

- Version detection and beta-package operations: 9 checks, no failures.
- File ownership, version matching and interrupted changes: 63 checks, no failures.
- Stable and beta mods with the same ID: 15 checks, no failures.
- Corrupt ZIPs and manually installed files: 10 checks, no failures.
- Descriptions, authors and READMEs: 31 checks, no failures.
- Required mods and grouped changes: 28 checks, no failures.
- UI operation paths and 22 languages: 3,786 checks, no failures. The count
  includes text keys and formatting arguments for each language. It includes
  refreshing an incompatible disabled mod and clearing a resolved error.
- Automatic mod updates: 47 checks, no failures.
- The beta 1.3.11 Prime Sobos package was installed, disabled, re-enabled and
  uninstalled through the manager's file-operation backend.

The first UI run could not start because its test-engine path was missing.
After selecting the existing engine, the new startup detection exposed a
readiness issue, which was fixed before repeating the UI checks.

The exported Windows app detected beta 1.3.11, then installed, disabled,
re-enabled and uninstalled Prime Sobos through its interface. A person selected
the ZIP in the native file picker because the automation tool could not target
that child window. The remaining actions were automated and checked on screen.
The manager was closed afterwards. The real game's 28 files and 92 game-data
files had identical names and SHA256 hashes before and after the check.

The new Linux executable started under Ubuntu 24.04 in WSL with a separate HOME
and XDG folders. Its headless startup probe saved version 0.3.0-alpha.5 and the
expected executable SHA256, then exited with code 0. This was not a desktop UI
check. Both executables were exported from source revision 697a493.

The automatic independent review did not respond. The project owner authorized
the coordinator to merge the source changes after the focused checks above.

Remaining checks include a native Linux desktop, administrator-prompt update
handoff, native-speaker review of all translations, long game sessions and every
combination of mods. Each mod needs its own working loader for the selected game
version. Sandbox gameplay was outside this verification.
