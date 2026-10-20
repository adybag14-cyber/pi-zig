// Private allocator for the selected Node v24.13 simdjson ondemand owner.
// Vendor source remains under vendor/node-v24.13.0/simdjson unchanged.
// This header is included only by its separately pinned allocator successor.
#ifndef PI_NATIVE_SIMDJSON_MEMORY_HPP
#define PI_NATIVE_SIMDJSON_MEMORY_HPP
#include <cstddef>
#include <cstdlib>
#include <limits>
#include <memory>
#include <new>
#include <type_traits>

namespace pi_simd {

// An actual native allocation domain, scoped to one synchronous parser action.
// There is no Engine or JavaScript value in this owner. Every successful block
// separately retains its original memory owner until that exact block is freed.
class Scope final {
 public:
  explicit Scope(void* memory_owner) noexcept;
  ~Scope() noexcept;
  Scope(const Scope&) = delete;
  Scope& operator=(const Scope&) = delete;
  bool failed() const noexcept { return failed_; }

 private:
  friend void* allocate(std::size_t) noexcept;
  friend void allocationFailure() noexcept;
  Scope* previous_;
  void* memory_owner_;
  bool failed_ = false;
};

// Allocates exactly payload bytes plus the actual aligned ownership prefix.
// The same active domain remains charged while an old block is replaced.
void* allocate(std::size_t payload) noexcept;
void release(void* block) noexcept;
void allocationFailure() noexcept;

template<class T>
struct ArrayDelete {
  void operator()(T* value) const noexcept {
    static_assert(std::is_trivially_destructible<T>::value,
                  "selected simdjson array requires a trivial destructor");
    release(value);
  }
};
template<class T>
using Array = std::unique_ptr<T[], ArrayDelete<T>>;

template<class T>
inline T* array(std::size_t count) noexcept {
  static_assert(std::is_trivial<T>::value,
                "selected simdjson array has the original trivial lifetime");
  static_assert(alignof(T) <= alignof(std::max_align_t),
                "selected simdjson array exceeds malloc alignment");
  if (count > std::numeric_limits<std::size_t>::max() / sizeof(T)) {
    allocationFailure();
    return nullptr;
  }
  T* value = static_cast<T*>(allocate(count * sizeof(T)));
  if (!value) return nullptr;
  // Start the same default-initialized trivial element lifetimes as new T[n].
  // No value initialization or zeroing is added.
  for (std::size_t i = 0; i < count; ++i) {
    ::new (static_cast<void*>(value + i)) T;
  }
  return value;
}

}  // namespace pi_simd
#endif
