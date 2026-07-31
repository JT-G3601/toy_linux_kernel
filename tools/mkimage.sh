#!/usr/bin/env bash
set -euo pipefail

if (($# != 4)); then
    printf 'usage: %s KERNEL_ELF OUTPUT_IMAGE IMAGE_SIZE KERNEL_DISK_OFFSET\n' "$0" >&2
    exit 2
fi

KERNEL_ELF=$1
OUTPUT_IMAGE=$2
IMAGE_SIZE=$3
KERNEL_DISK_OFFSET=$4

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
dd if="$KERNEL_ELF" of="$TEMP_IMAGE" bs=1 seek="$KERNEL_DISK_OFFSET" \
    conv=notrunc status=none
mv -f -- "$TEMP_IMAGE" "$OUTPUT_IMAGE"
trap - EXIT

printf 'image: %s (%s bytes), kernel ELF at byte %s\n' \
    "$OUTPUT_IMAGE" "$IMAGE_SIZE" "$KERNEL_DISK_OFFSET"
