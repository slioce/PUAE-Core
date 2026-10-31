# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An Amiga system for OpenEmu, backed by the PUAE emulator (libretro-uae, a WinUAE derivative). OpenEmu has no Amiga system of its own, so this repo builds two bundles:

- **`Amiga.oesystemplugin`** (`Amiga/`), the system definition: file types, controls, and a responder that forwards gamepad, keyboard and mouse to the core. OpenEmuKit deletes system plugins found in `~/Library/Application Support/OpenEmu/Systems`, so this one has to be copied into `/Applications/OpenEmu.app/Contents/PlugIns/Systems/`.
- **`PUAE.oecoreplugin`** (`Core/`), the core. It links `deps/libretro-uae` statically as `libpuae.a` and acts as a minimal libretro frontend (`PUAEBridge.c`), wrapped by the `PUAEGameCore` `OEGameCore` subclass. It installs into `~/Library/Application Support/OpenEmu/Cores/`.

The sibling repo `../UME-Core` (the MAME core) is the proven reference for every OpenEmu API used here.

The repo is public (`slioce/PUAE-Core`, GPL-2.0-or-later; the release zips embed libretro-uae, GPL-2.0). Releases are prebuilt plugins on GitHub Releases plus `appcast.xml`, which OpenEmu polls through the core's `SUFeedURL`. Keep the README, the Makefile and this file in English, and keep personal paths and notes out of the tree (`docs/` is ignored for that reason).

## Build

All binaries are **x86_64**. The installed OpenEmu.app (2.4.1 experimental) and its helper are Intel-only and run under Rosetta on Apple Silicon, so an arm64 plugin would not load.

```sh
git submodule update --init deps/libretro-uae   # pinned at 7387937066
make sdk    # OpenEmuBase + OpenEmuSystem frameworks from $(OPENEMU_DIR)/OpenEmu-SDK into build/Release
make puae   # build/libpuae.a (x86_64) from deps/libretro-uae
```

- `make sdk` needs the OpenEmu sources (a shallow clone plus the `OpenEmu-SDK` submodule is enough) at `../OpenEmu`, or wherever `OPENEMU_DIR` points. Per-machine settings go in `Config/Local.mk`, ignored by git; on this machine it holds `OPENEMU_DIR = ../../openemu_ax/OpenEmu`. Current Xcode rejects deployment targets below 12.0. The SDK project sets `GCC_TREAT_WARNINGS_AS_ERRORS = YES`, and current clang flags `-Wenum-compare` in `OESwitchProControllerHIDDeviceHandler.m`, so the Makefile passes `GCC_TREAT_WARNINGS_AS_ERRORS=NO` instead of patching the SDK.
- `make puae` uses libretro-uae's `platform=osx CROSS_COMPILE=1` path with `LIBRETRO_APPLE_PLATFORM=x86_64-apple-macos12.0`, which forces x86_64 on an arm64 host. `STATIC_LINKING_LINK=1` switches the link step to `ar`. Never pass `STATIC_LINKING=1`, because it drops the libretro-common sources that RetroArch would normally provide. Objects go to `build/puae-obj`, so the submodule stays clean.
- Never patch `deps/libretro-uae`.

## Tests

```sh
make test          # unit tests (tests/test_*.c): options, keymap, disk sets, Kickstart links, bridge callbacks
make smoke-check   # boots real games through the bridge, no OpenEmu needed
```

`make smoke-check` also checks that a left click reaches the game, by comparing NZS's trainer screen with and without a scripted click (emulation is deterministic). `puae-smoke --press F:input` and `--snap F:file.ppm` script input and screenshots for debugging by hand.

`make smoke-check` uses an FS-UAE folder (`FSUAE=~/Documents/FS-UAE` by default). `tools/link-fsuae-kickstarts.sh` matches its Kickstarts by MD5, and `build/puae-smoke` then boots an ADF (it checks the save-state round trip and that the A500 Kickstart 1.3 is used), a two-disk ADF set, a WHDLoad `.lha` (A1200 Kickstart 3.1), an HDF, and a run with no Kickstarts, which must fail. Logs and PPM screenshots go to `build/smoke/`; view them with `sips -s format png x.ppm --out x.png`. `puae-smoke` runs any game by hand too (see the header of `tools/puae-smoke.c`).

- PUAE logs `Kickstart: "<name>".` when it loads a Kickstart; the checks rely on that line.
- A missing Kickstart is only logged by PUAE, which then boots without one. `puae_bridge_load` turns that into a failed load.
- A WHDLoad `.lha` must contain a `.slave`. A 75 KB `Syndicate.lha` is just an installer and lands in a Workbench file requester.
- PUAE (libretro-common VFS) prints `retro_vfs_file_open_impl ...` lines straight to stderr. They are noise.

## Installing into OpenEmu.app

```sh
make system install-system   # build/Amiga.oesystemplugin -> /Applications/OpenEmu.app/Contents/PlugIns/Systems/
make install                 # both bundles, through tools/install.sh (the script the release zip ships)
```

- Every install target runs `tools/install.sh`, which refuses to run while OpenEmu is running, keeps a bundle being replaced beside the new one as `<bundle>.bak-YYYYMMDD` (an extension OpenEmu ignores) and clears the quarantine flag. Users run the same script from the release zip, because OpenEmu's double-click import accepts cores but not system plugins (`PluginDocument.importSystemPlugin` throws `outOfSupport`).
- The system plugin links only `OpenEmuSystem` (`@rpath/...`) and has no `LC_RPATH` of its own, the same as the installed system plugins. The host app's rpath resolves it to the app's framework at runtime. `tools/make-icon.swift` renders the sidebar icon (`amiga_library`, 16×16 and 32×32, matching the installed icons).
- The controller mappings are the Commodore 64 plugin's, with keys renamed: Fire = C64 Fire, Fire 2 = C64 Jump. `Keyboard-Mappings.plist` is empty on purpose, so the keyboard stays an Amiga keyboard.
- OpenEmu creates the `openemu.system.amiga` library entry at launch. If OpenEmu is ever started while the plugin is missing, it disables the system, and the system stays disabled when the plugin comes back. Re-enable it in Preferences → Library.
- An OpenEmu update replaces the app bundle, so run `make install` again afterwards.
- **Importer fix.** XADMaster reads AmigaDOS disks as archives, so without help OpenEmu rejects multi-file ADFs whose entries have another system's extension (for example `Syndicate_Disk2.adf` with `.gam`, Vectrex), and it "extracts" single-file ADFs. `Amiga/OEAmigaImportFix.m` swizzles the app's `+[XADArchive OE_archiveForFileAtPath:]` from the system plugin's `+load` so that `adf hdf ipf lha` are never archives. It logs `Import fix installed` (subsystem `org.openemu.Amiga`) in the OpenEmu process. In the helper it stays silent, because XADMaster isn't loaded there. ADFs imported before the fix must be re-imported.
- **Importing from the command line.** `open -a OpenEmu x.adf y.adf` silently drops ADF/HDF, because LaunchServices forwards only types the app declares (macOS types them `public.retro.adf`/`hdf`) while `.lha` gets through. Drag and drop works, and so does `osascript -e 'tell application "OpenEmu" to open {POSIX file "/path/a.adf", POSIX file "/path/b.adf"}'`. With two or more files OpenEmu imports without launching a game.

## Using it

- Build and install both bundles with OpenEmu closed: `make install`. Then drop the Kickstart `.rom` files onto OpenEmu (or onto Preferences → System Files). OpenEmu matches them by MD5 and stores them in `~/Library/Application Support/OpenEmu/BIOS` under the names the core declares (`kick34005.A500`, `kick40068.A1200`, and optionally `kick40063.A600`, `kick37175.A500`). At load the core symlinks them into `~/Library/Application Support/OpenEmu/PUAE/system`.
- Start games by double-clicking them in the library. Opening a single `.adf` from Finder or with `open` fails ("OpenEmu can't open files in the ADF files format"), because the app's document types don't include Amiga files. With two or more files OpenEmu imports instead of opening, and that works.
- Multi-disk games: import every disk unzipped. A zip gets unpacked alone into a temp folder, which loses its siblings. The core finds the other disks by their tag (`_Disk2`, `(Disk 2 of 4)`, `Disk 2`), writes `PUAE/playlists/<game>.m3u` and always boots disk 1. Switch disks from the HUD's disc menu. A hand-written `<game>.m3u` next to the game in `roms/Amiga/` takes precedence, for save disks or odd names.
- Saves: WHDLoad and floppy writes go to OpenEmu's battery-saves folder for the core (`WHDSaves/`, `*_save.adf`).

Floppy speed: Turbo by default (`puae_floppy_speed=0`, no disk-rotation emulation). On New Zealand Story's main load that saves about 12 s, roughly half the time. The core's display-mode menu in the in-game HUD (Floppy Speed: Turbo / Normal / 2x / 4x / 8x) switches it live, for the rare loader that needs real disk timing. OpenEmu saves the choice per core, so it applies to every Amiga game, and hands it back in `displayModeInfo`. PUAE reads its options once in `retro_init`, so the saved speed goes in through `puae_bridge_config.options`, and later changes through `puae_bridge_set_option` (picked up at PUAE's next frame). `puae-smoke --option puae_floppy_speed=100` does the same in the harness.

Known limitations:

- **Load errors.** OpenEmu 2.4.1's helper wraps a core's load error in a generic "The emulator could not load ROM." (`OpenEmuHelperApp.loadROM`), so the core's reason, such as a missing Kickstart, only shows up in the log. OpenEmu's own missing-BIOS alert names the two required Kickstarts. The optional ones (A600 3.1, A500+ 2.04) are needed only when PUAE picks those models from the path, for example `(A600)`, `ECS` or `(A500+)`. Without them the user sees only the generic error.
- **IPF.** Not importable until capsimg is built (deferred). Without capsimg, PUAE boots an IPF silently to the Kickstart insert-disk screen.
- **CD32 pad.** Only Fire and Fire 2 are mapped. CD32-pad games that wait for PLAY can't go on.

## Releasing

```sh
make dist      # build/PUAE-Core_<version>.zip (both bundles + install.sh) and build/PUAE_<version>.zip (core only)
make release   # push, GitHub Release v<version> with both zips, then appcast.xml committed and pushed
```

The version is `CFBundleVersion` in `Core/Info.plist` (the Makefile reads it from there); bump it, and the same key in `Amiga/Info.plist`, before `make release`. OpenEmu's core updater extracts the whole zip into its Cores folder and takes the first entry as the plugin, so the appcast points at the core-only zip. The system plugin cannot be updated by OpenEmu; users rerun `install.sh` when it changes or after an OpenEmu update. OpenEmu caches a failed appcast fetch for 5 minutes (raw.githubusercontent `max-age`).

## Debugging

```sh
/usr/bin/log show --last 10m --style compact --info --debug --predicate 'subsystem == "org.openemu.PUAE" OR subsystem == "org.openemu.Amiga"'
```

PUAE's own log (model, `Kickstart: "..."`, WHDLoad) goes to subsystem `org.openemu.PUAE`. The core runs inside `OpenEmuHelperApp`. For anything emulation-side, reproduce it first with `build/puae-smoke`, which runs the same bridge without OpenEmu.

## Box art and titles

OpenEmu looks covers up in OpenVGDB, which has no Amiga games. The Amiga system plugin does the job itself, inside the OpenEmu process:

- `Amiga/OEAmigaBoxArtFetcher.m` checks the Amiga games without a cover when the library loads, and new ones when the library's writer context saves them. The library window shows the main context's instance of a new game, which keeps the importer's temporary ID, so the cover has to go on that instance: an instance fetched by the permanent ID is a second copy the window never shows, and the cover then appears only after a restart. Main gives its instance a permanent ID only after the writer has saved the game, because doing it earlier makes Core Data store the game twice. `tests/test_box_art_library.m` replays that save chain.
- It downloads the libretro thumbnail server's "Commodore - Amiga/Named_Boxarts" index and caches it for a week at `~/Library/Application Support/OpenEmu/Amiga/boxart-index.html`.
- It matches the game's file name (`Amiga/OEAmigaBoxArt.m`, unit-tested in `tests/test_box_art.m`), downloads the PNG and sets it with `OEDBGame -setBoxImageByURL:`. The matched title goes to `gameTitle`, with " (Disk N)" for multi-disk entries. The main context is then saved, exactly like "Add Cover Art from File…".
- It never replaces an existing cover or title, honours OpenEmu's `automaticallyGetInfo` preference, and sets nothing without a confident match. For example, `swos2223` gets no cover. Logs go to subsystem `org.openemu.Amiga`, category `boxart`.
