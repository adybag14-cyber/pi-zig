// Copyright 2013 the V8 project authors. All rights reserved.
// BSD-style license retained with the exact original source authority.
#include "native_node_tracing_platform.hpp"

#ifdef DEBUG
#include <sstream>
#include <string>
#endif

namespace pi_node::tracing {

#ifdef DEBUG
void V8MutexDcheckEq(const char* file, int line, const char* expression,
                     int lhs, int rhs) {
  if (lhs == rhs) return;

  // logging.h PrintCheckOperand<int>, MakeCheckOpString<int, int>, and
  // DCHECK_OP. Both selected operands retain the original signed int type.
  std::ostringstream lhs_stream;
  lhs_stream << lhs;
  std::string lhs_str = lhs_stream.str();
  std::ostringstream rhs_stream;
  rhs_stream << rhs;
  std::string rhs_str = rhs_stream.str();
  std::ostringstream ss;
  ss << expression;
  constexpr size_t kMaxInlineLength = 50;
  if (lhs_str.size() <= kMaxInlineLength &&
      rhs_str.size() <= kMaxInlineLength) {
    ss << " (" << lhs_str << " vs. " << rhs_str << ")";
  } else {
    ss << "\n   " << lhs_str << "\n vs.\n   " << rhs_str << "\n";
  }
  std::string* message = new std::string(ss.str());
  pi_v8_base_dcheck(file, line, message->c_str());
  delete message;
}
#endif

V8Mutex::V8Mutex() {
#ifdef DEBUG
  level_ = 0;
#endif
}

V8Mutex::~V8Mutex() {
#ifdef DEBUG
  V8MutexDcheckEq(__FILE__, __LINE__, "0 == level_", 0, level_);
#endif
}

void V8Mutex::Lock() ABSL_NO_THREAD_SAFETY_ANALYSIS {
  native_handle_.Lock();
  AssertUnheldAndMark();
}

void V8Mutex::Unlock() ABSL_NO_THREAD_SAFETY_ANALYSIS {
  AssertHeldAndUnmark();
  native_handle_.Unlock();
}

bool V8Mutex::TryLock() ABSL_NO_THREAD_SAFETY_ANALYSIS {
  if (!native_handle_.TryLock()) return false;
  AssertUnheldAndMark();
  return true;
}

}  // namespace pi_node::tracing
