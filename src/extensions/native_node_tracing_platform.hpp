// Copyright 2013 the V8 project authors. All rights reserved.
// BSD-style license retained with the exact original source authority.
// Selected src/base/platform/mutex.h owner, backed by the original Abseil
// mutex. Only native names, allocation ownership and diagnostic entry change.
#ifndef PI_NATIVE_NODE_TRACING_PLATFORM_HPP
#define PI_NATIVE_NODE_TRACING_PLATFORM_HPP

#include "native_node_tracing_core.hpp"
#include "native_v8_base_fatal.h"
#include "absl/synchronization/mutex.h"
#ifdef DEBUG
#include <string>
#endif

namespace pi_node::tracing {

#ifdef DEBUG
// Selected DCHECK_EQ operands are both int. The original diagnostic macro
// calls the shared dcheck owner at the assertion site and deletes its allocated
// message if that hook returns; no terminal helper removes the caller frame.
PI_V8_BASE_NOINLINE std::string* V8MutexMakeCheckOpString(
    int lhs, int rhs, const char* expression);
inline std::string* V8MutexCheckEqImpl(
    int lhs, int rhs, const char* expression) {
  return lhs == rhs ? nullptr : V8MutexMakeCheckOpString(lhs, rhs, expression);
}
#define PI_TRACE_V8_DCHECK_EQ(lhs, rhs) \
  do { \
    if (std::string* message = ::pi_node::tracing::V8MutexCheckEqImpl( \
            (lhs), (rhs), #lhs " == " #rhs)) { \
      pi_v8_base_dcheck(__FILE__, __LINE__, message->c_str()); \
      delete message; \
    } \
  } while (false)
#define PI_TRACE_V8_DCHECK_NOT_NULL(value) \
  do { \
    if (!((value) != nullptr)) [[unlikely]] { \
      pi_v8_base_dcheck(__FILE__, __LINE__, "(" #value ") != nullptr"); \
    } \
  } while (false)
#else
#define PI_TRACE_V8_DCHECK_EQ(lhs, rhs) ((void)0)
#define PI_TRACE_V8_DCHECK_NOT_NULL(value) ((void)0)
#endif

class V8Mutex final : public NativeAllocated {
 public:
  V8Mutex();
  V8Mutex(const V8Mutex&) = delete;
  V8Mutex& operator=(const V8Mutex&) = delete;
  ~V8Mutex();

  void Lock();
  void Unlock();
  [[nodiscard]] bool TryLock();

  inline void AssertHeld() const {
    PI_TRACE_V8_DCHECK_EQ(1, level_);
  }

 private:
#ifdef DEBUG
  int level_;
#endif

  inline void AssertHeldAndUnmark() {
#ifdef DEBUG
    PI_TRACE_V8_DCHECK_EQ(1, level_);
    level_--;
#endif
  }

  inline void AssertUnheldAndMark() {
#ifdef DEBUG
    PI_TRACE_V8_DCHECK_EQ(0, level_);
    level_++;
#endif
  }

  absl::Mutex native_handle_;
};

template <typename Mutex>
class [[nodiscard]] V8LockGuard final {
 public:
  explicit V8LockGuard(Mutex* mutex) : mutex_(mutex) {
    PI_TRACE_V8_DCHECK_NOT_NULL(mutex_);
    mutex_->Lock();
  }
  explicit V8LockGuard(Mutex& mutex) : mutex_(&mutex) {
    mutex_->Lock();
  }
  V8LockGuard(const V8LockGuard&) = delete;
  V8LockGuard& operator=(const V8LockGuard&) = delete;
  V8LockGuard(V8LockGuard&& other) noexcept : mutex_(other.mutex_) {
    PI_TRACE_V8_DCHECK_NOT_NULL(mutex_);
    other.mutex_ = nullptr;
  }
  ~V8LockGuard() {
    if (mutex_) {
      mutex_->Unlock();
    }
  }

 private:
  Mutex* mutex_;
};

using V8MutexGuard = V8LockGuard<V8Mutex>;

#ifndef DEBUG
static_assert(sizeof(V8Mutex) == sizeof(absl::Mutex));
static_assert(alignof(V8Mutex) == alignof(absl::Mutex));
#endif

#undef PI_TRACE_V8_DCHECK_NOT_NULL
#undef PI_TRACE_V8_DCHECK_EQ

}  // namespace pi_node::tracing
#endif
