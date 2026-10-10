# Feuxton

A Windows app and WoW addon that reduce repeated ability input. Currently supports Beast Mastery Hunter and Retribution Paladin, levels 1â€“30, on WoW Forever (interface 16001).

## Download and run

1. Download **Feuxton-VERSION.zip** from [Releases](https://github.com/brandonjank/feuxton-public/releases).
2. Extract the entire archive into a writable folder and open **Start-Feuxton.cmd**. Keep the included assets, profiles and bundled-addon folders beside the executable.
3. In Settings, select your WoW client folder containing Wow.exe or WowB.exe. The app installs HandHelperProbe there. For the first installation, restart WoW.
4. Keep the addon HUD visible and start live capture. Backtick (`) toggles casting; it starts OFF. Input only goes to the selected WoW window while it is in the foreground.

Compatible addon updates are checked independently of the app. Installation waits for casting/dry run OFF and an idle or closed client. Existing Lua changes require `/reload`; new TOC files require a game restart. Prior addon files are kept in Interface/HandHelperBackups. Disable automatic addon updates in Settings if preferred.

To update the app, close it and extract a newer release over the same folder. Preserve your app-settings.json, window-placement.json and profiles/*.overrides.json. App self-updating and automatic diagnostic uploads are not implemented yet.

## Repository contents and licensing

This public repository contains the addon and its update metadata. Windows app binaries and required runtime resources are distributed as release assets. **The Windows app source is private and is not included.**

The MIT license in addon/HandHelperProbe/LICENSE applies only to the addon. It does not license the Windows app, whose rights are reserved. Addon Lua is readable in installed copies.

Updates declare interface/layout compatibility and SHA-256 file hashes. Downloads use HTTPS and immutable addon commit references; hashes verify file integrity rather than publisher signatures. Windows binaries are currently unsigned.