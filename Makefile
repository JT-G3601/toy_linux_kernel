SHELL := /bin/bash
.DEFAULT_GOAL := all

PROJECT_ROOT := $(CURDIR)
BUILD_DIR ?= $(PROJECT_ROOT)/build
BUILD_MARKER := $(BUILD_DIR)/.tiny-linux-kernel-build
KERNEL_ELF := $(BUILD_DIR)/kernel/kernel.elf
IMAGE := $(BUILD_DIR)/toy-linux.img

IMAGE_SIZE := 16777216
KERNEL_DISK_OFFSET := 65536
QEMU_MEMORY ?= 128M
QEMU_GDB_PORT ?= 1234

ifeq ($(origin CC),default)
CC := gcc
endif
ifeq ($(origin LD),default)
LD := ld
endif
OBJCOPY ?= objcopy
READELF ?= readelf

LOCAL_QEMU := /home/godot/ai_native/QEMU_NET/qemu-build/qemu-system-x86_64
LOCAL_QEMU_IMG := /home/godot/ai_native/QEMU_NET/qemu-build/qemu-img
QEMU ?= $(shell command -v qemu-system-x86_64 2>/dev/null || { test -x "$(LOCAL_QEMU)" && printf '%s' "$(LOCAL_QEMU)"; })
QEMU_IMG ?= $(shell command -v qemu-img 2>/dev/null || { test -x "$(LOCAL_QEMU_IMG)" && printf '%s' "$(LOCAL_QEMU_IMG)"; })
GDB ?= $(shell command -v gdb 2>/dev/null || true)

KERNEL_CPPFLAGS := -Ikernel/include
KERNEL_ARCH_FLAGS := \
	-m64 \
	-mcmodel=kernel \
	-mno-red-zone \
	-mno-mmx \
	-mno-sse \
	-mno-sse2 \
	-fno-pic \
	-fno-pie
KERNEL_CFLAGS := \
	$(KERNEL_ARCH_FLAGS) \
	-std=c11 \
	-ffreestanding \
	-fno-stack-protector \
	-fno-builtin \
	-fno-asynchronous-unwind-tables \
	-fno-unwind-tables \
	-ffunction-sections \
	-fdata-sections \
	-ffile-prefix-map=$(PROJECT_ROOT)=. \
	-fdebug-prefix-map=$(PROJECT_ROOT)=. \
	-Wall \
	-Wextra \
	-Werror \
	-O2 \
	-g
KERNEL_ASFLAGS := \
	$(KERNEL_ARCH_FLAGS) \
	-ffreestanding \
	-ffile-prefix-map=$(PROJECT_ROOT)=. \
	-fdebug-prefix-map=$(PROJECT_ROOT)=. \
	-g
KERNEL_LDFLAGS := \
	-nostdlib \
	-static \
	--gc-sections \
	--build-id=none \
	-z max-page-size=0x1000 \
	-z noexecstack \
	-T kernel/linker.ld

KERNEL_C_SOURCES := $(shell find kernel -type f -name '*.c' -print 2>/dev/null | LC_ALL=C sort)
KERNEL_ASM_SOURCES := $(shell find kernel -type f -name '*.S' -print 2>/dev/null | LC_ALL=C sort)
KERNEL_C_OBJECTS := $(patsubst %.c,$(BUILD_DIR)/%.c.o,$(KERNEL_C_SOURCES))
KERNEL_ASM_OBJECTS := $(patsubst %.S,$(BUILD_DIR)/%.S.o,$(KERNEL_ASM_SOURCES))
KERNEL_OBJECTS := $(KERNEL_ASM_OBJECTS) $(KERNEL_C_OBJECTS)
KERNEL_DEPS := $(KERNEL_OBJECTS:.o=.d)

QEMU_COMMON_ARGS := \
	-machine pc \
	-cpu qemu64 \
	-m $(QEMU_MEMORY) \
	-drive file=$(IMAGE),format=raw,if=ide,index=0 \
	-display none \
	-serial stdio \
	-monitor none \
	-no-reboot \
	-no-shutdown

.PHONY: all kernel image verify doctor run debug clean help print-config

all: image

kernel: $(KERNEL_ELF)

image: $(IMAGE)

$(KERNEL_ELF): $(KERNEL_OBJECTS) kernel/linker.ld
	@mkdir -p "$(@D)"
	$(LD) $(KERNEL_LDFLAGS) -Map "$(BUILD_DIR)/kernel/kernel.map" -o "$@" $(KERNEL_OBJECTS)

$(BUILD_MARKER):
	@mkdir -p "$(@D)"
	@printf 'tiny-linux-kernel build directory\n' > "$@"

$(KERNEL_OBJECTS): | $(BUILD_MARKER)

$(BUILD_DIR)/%.c.o: %.c
	@mkdir -p "$(@D)"
	$(CC) $(KERNEL_CPPFLAGS) $(KERNEL_CFLAGS) -MMD -MP -c "$<" -o "$@"

$(BUILD_DIR)/%.S.o: %.S
	@mkdir -p "$(@D)"
	$(CC) $(KERNEL_CPPFLAGS) $(KERNEL_ASFLAGS) -MMD -MP -c "$<" -o "$@"

$(IMAGE): $(KERNEL_ELF) tools/mkimage.sh | $(BUILD_MARKER)
	@mkdir -p "$(@D)"
	./tools/mkimage.sh "$(KERNEL_ELF)" "$@" "$(IMAGE_SIZE)" "$(KERNEL_DISK_OFFSET)"

verify: $(IMAGE)
	READELF="$(READELF)" ./tools/verify-image.sh \
		"$(KERNEL_ELF)" "$(IMAGE)" "$(IMAGE_SIZE)" "$(KERNEL_DISK_OFFSET)"

doctor:
	CC="$(CC)" LD="$(LD)" OBJCOPY="$(OBJCOPY)" READELF="$(READELF)" \
	QEMU="$(QEMU)" QEMU_IMG="$(QEMU_IMG)" GDB="$(GDB)" \
		./tools/doctor.sh

run: $(IMAGE)
	@test -n "$(QEMU)" && test -x "$(QEMU)" || { \
		printf 'error: qemu-system-x86_64 not found; run make doctor or set QEMU=/path/to/qemu-system-x86_64\n' >&2; \
		exit 1; \
	}
	@printf 'M0 note: this image has no boot sector yet; BIOS will report it as non-bootable.\n'
	"$(QEMU)" $(QEMU_COMMON_ARGS)

debug: $(IMAGE)
	@test -n "$(QEMU)" && test -x "$(QEMU)" || { \
		printf 'error: qemu-system-x86_64 not found; run make doctor or set QEMU=/path/to/qemu-system-x86_64\n' >&2; \
		exit 1; \
	}
	@printf 'QEMU is paused before the first instruction; attach GDB to localhost:%s.\n' "$(QEMU_GDB_PORT)"
	"$(QEMU)" $(QEMU_COMMON_ARGS) -S -gdb "tcp::$(QEMU_GDB_PORT)"

print-config:
	@printf 'CC=%s\n' "$(CC)"
	@printf 'LD=%s\n' "$(LD)"
	@printf 'READELF=%s\n' "$(READELF)"
	@printf 'QEMU=%s\n' "$(QEMU)"
	@printf 'QEMU_IMG=%s\n' "$(QEMU_IMG)"
	@printf 'GDB=%s\n' "$(GDB)"
	@printf 'BUILD_DIR=%s\n' "$(BUILD_DIR)"
	@printf 'IMAGE=%s\n' "$(IMAGE)"
	@printf 'IMAGE_SIZE=%s\n' "$(IMAGE_SIZE)"
	@printf 'KERNEL_DISK_OFFSET=%s\n' "$(KERNEL_DISK_OFFSET)"

clean:
	@if [[ ! -e "$(BUILD_DIR)" ]]; then \
		exit 0; \
	fi; \
	if [[ ! -f "$(BUILD_MARKER)" ]]; then \
		printf 'error: refusing to remove unmarked BUILD_DIR=%s\n' "$(BUILD_DIR)" >&2; \
		exit 1; \
	fi; \
	rm -rf -- "$(BUILD_DIR)"

help:
	@printf '%s\n' \
		'make / make image  Build the freestanding kernel ELF and deterministic disk image' \
		'make kernel        Build only build/kernel/kernel.elf' \
		'make verify        Validate the ELF and image layout' \
		'make doctor        Check required and optional host tools' \
		'make run           Start QEMU (M0 image is intentionally not bootable yet)' \
		'make debug         Start paused QEMU with a GDB server on port 1234' \
		'make print-config  Show resolved tools and build paths' \
		'make clean         Remove only BUILD_DIR'

-include $(KERNEL_DEPS)
