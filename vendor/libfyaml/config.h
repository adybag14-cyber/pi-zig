/* Portable static subset of upstream cmake/config.h.in for Zig Clang 0.16.0.
 * Platform capabilities are explicit; no configure-time code is executed. */
#ifndef CONFIG_H
#define CONFIG_H
#define VERSION "0.9.6"
#define HAVE_STATIC 1
#define HAVE_PORTABLE_TARGET 1
#define HAVE___BUILTIN_BSWAP16 1
#define HAVE___BUILTIN_BSWAP32 1
#define HAVE___BUILTIN_BSWAP64 1
#define HAVE_QSORT_R 0
#define HAVE_MREMAP 0
#define HAVE_LIBCLANG 0
#define HAVE_HEAP_TRAMPOLINES 0
#define TARGET_HAS_SSE2 0
#define TARGET_HAS_SSE41 0
#define TARGET_HAS_AVX2 0
#define TARGET_HAS_AVX512 0
#define TARGET_HAS_NEON 0
#ifndef _WIN32
#define HAVE_ALLOCA_H 1
#define HAVE_DECL_ENVIRON 1
#endif
#endif
