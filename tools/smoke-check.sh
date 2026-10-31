#!/bin/sh
# Boots real games from an FS-UAE folder through build/puae-smoke (see `make smoke-check`).
# Logs and screenshots (PPM) end up in build/smoke.
#
#   tools/smoke-check.sh ~/Documents/FS-UAE
set -u
fsuae=${1:?usage: $0 FSUAE_DIR}
out=build/smoke
smoke=build/puae-smoke
floppies=$fsuae/Floppies

rm -rf "$out"
mkdir -p "$out/empty"
sh tools/link-fsuae-kickstarts.sh "$fsuae/Kickstarts" "$out/bios" > "$out/kickstarts.log"

failures=0 skipped=0
result() {  # name, ok (0/1/2=skipped), what
    if [ "$2" -eq 2 ]; then return; fi
    if [ "$2" -eq 0 ]; then echo "PASS $1: $3"; else echo "FAIL $1: $3 (see $out/$1.log)"; failures=$((failures + 1)); fi
}
run() {  # name, smoke args... (the game is the last argument; a game missing from the folder is skipped)
    name=$1; shift
    for game; do :; done
    if [ ! -e "$game" ]; then echo "SKIP $name: $(basename "$game") not in $floppies"; skipped=$((skipped + 1)); return 2; fi
    "$smoke" --bios "$out/bios" --system "$out/system" --save "$out/save" "$@" > "$out/$name.log" 2>&1
}
logged() {  # name, fixed string (2 when the run was skipped)
    [ -f "$out/$1.log" ] || return 2
    grep -qF "$2" "$out/$1.log"
}

run nzs --frames 1500 --ppm "$out/nzs.ppm" --state-roundtrip --min-nonblack 5 "$floppies/New Zealand Story, The.adf"
result nzs $? "ADF boots, save state round-trips"
logged nzs 'Kickstart: "kick34005.A500"'
result nzs $? "ADF runs on the A500 Kickstart 1.3"

# Mouse: NZS's trainer toggles "Unlimited lives" on a left click. Emulation is deterministic, so the
# screen at frame 1650 differs from a run without the click only if the click reached the Amiga.
run nzsplain --frames 1660 --snap 1650:"$out/nzs-plain.ppm" "$floppies/New Zealand Story, The.adf"
if run nzsclick --frames 1660 --press 1500:lmb --snap 1650:"$out/nzs-click.ppm" "$floppies/New Zealand Story, The.adf"; then
    [ -s "$out/nzs-plain.ppm" ] && [ -s "$out/nzs-click.ppm" ] && ! cmp -s "$out/nzs-plain.ppm" "$out/nzs-click.ppm"
    result nzsclick $? "left mouse click reaches the game"
fi

run lemmings --frames 300 --expect-disks 2 "$floppies/Lemmings_Disk1.adf"
result lemmings $? "sibling disks form a 2-disk set"

# A playable WHDLoad package (with a .slave); Syndicate.lha in the same folder is only an installer.
run cannonfodder --frames 2000 --ppm "$out/cannonfodder.ppm" --min-nonblack 5 "$floppies/CannonFodder_v1.2_CD32.lha"
result cannonfodder $? "WHDLoad LHA boots"
logged cannonfodder 'Kickstart: "kick40068.A1200"'
result cannonfodder $? "WHDLoad runs on the A1200 Kickstart 3.1"

run swos --frames 1500 --ppm "$out/swos.ppm" "$floppies/swos2223.hdf"
result swos $? "HDF loads"

if [ -e "$floppies/New Zealand Story, The.adf" ]; then
    "$smoke" --bios "$out/empty" --system "$out/empty-system" --save "$out/save-empty" \
        "$floppies/New Zealand Story, The.adf" > "$out/nokick.log" 2>&1
    [ $? -ne 0 ] && grep -qi kickstart "$out/nokick.log"
    result nokick $? "missing Kickstart fails the load and says so"
fi

[ "$failures" -eq 0 ] && echo "smoke-check: all passed ($skipped skipped)" || echo "smoke-check: $failures failed ($skipped skipped)"
exit "$failures"
