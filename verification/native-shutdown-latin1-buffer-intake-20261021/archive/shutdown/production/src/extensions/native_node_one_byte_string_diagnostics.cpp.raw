// Copyright 2012 the V8 project authors. BSD-style license retained.
// Direct native projection of StringLength(uint8_t*) and the failing
// MaybeHandle::Check path selected by NewFromOneByte(kNormal).
#include "native_node_one_byte_string_diagnostics.h"
#include "native_node_diagnostic_context.hpp"
#include "native_v8_base_fatal.h"
#include <cstring>
#include <limits>

#ifdef DEBUG
#include <sstream>
#include <string>
namespace {
class CheckMessageStream : public std::ostringstream {};
template <typename T>
std::string PrintCheckOperand(T value) {
  CheckMessageStream oss;
  oss << value;
  return oss.str();
}
template <typename Lhs, typename Rhs>
PI_V8_BASE_NOINLINE std::string* MakeCheckOpString(
    Lhs lhs, Rhs rhs, const char* msg) {
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

extern "C" int pi_node_one_byte_string_cstring_length(
    JSContext* context, const uint8_t* data) {
  pi::node::DiagnosticContextScope diagnostic_scope(context);
  const size_t len = std::strlen(reinterpret_cast<const char*>(data));
  constexpr int kMaxInt = std::numeric_limits<int>::max();
  static_assert(kMaxInt == 2147483647);
  // Original CHECK_GE uses its safe signed/unsigned comparison helper.
  // kMaxInt is nonnegative, so this exact conversion preserves that result.
  // strlen and both comparison operands are evaluated once.
  if (!(static_cast<size_t>(kMaxInt) >= len)) [[unlikely]] {
#ifdef DEBUG
    std::string* message = MakeCheckOpString<int, size_t>(
        kMaxInt, len, "i::kMaxInt >= len");
    pi_v8_base_fatal("deps/v8/src/api/api.cc", 7537,
                    "Check failed: %s.", message->c_str());
    delete message;
#elif defined(OFFICIAL_BUILD)
    PI_V8_BASE_IMMEDIATE_CRASH();
#else
    pi_v8_base_fatal("Check failed: %s.", "i::kMaxInt >= len");
#endif
  }
  return static_cast<int>(len);
}

extern "C" [[noreturn]] void pi_node_one_byte_string_empty_maybe_handle(
    JSContext* context) {
  pi::node::DiagnosticContextScope diagnostic_scope(context);
#ifdef DEBUG
  pi_v8_base_fatal("deps/v8/src/handles/maybe-handles.h", 53,
                  "Check failed: %s.", "(location_) != nullptr");
#elif defined(OFFICIAL_BUILD)
  PI_V8_BASE_IMMEDIATE_CRASH();
#else
  pi_v8_base_fatal("Check failed: %s.", "(location_) != nullptr");
#endif
}
