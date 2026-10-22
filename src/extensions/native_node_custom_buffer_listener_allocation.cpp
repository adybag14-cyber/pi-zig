// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
// Native standard-new allocation for the Zig CustomBufferJSListener record.
#include "native_node_custom_buffer_listener_allocation.h"
#include "native_node_diagnostic_context.hpp"
#include "native_node_standard_allocator.hpp"

#include <cassert>
#include <cstddef>

extern "C" void* pi_node_custom_buffer_listener_allocate(
    JSContext* context, void* memory_owner,
    std::size_t allocation_size, std::size_t alignment) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    assert(memory_owner != nullptr && allocation_size != 0);
    assert(alignment != 0 && (alignment & (alignment - 1)) == 0);
    assert(alignment <= alignof(std::max_align_t));
    pi_node::AllocationScope allocation_scope(memory_owner);
    // Matches plain new's real new_handler retry / native bad_alloc fatal
    // policy. A returned nullable allocation or a guest OOM is not substituted.
    return pi_node::allocateStandard(allocation_size);
}

extern "C" void pi_node_custom_buffer_listener_free(
    JSContext* context, void* storage) {
    pi::node::DiagnosticContextScope diagnostic_scope(context);
    // The caller has completed StreamListener::~StreamListener already.
    // The prefix owns the allocator domain, including after Engine teardown.
    pi_simd::release(storage);
}
