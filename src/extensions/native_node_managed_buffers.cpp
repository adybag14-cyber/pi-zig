// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Node24.13 Environment::allocate_managed_buffer/release_managed_buffer table.
// The VM's move-only token stores native callbacks inline. This changes the
// mapped node's representation relative to V8's unique_ptr, without adding a
// boxed-token allocation. No native-node byte-size parity is claimed.
#include "native_node_managed_buffers.h"
#include "native_node_standard_allocator.hpp"
#include "native_node_check_failure.h"
#include <cstdlib>
#include <functional>
#include <new>
#include <unordered_map>
#include <utility>

namespace {
class BackingStore {
 public:
  BackingStore() noexcept = default;
  explicit BackingStore(JSPiArrayBufferBackingStore* owned) noexcept
      : value_(std::exchange(*owned, JSPiArrayBufferBackingStore{})) {}
  BackingStore(BackingStore&& other) noexcept
      : value_(std::exchange(other.value_, JSPiArrayBufferBackingStore{})) {}
  BackingStore& operator=(BackingStore&& other) noexcept {
    if (this != &other) {
      JS_PiReleaseArrayBufferBackingStore(&value_);
      value_ = std::exchange(other.value_, JSPiArrayBufferBackingStore{});
    }
    return *this;
  }
  ~BackingStore() noexcept { JS_PiReleaseArrayBufferBackingStore(&value_); }
  BackingStore(const BackingStore&) = delete;
  BackingStore& operator=(const BackingStore&) = delete;

  char* data() const noexcept {
    return reinterpret_cast<char*>(JS_PiArrayBufferBackingStoreData(&value_));
  }
  std::size_t byteLength() const noexcept {
    return JS_PiArrayBufferBackingStoreByteLength(&value_);
  }
  JSPiArrayBufferBackingStore take() noexcept {
    return std::exchange(value_, JSPiArrayBufferBackingStore{});
  }
 private:
  JSPiArrayBufferBackingStore value_{};
};
using Entry = std::pair<char* const, BackingStore>;
using Entries = std::unordered_map<char*, BackingStore, std::hash<char*>,
    std::equal_to<char*>, pi_node::Allocator<Entry>>;
}  // namespace

struct PiNodeManagedBuffers {
  Entries entries;
};

extern "C" std::size_t pi_node_managed_buffers_storage_size() noexcept {
  return sizeof(PiNodeManagedBuffers);
}
extern "C" std::size_t pi_node_managed_buffers_storage_alignment() noexcept {
  return alignof(PiNodeManagedBuffers);
}
extern "C" PiNodeManagedBuffers* pi_node_managed_buffers_construct(
    void* storage) noexcept {
  return ::new (storage) PiNodeManagedBuffers;
}
extern "C" void pi_node_managed_buffers_destroy(
    PiNodeManagedBuffers* table) noexcept {
  table->~PiNodeManagedBuffers();
}
extern "C" void pi_node_managed_buffers_adopt(PiNodeManagedBuffers* table,
    void* memory_owner, JSPiArrayBufferBackingStore* owned,
    uv_buf_t* buffer) noexcept {
  BackingStore bs(owned);
  *buffer = uv_buf_init(bs.data(), static_cast<unsigned int>(bs.byteLength()));
  pi_node::AllocationScope allocation(memory_owner);
  table->entries.emplace(buffer->base, std::move(bs));
}
extern "C" void pi_node_managed_buffers_release(PiNodeManagedBuffers* table,
    JSContext* context, const uv_buf_t* buffer,
    JSPiArrayBufferBackingStore* owned_out) noexcept {
  BackingStore bs;
  if (buffer->base != nullptr) {
    auto it = table->entries.find(buffer->base);
    if (it == table->entries.end()) {
      // Original src/env.cc:749 CHECK_NE at the selected operation.
      const PiNodeAssertionInfo info = {
          "../src/env.cc:749",
          "(it) != (released_allocated_buffers_.end())",
          "node::Environment::release_managed_buffer"};
      pi_node_assert_failure(context, &info);
      std::abort();
    }
    bs = std::move(it->second);
    table->entries.erase(it);
  }
  *owned_out = bs.take();
}
extern "C" std::size_t pi_node_managed_buffers_count(
    const PiNodeManagedBuffers* table) noexcept {
  return table->entries.size();
}
