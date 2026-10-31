# PUAE-Core

Amiga support for [OpenEmu](https://openemu.org): an Amiga system plugin and a core built on PUAE, the libretro port of the UAE/WinUAE emulator. Import your ADF, HDF and WHDLoad games into the OpenEmu library, double-click one, and it boots with the right Kickstart and the right Amiga model. Both plugins come prebuilt: download, run the install script, done.

## Features

- **Floppy, hard disk and WHDLoad games**: `.adf`, `.hdf` and WHDLoad `.lha` archives. PUAE picks the Amiga model from the file type and name: an A500 for floppies, an A1200 for WHDLoad and hard disks, or the model named in the file name, such as `(A1200)`, `AGA` or `(A600)`. Without the matching Kickstart the game refuses to load, instead of booting on PUAE's built-in replacement ROM.
- **Multi-disk games** found by name: `Game_Disk2.adf`, `Game (Disk 2 of 4).adf` and `Game Disk 2.adf` join disk 1 as a set, and the HUD's disc menu swaps disks. A hand-written `.m3u` next to the game takes precedence, for save disks or odd names.
- **Gamepad, mouse and keyboard.** The joystick on the pad, Fire and Fire 2 on the buttons, the mouse where the game needs a mouse, and the keyboard stays an Amiga keyboard, so Shift, Return, the function keys and the rest reach the game.
- **Turbo floppy loading** by default (no disk-rotation emulation, which halves load times). Floppy Speed in the in-game display-mode menu switches to Normal, 2x, 4x or 8x for the rare loader that needs real timing.
- **Save states**, and saves that persist: WHDLoad saves and writes to floppies land in OpenEmu's battery-saves folder for the core, so the original images stay untouched.
- **Box art and titles.** OpenEmu's database has no Amiga games, so the system plugin fetches covers and proper titles from the libretro thumbnail server after an import, when the file name matches a known game.
- **Imports that work.** OpenEmu treats AmigaDOS disks as archives and rejects or unpacks them; the system plugin fixes that inside OpenEmu, so ADF, HDF and LHA files import as what they are.
- **Updates itself** through OpenEmu's core updater once installed (the core; the system plugin changes rarely, see Install).

## Requirements

OpenEmu 2.4.1 on macOS 12 or later. OpenEmu.app is an Intel binary, so the plugins are x86_64 too; on Apple Silicon everything runs under Rosetta.

You need your own Kickstart ROMs. The core ships none, and neither do the games.

## Install

1. Download `PUAE-Core_<version>.zip` from the [latest release](https://github.com/slioce/PUAE-Core/releases/latest) and unzip it.
2. Quit OpenEmu, then in Terminal run the script that came in the zip:

   ```sh
   sh ~/Downloads/PUAE-Core_<version>/install.sh
   ```

   It copies `Amiga.oesystemplugin` into `/Applications/OpenEmu.app/Contents/PlugIns/Systems/` and `PUAE.oecoreplugin` into `~/Library/Application Support/OpenEmu/Cores/`, clears the quarantine flag that Safari sets on downloads, and keeps anything it replaces next to the new copy as `<bundle>.bak-<date>`.
3. Launch OpenEmu, open Preferences › System Files and drop your Kickstart ROMs onto it (see below). Then import your games: drag them into the library.

Why a script and not a double-click: OpenEmu installs cores from a double-click, but it only accepts its own system plugins and deletes third-party ones found in `~/Library/Application Support/OpenEmu/Systems`. The Amiga system therefore has to live inside OpenEmu.app, and an OpenEmu update, which replaces the app, removes it. After an update, run the script again. The core needs no attention: from the first launch on, OpenEmu checks this repository's `appcast.xml` and installs newer versions by itself.

If OpenEmu was ever started while the Amiga plugin was missing, it disables the system; turn it back on in Preferences › Library.

To install by hand instead, quit OpenEmu, copy the two bundles into the folders above and clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/OpenEmu.app/Contents/PlugIns/Systems/Amiga.oesystemplugin
xattr -dr com.apple.quarantine ~/Library/Application\ Support/OpenEmu/Cores/PUAE.oecoreplugin
```

The plugins are signed ad hoc, not notarized.

## Kickstarts

OpenEmu matches BIOS files by MD5 and stores them under the names the core declares. Drop the files onto Preferences › System Files (or onto the library window); their file names don't matter.

| File             | Kickstart                      | MD5                                | Needed for                              |
|------------------|--------------------------------|------------------------------------|-----------------------------------------|
| `kick34005.A500`  | 1.3 (34.5), A500              | `82a21c1890cae844b3df741f2762d48d` | Required: floppy games                   |
| `kick40068.A1200` | 3.1 (40.68), A1200            | `646773759326fbac3b2311fd8c8793ee` | Required: WHDLoad, HDF, AGA games        |
| `kick40063.A600`  | 3.1 (40.63), A600             | `e40a5dfb3d017ba8779faba30cbd1c8e` | Optional: names tagged `(A600)` or `ECS` |
| `kick37175.A500`  | 2.04 (37.175), A500+          | `dc10d7bdd1b6f450773dfb558477c230` | Optional: names tagged `(A500+)`         |

The core links the installed ROMs into `~/Library/Application Support/OpenEmu/PUAE/system` when a game loads. A game whose Kickstart is missing fails to load; OpenEmu's own alert names the two required files, while a missing optional one only shows up in the log (see Debugging).

## Games

- **Importing.** Drag files into the library. `open -a OpenEmu game.adf` does not work, because macOS forwards only the file types the app declares; `osascript -e 'tell application "OpenEmu" to open {POSIX file "/path/a.adf", POSIX file "/path/b.adf"}'` does. With two or more files OpenEmu imports without starting a game.
- **Multi-disk games**: import every disk, unzipped. A zip is unpacked alone into a temporary folder, which loses its siblings. The core writes `PUAE/playlists/<game>.m3u` from the disks it finds and always boots disk 1.
- **WHDLoad**: an `.lha` must contain a `.slave`. A small archive that lands in a Workbench file requester is an installer, not the game.
- **Saves** go to `~/Library/Application Support/OpenEmu/PUAE/Battery Saves/`: `WHDSaves/` for WHDLoad games, `<disk>_save.adf` for writes to floppies.
- **Floppy speed** is Turbo for every Amiga game until you change it; OpenEmu remembers the choice for the core.
- **Covers and titles** are only set when the file name matches a known game with confidence, and never replace a cover or title already there.

## Build from source

Requires Xcode 16 or later and an OpenEmu checkout next to this one (for the OpenEmu SDK frameworks); set `OPENEMU_DIR` in `Config/Local.mk`, which git ignores, to use another location.

```sh
git clone --recurse-submodules https://github.com/slioce/PUAE-Core.git
git clone --depth 1 --recurse-submodules https://github.com/OpenEmu/OpenEmu.git   # sibling checkout
cd PUAE-Core
make sdk          # OpenEmuBase and OpenEmuSystem frameworks into build/Release
make puae         # libretro-uae as build/libpuae.a (a few minutes)
make system core  # build/Amiga.oesystemplugin and build/PUAE.oecoreplugin
make test         # unit tests
make install      # both bundles into OpenEmu (quit OpenEmu first)
```

`deps/libretro-uae` is the unmodified upstream libretro-uae, built for x86_64 on any host. `make smoke-check` boots real games through the bridge without OpenEmu, from an FS-UAE folder (`FSUAE=…`); it expects the games listed in `tools/smoke-check.sh` and skips the ones it doesn't find.

## Project layout

```
Amiga/              The system plugin: file types, controls, the responder that forwards gamepad,
                    keyboard and mouse to the core, the import fix and the box art fetcher.
Core/               The core plugin: PUAEGameCore (OEGameCore) over PUAEBridge, a minimal libretro
                    frontend, plus options, disk sets, keymap, mouse and floppy speed as plain C.
tests/              Unit tests (make test).
tools/              install.sh (what the release zip runs), puae-smoke (the bridge from the command
                    line), smoke-check.sh, make-appcast.sh, make-icon.swift.
deps/libretro-uae   Upstream libretro-uae, as a submodule.
appcast.xml         The feed OpenEmu polls for core updates; rewritten by `make release`.
Makefile            sdk, puae, system, core, test, smoke-check, install, dist, appcast, release.
```

`CLAUDE.md` has the details of the build, the tests and the debugging notes.

## Releasing

Releases are built on a Mac, not in CI: the build needs an OpenEmu checkout, and the result is verified inside OpenEmu.

1. Bump `CFBundleVersion` in `Core/Info.plist` and `Amiga/Info.plist` (`MAJOR.MINOR.PATCH`), commit.
2. `make release`. It builds `PUAE-Core_<version>.zip` (both bundles and `install.sh`) and `PUAE_<version>.zip` (the core alone, the file OpenEmu's updater downloads), pushes the commit, creates the GitHub Release `v<version>` with both attached, then regenerates `appcast.xml`, commits and pushes it. OpenEmu compares `sparkle:version` with the installed `CFBundleVersion`, so the appcast only goes live once the download exists.

## Debugging

The core logs through `os_log` under the subsystem `org.openemu.PUAE` (PUAE's own log: model, `Kickstart: "…"`, WHDLoad) and the system plugin under `org.openemu.Amiga` (category `boxart` for covers). The core runs inside `OpenEmuHelperApp`:

```sh
/usr/bin/log show --last 10m --style compact --info --debug \
  --predicate 'subsystem == "org.openemu.PUAE" OR subsystem == "org.openemu.Amiga"'
```

For anything emulation-side, `build/puae-smoke` runs the same bridge without OpenEmu, with scripted input and screenshots; its header explains the options.

## Known limitations

- OpenEmu 2.4.1 wraps a core's load error in a generic "The emulator could not load ROM.", so the real reason, usually a missing Kickstart, is only in the log.
- IPF images are not supported (no capsimg).
- CD32 pad: only the two fire buttons are mapped, so CD32 games that wait for Play can't go on.
- No rewind.

## Acknowledgements

The emulator is [libretro-uae](https://github.com/libretro/libretro-uae), the libretro port of PUAE, itself built on UAE and WinUAE by Bernd Schmidt, Toni Wilen and many others; the core embeds it unmodified, with the WHDLoad files libretro-uae ships. The system plugin follows the design of the [OpenEmu Team](https://github.com/OpenEmu)'s own system plugins, and its controller mappings started from their Commodore 64 plugin. Covers come from the [libretro thumbnails](https://thumbnails.libretro.com). PUAE-Core was written with the help of AI coding agents; design, review and testing are the author's. This project is not affiliated with OpenEmu or libretro.

## License

Copyright © 2026 Alessandro Lioce. The code in this repository is free software, released under the [GNU General Public License version 2](LICENSE) or any later version. It is combined with libretro-uae, which is GPL-2.0, so the plugins in the release zips are distributed under the GPL-2.0; each core carries the license texts in `Contents/Resources/legal/`, and the corresponding source is the `deps/libretro-uae` submodule commit of the release tag. The controller mappings and the responder client header derived from OpenEmu's Commodore 64 plugin remain under the OpenEmu Team's BSD 3-Clause license.
