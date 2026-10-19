#include "engine_abi.h"
#include <stddef.h>
#include <stdint.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#elif defined(__linux__)
#include <sys/mman.h>
#include <unistd.h>
#endif

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
void pi_js_retain_memory_owner(void *opaque) {
    PiMemoryOwner *owner = opaque;
    atomic_fetch_add_explicit(&owner->references, 1, memory_order_relaxed);
}
int pi_js_native_memory_reserve(void *opaque, size_t bytes) {
    return pi_reserve(opaque, bytes);
}
void pi_js_native_memory_release(void *opaque, size_t bytes) {
    PiMemoryOwner *owner = opaque;
    if (atomic_fetch_sub_explicit(&owner->used, bytes, memory_order_relaxed) < bytes) abort();
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


/* Native ArrayBuffer storage. This is the allocation owner, not a JS wrapper
 * lease. Fixed storage is separately allocated; resizable storage reserves a
 * stable maximum virtual range and commits only the current data pages.
 *
 * Authority: Node v24.13.0's V8 BackingStore::{Resize,Grow}InPlace and platform
 * SetPermissions. Shrink clears the exact truncated bytes before decommit;
 * growth changes permissions, not bytes in an already committed partial page.
 * A native I/O write to that retained partial page is therefore not erased by
 * a subsequent grow. There is no delayed-copy buffer or detach/resize lock. */
typedef struct PiArrayBufferBacking PiArrayBufferBacking;
typedef union {
    PiArrayBufferBacking *owner;
    max_align_t alignment;
} PiBackingPrefix;
struct PiArrayBufferBacking {
    _Atomic size_t references;
    _Atomic size_t byte_length;
    _Atomic size_t committed;
    _Atomic int resize_busy;
    PiMemoryOwner *memory;
    uint8_t *data;
    void *allocation;
    size_t allocation_size;
    size_t page_size;
    size_t max_byte_length;
    size_t base_charge;
    unsigned flags;
};
static _Atomic size_t pi_backing_allocations;
static _Atomic size_t pi_shared_allocations;

static int pi_backing_round_pages(size_t size, size_t page, size_t *out) {
    if (!page || size > SIZE_MAX - (page - 1)) return 0;
    *out = ((size + page - 1) / page) * page;
    return 1;
}
static size_t pi_backing_page_size(void) {
#if defined(_WIN32)
    SYSTEM_INFO info;
    GetSystemInfo(&info);
    return info.dwPageSize;
#elif defined(__linux__)
    long page = sysconf(_SC_PAGESIZE);
    return page > 0 ? (size_t)page : 0;
#else
    return 0;
#endif
}
static void *pi_backing_reserve_pages(size_t size) {
#if defined(_WIN32)
    return VirtualAlloc(NULL, size, MEM_RESERVE, PAGE_NOACCESS);
#elif defined(__linux__)
    void *result = mmap(NULL, size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    return result == MAP_FAILED ? NULL : result;
#else
    (void)size;
    return NULL;
#endif
}
static int pi_backing_permissions(void *address, size_t size, int writable) {
    if (!size) return 1;
#if defined(_WIN32)
    if (!writable) return VirtualFree(address, size, MEM_DECOMMIT) != 0;
    return VirtualAlloc(address, size, MEM_COMMIT, PAGE_READWRITE) != NULL;
#elif defined(__linux__)
    if (mprotect(address, size, writable ? PROT_READ | PROT_WRITE : PROT_NONE))
        return 0;
    /* The original POSIX owner discards no-access pages after protection.
       Contents were explicitly zeroed before shrink, including partial pages. */
    if (!writable) (void)madvise(address, size, MADV_DONTNEED);
    return 1;
#else
    (void)address; (void)writable;
    return 0;
#endif
}
static void pi_backing_free_pages(void *address, size_t size) {
#if defined(_WIN32)
    (void)size;
    if (!VirtualFree(address, 0, MEM_RELEASE)) abort();
#elif defined(__linux__)
    if (munmap(address, size)) abort();
#else
    (void)address; (void)size;
    abort();
#endif
}
static void *pi_backing_allocate(void *opaque, size_t length, size_t maximum,
                                 unsigned flags) {
    PiMemoryOwner *memory = opaque;
    const int resizable = (flags & JS_PI_BACKING_RESIZABLE) != 0;
    size_t page = 0, capacity, committed, base_charge, allocation_size;
    void *allocation = NULL;
    uint8_t *data;
    if (length > maximum) return NULL;
    if (resizable) {
        page = pi_backing_page_size();
        if (!pi_backing_round_pages(maximum, page, &capacity) ||
            !pi_backing_round_pages(length, page, &committed))
            return NULL;
        if (!capacity) capacity = page;
        if (capacity > SIZE_MAX - page ||
            sizeof(PiArrayBufferBacking) > SIZE_MAX - page)
            return NULL;
        allocation_size = page + capacity; /* prefix page + stable data range */
        base_charge = sizeof(PiArrayBufferBacking) + page;
    } else {
        capacity = length ? length : 1;
        committed = capacity;
        if (capacity > SIZE_MAX - sizeof(PiBackingPrefix) ||
            sizeof(PiArrayBufferBacking) > SIZE_MAX - sizeof(PiBackingPrefix))
            return NULL;
        allocation_size = sizeof(PiBackingPrefix) + capacity;
        base_charge = sizeof(PiArrayBufferBacking) + sizeof(PiBackingPrefix);
    }
    if (committed > SIZE_MAX - base_charge ||
        !pi_reserve(memory, base_charge + committed))
        return NULL;
    PiArrayBufferBacking *backing = malloc(sizeof(*backing));
    if (!backing) goto fail;
    if (resizable) {
        allocation = pi_backing_reserve_pages(allocation_size);
        if (!allocation) goto fail;
        if (!pi_backing_permissions(allocation, page + committed, 1)) goto fail;
        data = (uint8_t *)allocation + page;
    } else {
        allocation = calloc(1, allocation_size);
        if (!allocation) goto fail;
        data = (uint8_t *)allocation + sizeof(PiBackingPrefix);
    }
    atomic_init(&backing->references, 1);
    atomic_init(&backing->byte_length, length);
    atomic_init(&backing->committed, committed);
    atomic_init(&backing->resize_busy, 0);
    backing->memory = memory;
    backing->data = data;
    backing->allocation = allocation;
    backing->allocation_size = allocation_size;
    backing->page_size = page;
    backing->max_byte_length = maximum;
    backing->base_charge = base_charge;
    backing->flags = flags;
    ((PiBackingPrefix *)data)[-1].owner = backing;
    pi_js_retain_memory_owner(memory);
    atomic_fetch_add_explicit(&pi_backing_allocations, 1, memory_order_relaxed);
    if (flags & JS_PI_BACKING_SHARED)
        atomic_fetch_add_explicit(&pi_shared_allocations, 1, memory_order_relaxed);
    return backing;
fail:
    if (allocation) {
        if (resizable) pi_backing_free_pages(allocation, allocation_size);
        else free(allocation);
    }
    free(backing);
    pi_js_native_memory_release(memory, base_charge + committed);
    return NULL;
}
static uint8_t *pi_backing_data(void *opaque) {
    return ((PiArrayBufferBacking *)opaque)->data;
}
static size_t pi_backing_length(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    return atomic_load_explicit(&backing->byte_length, memory_order_seq_cst);
}
static void pi_backing_retain(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    if (atomic_fetch_add_explicit(&backing->references, 1, memory_order_relaxed) == 0)
        abort();
}
static void pi_backing_release(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    const size_t previous = atomic_fetch_sub_explicit(
        &backing->references, 1, memory_order_acq_rel);
    if (!previous) abort();
    if (previous != 1) return;
    PiMemoryOwner *memory = backing->memory;
    size_t charge = backing->base_charge +
        atomic_load_explicit(&backing->committed, memory_order_relaxed);
    if (backing->flags & JS_PI_BACKING_RESIZABLE)
        pi_backing_free_pages(backing->allocation, backing->allocation_size);
    else
        free(backing->allocation);
    if (backing->flags & JS_PI_BACKING_SHARED)
        atomic_fetch_sub_explicit(&pi_shared_allocations, 1, memory_order_relaxed);
    atomic_fetch_sub_explicit(&pi_backing_allocations, 1, memory_order_relaxed);
    free(backing);
    pi_js_native_memory_release(memory, charge);
    pi_js_release_memory_owner(memory);
}
static int pi_backing_resize(void *opaque, size_t length) {
    PiArrayBufferBacking *backing = opaque;
    if (!(backing->flags & JS_PI_BACKING_RESIZABLE) ||
        length > backing->max_byte_length)
        return -2;
    /* This native-only critical section serializes page/accounting changes.
       No guest code or JS reference is accessed, retained or released here. */
    while (atomic_exchange_explicit(&backing->resize_busy, 1, memory_order_acquire))
        ;
    const size_t old_length = atomic_load_explicit(
        &backing->byte_length, memory_order_seq_cst);
    const size_t old_committed = atomic_load_explicit(
        &backing->committed, memory_order_relaxed);
    size_t committed;
    int result = 0;
    if ((backing->flags & JS_PI_BACKING_SHARED) && length < old_length) {
        result = -2; /* another grow may have won since the caller's check */
        goto done;
    }
    if (length == old_length) goto done;
    if (!pi_backing_round_pages(length, backing->page_size, &committed)) {
        result = -1;
        goto done;
    }
    if (length < old_length) {
        memset(backing->data + length, 0, old_length - length);
        if (committed < old_committed &&
            !pi_backing_permissions(backing->data + committed,
                                     old_committed - committed, 0)) {
            result = -1;
            goto done;
        }
        if (committed < old_committed)
            pi_js_native_memory_release(backing->memory, old_committed - committed);
    } else {
        size_t charge = committed - old_committed;
        if (charge && !pi_reserve(backing->memory, charge)) {
            result = -1;
            goto done;
        }
        if (!pi_backing_permissions(backing->data, committed, 1)) {
            if (charge) pi_js_native_memory_release(backing->memory, charge);
            result = -1;
            goto done;
        }
    }
    atomic_store_explicit(&backing->committed, committed, memory_order_relaxed);
    atomic_store_explicit(&backing->byte_length, length, memory_order_seq_cst);
done:
    atomic_store_explicit(&backing->resize_busy, 0, memory_order_release);
    return result;
}
/* Only trusted same-process serializer tables use this prefix, as before. */
static void *pi_backing_shared_owner(uint8_t *data) {
    PiArrayBufferBacking *backing = ((PiBackingPrefix *)data)[-1].owner;
    if (!(backing->flags & JS_PI_BACKING_SHARED)) abort();
    return backing;
}
static void *pi_shared_alloc(void *opaque, size_t size) {
    PiArrayBufferBacking *backing = pi_backing_allocate(
        opaque, size, size, JS_PI_BACKING_SHARED);
    return backing ? backing->data : NULL;
}
static void pi_shared_dup(void *opaque, void *ptr) {
    (void)opaque;
    pi_backing_retain(pi_backing_shared_owner(ptr));
}
static void pi_shared_free(void *opaque, void *ptr) {
    (void)opaque;
    pi_backing_release(pi_backing_shared_owner(ptr));
}
void pi_js_retain_shared_buffer(void *buffer) { pi_shared_dup(NULL, buffer); }
void pi_js_release_shared_buffer(void *buffer) { pi_shared_free(NULL, buffer); }

/* Native diagnostics inspect the real owner, never a guest wrapper. */
size_t pi_js_array_buffer_backing_allocations(void) {
    return atomic_load_explicit(&pi_backing_allocations, memory_order_relaxed);
}
size_t pi_js_array_buffer_backing_references(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    return atomic_load_explicit(&backing->references, memory_order_acquire);
}
size_t pi_js_array_buffer_backing_byte_length(void *opaque) {
    return pi_backing_length(opaque);
}
size_t pi_js_array_buffer_backing_committed(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    return atomic_load_explicit(&backing->committed, memory_order_acquire);
}
size_t pi_js_array_buffer_backing_reserved(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    return backing->allocation_size;
}
size_t pi_js_array_buffer_backing_page_size(void *opaque) {
    PiArrayBufferBacking *backing = opaque;
    return backing->page_size;
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
#if defined(_WIN32) || defined(__linux__)
    /* Only these admitted page backends activate managed resizable storage.
       Other platforms retain the existing QuickJS allocation path. */
    const JSPiArrayBufferStorageFunctions storage = {
        .allocate = pi_backing_allocate, .shared_owner = pi_backing_shared_owner,
        .data = pi_backing_data, .byte_length = pi_backing_length,
        .resize = pi_backing_resize, .retain = pi_backing_retain,
        .release = pi_backing_release, .opaque = owner,
    };
    JS_PiSetArrayBufferStorageFunctions(runtime, &storage);
#endif
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
JSValue pi_js_exception(void) { return JS_EXCEPTION; }
JSValue pi_js_null(void) { return JS_NULL; }
JSValue pi_js_bool(JSContext *context, int value) { return JS_NewBool(context, value); }
JSValue pi_js_int32(JSContext *context, int32_t value) { return JS_NewInt32(context, value); }
JSModuleDef *pi_js_module(JSValue value) { return JS_VALUE_GET_PTR(value); }
void *pi_js_object_identity(JSValue value) { return JS_VALUE_GET_PTR(value); }
JSValue pi_js_module_value(JSContext *context, JSModuleDef *module) { return JS_DupValue(context, JS_MKPTR(JS_TAG_MODULE, module)); }
JSValue pi_js_function_magic(JSContext *context, JSCFunctionMagic *function, const char *name, int length, int magic) {
    return JS_NewCFunctionMagic(context, function, name, length, JS_CFUNC_generic_magic, magic);
}
