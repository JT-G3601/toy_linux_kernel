#!/usr/bin/env bash
set -euo pipefail

ERRORS=0
WARNINGS=0

pass() {
    printf 'PASS  %-12s %s\n' "$1" "$2"
}

warn() {
    printf 'WARN  %-12s %s\n' "$1" "$2"
    WARNINGS=$((WARNINGS + 1))
}

fail() {
    printf 'FAIL  %-12s %s\n' "$1" "$2" >&2
    ERRORS=$((ERRORS + 1))
}

resolve_tool() {
    local label=$1
    local value=$2
    local required=$3
    local resolved=

    if [[ -n "$value" ]]; then
        if [[ "$value" == */* ]]; then
            [[ -x "$value" ]] && resolved=$value
        else
            resolved=$(command -v "$value" 2>/dev/null || true)
        fi
    fi

    if [[ -n "$resolved" ]]; then
        pass "$label" "$resolved"
    elif [[ "$required" == required ]]; then
        fail "$label" "not found (configured as '${value:-<empty>}')"
    else
        warn "$label" "not found (optional)"
    fi
}

resolve_tool make make required
resolve_tool cc "${CC:-gcc}" required
resolve_tool ld "${LD:-ld}" required
resolve_tool objcopy "${OBJCOPY:-objcopy}" required
resolve_tool readelf "${READELF:-readelf}" required
resolve_tool bash bash required
resolve_tool dd dd required
resolve_tool truncate truncate required
resolve_tool cmp cmp required
resolve_tool sha256sum sha256sum required
resolve_tool qemu "${QEMU:-}" required
resolve_tool qemu-img "${QEMU_IMG:-}" optional
resolve_tool gdb "${GDB:-}" optional

printf '\nDoctor summary: %d error(s), %d warning(s)\n' "$ERRORS" "$WARNINGS"
if ((ERRORS > 0)); then
    exit 1
fi
