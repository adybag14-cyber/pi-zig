#ifndef PI_NATIVE_NODE_CUSTOM_BUFFER_LISTENER_ALLOCATION_H
#define PI_NATIVE_NODE_CUSTOM_BUFFER_LISTENER_ALLOCATION_H

#include <stddef.h>

typedef struct JSContext JSContext;

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Storage for the Zig port of CustomBufferJSListener. The caller constructs the
 * actual Listener and uv_buf_t in this stable allocation, and runs the real
 * StreamListener destructor before release. There is no JS/backing-store root.
 *
 * These synchronous calls borrow context. allocation_size and alignment are
 * exactly the native Zig record's size/alignment; alignment must not exceed
 * max_align_t. The genuine standard-new retry/fatal policy does not return
 * allocation failure. The native allocation prefix owns its memory-domain
 * entitlement independently of the Engine.
 */
void* pi_node_custom_buffer_listener_allocate(
    JSContext* context, void* memory_owner,
    size_t allocation_size, size_t alignment);

/* After unlink/destruction. A NULL context is valid for an unlinked listener;
 * no current or former Engine is needed to retire its allocation prefix. */
void pi_node_custom_buffer_listener_free(JSContext* context, void* storage);

#ifdef __cplusplus
}
#endif
#endif
