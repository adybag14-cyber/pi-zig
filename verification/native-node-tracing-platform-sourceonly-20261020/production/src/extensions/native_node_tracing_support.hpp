// Selected native synchronization and embedding-pointer helpers from Node.
// Full licensed originals and exact source ranges are retained in verification.
#ifndef PI_NATIVE_NODE_TRACING_SUPPORT_HPP
#define PI_NATIVE_NODE_TRACING_SUPPORT_HPP
#include "uv.h"
#include "native_node_check_failure.h"
#include "native_node_diagnostic_context.h"
#include <cstdint>
#include <cstdlib>
#include <utility>
#ifdef _WIN32
#include <process.h>
#endif

namespace pi_node::tracing {
// The real native loop-close diagnostic owns its temporary symbol context.
// Neither it nor the assertion owner retains the borrowed current context.
void CheckedUvLoopClose(uv_loop_t* loop);
}

#if defined(__GNUC__)
#define PI_TRACE_PRETTY_FUNCTION __PRETTY_FUNCTION__
#elif defined(_MSC_VER)
#define PI_TRACE_PRETTY_FUNCTION __FUNCSIG__
#else
#define PI_TRACE_PRETTY_FUNCTION ""
#endif
#define PI_TRACE_STRINGIFY_(value) #value
#define PI_TRACE_STRINGIFY(value) PI_TRACE_STRINGIFY_(value)
#ifdef _WIN32
#define PI_NODE_TRACE_ABORT_NO_BACKTRACE() _exit(134)
#else
#define PI_NODE_TRACE_ABORT_NO_BACKTRACE() std::abort()
#endif

// util.h ERROR_AND_ABORT keeps one static assertion record and does not mark
// its actual diagnostic call noreturn, preserving the caller's stack frame.
// The source-selected Node Abort exit code is 134. Read the existing borrowed
// TLS context only on the immediate failure path; never store it in an object.
#define PI_NODE_TRACE_ERROR_AND_ABORT(expr) \
  do { \
    static const PiNodeAssertionInfo error_and_abort_args = { \
        __FILE__ ":" PI_TRACE_STRINGIFY(__LINE__), #expr, \
        PI_TRACE_PRETTY_FUNCTION}; \
    pi_node_assert_failure(pi_node_diagnostic_context_current(), \
                           &error_and_abort_args); \
    PI_NODE_TRACE_ABORT_NO_BACKTRACE(); \
  } while (0)
#define PI_NODE_TRACE_CHECK(expr) \
  do { \
    if (!(expr)) [[unlikely]] { \
      PI_NODE_TRACE_ERROR_AND_ABORT(expr); \
    } \
  } while (0)
#define PI_NODE_TRACE_CHECK_EQ(a, b) PI_NODE_TRACE_CHECK((a) == (b))
#define PI_NODE_TRACE_CHECK_GE(a, b) PI_NODE_TRACE_CHECK((a) >= (b))
#define PI_NODE_TRACE_CHECK_NULL(val) PI_NODE_TRACE_CHECK((val) == nullptr)
#define PI_NODE_TRACE_CHECK_NOT_NULL(val) PI_NODE_TRACE_CHECK((val) != nullptr)

namespace pi_node::tracing {
template <typename Traits> class ConditionVariableBase;
template <typename Traits> class MutexBase;
struct LibuvMutexTraits;
using ConditionVariable = ConditionVariableBase<LibuvMutexTraits>;
using Mutex = MutexBase<LibuvMutexTraits>;

template <typename Traits>
class MutexBase {
 public:
  inline MutexBase();
  inline ~MutexBase();
  inline void Lock();
  inline void Unlock();
  inline void RdLock();
  inline void RdUnlock();

  MutexBase(const MutexBase&) = delete;
  MutexBase& operator=(const MutexBase&) = delete;

  class ScopedLock;
  class ScopedUnlock;

  class ScopedLock {
   public:
    inline explicit ScopedLock(const MutexBase& mutex);
    inline explicit ScopedLock(const ScopedUnlock& scoped_unlock);
    inline ~ScopedLock();

    ScopedLock(const ScopedLock&) = delete;
    ScopedLock& operator=(const ScopedLock&) = delete;

   private:
    template <typename> friend class ConditionVariableBase;
    friend class ScopedUnlock;
    const MutexBase& mutex_;
  };

  class ScopedReadLock {
   public:
    inline explicit ScopedReadLock(const MutexBase& mutex);
    inline ~ScopedReadLock();

    ScopedReadLock(const ScopedReadLock&) = delete;
    ScopedReadLock& operator=(const ScopedReadLock&) = delete;

   private:
    template <typename> friend class ConditionVariableBase;
    const MutexBase& mutex_;
  };

  using ScopedWriteLock = ScopedLock;

  class ScopedUnlock {
   public:
    inline explicit ScopedUnlock(const ScopedLock& scoped_lock);
    inline ~ScopedUnlock();

    ScopedUnlock(const ScopedUnlock&) = delete;
    ScopedUnlock& operator=(const ScopedUnlock&) = delete;

   private:
    friend class ScopedLock;
    const MutexBase& mutex_;
  };

 private:
  template <typename> friend class ConditionVariableBase;
  mutable typename Traits::MutexT mutex_;
};

template <typename Traits>
class ConditionVariableBase {
 public:
  using ScopedLock = typename MutexBase<Traits>::ScopedLock;

  inline ConditionVariableBase();
  inline ~ConditionVariableBase();
  inline void Broadcast(const ScopedLock&);
  inline void Signal(const ScopedLock&);
  inline void Wait(const ScopedLock& scoped_lock);

  ConditionVariableBase(const ConditionVariableBase&) = delete;
  ConditionVariableBase& operator=(const ConditionVariableBase&) = delete;

 private:
  typename Traits::CondT cond_;
};

struct LibuvMutexTraits {
  using CondT = uv_cond_t;
  using MutexT = uv_mutex_t;

  static inline int cond_init(CondT* cond) {
    return uv_cond_init(cond);
  }

  static inline int mutex_init(MutexT* mutex) {
    return uv_mutex_init(mutex);
  }

  static inline void cond_broadcast(CondT* cond) {
    uv_cond_broadcast(cond);
  }

  static inline void cond_destroy(CondT* cond) {
    uv_cond_destroy(cond);
  }

  static inline void cond_signal(CondT* cond) {
    uv_cond_signal(cond);
  }

  static inline void cond_wait(CondT* cond, MutexT* mutex) {
    uv_cond_wait(cond, mutex);
  }

  static inline void mutex_destroy(MutexT* mutex) {
    uv_mutex_destroy(mutex);
  }

  static inline void mutex_lock(MutexT* mutex) {
    uv_mutex_lock(mutex);
  }

  static inline void mutex_unlock(MutexT* mutex) {
    uv_mutex_unlock(mutex);
  }

  static inline void mutex_rdlock(MutexT* mutex) {
    uv_mutex_lock(mutex);
  }

  static inline void mutex_rdunlock(MutexT* mutex) {
    uv_mutex_unlock(mutex);
  }
};

template <typename Traits>
ConditionVariableBase<Traits>::ConditionVariableBase() {
  PI_NODE_TRACE_CHECK_EQ(0, Traits::cond_init(&cond_));
}

template <typename Traits>
ConditionVariableBase<Traits>::~ConditionVariableBase() {
  Traits::cond_destroy(&cond_);
}

template <typename Traits>
void ConditionVariableBase<Traits>::Broadcast(const ScopedLock&) {
  Traits::cond_broadcast(&cond_);
}

template <typename Traits>
void ConditionVariableBase<Traits>::Signal(const ScopedLock&) {
  Traits::cond_signal(&cond_);
}

template <typename Traits>
void ConditionVariableBase<Traits>::Wait(const ScopedLock& scoped_lock) {
  Traits::cond_wait(&cond_, &scoped_lock.mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::MutexBase() {
  PI_NODE_TRACE_CHECK_EQ(0, Traits::mutex_init(&mutex_));
}

template <typename Traits>
MutexBase<Traits>::~MutexBase() {
  Traits::mutex_destroy(&mutex_);
}

template <typename Traits>
void MutexBase<Traits>::Lock() {
  Traits::mutex_lock(&mutex_);
}

template <typename Traits>
void MutexBase<Traits>::Unlock() {
  Traits::mutex_unlock(&mutex_);
}

template <typename Traits>
void MutexBase<Traits>::RdLock() {
  Traits::mutex_rdlock(&mutex_);
}

template <typename Traits>
void MutexBase<Traits>::RdUnlock() {
  Traits::mutex_rdunlock(&mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedLock::ScopedLock(const MutexBase& mutex)
    : mutex_(mutex) {
  Traits::mutex_lock(&mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedLock::ScopedLock(const ScopedUnlock& scoped_unlock)
    : MutexBase(scoped_unlock.mutex_) {}

template <typename Traits>
MutexBase<Traits>::ScopedLock::~ScopedLock() {
  Traits::mutex_unlock(&mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedReadLock::ScopedReadLock(const MutexBase& mutex)
    : mutex_(mutex) {
  Traits::mutex_rdlock(&mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedReadLock::~ScopedReadLock() {
  Traits::mutex_rdunlock(&mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedUnlock::ScopedUnlock(const ScopedLock& scoped_lock)
    : mutex_(scoped_lock.mutex_) {
  Traits::mutex_unlock(&mutex_.mutex_);
}

template <typename Traits>
MutexBase<Traits>::ScopedUnlock::~ScopedUnlock() {
  Traits::mutex_lock(&mutex_.mutex_);
}


// The helper is for doing safe downcasts from base types to derived types.
template <typename Inner, typename Outer>
class ContainerOfHelper {
 public:
  inline ContainerOfHelper(Inner Outer::*field, Inner* pointer);
  template <typename TypeName>
  inline operator TypeName*() const;
 private:
  Outer* const pointer_;
};

// Calculate the address of the outer (i.e. embedding) struct from
// the interior pointer to a data member.
template <typename Inner, typename Outer>
constexpr ContainerOfHelper<Inner, Outer> ContainerOf(Inner Outer::*field,
                                                      Inner* pointer);

template <typename Inner, typename Outer>
constexpr uintptr_t OffsetOf(Inner Outer::*field) {
  return reinterpret_cast<uintptr_t>(&(static_cast<Outer*>(nullptr)->*field));
}

template <typename Inner, typename Outer>
ContainerOfHelper<Inner, Outer>::ContainerOfHelper(Inner Outer::*field,
                                                   Inner* pointer)
    : pointer_(
        reinterpret_cast<Outer*>(
            reinterpret_cast<uintptr_t>(pointer) - OffsetOf(field))) {}

template <typename Inner, typename Outer>
template <typename TypeName>
ContainerOfHelper<Inner, Outer>::operator TypeName*() const {
  return static_cast<TypeName*>(pointer_);
}

template <typename Inner, typename Outer>
constexpr ContainerOfHelper<Inner, Outer> ContainerOf(Inner Outer::*field,
                                                      Inner* pointer) {
  return ContainerOfHelper<Inner, Outer>(field, pointer);
}

}  // namespace pi_node::tracing
#endif
