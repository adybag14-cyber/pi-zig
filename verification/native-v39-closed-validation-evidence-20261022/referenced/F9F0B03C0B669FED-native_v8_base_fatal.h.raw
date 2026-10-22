// Copyright 2006-2008, 2012, 2021, 2023 the V8 project authors.
// BSD-style license retained with the pinned Node/V8 source authority.
// Direct native projection of V8 base logging, abort mode and immediate crash.
// Source mappings: verification/native-v8-fatal-tracing-sourceonly-20261020/.
#ifndef PI_NATIVE_V8_BASE_FATAL_H
#define PI_NATIVE_V8_BASE_FATAL_H

#include <stdint.h>

#ifdef __cplusplus
#define PI_V8_BASE_NORETURN [[noreturn]]
extern "C" {
#else
#define PI_V8_BASE_NORETURN _Noreturn
#endif

#if defined(__clang__) || defined(__GNUC__)
#define PI_V8_BASE_NOINLINE __attribute__((noinline))
#define PI_V8_BASE_PRINTF_FORMAT(format_index, first_arg) \
  __attribute__((format(printf, format_index, first_arg)))
#elif defined(_MSC_VER)
#define PI_V8_BASE_NOINLINE __declspec(noinline)
#define PI_V8_BASE_PRINTF_FORMAT(format_index, first_arg)
#else
#define PI_V8_BASE_NOINLINE
#define PI_V8_BASE_PRINTF_FORMAT(format_index, first_arg)
#endif

// The ordinal order and initial kDefault value are from abort-mode.h/.cc.
// The native embedder owns mode changes; this is the original mutable process
// state, with no added synchronization or guest state.
typedef enum pi_v8_base_abort_mode
#ifdef __cplusplus
    : int
#endif
{
  PI_V8_BASE_EXIT_WITH_SUCCESS_AND_IGNORE_DCHECK_FAILURES = 0,
  PI_V8_BASE_EXIT_WITH_FAILURE_AND_IGNORE_DCHECK_FAILURES = 1,
  PI_V8_BASE_IMMEDIATE_CRASH_MODE = 2,
  PI_V8_BASE_DEFAULT_ABORT_MODE = 3
} pi_v8_base_abort_mode;

extern pi_v8_base_abort_mode pi_v8_base_g_abort_mode;

typedef void (*pi_v8_base_print_stack_trace_function)(void);
typedef void (*pi_v8_base_dcheck_function)(const char*, int, const char*);
typedef void (*pi_v8_base_fatal_function)(const char*, int, const char*);

// Native process hooks. Print-stack and fatal start null. A null dcheck setter
// restores the original default handler. Callback arguments are borrowed for
// the immediate call only. Hook installation belongs to process bootstrap.
void pi_v8_base_set_print_stack_trace(
    pi_v8_base_print_stack_trace_function print_stack_trace);
void pi_v8_base_set_dcheck_function(pi_v8_base_dcheck_function dcheck_function);
void pi_v8_base_set_fatal_function(pi_v8_base_fatal_function fatal_function);

PI_V8_BASE_NOINLINE void pi_v8_base_dcheck(
    const char* file, int line, const char* message);

#ifdef DEBUG
PI_V8_BASE_NORETURN PI_V8_BASE_PRINTF_FORMAT(3, 4)
PI_V8_BASE_NOINLINE void pi_v8_base_fatal(
    const char* file, int line, const char* format, ...);
#else
PI_V8_BASE_NORETURN PI_V8_BASE_PRINTF_FORMAT(1, 2)
PI_V8_BASE_NOINLINE void pi_v8_base_fatal(const char* format, ...);
#endif

typedef enum pi_v8_base_oom_type
#ifdef __cplusplus
    : int
#endif
{
  PI_V8_BASE_OOM_JAVASCRIPT = 0,
  PI_V8_BASE_OOM_PROCESS = 1
} pi_v8_base_oom_type;

PI_V8_BASE_NORETURN void pi_v8_base_fatal_oom(
    pi_v8_base_oom_type type, const char* message);
PI_V8_BASE_NORETURN void pi_v8_base_abort(void);

#ifdef __cplusplus
}  // extern "C"

#if defined(_MSC_VER)
#include <intrin.h>
#endif

// immediate-crash.h, with only names and v8config.h compiler/host predicates
// projected. GNU is selected by __GNUC__; clang-cl takes the MSVC branch.
// Keep the individual asm instructions, GNU lambda and unreachable epilogue.
#if defined(__GNUC__)

#if defined(_M_X64) || defined(__x86_64__) || \
    defined(_M_IX86) || defined(__i386__)
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile("int3")
#if defined(__APPLE__)
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("")
#else
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("ud2")
#endif

#elif defined(__ARMEL__)
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile("bkpt #0")
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("udf #0")

#elif defined(__AARCH64EL__) || defined(_M_ARM64)
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile("brk #0")
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("hlt #0")

#elif defined(__PPC64__) || defined(_ARCH_PPC64)
#if defined(_AIX)
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile(".vbyte 4,0x7D821008");
#else
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile(".4byte 0x7D821008");
#endif
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("")

#elif defined(__MVS__)
#define PI_V8_BASE_TRAP_SEQUENCE1_() __builtin_trap()
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("")

#elif defined(__s390x__)
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile(".2byte 0x0001");
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("")

#else
#define PI_V8_BASE_TRAP_SEQUENCE1_() __builtin_trap()
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("")
#endif

#elif defined(_MSC_VER)

#if !defined(__clang__)
#define PI_V8_BASE_TRAP_SEQUENCE1_() __debugbreak()
#define PI_V8_BASE_TRAP_SEQUENCE2_()
#elif defined(__AARCH64EL__) || defined(_M_ARM64)
#define PI_V8_BASE_TRAP_SEQUENCE1_() __debugbreak()
#define PI_V8_BASE_TRAP_SEQUENCE2_() __asm volatile("")
#else
#define PI_V8_BASE_TRAP_SEQUENCE1_() asm volatile("int3")
#define PI_V8_BASE_TRAP_SEQUENCE2_() asm volatile("ud2")
#endif

#else
#error No supported trap sequence!
#endif

#define PI_V8_BASE_TRAP_SEQUENCE_() \
  do {                              \
    PI_V8_BASE_TRAP_SEQUENCE1_();    \
    PI_V8_BASE_TRAP_SEQUENCE2_();    \
  } while (false)

#if !defined(__GNUC__)
#define PI_V8_BASE_WRAPPED_TRAP_SEQUENCE_() PI_V8_BASE_TRAP_SEQUENCE_()
#else
#define PI_V8_BASE_WRAPPED_TRAP_SEQUENCE_() \
  do {                                      \
    [] { PI_V8_BASE_TRAP_SEQUENCE_(); }();   \
  } while (false)
#endif

#if defined(__clang__) || defined(__GNUC__)
#define PI_V8_BASE_IMMEDIATE_CRASH()       \
  ({                                      \
    PI_V8_BASE_WRAPPED_TRAP_SEQUENCE_();   \
    __builtin_unreachable();               \
  })
#else
#define PI_V8_BASE_IMMEDIATE_CRASH() \
  PI_V8_BASE_WRAPPED_TRAP_SEQUENCE_()
#endif

// logging.h preserves all three build selections. Official single-argument
// FATAL discards its argument and emits the actual immediate-crash sequence.
#ifdef DEBUG
#define PI_V8_BASE_FATAL(...) \
  pi_v8_base_fatal(__FILE__, __LINE__, __VA_ARGS__)
#define PI_V8_BASE_GRACEFUL_FATAL(...) PI_V8_BASE_FATAL(__VA_ARGS__)
#else
#define PI_V8_BASE_GRACEFUL_FATAL(...) pi_v8_base_fatal(__VA_ARGS__)
#if !defined(OFFICIAL_BUILD)
#define PI_V8_BASE_FATAL(...) pi_v8_base_fatal(__VA_ARGS__)
#else
#define PI_V8_BASE_FATAL_HELPER_(_7, _6, _5, _4, _3, _2, _1, _0, ...) _0
#define PI_V8_BASE_FATAL_DISCARD_ARG_(arg) PI_V8_BASE_IMMEDIATE_CRASH()
#define PI_V8_BASE_FATAL(...) \
  PI_V8_BASE_FATAL_HELPER_(__VA_ARGS__, pi_v8_base_fatal, pi_v8_base_fatal, \
      pi_v8_base_fatal, pi_v8_base_fatal, pi_v8_base_fatal, \
      pi_v8_base_fatal, PI_V8_BASE_FATAL_DISCARD_ARG_)(__VA_ARGS__)
#endif
#endif

#if !defined(DEBUG) && defined(OFFICIAL_BUILD)
#define PI_V8_BASE_CHECK_FAILED_HANDLER(message) PI_V8_BASE_FATAL("ignored")
#else
#define PI_V8_BASE_CHECK_FAILED_HANDLER(message) \
  PI_V8_BASE_FATAL("Check failed: %s.", message)
#endif

#define PI_V8_BASE_CHECK_WITH_MSG(condition, message) \
  do {                                                \
    if (!(condition)) [[unlikely]] {                  \
      PI_V8_BASE_CHECK_FAILED_HANDLER(message);        \
    }                                                 \
  } while (false)
#define PI_V8_BASE_CHECK(condition) \
  PI_V8_BASE_CHECK_WITH_MSG(condition, #condition)

constexpr const char* pi_v8_base_kUnreachableCodeMessage = "unreachable code";
constexpr const char* pi_v8_base_kUnimplementedCodeMessage = "unimplemented code";
#define PI_V8_BASE_UNREACHABLE() \
  PI_V8_BASE_FATAL(pi_v8_base_kUnreachableCodeMessage)
#define PI_V8_BASE_UNIMPLEMENTED() \
  PI_V8_BASE_FATAL(pi_v8_base_kUnimplementedCodeMessage)

#endif  // __cplusplus
#endif  // PI_NATIVE_V8_BASE_FATAL_H
