#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
    printf 'usage: %s QEMU IMAGE\n' "$0" >&2
    exit 2
fi

QEMU=$1
IMAGE=$2

[[ -x "$QEMU" ]] || {
    printf 'boot-test: FAIL: QEMU is not executable: %s\n' "$QEMU" >&2
    exit 1
}
[[ -f "$IMAGE" ]] || {
    printf 'boot-test: FAIL: image does not exist: %s\n' "$IMAGE" >&2
    exit 1
}

TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT

run_qemu() {
    local image=$1
    local output
    local status

    set +e
    output=$(timeout 2s "$QEMU" \
        -machine pc \
        -cpu qemu64 \
        -m 128M \
        -drive "file=$image,format=raw,if=ide,index=0" \
        -display none \
        -serial stdio \
        -monitor none \
        -no-reboot \
        -no-shutdown 2>&1)
    status=$?
    set -e

    if ((status != 0 && status != 124)); then
        printf 'boot-test: QEMU exited unexpectedly with status %s\n%s\n' \
            "$status" "$output" >&2
        return 1
    fi
    printf '%s' "$output"
}

GOOD_OUTPUT=$(run_qemu "$IMAGE")
grep -Fq 'S1' <<<"$GOOD_OUTPUT" || {
    printf 'boot-test: FAIL: normal image did not print S1\n' >&2
    exit 1
}
grep -Fq 'S2' <<<"$GOOD_OUTPUT" || {
    printf 'boot-test: FAIL: normal image did not reach stage2\n' >&2
    exit 1
}

BAD_IMAGE="$TEST_DIR/corrupt-stage2.img"
cp -- "$IMAGE" "$BAD_IMAGE"
printf 'X' | dd of="$BAD_IMAGE" bs=1 seek=512 conv=notrunc status=none
BAD_OUTPUT=$(run_qemu "$BAD_IMAGE")
grep -Fq 'S1' <<<"$BAD_OUTPUT" || {
    printf 'boot-test: FAIL: corrupt image did not start stage1\n' >&2
    exit 1
}
grep -Fq 'E2' <<<"$BAD_OUTPUT" || {
    printf 'boot-test: FAIL: corrupt stage2 did not report E2\n' >&2
    exit 1
}
if grep -Fq 'S2' <<<"$BAD_OUTPUT"; then
    printf 'boot-test: FAIL: stage1 jumped into corrupt stage2\n' >&2
    exit 1
fi

printf 'boot-test: PASS\n'
printf '  normal:  S1 -> S2\n'
printf '  corrupt: S1 -> E2, no stage2 handoff\n'
