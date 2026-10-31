#!/bin/sh
# Symlinks the Kickstart ROMs found in SRC into DEST under the names PUAE (and the core's
# Info.plist) use, matching them by MD5 — the same way OpenEmu imports BIOS files.
#
#   tools/link-fsuae-kickstarts.sh ~/Documents/FS-UAE/Kickstarts build/smoke/bios
set -e
src=$1
dest=$2
[ -d "$src" ] && [ -n "$dest" ] || { echo "usage: $0 SRC DEST" >&2; exit 2; }
mkdir -p "$dest"

for rom in "$src"/*.rom; do
    [ -f "$rom" ] || continue
    case $(md5 -q "$rom") in
        82a21c1890cae844b3df741f2762d48d) name=kick34005.A500 ;;
        646773759326fbac3b2311fd8c8793ee) name=kick40068.A1200 ;;
        e40a5dfb3d017ba8779faba30cbd1c8e) name=kick40063.A600 ;;
        dc10d7bdd1b6f450773dfb558477c230) name=kick37175.A500 ;;
        *) continue ;;
    esac
    ln -sf "$rom" "$dest/$name"
    echo "$name <- $(basename "$rom")"
done
