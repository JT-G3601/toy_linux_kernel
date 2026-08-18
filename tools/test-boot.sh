#!/usr/bin/env bash
set -euo pipefail

if (($# != 6)); then
    printf 'usage: %s QEMU IMAGE DIVIDE_IMAGE UNMAPPED_IMAGE READ_ONLY_IMAGE NX_IMAGE\n' "$0" >&2
    exit 2
fi

QEMU=$1
IMAGE=$2
DIVIDE_IMAGE=$3
UNMAPPED_IMAGE=$4
READ_ONLY_IMAGE=$5
NX_IMAGE=$6
QEMU_TEST_TIMEOUT=${QEMU_TEST_TIMEOUT:-30s}

[[ -x "$QEMU" ]] || {
    printf 'boot-test: FAIL: QEMU is not executable: %s\n' "$QEMU" >&2
    exit 1
}
for required_image in "$IMAGE" "$DIVIDE_IMAGE" "$UNMAPPED_IMAGE" \
    "$READ_ONLY_IMAGE" "$NX_IMAGE"; do
    [[ -f "$required_image" ]] || {
        printf 'boot-test: FAIL: image does not exist: %s\n' "$required_image" >&2
        exit 1
    }
done
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
    local send_key=${4:-}
    local input_marker=${5:-K3:READY}
    local serial_output
    local qemu_output
    local monitor_pipe
    local monitor_fd
    local deadline
    local marker_reached=0
    local input_sent=0
    local status

    serial_output=$(mktemp "$TEST_DIR/serial.XXXXXX.log")
    qemu_output=$(mktemp "$TEST_DIR/qemu.XXXXXX.log")
    monitor_pipe="$TEST_DIR/monitor.$RANDOM.$RANDOM.pipe"
    mkfifo "$monitor_pipe"
    exec {monitor_fd}<>"$monitor_pipe"

    "$QEMU" \
        -machine pc \
        -cpu qemu64 \
        -m "$memory" \
        -drive "file=$image,format=raw,if=ide,index=0" \
        -display none \
        -serial "file:$serial_output" \
        -monitor stdio \
        -no-reboot \
        -no-shutdown <&${monitor_fd} >"$qemu_output" 2>&1 &
    QEMU_PID=$!
    deadline=$((SECONDS + QEMU_TEST_TIMEOUT_SECONDS))

    while kill -0 "$QEMU_PID" 2>/dev/null; do
        if [[ -n "$send_key" ]] && ((input_sent == 0)) &&
            grep -Fq "$input_marker" "$serial_output"; then
            printf 'sendkey %s\n' "$send_key" >&${monitor_fd}
            input_sent=1
        fi
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
    exec {monitor_fd}>&-

    QEMU_OUTPUT=$(cat "$serial_output")
    for diagnostic in "$qemu_output"; do
        if [[ -s "$diagnostic" ]]; then
            if [[ -n "$QEMU_OUTPUT" ]]; then
                QEMU_OUTPUT+=$'\n'
            fi
            QEMU_OUTPUT+=$(cat "$diagnostic")
        fi
    done

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

assert_marker() {
    local output=$1
    local marker=$2
    local scenario=$3

    grep -Fq "$marker" <<<"$output" || {
        printf 'boot-test: FAIL: %s did not print %s\n' "$scenario" "$marker" >&2
        print_qemu_output "$output"
        exit 1
    }
}

printf 'boot-test: M4 normal memory and M3 timer/keyboard path (max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$IMAGE" 'K4:HALT' 128M a
GOOD_OUTPUT=$QEMU_OUTPUT
for marker in \
    'S1' 'S2' 'M2:E820 OK' 'M2:ELF OK' 'K2:LONG MODE OK' 'K2:E820[' \
    'K3:RUNTIME OK' 'K3:GDT TSS OK' 'K3:IDT OK' 'K3:PIC OK' 'K3:PIT OK' \
    'K4:PMM READY' 'K4:VMM READY' 'K4:HEAP READY' 'K4:VMM PERMS OK' \
    'K4:PMM STRESS OK' 'K4:VMM MAP/PROTECT OK' 'K4:HEAP STRESS OK' \
    'K3:KEYBOARD READY' 'K3:READY' 'K3:TIMER OK' 'K3:KEY char=a' \
    'K3:KEYBOARD OK last=a' 'K4:HALT' 'K3:HALT'; do
    assert_marker "$GOOD_OUTPUT" "$marker" 'normal image'
done

BAD_IMAGE="$TEST_DIR/corrupt-stage2.img"
cp -- "$IMAGE" "$BAD_IMAGE"
printf 'X' | dd of="$BAD_IMAGE" bs=1 seek=512 conv=notrunc status=none
printf 'boot-test: corrupt stage2 (wait for E2, max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$BAD_IMAGE" 'E2'
BAD_OUTPUT=$QEMU_OUTPUT
assert_marker "$BAD_OUTPUT" 'S1' 'corrupt stage2'
assert_marker "$BAD_OUTPUT" 'E2' 'corrupt stage2'
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
    assert_marker "$BAD_ELF_OUTPUT" "$marker" 'corrupt kernel ELF'
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
    assert_marker "$LOW_MEMORY_OUTPUT" "$marker" 'low-memory boot'
done
if grep -Fq 'K2:LONG MODE OK' <<<"$LOW_MEMORY_OUTPUT"; then
    printf 'boot-test: FAIL: low-memory boot unexpectedly entered the kernel\n' >&2
    print_qemu_output "$LOW_MEMORY_OUTPUT"
    exit 1
fi

printf 'boot-test: divide-error exception path (max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$DIVIDE_IMAGE" 'PANIC: fatal exception'
DIVIDE_OUTPUT=$QEMU_OUTPUT
for marker in 'K3:TRIGGER DIVIDE' 'K3:EXCEPTION vector=0 name=Divide Error' \
    'K3:REG rip=' 'K3:DIVIDE ERROR OK' 'PANIC: fatal exception'; do
    assert_marker "$DIVIDE_OUTPUT" "$marker" 'divide-error image'
done

printf 'boot-test: unmapped-page fault path (max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$UNMAPPED_IMAGE" 'PANIC: fatal exception'
UNMAPPED_OUTPUT=$QEMU_OUTPUT
for marker in 'K4:TRIGGER UNMAPPED' 'K3:EXCEPTION vector=14 name=Page Fault' \
    'K3:REG rip=' 'K3:PAGE FAULT cr2=0xffffc00000000000' \
    'K4:UNMAPPED FAULT OK error=0x0' \
    'PANIC: fatal exception'; do
    assert_marker "$UNMAPPED_OUTPUT" "$marker" 'unmapped-page image'
done

printf 'boot-test: read-only page fault path (max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$READ_ONLY_IMAGE" 'PANIC: fatal exception'
READ_ONLY_OUTPUT=$QEMU_OUTPUT
for marker in 'K4:TRIGGER READONLY' 'K3:EXCEPTION vector=14 name=Page Fault error=0x3' \
    'K3:PAGE FAULT cr2=0xffffc00000000000' 'K4:READONLY FAULT OK error=0x3' \
    'PANIC: fatal exception'; do
    assert_marker "$READ_ONLY_OUTPUT" "$marker" 'read-only image'
done

printf 'boot-test: NX page fault path (max %s)\n' "$QEMU_TEST_TIMEOUT"
run_qemu "$NX_IMAGE" 'PANIC: fatal exception'
NX_OUTPUT=$QEMU_OUTPUT
for marker in 'K4:TRIGGER NX' 'K3:EXCEPTION vector=14 name=Page Fault error=0x11' \
    'K3:PAGE FAULT cr2=0xffffc00000000000' 'K4:NX FAULT OK error=0x11' \
    'PANIC: fatal exception'; do
    assert_marker "$NX_OUTPUT" "$marker" 'NX image'
done

printf 'boot-test: PASS\n'
printf '  M4 normal:       PMM/VMM/heap stress -> PIT ticks -> injected PS/2 key -> halt\n'
printf '  M4 permissions:  unmapped, read-only, and NX mappings fault with exact error bits\n'
printf '  M3 exception:    divide error still reports a register frame and halts\n'
printf '  M2 regressions:  corrupt stage2, invalid ELF, and low memory still fail safely\n'
