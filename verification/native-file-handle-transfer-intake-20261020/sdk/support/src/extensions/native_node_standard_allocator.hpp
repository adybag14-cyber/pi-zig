// Native C++ standard-container allocation for the pinned libc++ build.
// The allocation/new-handler sequence follows libc++ new.cpp (Apache-2.0
// WITH LLVM-exception); the underlying charged block owner is shared with
// the separately reviewed simdjson owner. No Engine or JS value is stored.
#ifndef PI_NATIVE_NODE_STANDARD_ALLOCATOR_HPP
#define PI_NATIVE_NODE_STANDARD_ALLOCATOR_HPP
#include "native_simdjson_memory.hpp"
#include <__new/exceptions.h>
#include <cstddef>
#include <limits>
#include <new>
#include <type_traits>

#if !defined(_LIBCPP_VERSION) || _LIBCPP_STD_VER < 20
#error "the standard-container owner requires the pinned C++20 libc++ source"
#endif
#if _LIBCPP_HAS_EXCEPTIONS
#error "the selected Node standard-container translation units disable exceptions"
#endif

namespace pi_node {
using AllocationScope = pi_simd::Scope;

// A standard allocator must not return nullptr. Preserve the actual native
// new-handler retry and bad_alloc path; this is never a JavaScript exception.
// The prefix allocator rolls a failed physical malloc reservation back before
// the handler runs. Every successful block retains its original native owner.
inline void* allocateStandard(std::size_t bytes) {
  if (bytes == 0) bytes = 1;
  for (;;) {
    if (void* result = pi_simd::allocate(bytes)) return result;
    const std::new_handler handler = std::get_new_handler();
    if (handler) handler();
    else std::__throw_bad_alloc();
  }
}

template<class T>
class Allocator {
 public:
  using value_type = T;
  using size_type = std::size_t;
  using difference_type = std::ptrdiff_t;
  using propagate_on_container_move_assignment = std::true_type;
  using is_always_equal = std::true_type;

  constexpr Allocator() noexcept = default;
  template<class U>
  constexpr Allocator(const Allocator<U>&) noexcept {}

  [[nodiscard]] T* allocate(std::size_t count) {
    static_assert(alignof(T) <= alignof(std::max_align_t),
                  "the admitted native containers use malloc-aligned elements");
    if (count > std::numeric_limits<std::size_t>::max() / sizeof(T))
      std::__throw_bad_array_new_length();
    return static_cast<T*>(allocateStandard(count * sizeof(T)));
  }
  void deallocate(T* value, std::size_t) noexcept {
    pi_simd::release(value);
  }
};

template<class T, class U>
constexpr bool operator==(const Allocator<T>&, const Allocator<U>&) noexcept {
  return true;
}
static_assert(std::is_empty_v<Allocator<char>>,
              "the allocator must not add per-string state or remove SSO");
}  // namespace pi_node
#endif
