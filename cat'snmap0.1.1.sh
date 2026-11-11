#!/usr/bin/env bash
# ============================================================================
#  Catsnmap all-in-one fixer — v0.1.1.1a
#  © AC Kondo 1999–2026 — meow meow me :3
#
#  Does everything in one run:
#    1. Finds the source nmap wrapper (handles the cursed >Cat'snmap0.1.1.sh path)
#    2. Copies it to a clean filename (no > or ' in the path)
#    3. Applies the three fixes:
#         - -v/--version flag
#         - -p override clears RAW_PORTS
#         - UDP open|filtered overcount grep
#    4. Validates with `bash -n`
#    5. Prints a summary and the exact command to run the result
# ============================================================================

set -euo pipefail

VERSION="0.1.1.1a"
NAME="catsnmap all-in-one fixer"

# ---- locate source ------------------------------------------------------
# Search order: $1, common paths, then a filesystem scan.
find_src() {
    local candidates=(
        "$1"
        "/Volumes/1TBUSB/>Coding/>Cat'snmap0.1.1.sh"
        "/Volumes/1TBUSB/>Coding/>Catsnmap0.1.1.sh"
        "./Catsnmap0.1.1.sh"
        "./Cat'snmap0.1.1.sh"
        "$HOME/Catsnmap0.1.1.sh"
        "$HOME/Cat'snmap0.1.1.sh"
    )
    local c
    for c in "${candidates[@]}"; do
        [[ -n "$c" && -f "$c" ]] && { printf '%s\n' "$c"; return 0; }
    done
    # last resort: search /Volumes for anything matching *nmap*.sh
    local hit
    hit=$(find /Volumes -maxdepth 4 -type f -name '*nmap*.sh' 2>/dev/null | head -n1 || true)
    [[ -n "$hit" ]] && { printf '%s\n' "$hit"; return 0; }
    return 1
}

SRC=$(find_src "${1-}") || {
    echo "[x] Could not find the nmap wrapper." >&2
    echo "    Pass it explicitly: bash $0 /path/to/Cat'snmap0.1.1.sh" >&2
    exit 1
}

echo "[*] $NAME v$VERSION"
echo "[*] source: $SRC"

# ---- clean destination path --------------------------------------------
DST_DIR="$HOME/catsnmap"
DST="$DST_DIR/Catsnmapv$VERSION.sh"
mkdir -p "$DST_DIR"

# If destination already exists, back it up instead of clobbering.
if [[ -f "$DST" ]]; then
    BAK="$DST.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$DST" "$BAK"
    echo "[*] backed up old output to $BAK"
fi

cp -p "$SRC" "$DST"
chmod +x "$DST"
echo "[*] copied to: $DST"

# ---- apply fixes via python --------------------------------------------
python3 - "$DST" <<'PY'
import sys, pathlib

path = pathlib.Path(sys.argv[1])
src = path.read_text(encoding="utf-8")
changes = []

# Fix: -v/--version
needle = 'while [[ $# -gt 0 ]]; do\n  case "$1" in\n'
if "  -v|--version)" not in src:
    if needle in src:
        src = src.replace(
            needle,
            needle + '    -v|--version) echo "${NAME} v${VERSION}"; exit 0 ;;\n',
            1,
        )
        changes.append("-v/--version")
    else:
        print("[!] could not find arg parser anchor; skipping version flag", file=sys.stderr)

# Fix: -p override clears RAW_PORTS
old_p = '    -p) PORTS="$2"; shift 2 ;;'
new_p = '    -p) PORTS="$2"; RAW_PORTS=(); shift 2 ;;'
if old_p in src:
    src = src.replace(old_p, new_p, 1)
    changes.append("-p override clears RAW_PORTS")
elif new_p in src:
    print("[=] -p override already applied")
else:
    print("[!] -p parser line not found; inspect manually", file=sys.stderr)

# Fix: UDP open|filtered overcount
old_g = "PORTS_FOUND=$(grep -cE '^[0-9]+/(tcp|udp)[[:space:]]+open' \"${PREFIX}.nmap\" || true)"
new_g = "PORTS_FOUND=$(grep -cE '^[0-9]+/(tcp|udp)[[:space:]]+open([[:space:]]|$)' \"${PREFIX}.nmap\" || true)"
if old_g in src:
    src = src.replace(old_g, new_g, 1)
    changes.append("UDP open|filtered count")
elif new_g in src:
    print("[=] UDP count fix already applied")
else:
    print("[!] PORTS_FOUND line not found; inspect manually", file=sys.stderr)

path.write_text(src, encoding="utf-8")
path.chmod(path.stat().st_mode | 0o111)

if changes:
    print("[+] applied:", ", ".join(changes))
else:
    print("[=] no changes applied (already clean?)")
PY

# ---- validate -----------------------------------------------------------
if bash -n "$DST" 2>/tmp/catsnmap_syntax.err; then
    echo "[+] bash syntax OK"
else
    echo "[x] syntax error in output:" >&2
    cat /tmp/catsnmap_syntax.err >&2
    exit 1
fi

# ---- smoke test --------------------------------------------------------
if "$DST" -v >/tmp/catsnmap_v.out 2>&1; then
    echo "[+] version check: $(cat /tmp/catsnmap_v.out)"
else
    echo "[!] -v did not exit cleanly (not fatal; check manually)" >&2
fi

# ---- summary -----------------------------------------------------------
echo
echo "[+] done"
echo "    output: $DST"
echo
echo "    next:"
echo "      bash \"$DST\" -t 127.0.0.1 -m quick"
echo "      bash \"$DST\" -t 10.0.0.0/24 -m discover"
echo "      bash \"$DST\" -h"
echo
echo "meow meow me :3"
