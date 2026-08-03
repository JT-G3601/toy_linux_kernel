#!/usr/bin/env bash
set -euo pipefail

if (($# != 6)); then
    printf 'usage: %s STAGE1 STAGE2 KERNEL_ELF IMAGE IMAGE_SIZE KERNEL_DISK_OFFSET\n' "$0" >&2
    exit 2
fi

STAGE1=$1
STAGE2=$2
KERNEL_ELF=$3
IMAGE=$4
EXPECTED_IMAGE_SIZE=$5
KERNEL_DISK_OFFSET=$6
READELF=${READELF:-readelf}
SECTOR_SIZE=512
STAGE2_DISK_OFFSET=$SECTOR_SIZE

fail() {
    printf 'verify: FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -f "$STAGE1" ]] || fail "missing stage1: $STAGE1"
[[ -f "$STAGE2" ]] || fail "missing stage2: $STAGE2"
[[ -f "$KERNEL_ELF" ]] || fail "missing kernel ELF: $KERNEL_ELF"
[[ -f "$IMAGE" ]] || fail "missing disk image: $IMAGE"

ACTUAL_IMAGE_SIZE=$(stat -c '%s' "$IMAGE")
[[ "$ACTUAL_IMAGE_SIZE" == "$EXPECTED_IMAGE_SIZE" ]] ||
    fail "image size is $ACTUAL_IMAGE_SIZE, expected $EXPECTED_IMAGE_SIZE"

STAGE1_SIZE=$(stat -c '%s' "$STAGE1")
[[ "$STAGE1_SIZE" == "$SECTOR_SIZE" ]] ||
    fail "stage1 is $STAGE1_SIZE bytes, expected exactly 512"
STAGE1_SIGNATURE=$(od -An -tx1 -j510 -N2 "$STAGE1" | tr -d '[:space:]')
[[ "$STAGE1_SIGNATURE" == 55aa ]] || fail "stage1 lacks the 0xAA55 signature"
cmp -s -n "$STAGE1_SIZE" "$STAGE1" "$IMAGE" ||
    fail "stage1 bytes do not match image LBA 0"

STAGE2_SIZE=$(stat -c '%s' "$STAGE2")
((STAGE2_SIZE >= 4)) || fail "stage2 is too small to contain its header"
((STAGE2_DISK_OFFSET + STAGE2_SIZE <= KERNEL_DISK_OFFSET)) ||
    fail "stage2 exceeds reserved LBA 1..127"
STAGE2_MAGIC=$(dd if="$STAGE2" bs=1 count=4 status=none)
[[ "$STAGE2_MAGIC" == S2OK ]] || fail "stage2 lacks the S2OK header"
dd if="$IMAGE" bs=1 skip="$STAGE2_DISK_OFFSET" count="$STAGE2_SIZE" status=none |
    cmp -s "$STAGE2" - || fail "stage2 bytes do not match image LBA 1"

ZERO_START=$((STAGE2_DISK_OFFSET + STAGE2_SIZE))
ZERO_SIZE=$((KERNEL_DISK_OFFSET - ZERO_START))
if ((ZERO_SIZE > 0)); then
    dd if="$IMAGE" bs=1 skip="$ZERO_START" count="$ZERO_SIZE" status=none |
        cmp -s -n "$ZERO_SIZE" - /dev/zero ||
        fail "unused stage2 reserved area is not zero-filled"
fi

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

printf 'verify: PASS\n'
printf '  stage1: %s bytes, signature 0xAA55\n' "$STAGE1_SIZE"
printf '  stage2: %s bytes, header S2OK\n' "$STAGE2_SIZE"
printf '  kernel: %s bytes, entry %s\n' "$KERNEL_SIZE" "$ENTRY_HEX"
printf '  image:  %s bytes, payload offset %s\n' \
    "$ACTUAL_IMAGE_SIZE" "$KERNEL_DISK_OFFSET"
