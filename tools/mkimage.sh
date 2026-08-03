#!/usr/bin/env bash
set -euo pipefail

if (($# != 6)); then
    printf 'usage: %s STAGE1 STAGE2 KERNEL_ELF OUTPUT_IMAGE IMAGE_SIZE KERNEL_DISK_OFFSET\n' "$0" >&2
    exit 2
fi

STAGE1=$1
STAGE2=$2
KERNEL_ELF=$3
OUTPUT_IMAGE=$4
IMAGE_SIZE=$5
KERNEL_DISK_OFFSET=$6
SECTOR_SIZE=512
STAGE2_DISK_OFFSET=$SECTOR_SIZE

[[ -f "$STAGE1" ]] || {
    printf 'error: stage1 does not exist: %s\n' "$STAGE1" >&2
    exit 1
}
[[ -f "$STAGE2" ]] || {
    printf 'error: stage2 does not exist: %s\n' "$STAGE2" >&2
    exit 1
}
[[ -f "$KERNEL_ELF" ]] || {
    printf 'error: kernel ELF does not exist: %s\n' "$KERNEL_ELF" >&2
    exit 1
}
[[ "$IMAGE_SIZE" =~ ^[0-9]+$ ]] || {
    printf 'error: IMAGE_SIZE must be a non-negative integer\n' >&2
    exit 1
}
[[ "$KERNEL_DISK_OFFSET" =~ ^[0-9]+$ ]] || {
    printf 'error: KERNEL_DISK_OFFSET must be a non-negative integer\n' >&2
    exit 1
}
((KERNEL_DISK_OFFSET % 512 == 0)) || {
    printf 'error: KERNEL_DISK_OFFSET must be sector aligned\n' >&2
    exit 1
}

STAGE1_SIZE=$(stat -c '%s' "$STAGE1")
[[ "$STAGE1_SIZE" == "$SECTOR_SIZE" ]] || {
    printf 'error: stage1 must be exactly 512 bytes (got %s)\n' "$STAGE1_SIZE" >&2
    exit 1
}
STAGE1_SIGNATURE=$(od -An -tx1 -j510 -N2 "$STAGE1" | tr -d '[:space:]')
[[ "$STAGE1_SIGNATURE" == 55aa ]] || {
    printf 'error: stage1 is missing the 0xAA55 BIOS signature\n' >&2
    exit 1
}

STAGE2_SIZE=$(stat -c '%s' "$STAGE2")
((STAGE2_SIZE >= 4)) || {
    printf 'error: stage2 is too small to contain its header\n' >&2
    exit 1
}
((STAGE2_DISK_OFFSET + STAGE2_SIZE <= KERNEL_DISK_OFFSET)) || {
    printf 'error: stage2 exceeds its reserved LBA 1..127 area\n' >&2
    exit 1
}
STAGE2_MAGIC=$(dd if="$STAGE2" bs=1 count=4 status=none)
[[ "$STAGE2_MAGIC" == S2OK ]] || {
    printf 'error: stage2 is missing the S2OK header\n' >&2
    exit 1
}

KERNEL_SIZE=$(stat -c '%s' "$KERNEL_ELF")
((KERNEL_DISK_OFFSET + KERNEL_SIZE <= IMAGE_SIZE)) || {
    printf 'error: kernel ELF does not fit in image\n' >&2
    exit 1
}

OUTPUT_DIR=$(dirname "$OUTPUT_IMAGE")
OUTPUT_NAME=$(basename "$OUTPUT_IMAGE")
mkdir -p "$OUTPUT_DIR"
TEMP_IMAGE="$OUTPUT_DIR/.${OUTPUT_NAME}.tmp.$$"
trap 'rm -f -- "$TEMP_IMAGE"' EXIT

truncate -s "$IMAGE_SIZE" "$TEMP_IMAGE"
dd if="$STAGE1" of="$TEMP_IMAGE" bs=1 seek=0 conv=notrunc status=none
dd if="$STAGE2" of="$TEMP_IMAGE" bs=1 seek="$STAGE2_DISK_OFFSET" \
    conv=notrunc status=none
dd if="$KERNEL_ELF" of="$TEMP_IMAGE" bs=1 seek="$KERNEL_DISK_OFFSET" \
    conv=notrunc status=none
mv -f -- "$TEMP_IMAGE" "$OUTPUT_IMAGE"
trap - EXIT

printf 'image: %s (%s bytes), stage1/stage2/kernel at bytes 0/%s/%s\n' \
    "$OUTPUT_IMAGE" "$IMAGE_SIZE" "$STAGE2_DISK_OFFSET" "$KERNEL_DISK_OFFSET"
