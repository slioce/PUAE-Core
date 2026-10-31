# PUAE-Core: Amiga system plugin + PUAE core for OpenEmu.
# Everything is x86_64: the installed OpenEmu.app (2.4.1) is Intel-only and runs under Rosetta.
#
#   make sdk puae     OpenEmu SDK frameworks and libretro-uae as build/libpuae.a
#   make system core  build/Amiga.oesystemplugin and build/PUAE.oecoreplugin
#   make test         unit tests; make smoke-check boots real games through the bridge
#   make install      installs both bundles (quit OpenEmu first)
#   make release      zips the bundles, publishes a GitHub Release and updates appcast.xml
#
# Per-machine settings go in Config/Local.mk (not committed), for example:
#   OPENEMU_DIR = ../../openemu_ax/OpenEmu

ARCH  := x86_64
MINOS := 12.0
BUILD := build
PUAE  := deps/libretro-uae
JOBS  := $(shell sysctl -n hw.ncpu)
OPENEMU_DIR ?= ../OpenEmu
-include Config/Local.mk

# The plugin version is CFBundleVersion, which OpenEmu compares with the appcast.
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleVersion' Core/Info.plist)
REPO    := slioce/PUAE-Core

CFLAGS_COMMON := -arch $(ARCH) -mmacosx-version-min=$(MINOS) -O2 -g -Wall -Wextra \
                 -I$(PUAE)/libretro-common/include -ICore

FSUAE ?= $(HOME)/Documents/FS-UAE

# Core sources shared by the core bundle and the smoke tool.
BRIDGE_SRCS := Core/PUAEBridge.c Core/PUAEOptions.c Core/PUAEDiskList.c Core/PUAESystemDir.c

# Bundles and where they install.
SYSTEM      := $(BUILD)/Amiga.oesystemplugin
SYSTEM_SRCS := Amiga/OEAmigaSystemResponder.m Amiga/OEAmigaImportFix.m Amiga/OEAmigaBoxArt.m Amiga/OEAmigaBoxArtFetcher.m
SYSTEM_RES  := Amiga/Controller-Mappings.plist Amiga/Controller-Preferences.plist Amiga/Keyboard-Mappings.plist \
               Amiga/amiga_library.png Amiga/amiga_library@2x.png
CORE        := $(BUILD)/PUAE.oecoreplugin
CORE_SRCS   := Core/PUAEGameCore.m $(BRIDGE_SRCS) Core/PUAEKeymap.c Core/PUAEMouse.c Core/PUAEFloppySpeed.c
OBJC_FLAGS  := -fobjc-arc -fmodules -F $(BUILD)/Release

# Release archives. OpenEmu's core updater extracts the whole zip into its Cores folder and treats the
# first entry as the plugin, so the appcast zip holds the core alone; the full zip adds the system
# plugin and the install script for a first installation.
CORE_ZIP := $(BUILD)/PUAE_$(VERSION).zip
FULL_ZIP := $(BUILD)/PUAE-Core_$(VERSION).zip
STAGING  := $(BUILD)/dist/PUAE-Core_$(VERSION)

.PHONY: all sdk puae test smoke smoke-check system install-system core install-core install dist appcast release clean

# Unit tests: tests/test_<name>.c linked with the Core sources listed in test_<name>_SRCS.
TESTS := options keymap disk_list system_dir bridge mouse floppy_speed
test_options_SRCS    := Core/PUAEOptions.c
test_keymap_SRCS     := Core/PUAEKeymap.c
test_disk_list_SRCS  := Core/PUAEDiskList.c
test_system_dir_SRCS := Core/PUAESystemDir.c
test_bridge_SRCS     := Core/PUAEBridge.c Core/PUAEOptions.c
test_bridge_LIBS     := $(BUILD)/libpuae.a
test_mouse_SRCS      := Core/PUAEMouse.c
test_floppy_speed_SRCS := Core/PUAEFloppySpeed.c

all: sdk puae

# OpenEmu SDK frameworks, built into build/Release (same layout UME-Core uses).
sdk: $(BUILD)/Release/OpenEmuBase.framework $(BUILD)/Release/OpenEmuSystem.framework

$(BUILD)/Release/%.framework:
	xcodebuild -project $(OPENEMU_DIR)/OpenEmu-SDK/OpenEmu-SDK.xcodeproj -scheme $* -configuration Release \
	  ARCHS=$(ARCH) ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=$(MINOS) \
	  SYMROOT=$(CURDIR)/$(BUILD) CODE_SIGNING_ALLOWED=NO GCC_TREAT_WARNINGS_AS_ERRORS=NO build

# libretro-uae as a static library. Never pass STATIC_LINKING=1: it drops libretro-common.
puae: $(BUILD)/libpuae.a

$(BUILD)/libpuae.a:
	@mkdir -p $(BUILD)
	$(MAKE) -C $(PUAE) platform=osx CROSS_COMPILE=1 \
	  LIBRETRO_APPLE_PLATFORM=$(ARCH)-apple-macos$(MINOS) \
	  LIBRETRO_APPLE_ISYSROOT=$$(xcrun --show-sdk-path) \
	  STATIC_LINKING_LINK=1 OBJDIR=$(CURDIR)/$(BUILD)/puae-obj \
	  TARGET=$(CURDIR)/$@ -j$(JOBS)

.SECONDEXPANSION:
$(BUILD)/tests/test_%: tests/test_%.c tests/test.h $$(wildcard Core/*.h) $$(wildcard $$(test_%_SRCS)) $$(test_%_LIBS)
	@mkdir -p $(dir $@)
	clang $(CFLAGS_COMMON) -O0 -Itests -o $@ $< $(wildcard $(test_$*_SRCS)) $(test_$*_LIBS)

# Objective-C tests: tests/test_<name>.m linked with test_<name>_SRCS and Foundation.
OBJC_TESTS := import_fix box_art box_art_fetcher box_art_library
test_import_fix_SRCS := Amiga/OEAmigaImportFix.m
test_box_art_SRCS    := Amiga/OEAmigaBoxArt.m
test_box_art_fetcher_SRCS := Amiga/OEAmigaBoxArtFetcher.m Amiga/OEAmigaBoxArt.m
test_box_art_library_SRCS := Amiga/OEAmigaBoxArtFetcher.m Amiga/OEAmigaBoxArt.m

$(BUILD)/tests/test_%: tests/test_%.m tests/test.h $$(wildcard $$(test_%_SRCS))
	@mkdir -p $(dir $@)
	clang $(CFLAGS_COMMON) -O0 -fobjc-arc -Itests -IAmiga -framework Foundation -framework CoreData -o $@ $< $(wildcard $(test_$*_SRCS))

test: $(TESTS:%=$(BUILD)/tests/test_%) $(OBJC_TESTS:%=$(BUILD)/tests/test_%)
	@status=0; for t in $^; do $$t || status=1; done; exit $$status

# The bridge outside OpenEmu: boots real games from $(FSUAE) (see tools/smoke-check.sh).
smoke: $(BUILD)/puae-smoke

$(BUILD)/puae-smoke: tools/puae-smoke.c $(BRIDGE_SRCS) $(wildcard Core/*.h) $(BUILD)/libpuae.a
	clang $(CFLAGS_COMMON) -o $@ tools/puae-smoke.c $(BRIDGE_SRCS) $(BUILD)/libpuae.a

smoke-check: smoke
	sh tools/smoke-check.sh "$(FSUAE)"

# Amiga.oesystemplugin: links only OpenEmuSystem, resolved at runtime through the app's rpath (like the
# installed system plugins, which carry no LC_RPATH of their own).
system: $(SYSTEM)

$(SYSTEM): $(SYSTEM_SRCS) $(wildcard Amiga/*.h) Amiga/Info.plist $(SYSTEM_RES) $(BUILD)/Release/OpenEmuSystem.framework
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	clang $(CFLAGS_COMMON) $(OBJC_FLAGS) -bundle -framework OpenEmuSystem -framework Cocoa -framework CoreData \
	  -o $@/Contents/MacOS/Amiga $(SYSTEM_SRCS)
	cp Amiga/Info.plist $@/Contents/
	cp $(SYSTEM_RES) $@/Contents/Resources/
	codesign -s - -f $@

install-system: system
	sh tools/install.sh --system $(BUILD)

# PUAE.oecoreplugin: libpuae.a linked statically; OpenEmuBase resolves through the helper's rpath, as
# for the installed MAME core.
core: $(CORE)

$(CORE): $(CORE_SRCS) $(wildcard Core/*.h) Amiga/OEAmigaSystemResponderClient.h Core/Info.plist \
         $(BUILD)/libpuae.a $(BUILD)/Release/OpenEmuBase.framework
	rm -rf $@
	mkdir -p $@/Contents/MacOS $(BUILD)/core-obj
	clang $(CFLAGS_COMMON) -c -o $(BUILD)/core-obj/PUAEGameCore.o $(OBJC_FLAGS) -IAmiga Core/PUAEGameCore.m
	for f in $(filter %.c,$(CORE_SRCS)); do clang $(CFLAGS_COMMON) -c -o $(BUILD)/core-obj/$$(basename $$f .c).o $$f || exit 1; done
	clang -arch $(ARCH) -mmacosx-version-min=$(MINOS) -bundle -F $(BUILD)/Release -framework OpenEmuBase -framework Cocoa \
	  -framework OpenGL -o $@/Contents/MacOS/PUAE $(BUILD)/core-obj/*.o $(BUILD)/libpuae.a
	cp Core/Info.plist $@/Contents/
	mkdir -p $@/Contents/Resources/legal
	cp LICENSE $@/Contents/Resources/legal/LICENSE
	cp $(PUAE)/COPYING $@/Contents/Resources/legal/COPYING-libretro-uae.txt
	codesign -s - -f $@

install-core: core
	sh tools/install.sh --core $(BUILD)

# Both bundles; tools/install.sh refuses while OpenEmu runs and keeps the replaced bundles as .bak-YYYYMMDD.
install: system core
	sh tools/install.sh $(BUILD)

dist: $(CORE_ZIP) $(FULL_ZIP)

$(CORE_ZIP): core
	rm -f $@
	ditto -c -k --keepParent "$(CORE)" $@
	@echo "Built $@ ($$(du -h $@ | cut -f1))"

$(FULL_ZIP): system core tools/install.sh
	rm -rf $(STAGING) $@
	mkdir -p $(STAGING)
	ditto "$(SYSTEM)" $(STAGING)/Amiga.oesystemplugin
	ditto "$(CORE)" $(STAGING)/PUAE.oecoreplugin
	cp tools/install.sh $(STAGING)/install.sh
	ditto -c -k --keepParent $(STAGING) $@
	@echo "Built $@ ($$(du -h $@ | cut -f1))"

# appcast.xml is what OpenEmu polls (SUFeedURL in Core/Info.plist) to offer the next core version.
appcast: $(CORE_ZIP)
	sh tools/make-appcast.sh "$(VERSION)" "$(REPO)" "$(CORE_ZIP)" "$(MINOS)" > appcast.xml
	xmllint --noout appcast.xml
	@echo "Wrote appcast.xml for $(VERSION)"

# Publish: push the current commit, create the GitHub Release v<VERSION> with both zips attached, then
# commit and push the appcast so that OpenEmu only sees the new version once the download exists.
release: dist
	@git diff --quiet && git diff --cached --quiet || { echo "Commit your changes before releasing."; exit 1; }
	@! gh release view v$(VERSION) -R $(REPO) >/dev/null 2>&1 || { echo "v$(VERSION) is already released. Bump CFBundleVersion in Core/Info.plist and Amiga/Info.plist."; exit 1; }
	git push origin HEAD
	printf '%s\n' \
	  "Amiga for OpenEmu: the PUAE core and the Amiga system plugin, version $(VERSION)." "" \
	  "**Install:** download and unzip \`PUAE-Core_$(VERSION).zip\`, quit OpenEmu and run \`sh PUAE-Core_$(VERSION)/install.sh\`. From then on the core updates itself through OpenEmu; after an OpenEmu update, run the script again to put the system plugin back. \`PUAE_$(VERSION).zip\` is the core alone, the file OpenEmu's updater downloads." "" \
	  "**Requirements:** OpenEmu 2.4.1, macOS $(MINOS) or later (Intel, or Apple Silicon through Rosetta), and your own Kickstart ROMs." "" \
	  "The core embeds libretro-uae, licensed under the GPL-2.0. Corresponding source: https://github.com/libretro/libretro-uae/tree/$$(git -C $(PUAE) rev-parse HEAD)" \
	  > $(BUILD)/notes.md
	gh release create v$(VERSION) -R $(REPO) --title "PUAE-Core $(VERSION)" --notes-file $(BUILD)/notes.md $(FULL_ZIP) $(CORE_ZIP)
	sh tools/make-appcast.sh "$(VERSION)" "$(REPO)" "$(CORE_ZIP)" "$(MINOS)" > appcast.xml
	git add appcast.xml
	git commit -m "Update appcast for $(VERSION)"
	git push origin HEAD
	@echo "Released https://github.com/$(REPO)/releases/tag/v$(VERSION)"

clean:
	rm -rf $(BUILD)
