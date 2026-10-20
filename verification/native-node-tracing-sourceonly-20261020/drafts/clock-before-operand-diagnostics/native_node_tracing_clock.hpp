// Copyright 2013 the V8 project authors. BSD-style license retained in verification.
#ifndef PI_NATIVE_NODE_TRACING_CLOCK_HPP
#define PI_NATIVE_NODE_TRACING_CLOCK_HPP
#include <cstdint>

namespace pi_node::tracing {
// Concrete native platform observations; no Engine, JSContext or callback is stored.
int CurrentProcessId() noexcept;
int CurrentThreadId() noexcept;
int64_t CurrentTimestampMicrosecondsNative() noexcept;
int64_t CurrentCpuTimestampMicrosecondsNative() noexcept;
bool CpuTimestampSupportedNative() noexcept;
void WaitForCpuTimestampInitializationNative() noexcept;

// Required V8 diagnostic projection. This is a terminal owner, never a guest
// exception or recoverable clock error. No fallback implementation is supplied.
[[noreturn]] void ClockCheckFailure(const char* file, int line,
                                   const char* expression) noexcept;
[[noreturn]] void Unreachable(const char* file, int line);
}
#endif
