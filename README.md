# Mega Maker for Android

Unofficial Android port of **Mega Man Maker 1.10.5.4** (GameMaker), developed for the **AYN Odin 3**.

The APK can be downloaded from the repository's **Releases** section.

## What's Included in the Port

- **On-screen touch controls** (can be disabled under OPTIONS > OTHER > TOUCH) and Xbox controller support.
- **Touch-friendly level editor:** PLACE / ERASE / MOVE / SELECT, UNDO / REDO, recent items, and favorites.
- **NSF music playback** using GameMusicEmu (JNI extension).
- **Online features:** Login, REMEMBER ME, online levels, and Wily Challenge (gzip support using Android's zlib).
- **Display options:** OPTIONS > VIDEO/SOUND > SCREEN offers ORIGINAL (8:7), 4:3, 16:9, and FULL. These modes stretch the image using sharp scaling. Menus and the level editor remain in 8:7.

## This Repository Does Not Include the Game

This repository contains only the patches and tools required for the Android port.

To build the port, you must provide your own copy of **Mega Man Maker 1.10.5.4**:

- Place `data.win` in `work/windows-original/`.
- Place the decompiled game code (using UndertaleModTool) in `work/decompiled/CodeEntries/`.

## Building the Port

**Requirements:**

- Android SDK (Build Tools 36 and NDK)
- Python 3 with Pillow
- UndertaleModTool CLI in `work/tools/utmt/`
- Base runner APK in `work/base-v1.apk`
- Your own signing keystore in `work/probe-key.jks`

**Build command (PowerShell):**

```powershell
.\work\build_megamaker.ps1 -Out 'outputs\Mega Maker.apk'
```

## Project Files

| File | Description |
|---|---|
| `work/patch_startup.py` | Generates GML patches in `work/android-gml/` |
| `work/android_ui.gml` | Menus, keyboard, display modes, account management, and level files |
| `work/android_touch.gml` | In-game touch controls |
| `work/android_editor.gml` | Touch interface layer for the level editor |
| `work/music/` | GameMusicEmu JNI bridge and zlib integration |
| `work/apply_launcher_icon.py` | Android launcher icon |
