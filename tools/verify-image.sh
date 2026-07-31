#!/usr/bin/env bash
set -euo pipefail

if (($# != 4)); then
    printf 'usage: %s KERNEL_ELF IMAGE IMAGE_SIZE KERNEL_DISK_OFFSET\n' "$0" >&2
    exit 2
fi

KERNEL_ELF=$1
IMAGE=$2
EXPECTED_IMAGE_SIZE=$3
KERNEL_DISK_OFFSET=$4
READELF=${READELF:-readelf}

fail() {
    printf 'verify: FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$KERNEL_ELF" ]] || fail "missing kernel ELF: $KERNEL_ELF"
[[ -f "$IMAGE" ]] || fail "missing disk image: $IMAGE"

ACTUAL_IMAGE_SIZE=$(stat -c '%s' "$IMAGE")
[[ "$ACTUAL_IMAGE_SIZE" == "$EXPECTED_IMAGE_SIZE" ]] ||
    fail "image size is $ACTUAL_IMAGE_SIZE, expected $EXPECTED_IMAGE_SIZE"

ELF_HEADER=$("$READELF" -hW "$KERNEL_ELF")
grep -q 'Class:[[:space:]]*ELF64' <<<"$ELF_HEADER" ||
    fail "kernel is not ELF64"
grep -q 'Type:[[:space:]]*EXEC' <<<"$ELF_HEADER" ||
    fail "kernel is not an executable ELF"
grep -q 'Machine:[[:space:]]*Advanced Micro Devices X86-64' <<<"$ELF_HEADER" ||
    fail "kernel machine is not x86-64"

ENTRY_HEX=$(awk '/Entry point address:/ { print $4 }' <<<"$ELF_HEADER")
[[ "$ENTRY_HEX" =~ ^0x[fF]{8}[89aAbBcCdDeEfF][0-9a-fA-F]{7}$ ]] ||
    fail "entry point is not in the expected higher half: $ENTRY_HEX"

PROGRAM_HEADERS=$("$READELF" -lW "$KERNEL_ELF")
grep -q 'LOAD' <<<"$PROGRAM_HEADERS" || fail "kernel has no loadable segment"
if grep -Eq 'INTERP|DYNAMIC' <<<"$PROGRAM_HEADERS"; then
    fail "kernel unexpectedly requires a dynamic loader"
fi
FIRST_LOAD=$(awk '$1 == "LOAD" { print; exit }' <<<"$PROGRAM_HEADERS")
grep -Eq '0xffffffff80000000[[:space:]]+0x0000000000100000' <<<"$FIRST_LOAD" ||
    fail "first load segment does not map higher-half VMA to 1 MiB LMA"
if awk '$1 == "LOAD" && /W/ && /E/ { found=1 } END { exit !found }' \
    <<<"$PROGRAM_HEADERS"; then
    fail "kernel contains a writable and executable load segment"
fi

if "$READELF" -Ws "$KERNEL_ELF" |
    awk '$7 == "UND" && $8 != "" { print; found=1 } END { exit !found }' |
    grep -q .; then
    fail "kernel contains undefined symbols"
fi

KERNEL_SIZE=$(stat -c '%s' "$KERNEL_ELF")
dd if="$IMAGE" bs=1 skip="$KERNEL_DISK_OFFSET" count="$KERNEL_SIZE" status=none |
    cmp -s "$KERNEL_ELF" - ||
    fail "kernel bytes do not match image payload"

cmp -s -n "$KERNEL_DISK_OFFSET" "$IMAGE" /dev/zero ||
    fail "reserved boot area is not zero-filled in M0"

printf 'verify: PASS\n'
printf '  kernel: %s bytes, entry %s\n' "$KERNEL_SIZE" "$ENTRY_HEX"
printf '  image:  %s bytes, payload offset %s\n' \
    "$ACTUAL_IMAGE_SIZE" "$KERNEL_DISK_OFFSET"
