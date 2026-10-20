/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Selected Environment managed-buffer ownership. Native backing allocation and
 * later ArrayBuffer adoption are distinct callers of this table.
 */
#ifndef PI_NATIVE_NODE_MANAGED_BUFFERS_H
#define PI_NATIVE_NODE_MANAGED_BUFFERS_H
#include "quickjs.h"
#include "uv.h"
#include <stddef.h>
#ifdef __cplusplus
#define PI_MANAGED_NOEXCEPT noexcept
extern "C" {
#else
#define PI_MANAGED_NOEXCEPT
#endif

typedef struct PiNodeManagedBuffers PiNodeManagedBuffers;

/* The single Environment block supplies this exact native size and alignment.
 * Construction performs no backing allocation and creates no JavaScript value.
 * Storage remains stable until destroy, and is freed separately by its owner. */
size_t pi_node_managed_buffers_storage_size(void) PI_MANAGED_NOEXCEPT;
size_t pi_node_managed_buffers_storage_alignment(void) PI_MANAGED_NOEXCEPT;
PiNodeManagedBuffers* pi_node_managed_buffers_construct(void* storage)
    PI_MANAGED_NOEXCEPT;
void pi_node_managed_buffers_destroy(PiNodeManagedBuffers* table)
    PI_MANAGED_NOEXCEPT;

/* Consumes the actual owned token, including an unsuccessful duplicate-key
 * insertion. The caller has already performed NewBackingStore's allocation.
 * The original uv_buf_init unsigned-length conversion is retained. Container
 * allocation uses the actual native standard allocator/new-handler policy. */
void pi_node_managed_buffers_adopt(PiNodeManagedBuffers* table,
    void* memory_owner, JSPiArrayBufferBackingStore* owned,
    uv_buf_t* buffer) PI_MANAGED_NOEXCEPT;

/* owned_out must be empty. A null buffer base returns an empty token without a
 * lookup. A nonnull unknown base reaches the original Environment native CHECK.
 * A found token moves out before the actual table node is erased. */
void pi_node_managed_buffers_release(PiNodeManagedBuffers* table,
    JSContext* context, const uv_buf_t* buffer,
    JSPiArrayBufferBackingStore* owned_out) PI_MANAGED_NOEXCEPT;
size_t pi_node_managed_buffers_count(const PiNodeManagedBuffers* table)
    PI_MANAGED_NOEXCEPT;

#ifdef __cplusplus
}
#endif
#undef PI_MANAGED_NOEXCEPT
#endif
