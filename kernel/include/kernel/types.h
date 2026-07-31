#ifndef TINY_LINUX_KERNEL_TYPES_H
#define TINY_LINUX_KERNEL_TYPES_H

/*
 * Compiler-provided fundamental types keep the freestanding kernel independent
 * from the host C library and its headers.
 */
typedef __UINT8_TYPE__ u8;
typedef __UINT16_TYPE__ u16;
typedef __UINT32_TYPE__ u32;
typedef __UINT64_TYPE__ u64;

typedef __INT8_TYPE__ i8;
typedef __INT16_TYPE__ i16;
typedef __INT32_TYPE__ i32;
typedef __INT64_TYPE__ i64;

typedef __SIZE_TYPE__ usize;
typedef __PTRDIFF_TYPE__ isize;
typedef __UINTPTR_TYPE__ uptr;
typedef __INTPTR_TYPE__ iptr;

typedef _Bool bool;

#define true ((bool)1)
#define false ((bool)0)

_Static_assert(sizeof(u8) == 1, "u8 must be one byte");
_Static_assert(sizeof(u16) == 2, "u16 must be two bytes");
_Static_assert(sizeof(u32) == 4, "u32 must be four bytes");
_Static_assert(sizeof(u64) == 8, "u64 must be eight bytes");
_Static_assert(sizeof(uptr) == 8, "the kernel requires a 64-bit target");

#endif
