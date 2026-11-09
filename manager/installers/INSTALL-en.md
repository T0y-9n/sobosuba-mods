# Install Sobosuba Mod Manager

Version 0.3.0-alpha.8. The game is required to use mods.

## Windows

1. Extract this ZIP.
2. Open the setup EXE inside `Windows`.
3. Approve the Windows administrator prompt. Choose a language and follow the setup pages. The desktop shortcut is optional.
4. Open **Sobosuba Mod Manager** from the Start menu.

The default location is `C:\Program Files (x86)\Sobosuba Mod Manager`. Setup installs for all users and requires administrator approval. It supports 64-bit Windows 10 version 1803 or later, or Windows 11. Close the manager before running setup again. The EXE is unsigned, so Windows may show an unknown-publisher warning. Check the source of your download before running it.

To remove the manager, open Windows **Settings → Apps**, select **Sobosuba Mod Manager**, and choose **Uninstall**. Installed game mods, saves, manager settings and extra files in the installation folder are kept.

For unattended installation, use `/S /NoShortcuts` from an elevated process. An optional `/D=C:\Program Files (x86)\Your Folder` must be the last argument. Choose a dedicated folder directly inside Program Files or Program Files (x86). Setup protects its folder and program files against changes by ordinary users. If an earlier per-user manager is installed, uninstall it first. Its settings are kept.

## Linux x86_64

Ubuntu 22.04 or later, Python 3, tar and a desktop with OpenGL support are required. Setup uses your account and needs no sudo.

1. Extract this ZIP.
2. Open a terminal in its `Linux` folder.
3. Run `sh Sobosuba-Mod-Manager-Setup-Linux-x86_64-v0.3.0-alpha.8.run`.
4. Open **Sobosuba Mod Manager** from your application menu.

The default location is `~/.local/opt/sobosuba-mod-manager`. The application-menu entry is saved under `${XDG_DATA_HOME:-~/.local/share}/applications`. An optional `--prefix "/your/folder"` chooses another application folder. Use a local filesystem that supports Unix executable permissions. Close the manager before running setup again.

To remove the manager, run `sh ~/.local/opt/sobosuba-mod-manager/uninstall.sh`. If you chose another folder, run the `uninstall.sh` in that folder. Installed game mods, saves, manager settings and extra files are kept.

The Linux setup runs in a terminal. Desktop display has yet to be checked on a Linux desktop. Installation and removal have been checked on Ubuntu 24.04 under WSL, including a regular user account.

## First use

Choose the game folder and its version, then use **Install from ZIP** to add a mod. `README-en.md` covers mod installation, prerequisites and automatic updates. The manager and Windows setup support the same 22 languages. Setup initially selects the Windows display language, with English as the fallback. Its first dialog lets you change the language. The Linux terminal setup prints English instructions.

The Windows manager runs with ordinary user permissions. For a machine-wide installation, automatic updates download the newer Windows setup and ask for administrator approval when you close the manager. Setup checks the expected version and tests startup in separate application data before keeping the update. Portable Windows and Linux copies keep their executable-update path. The setup files and OS-specific update ZIPs are separate release assets. The administrator-prompt update handoff still needs a hands-on check.
