#!/bin/sh
# Installs the Amiga system plugin and the PUAE core into OpenEmu 2.4.1.
#
#   sh install.sh [--system] [--core] [DIR]
#
# DIR holds Amiga.oesystemplugin and PUAE.oecoreplugin (default: the folder of this script, so from an
# unzipped release `sh install.sh` is enough). With no flag both bundles are installed.
#
# OpenEmu deletes system plugins found in ~/Library/Application Support/OpenEmu/Systems, so the Amiga
# system has to live inside OpenEmu.app, and an OpenEmu update removes it: run this script again
# afterwards. The core goes to the usual Cores folder and updates itself through OpenEmu from then on.
# A bundle being replaced is kept next to the new one as <bundle>.bak-YYYYMMDD, which OpenEmu ignores.
set -eu

app=/Applications/OpenEmu.app
systems="$app/Contents/PlugIns/Systems"
cores="$HOME/Library/Application Support/OpenEmu/Cores"
want_system=0 want_core=0 dir=

for arg in "$@"; do
    case $arg in
        --system) want_system=1 ;;
        --core) want_core=1 ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; exit 2 ;;
        *) dir=$arg ;;
    esac
done
[ "$want_system" -eq 1 ] || [ "$want_core" -eq 1 ] || want_system=1 want_core=1
[ -n "$dir" ] || dir=$(cd "$(dirname "$0")" && pwd)

[ -d "$app" ] || { echo "OpenEmu.app not found in /Applications." >&2; exit 1; }
if pgrep -x OpenEmu >/dev/null; then echo "Quit OpenEmu before installing." >&2; exit 1; fi

install_bundle() {  # bundle, destination directory
    name=$(basename "$1")
    [ -d "$1" ] || { echo "$1 not found." >&2; exit 1; }
    mkdir -p "$2"
    if [ -d "$2/$name" ]; then
        bak="$2/$name.bak-$(date +%Y%m%d)"
        rm -rf "$bak"
        mv "$2/$name" "$bak"
    fi
    ditto "$1" "$2/$name"
    xattr -dr com.apple.quarantine "$2/$name" 2>/dev/null || true
    echo "Installed $2/$name"
}

[ "$want_system" -eq 1 ] && install_bundle "$dir/Amiga.oesystemplugin" "$systems"
[ "$want_core" -eq 1 ] && install_bundle "$dir/PUAE.oecoreplugin" "$cores"

if [ "$want_system" -eq 1 ] && [ "$want_core" -eq 1 ]; then
    cat <<'MSG'

Next: launch OpenEmu and drop your Kickstart ROMs onto Preferences > System Files (the two required
ones are Kickstart 1.3 for the A500 and Kickstart 3.1 for the A1200), then import your Amiga games.
If the Amiga system is missing from the sidebar, enable it in Preferences > Library.
MSG
fi
