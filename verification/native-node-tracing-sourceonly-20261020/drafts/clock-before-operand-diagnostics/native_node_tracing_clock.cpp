// Copyright 2013 the V8 project authors. All rights reserved.
// BSD-style license retained with the pinned Node/V8 source authority.
// Native specialization of the trace-consumed TimeTicks/ThreadTicks/PID/TID
// paths. The exact original excerpts and explicit substitutions are recorded in
// verification/native-node-tracing-sourceonly-20261020/clock-component.json.
#include "native_node_tracing_clock.hpp"
#include <atomic>
#include <cstring>
#include <limits>

#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <mmsystem.h>
#if defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)
#if defined(_MSC_VER)
#include <intrin.h>
#else
#include <x86intrin.h>
#endif
#endif
#else
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#if defined(__linux__) && !defined(__ANDROID__)
#include <sys/syscall.h>
#endif
#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/mach_time.h>
#endif
#endif

#define PI_TRACE_CLOCK_CHECK(expr) \
  do { \
    if (!(expr)) [[unlikely]] \
      ::pi_node::tracing::ClockCheckFailure(__FILE__, __LINE__, #expr); \
  } while (0)

// Selected release DCHECK does not evaluate its expression. Debug platform
// diagnostics remain a separate build selection, as in the other trace units.
#define PI_TRACE_CLOCK_DCHECK(expr) ((void)0)

namespace pi_node::tracing {
namespace {
constexpr int64_t kMicrosecondsPerSecond = 1000000;
constexpr int64_t kMicrosecondsPerMillisecond = 1000;
constexpr int64_t kNanosecondsPerMicrosecond = 1000;

int CurrentThreadIdInternal() noexcept {
#if defined(_WIN32)
  return static_cast<int>(::GetCurrentThreadId());
#elif defined(__APPLE__)
  return static_cast<int>(pthread_mach_thread_np(pthread_self()));
#elif defined(__linux__) && !defined(__ANDROID__)
  return static_cast<int>(syscall(__NR_gettid));
#elif defined(__ANDROID__)
  return static_cast<int>(gettid());
#else
  return static_cast<int>(reinterpret_cast<intptr_t>(pthread_self()));
#endif
}

#if defined(__APPLE__)
int64_t ComputeThreadTicks() noexcept {
  mach_msg_type_number_t thread_info_count = THREAD_BASIC_INFO_COUNT;
  thread_basic_info_data_t thread_info_data;
  kern_return_t kr = thread_info(
      pthread_mach_thread_np(pthread_self()), THREAD_BASIC_INFO,
      reinterpret_cast<thread_info_t>(&thread_info_data), &thread_info_count);
  PI_TRACE_CLOCK_CHECK(kr == KERN_SUCCESS);
  PI_TRACE_CLOCK_CHECK(thread_info_data.user_time.seconds <=
      std::numeric_limits<int64_t>::max() -
          thread_info_data.system_time.seconds);
  int64_t seconds =
      thread_info_data.user_time.seconds + thread_info_data.system_time.seconds;
  static constexpr int64_t kSecondsLimit =
      (std::numeric_limits<int64_t>::max() / kMicrosecondsPerSecond) - 2;
  PI_TRACE_CLOCK_CHECK(kSecondsLimit > seconds);
  int64_t micros = seconds * kMicrosecondsPerSecond;
  micros += thread_info_data.user_time.microseconds +
            thread_info_data.system_time.microseconds;
  return micros;
}
#elif !defined(_WIN32)
int64_t ClockNow(clockid_t clock_id) noexcept {
#if (defined(_POSIX_MONOTONIC_CLOCK) && _POSIX_MONOTONIC_CLOCK >= 0) || \
    defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || \
    defined(__ANDROID__)
  struct timespec ts;
  if (clock_gettime(clock_id, &ts) != 0) Unreachable(__FILE__, __LINE__);
  static constexpr int64_t kSecondsLimit =
      (std::numeric_limits<int64_t>::max() / kMicrosecondsPerSecond) - 1;
  PI_TRACE_CLOCK_CHECK(kSecondsLimit > ts.tv_sec);
  int64_t result = int64_t{ts.tv_sec} * kMicrosecondsPerSecond;
  result += ts.tv_nsec / kNanosecondsPerMicrosecond;
  return result;
#else
  return 0;
#endif
}
#endif

#if defined(_WIN32)
#if defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)
void CpuId(int cpu_info[4], int info_type) noexcept {
#if defined(_MSC_VER)
  __cpuid(cpu_info, info_type);
#elif defined(__i386__) && defined(__pic__)
  __asm__ volatile(
      "mov %%ebx, %%edi\n\t"
      "cpuid\n\t"
      "xchg %%edi, %%ebx\n\t"
      : "=a"(cpu_info[0]), "=D"(cpu_info[1]), "=c"(cpu_info[2]),
        "=d"(cpu_info[3])
      : "a"(info_type), "c"(0));
#else
  __asm__ volatile("cpuid \n\t"
                   : "=a"(cpu_info[0]), "=b"(cpu_info[1]), "=c"(cpu_info[2]),
                     "=d"(cpu_info[3])
                   : "a"(info_type), "c"(0));
#endif
}
#endif

// Specializes the sole queried CPU field. The original extended-leaf bound,
// hypervisor-present gate and exact Microsoft Hyper-V signature are preserved.
// No unsupported architectural result is replaced by an optimistic constant.
bool HasNonStopTimeStampCounter() noexcept {
#if defined(_M_ARM64) || defined(__aarch64__)
  // Original CPU() Windows ARM64 branch: native high-resolution thread timing.
  return true;
#elif defined(_M_X64) || defined(_M_IX86) || defined(__x86_64__) || defined(__i386__)
  bool has_non_stop_time_stamp_counter = false;
  bool is_running_in_vm = false;
  int cpu_info[4];
  CpuId(cpu_info, 0);
  unsigned num_ids = cpu_info[0];
  if (num_ids > 0) {
    CpuId(cpu_info, 1);
    is_running_in_vm = (cpu_info[2] & 0x80000000) != 0;
  }
  CpuId(cpu_info, static_cast<int>(0x80000000u));
  unsigned num_ext_ids = cpu_info[0];
  const unsigned parameter_containing_non_stop_time_stamp_counter = 0x80000007;
  if (num_ext_ids >= parameter_containing_non_stop_time_stamp_counter) {
    CpuId(cpu_info, static_cast<int>(parameter_containing_non_stop_time_stamp_counter));
    has_non_stop_time_stamp_counter = (cpu_info[3] & (1 << 8)) != 0;
  }
  if (!has_non_stop_time_stamp_counter && is_running_in_vm) {
    int cpu_info_hv[4] = {};
    CpuId(cpu_info_hv, 0x40000000);
    if (cpu_info_hv[1] == 0x7263694D &&
        cpu_info_hv[2] == 0x666F736F &&
        cpu_info_hv[3] == 0x76482074) {
      has_non_stop_time_stamp_counter = true;
    }
  }
  return has_non_stop_time_stamp_counter;
#else
#error Unsupported Windows tracing clock architecture.
#endif
}

uint64_t QPCNowRaw() noexcept {
  LARGE_INTEGER perf_counter_now = {};
  BOOL result = ::QueryPerformanceCounter(&perf_counter_now);
  PI_TRACE_CLOCK_DCHECK(result);
  (void)result;
  return perf_counter_now.QuadPart;
}

DWORD TimeGetTimeWrapper() { return timeGetTime(); }
DWORD (*g_tick_function)(void) = &TimeGetTimeWrapper;

union LastTimeAndRolloversState {
  int32_t as_opaque_32;
  struct {
    uint8_t last_8;
    uint16_t rollovers;
  } as_values;
};
std::atomic<int32_t> g_last_time_and_rollovers{0};
static_assert(sizeof(LastTimeAndRolloversState) <=
              sizeof(g_last_time_and_rollovers));

int64_t RolloverProtectedNow() noexcept {
  LastTimeAndRolloversState state;
  DWORD now;
  int32_t original = g_last_time_and_rollovers.load(std::memory_order_acquire);
  while (true) {
    state.as_opaque_32 = original;
    now = g_tick_function();
    uint8_t now_8 = static_cast<uint8_t>(now >> 24);
    if (now_8 < state.as_values.last_8) ++state.as_values.rollovers;
    state.as_values.last_8 = now_8;
    if (state.as_opaque_32 == original) break;
    if (g_last_time_and_rollovers.compare_exchange_weak(
            original, state.as_opaque_32, std::memory_order_acq_rel)) break;
  }
  return static_cast<int64_t>(
      now + (static_cast<uint64_t>(state.as_values.rollovers) << 32)) *
      kMicrosecondsPerMillisecond;
}

int64_t InitialTimeTicksNowFunction() noexcept;
using TimeTicksNowFunction = int64_t (*)() noexcept;
TimeTicksNowFunction g_time_ticks_now_function = &InitialTimeTicksNowFunction;
int64_t g_qpc_ticks_per_second = 0;

int64_t QPCValueToMicroseconds(LONGLONG qpc_value) noexcept {
  std::atomic_thread_fence(std::memory_order_acquire);
  PI_TRACE_CLOCK_DCHECK(g_qpc_ticks_per_second > 0);
  static constexpr int64_t kQPCOverflowThreshold = INT64_C(0x8637BD05AF7);
  if (qpc_value < kQPCOverflowThreshold)
    return qpc_value * kMicrosecondsPerSecond / g_qpc_ticks_per_second;
  int64_t whole_seconds = qpc_value / g_qpc_ticks_per_second;
  int64_t leftover_ticks = qpc_value - whole_seconds * g_qpc_ticks_per_second;
  return whole_seconds * kMicrosecondsPerSecond +
      leftover_ticks * kMicrosecondsPerSecond / g_qpc_ticks_per_second;
}

int64_t QPCNow() noexcept { return QPCValueToMicroseconds(QPCNowRaw()); }

void InitializeTimeTicksNowFunctionPointer() noexcept {
  LARGE_INTEGER ticks_per_sec = {};
  if (!QueryPerformanceFrequency(&ticks_per_sec)) ticks_per_sec.QuadPart = 0;
  TimeTicksNowFunction now_function;
  const bool has_non_stop_time_stamp_counter = HasNonStopTimeStampCounter();
  if (ticks_per_sec.QuadPart <= 0 || !has_non_stop_time_stamp_counter)
    now_function = &RolloverProtectedNow;
  else
    now_function = &QPCNow;
  // Preserve the original publication protocol and function selection.
  g_qpc_ticks_per_second = ticks_per_sec.QuadPart;
  std::atomic_thread_fence(std::memory_order_release);
  g_time_ticks_now_function = now_function;
}

int64_t InitialTimeTicksNowFunction() noexcept {
  InitializeTimeTicksNowFunctionPointer();
  return g_time_ticks_now_function();
}

#if !defined(_M_ARM64) && !defined(__aarch64__)
double TSCTicksPerSecond() noexcept {
  PI_TRACE_CLOCK_DCHECK(CpuTimestampSupportedNative());
  static double tsc_ticks_per_second = 0;
  if (tsc_ticks_per_second != 0) return tsc_ticks_per_second;

  int previous_priority = ::GetThreadPriority(::GetCurrentThread());
  ::SetThreadPriority(::GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
  static const uint64_t tsc_initial = __rdtsc();
  static const uint64_t perf_counter_initial = QPCNowRaw();
  uint64_t tsc_now = __rdtsc();
  uint64_t perf_counter_now = QPCNowRaw();
  ::SetThreadPriority(::GetCurrentThread(), previous_priority);

  LARGE_INTEGER perf_counter_frequency = {};
  ::QueryPerformanceFrequency(&perf_counter_frequency);
  PI_TRACE_CLOCK_DCHECK(perf_counter_now >= perf_counter_initial);
  uint64_t perf_counter_ticks = perf_counter_now - perf_counter_initial;
  double elapsed_time_seconds =
      perf_counter_ticks / static_cast<double>(perf_counter_frequency.QuadPart);
  const double kMinimumEvaluationPeriodSeconds = 0.05;
  if (elapsed_time_seconds < kMinimumEvaluationPeriodSeconds) return 0;
  PI_TRACE_CLOCK_DCHECK(tsc_now >= tsc_initial);
  uint64_t tsc_ticks = tsc_now - tsc_initial;
  tsc_ticks_per_second = tsc_ticks / elapsed_time_seconds;
  return tsc_ticks_per_second;
}
#endif
#endif
}  // namespace

int CurrentProcessId() noexcept {
#if defined(_WIN32)
  return static_cast<int>(::GetCurrentProcessId());
#else
  return static_cast<int>(getpid());
#endif
}

int CurrentThreadId() noexcept {
  static thread_local int id = CurrentThreadIdInternal();
  return id;
}

int64_t CurrentTimestampMicrosecondsNative() noexcept {
#if defined(_WIN32)
  int64_t ticks = g_time_ticks_now_function();
  PI_TRACE_CLOCK_DCHECK(ticks != 0);
  return ticks;
#else
  int64_t ticks;
#if defined(__APPLE__)
  static struct mach_timebase_info info;
  if (info.denom == 0) {
    kern_return_t result = mach_timebase_info(&info);
    PI_TRACE_CLOCK_DCHECK(result == KERN_SUCCESS);
    (void)result;
  }
  ticks = mach_absolute_time() / kNanosecondsPerMicrosecond *
      info.numer / info.denom;
#else
  ticks = ClockNow(CLOCK_MONOTONIC);
#endif
  return ticks + 1;
#endif
}

bool CpuTimestampSupportedNative() noexcept {
#if defined(__APPLE__) || defined(__ANDROID__) || \
    (defined(_POSIX_THREAD_CPUTIME) && _POSIX_THREAD_CPUTIME >= 0)
  return true;
#elif defined(_WIN32)
  static bool is_supported = HasNonStopTimeStampCounter();
  return is_supported;
#else
  return false;
#endif
}

void WaitForCpuTimestampInitializationNative() noexcept {
#if defined(_WIN32) && !defined(_M_ARM64) && !defined(__aarch64__)
  while (TSCTicksPerSecond() == 0) ::Sleep(10);
#endif
}

int64_t CurrentCpuTimestampMicrosecondsNative() noexcept {
#if defined(__APPLE__)
  return ComputeThreadTicks();
#elif defined(__ANDROID__) || \
    (defined(_POSIX_THREAD_CPUTIME) && _POSIX_THREAD_CPUTIME >= 0)
  return ClockNow(CLOCK_THREAD_CPUTIME_ID);
#elif defined(_WIN32)
  PI_TRACE_CLOCK_DCHECK(CpuTimestampSupportedNative());
#if defined(_M_ARM64) || defined(__aarch64__)
  FILETIME creation_time, exit_time, kernel_time, user_time;
  ::GetThreadTimes(::GetCurrentThread(), &creation_time, &exit_time,
                   &kernel_time, &user_time);
  int64_t raw;
  static_assert(sizeof(raw) == sizeof(user_time));
  // The original bit_cast preserves these exact little-endian representation bytes.
  std::memcpy(&raw, &user_time, sizeof(raw));
  return raw / 10;
#else
  ULONG64 thread_cycle_time = 0;
  ::QueryThreadCycleTime(::GetCurrentThread(), &thread_cycle_time);
  double tsc_ticks_per_second = TSCTicksPerSecond();
  if (tsc_ticks_per_second == 0) return 0;
  double thread_time_seconds = thread_cycle_time / tsc_ticks_per_second;
  return static_cast<int64_t>(thread_time_seconds * kMicrosecondsPerSecond);
#endif
#else
  Unreachable(__FILE__, __LINE__);
#endif
}
}  // namespace pi_node::tracing
