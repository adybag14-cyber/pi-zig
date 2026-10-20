// Actual per-allocation accounting for the private simdjson successor.
// The allocator domain may leave scope before a parser or one of its blocks
// retires. Each block holds its own native memory-owner entitlement.
#include "native_simdjson_memory.hpp"

extern "C" {
void pi_js_retain_memory_owner(void* memory_owner);
void pi_js_release_memory_owner(void* memory_owner);
int pi_js_native_memory_reserve(void* memory_owner, std::size_t bytes);
void pi_js_native_memory_release(void* memory_owner, std::size_t bytes);
}

namespace pi_simd {
namespace {
struct alignas(std::max_align_t) Allocation {
  void* memory_owner;
  std::size_t charge;
};
static_assert(sizeof(Allocation) % alignof(std::max_align_t) == 0,
              "the payload must retain malloc alignment");
thread_local Scope* current_scope = nullptr;
}

Scope::Scope(void* memory_owner) noexcept
    : previous_(current_scope), memory_owner_(memory_owner) {
  // This is an internal C ABI precondition. The public native parser owner
  // obtains the actual nonnull memory owner before any parser operation.
  if (!memory_owner_) std::abort();
  pi_js_retain_memory_owner(memory_owner_);
  current_scope = this;
}
Scope::~Scope() noexcept {
  if (current_scope != this) std::abort();
  current_scope = previous_;
  pi_js_release_memory_owner(memory_owner_);
}
void allocationFailure() noexcept {
  if (!current_scope) std::abort();
  current_scope->failed_ = true;
}
void* allocate(std::size_t payload) noexcept {
  Scope* scope = current_scope;
  if (!scope) std::abort();
  if (payload > std::numeric_limits<std::size_t>::max() - sizeof(Allocation)) {
    scope->failed_ = true;
    return nullptr;
  }
  const std::size_t charge = sizeof(Allocation) + payload;
  void* owner = scope->memory_owner_;
  if (!pi_js_native_memory_reserve(owner, charge)) {
    scope->failed_ = true;
    return nullptr;
  }
  auto* allocation = static_cast<Allocation*>(std::malloc(charge));
  if (!allocation) {
    // Roll back only this failed request. Existing parser blocks keep both
    // their exact charges and their independent ownership entitlements.
    pi_js_native_memory_release(owner, charge);
    scope->failed_ = true;
    return nullptr;
  }
  pi_js_retain_memory_owner(owner);
  ::new (static_cast<void*>(allocation)) Allocation{owner, charge};
  return allocation + 1;
}
void release(void* block) noexcept {
  if (!block) return;
  auto* allocation = static_cast<Allocation*>(block) - 1;
  void* owner = allocation->memory_owner;
  const std::size_t charge = allocation->charge;
  allocation->~Allocation();
  std::free(allocation);
  pi_js_native_memory_release(owner, charge);
  pi_js_release_memory_owner(owner);
}
}  // namespace pi_simd
