#!/usr/bin/env bash
set -euo pipefail

if (($# != 2)); then
    printf 'usage: %s QEMU IMAGE\n' "$0" >&2
    exit 2
fi

QEMU=$1
IMAGE=$2
QEMU_TEST_TIMEOUT=${QEMU_TEST_TIMEOUT:-30s}

[[ -x "$QEMU" ]] || {
    printf 'boot-test: FAIL: QEMU is not executable: %s\n' "$QEMU" >&2
    exit 1
}
[[ -f "$IMAGE" ]] || {
    printf 'boot-test: FAIL: image does not exist: %s\n' "$IMAGE" >&2
    exit 1
}

TEST_DIR=$(mktemp -d)
QEMU_PID=
QEMU_OUTPUT=

if [[ "$QEMU_TEST_TIMEOUT" =~ ^([1-9][0-9]*)s?$ ]]; then
    QEMU_TEST_TIMEOUT_SECONDS=${BASH_REMATCH[1]}
else
    printf 'boot-test: FAIL: QEMU_TEST_TIMEOUT must be a positive integer with optional s suffix: %s\n' \
        "$QEMU_TEST_TIMEOUT" >&2
    exit 2
fi

cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    rm -rf -- "$TEST_DIR"
}
trap cleanup EXIT

print_qemu_output() {
    local output=$1

    printf 'boot-test: maximum marker wait was %s\n' "$QEMU_TEST_TIMEOUT" >&2
    if [[ -n "$output" ]]; then
        printf '%s\n%s\n%s\n' \
            '--- captured QEMU output ---' "$output" '--- end QEMU output ---' >&2
    else
        printf 'boot-test: captured QEMU output was empty\n' >&2
    fi
}

run_qemu() {
    local image=$1
    local expected_marker=$2
    local memory=${3:-128M}
    local serial_output
    local qemu_output
    local deadline
    local marker_reached=0
    local status

    serial_output=$(mktemp "$TEST_DIR/serial.XXXXXX.log")
    qemu_output=$(mktemp "$TEST_DIR/qemu.XXXXXX.log")

    "$QEMU" \
        -machine pc \
        -cpu qemu64 \
        -m "$memory" \
        -drive "file=$image,format=raw,if=ide,index=0" \
        -display none \
        -serial "file:$serial_output" \
        -monitor none \
        -no-reboot \
        -no-shutdown >"$qemu_output" 2>&1 &
    QEMU_PID=$!
    deadline=$((SECONDS + QEMU_TEST_TIMEOUT_SECONDS))

    while kill -0 "$QEMU_PID" 2>/dev/null; do
        if grep -Fq "$expected_marker" "$serial_output"; then
            marker_reached=1
            break
        fi
        if ((SECONDS >= deadline)); then
            break
        fi
        sleep 0.05
    done

    if kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
    fi
    set +e
    wait "$QEMU_PID"
    status=$?
    set -e
    QEMU_PID=

    QEMU_OUTPUT=$(cat "$serial_output")
    if [[ -s "$qemu_output" ]]; then
        if [[ -n "$QEMU_OUTPUT" ]]; then
            QEMU_OUTPUT+=$'\n'
        fi
        QEMU_OUTPUT+=$(cat "$qemu_output")
    fi

    if ((marker_reached)); then
        return 0
    fi

    if ((status != 0 && status != 143)); then
        printf 'boot-test: QEMU exited unexpectedly with status %s\n%s\n' \
            "$status" "$QEMU_OUTPUT" >&2
        return 1
    fi
    return 0
}

printf 'boot-test: normal image (wait for K2:HALT, max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$IMAGE" 'K2:HALT'
GOOD_OUTPUT=$QEMU_OUTPUT
grep -Fq 'S1' <<<"$GOOD_OUTPUT" || {
    printf 'boot-test: FAIL: normal image did not print S1\n' >&2
    print_qemu_output "$GOOD_OUTPUT"
    exit 1
}
grep -Fq 'S2' <<<"$GOOD_OUTPUT" || {
    printf 'boot-test: FAIL: normal image did not reach stage2\n' >&2
    print_qemu_output "$GOOD_OUTPUT"
    exit 1
}
for marker in 'M2:E820 OK' 'M2:ELF OK' 'K2:LONG MODE OK' 'K2:E820[' 'K2:HALT'; do
    grep -Fq "$marker" <<<"$GOOD_OUTPUT" || {
        printf 'boot-test: FAIL: normal image did not print %s\n' "$marker" >&2
        print_qemu_output "$GOOD_OUTPUT"
        exit 1
    }
done

BAD_IMAGE="$TEST_DIR/corrupt-stage2.img"
cp -- "$IMAGE" "$BAD_IMAGE"
printf 'X' | dd of="$BAD_IMAGE" bs=1 seek=512 conv=notrunc status=none
printf 'boot-test: corrupt stage2 (wait for E2, max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$BAD_IMAGE" 'E2'
BAD_OUTPUT=$QEMU_OUTPUT
grep -Fq 'S1' <<<"$BAD_OUTPUT" || {
    printf 'boot-test: FAIL: corrupt image did not start stage1\n' >&2
    print_qemu_output "$BAD_OUTPUT"
    exit 1
}
grep -Fq 'E2' <<<"$BAD_OUTPUT" || {
    printf 'boot-test: FAIL: corrupt stage2 did not report E2\n' >&2
    print_qemu_output "$BAD_OUTPUT"
    exit 1
}
if grep -Fq 'S2' <<<"$BAD_OUTPUT"; then
    printf 'boot-test: FAIL: stage1 jumped into corrupt stage2\n' >&2
    print_qemu_output "$BAD_OUTPUT"
    exit 1
fi

BAD_ELF_IMAGE="$TEST_DIR/corrupt-kernel-elf.img"
cp -- "$IMAGE" "$BAD_ELF_IMAGE"
printf 'X' | dd of="$BAD_ELF_IMAGE" bs=1 seek=65536 conv=notrunc status=none
printf 'boot-test: corrupt kernel ELF (wait for M2:ELF ERROR, max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$BAD_ELF_IMAGE" 'M2:ELF ERROR'
BAD_ELF_OUTPUT=$QEMU_OUTPUT
for marker in 'S1' 'S2' 'M2:E820 OK' 'M2:ELF ERROR'; do
    grep -Fq "$marker" <<<"$BAD_ELF_OUTPUT" || {
        printf 'boot-test: FAIL: corrupt kernel ELF did not print %s\n' "$marker" >&2
        print_qemu_output "$BAD_ELF_OUTPUT"
        exit 1
    }
done
if grep -Fq 'K2:LONG MODE OK' <<<"$BAD_ELF_OUTPUT"; then
    printf 'boot-test: FAIL: loader entered the corrupt kernel ELF\n' >&2
    print_qemu_output "$BAD_ELF_OUTPUT"
    exit 1
fi

printf 'boot-test: low memory (wait for M2:MEMORY ERROR, max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$IMAGE" 'M2:MEMORY ERROR' 1M
LOW_MEMORY_OUTPUT=$QEMU_OUTPUT
for marker in 'S1' 'S2' 'M2:E820 OK' 'M2:MEMORY ERROR'; do
    grep -Fq "$marker" <<<"$LOW_MEMORY_OUTPUT" || {
        printf 'boot-test: FAIL: low-memory boot did not print %s\n' "$marker" >&2
        print_qemu_output "$LOW_MEMORY_OUTPUT"
        exit 1
    }
done
if grep -Fq 'K2:LONG MODE OK' <<<"$LOW_MEMORY_OUTPUT"; then
    printf 'boot-test: FAIL: low-memory boot unexpectedly entered the kernel\n' >&2
    print_qemu_output "$LOW_MEMORY_OUTPUT"
    exit 1
fi

printf 'boot-test: PASS\n'
printf '  normal:         S1 -> S2 -> E820 -> ELF -> long mode -> kernel halt\n'
printf '  corrupt stage2: S1 -> E2, no stage2 handoff\n'
printf '  corrupt ELF:    stage2 reports ELF error, no kernel handoff\n'
printf '  low memory:     stage2 reports memory error, no kernel handoff\n'
