#include "engine_abi.h"
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    _Atomic size_t references;
    _Atomic size_t used;
    size_t limit;
} PiMemoryOwner;
static _Atomic size_t pi_memory_owners;
typedef struct {
    size_t size;
    max_align_t alignment;
} PiAllocation;
static int pi_reserve(PiMemoryOwner *owner, size_t size) {
    size_t used = atomic_load_explicit(&owner->used, memory_order_relaxed);
    do {
        if (size > owner->limit || used > owner->limit - size) return 0;
    } while (!atomic_compare_exchange_weak_explicit(&owner->used, &used, used + size,
                memory_order_relaxed, memory_order_relaxed));
    return 1;
}
void pi_js_release_memory_owner(void *opaque) {
    PiMemoryOwner *owner = opaque;
    if (atomic_fetch_sub_explicit(&owner->references, 1, memory_order_acq_rel) == 1) {
        atomic_fetch_sub_explicit(&pi_memory_owners, 1, memory_order_relaxed);
        free(owner);
    }
}
static void *pi_malloc(void *opaque, size_t size) {
    PiMemoryOwner *owner = opaque;
    if (size > SIZE_MAX - sizeof(PiAllocation)) return NULL;
    const size_t charge = sizeof(PiAllocation) + size;
    if (!pi_reserve(owner, charge)) return NULL;
    PiAllocation *allocation = malloc(charge);
    if (!allocation) {
        atomic_fetch_sub_explicit(&owner->used, charge, memory_order_relaxed);
        return NULL;
    }
    allocation->size = size;
    return allocation + 1;
}
static void *pi_calloc(void *opaque, size_t count, size_t size) {
    if (size && count > SIZE_MAX / size) return NULL;
    void *result = pi_malloc(opaque, count * size);
    if (result) memset(result, 0, count * size);
    return result;
}
static void pi_free(void *opaque, void *ptr) {
    if (!ptr) return;
    PiMemoryOwner *owner = opaque;
    PiAllocation *allocation = (PiAllocation *)ptr - 1;
    atomic_fetch_sub_explicit(&owner->used, sizeof(*allocation) + allocation->size, memory_order_relaxed);
    free(allocation);
}
static void *pi_realloc(void *opaque, void *ptr, size_t size) {
    if (!ptr) return pi_malloc(opaque, size);
    if (!size) { pi_free(opaque, ptr); return NULL; }
    if (size > SIZE_MAX - sizeof(PiAllocation)) return NULL;
    PiMemoryOwner *owner = opaque;
    PiAllocation *allocation = (PiAllocation *)ptr - 1;
    const size_t old = allocation->size;
    if (size > old && !pi_reserve(owner, size - old)) return NULL;
    PiAllocation *resized = realloc(allocation, sizeof(*allocation) + size);
    if (!resized) {
        if (size > old) atomic_fetch_sub_explicit(&owner->used, size - old, memory_order_relaxed);
        return NULL;
    }
    if (size < old) atomic_fetch_sub_explicit(&owner->used, old - size, memory_order_relaxed);
    resized->size = size;
    return resized + 1;
}
static size_t pi_usable_size(const void *ptr) {
    return ptr ? ((const PiAllocation *)ptr - 1)->size : 0;
}

/* Shared buffers may outlive either VM wrapper and cross worker runtimes.
 * Own the backing memory independently of JS objects; no opaque JS reference
 * is retained, so a source-buffer -> clone cycle remains collectable. */
typedef struct {
    _Atomic size_t references;
    PiMemoryOwner *owner;
    size_t charge;
    max_align_t alignment;
} PiSharedBuffer;
static _Atomic size_t pi_shared_allocations;
static void *pi_shared_alloc(void *opaque, size_t size) {
    PiMemoryOwner *owner = opaque;
    if (size > SIZE_MAX - sizeof(PiSharedBuffer)) return NULL;
    const size_t charge = sizeof(PiSharedBuffer) + size;
    if (!pi_reserve(owner, charge)) return NULL;
    PiSharedBuffer *buffer = malloc(charge);
    if (!buffer) { atomic_fetch_sub_explicit(&owner->used, charge, memory_order_relaxed); return NULL; }
    atomic_init(&buffer->references, 1);
    buffer->owner = owner;
    buffer->charge = charge;
    atomic_fetch_add_explicit(&owner->references, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&pi_shared_allocations, 1, memory_order_relaxed);
    return buffer + 1;
}
static void pi_shared_dup(void *opaque, void *ptr) {
    (void)opaque;
    PiSharedBuffer *buffer = (PiSharedBuffer *)ptr - 1;
    atomic_fetch_add_explicit(&buffer->references, 1, memory_order_relaxed);
}
static void pi_shared_free(void *opaque, void *ptr) {
    (void)opaque;
    PiSharedBuffer *buffer = (PiSharedBuffer *)ptr - 1;
    if (atomic_fetch_sub_explicit(&buffer->references, 1, memory_order_acq_rel) == 1) {
        atomic_fetch_sub_explicit(&pi_shared_allocations, 1, memory_order_relaxed);
        PiMemoryOwner *owner = buffer->owner;
        atomic_fetch_sub_explicit(&owner->used, buffer->charge, memory_order_relaxed);
        free(buffer);
        pi_js_release_memory_owner(owner);
    }
}
JSRuntime *pi_js_new_runtime(size_t memory_limit, void **memory_owner) {
    PiMemoryOwner *owner = malloc(sizeof(*owner));
    if (!owner) return NULL;
    atomic_init(&owner->references, 1);
    atomic_init(&owner->used, 0);
    owner->limit = memory_limit;
    atomic_fetch_add_explicit(&pi_memory_owners, 1, memory_order_relaxed);
    const JSMallocFunctions allocator = {
        .js_calloc = pi_calloc, .js_malloc = pi_malloc, .js_free = pi_free,
        .js_realloc = pi_realloc, .js_malloc_usable_size = pi_usable_size,
    };
    JSRuntime *runtime = JS_NewRuntime2(&allocator, owner);
    if (!runtime) { pi_js_release_memory_owner(owner); return NULL; }
    const JSSharedArrayBufferFunctions functions = {
        .sab_alloc = pi_shared_alloc,
        .sab_free = pi_shared_free,
        .sab_dup = pi_shared_dup,
        .sab_opaque = owner,
    };
    JS_SetSharedArrayBufferFunctions(runtime, &functions);
    *memory_owner = owner;
    return runtime;
}
size_t pi_js_shared_buffer_allocations(void) {
    return atomic_load_explicit(&pi_shared_allocations, memory_order_relaxed);
}
size_t pi_js_native_memory_owners(void) {
    return atomic_load_explicit(&pi_memory_owners, memory_order_relaxed);
}
size_t pi_js_native_memory_used(void *opaque) {
    PiMemoryOwner *owner = opaque;
    return atomic_load_explicit(&owner->used, memory_order_relaxed);
}
JSValue pi_js_undefined(void) { return JS_UNDEFINED; }
JSValue pi_js_null(void) { return JS_NULL; }
JSValue pi_js_bool(JSContext *context, int value) { return JS_NewBool(context, value); }
JSValue pi_js_int32(JSContext *context, int32_t value) { return JS_NewInt32(context, value); }
JSModuleDef *pi_js_module(JSValue value) { return JS_VALUE_GET_PTR(value); }
void *pi_js_object_identity(JSValue value) { return JS_VALUE_GET_PTR(value); }
JSValue pi_js_module_value(JSContext *context, JSModuleDef *module) { return JS_DupValue(context, JS_MKPTR(JS_TAG_MODULE, module)); }
JSValue pi_js_function_magic(JSContext *context, JSCFunctionMagic *function, const char *name, int length, int magic) {
    return JS_NewCFunctionMagic(context, function, name, length, JS_CFUNC_generic_magic, magic);
}
