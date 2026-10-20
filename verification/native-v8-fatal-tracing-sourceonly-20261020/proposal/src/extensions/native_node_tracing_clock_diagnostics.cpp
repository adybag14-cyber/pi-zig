// Copyright 2012-2013 the V8 project authors.
// BSD-style license retained with the pinned Node/V8 source authority.
// Native projection of logging.h CHECK_OP / CHECK / UNREACHABLE semantics for
// the selected tracing clock failure sites. No recovery or guest conversion.
#include "native_node_tracing_clock.hpp"
#include "native_v8_base_fatal.h"

#ifdef DEBUG
#include <sstream>
#include <string>
#endif

namespace pi_node::tracing {

#ifdef DEBUG
namespace {

// logging.h CheckMessageStream and integral PrintCheckOperand specialization.
// All four clock call sites capture signed integral operands representable in
// int64_t, compare their original types, and convert only on the failing path.
class CheckMessageStream : public std::ostringstream {};

std::string PrintCheckOperand(int64_t value) {
  CheckMessageStream oss;
  oss << value;
  return oss.str();
}

PI_V8_BASE_NOINLINE std::string* MakeCheckOpString(
    int64_t lhs, int64_t rhs, const char* msg) {
  std::string lhs_str = PrintCheckOperand(lhs);
  std::string rhs_str = PrintCheckOperand(rhs);
  CheckMessageStream ss;
  ss << msg;
  constexpr size_t kMaxInlineLength = 50;
  if (lhs_str.size() <= kMaxInlineLength &&
      rhs_str.size() <= kMaxInlineLength) {
    ss << " (" << lhs_str << " vs. " << rhs_str << ")";
  } else {
    ss << "\n   " << lhs_str << "\n vs.\n   " << rhs_str << "\n";
  }
  return new std::string(ss.str());
}

}  // namespace
#endif

[[noreturn]] void ClockCheckFailure(
    const char* file, int line, const char* expression) noexcept {
#ifdef DEBUG
  pi_v8_base_fatal(file, line, "Check failed: %s.", expression);
#elif defined(OFFICIAL_BUILD)
  PI_V8_BASE_IMMEDIATE_CRASH();
#else
  pi_v8_base_fatal("Check failed: %s.", expression);
#endif
}

[[noreturn]] void ClockCheckFailureOperands(
    const char* file, int line, const char* expression,
    int64_t lhs, int64_t rhs) noexcept {
#ifdef DEBUG
  std::string* message = MakeCheckOpString(lhs, rhs, expression);
  pi_v8_base_fatal(file, line, "Check failed: %s.", message->c_str());
  delete message;  // Retain the original CHECK_OP terminal-path ownership.
#elif defined(OFFICIAL_BUILD)
  PI_V8_BASE_IMMEDIATE_CRASH();
#else
  pi_v8_base_fatal("Check failed: %s.", expression);
#endif
}

[[noreturn]] void Unreachable(const char* file, int line) {
#ifdef DEBUG
  pi_v8_base_fatal(file, line, pi_v8_base_kUnreachableCodeMessage);
#elif defined(OFFICIAL_BUILD)
  PI_V8_BASE_IMMEDIATE_CRASH();
#else
  pi_v8_base_fatal(pi_v8_base_kUnreachableCodeMessage);
#endif
}

}  // namespace pi_node::tracing
