/* REVIEW ONLY. Include after JS_ARRAY_BUFFER_TRANSFER_* declarations.
 * Every allocation, ownership transition and final release is VM-owner-only.
 * Workers may call only Data/Length/Status and never release a lease. */
#include <stdatomic.h>
static _Thread_local unsigned char pi_io_thread;
typedef struct PiIOSABGeneration {
    struct PiIOSABGeneration *next;
    JSRuntime *rt;
    uintptr_t thread;
    uint8_t *data;
    size_t capacity, owners, pins;
} PiIOSABGeneration;
typedef struct PiIOStore PiIOStore;
typedef struct PiIOGeneration {
    PiIOStore *store;
    uint8_t *data;
    size_t logical, capacity, pins;
    JSPiIOLease *leases;
    int owned;
    void *mapping;
    size_t mapping_charge;
    _Atomic size_t accessible_end;
    _Atomic int retired_mapping;
} PiIOGeneration;
struct PiIOStore {
    JSRuntime *rt;
    uintptr_t thread;
    JSPiIOMapHooks hooks;
    PiIOGeneration *current;
    size_t generations;
    int attached;
};
struct JSPiIOLease {
    JSRuntime *rt;
    uintptr_t thread;
    uint8_t *data;
    size_t offset, length;
    PiIOGeneration *generation;
    JSPiIOLease *generation_next;
    JSValue root;
    void *sab_data;
    PiIOSABGeneration *sab_generation;
    void *external_token;
    JSPiIOExternalHooks external;
};
static void *pi_io_realloc(JSRuntime *, void *, void *, size_t);
static void pi_io_owner(uintptr_t thread) {
    /* Keep the invariant in ReleaseSafe builds that define NDEBUG as well. */
    if (thread != (uintptr_t)&pi_io_thread) abort();
}
static size_t pi_io_available(JSRuntime *rt) {
    size_t ceiling = rt->malloc_state.malloc_limit - 1;
    return rt->malloc_state.malloc_size < ceiling ? ceiling - rt->malloc_state.malloc_size : 0;
}
static size_t pi_io_page_end(size_t logical, size_t page) {
    return logical ? (logical + page - 1) / page * page : 0;
}
static void pi_io_sab_collect(PiIOSABGeneration *gen) {
    if (gen->owners || gen->pins) return;
    JSRuntime *rt = gen->rt;
    PiIOSABGeneration **link = &rt->pi_io_sab_generations;
    while (*link && *link != gen) link = &(*link)->next;
    assert(*link == gen); *link = gen->next;
    rt->malloc_state.malloc_size -= gen->capacity;
    rt->malloc_state.malloc_count--;
    js_free_rt(rt, gen);
}
static int pi_io_sab_attach(JSContext *ctx, JSArrayBuffer *abuf) {
    if (abuf->pi_io_sab) return 0;
    JSRuntime *rt = ctx->rt;
    size_t capacity = abuf->max_byte_length >= 0 ? abuf->max_byte_length : abuf->byte_length;
    PiIOSABGeneration *gen;
    for (gen = rt->pi_io_sab_generations; gen; gen = gen->next) {
        if (gen->data != abuf->data) continue;
        if (capacity != gen->capacity) {
            JS_ThrowInternalError(ctx, "SAB generation capacity mismatch"); return -1;
        }
        pi_io_owner(gen->thread);
        gen->owners++; abuf->pi_io_sab = gen; return 0;
    }
    gen = js_mallocz(ctx, sizeof(*gen));
    if (!gen) return -1;
    if (capacity > pi_io_available(rt)) {
        js_free(ctx, gen); JS_ThrowOutOfMemory(ctx); return -1;
    }
    /* The real SAB allocation remains charged to its original PiMemoryOwner
     * through the existing allocator/dup/free hooks. This adds exactly one
     * QJS charge per backing generation in this runtime, not per wrapper/job. */
    rt->malloc_state.malloc_size += capacity;
    rt->malloc_state.malloc_count++;
    *gen = (PiIOSABGeneration){ .next = rt->pi_io_sab_generations, .rt = rt,
        .thread = (uintptr_t)&pi_io_thread, .data = abuf->data,
        .capacity = capacity, .owners = 1 };
    rt->pi_io_sab_generations = gen;
    abuf->pi_io_sab = gen;
    return 0;
}
static void pi_io_sab_detach(JSRuntime *rt, JSArrayBuffer *abuf) {
    PiIOSABGeneration *gen = abuf->pi_io_sab;
    if (!gen) return;
    pi_io_owner(gen->thread); assert(gen->rt == rt && gen->owners);
    abuf->pi_io_sab = NULL; gen->owners--; pi_io_sab_collect(gen);
}
int JS_PiEnableSABIOAccounting(JSContext *ctx) {
    JSRuntime *rt = ctx->rt;
    if (rt->pi_io_sab_enabled) return 0;
    struct list_head *el;
    list_for_each(el, &rt->gc_obj_list) {
        JSGCObjectHeader *header = list_entry(el, JSGCObjectHeader, link);
        if (JS_GC_TYPE(header) != JS_GC_OBJ_TYPE_JS_OBJECT) continue;
        JSObject *obj = (JSObject *)header;
        if (obj->class_id != JS_CLASS_SHARED_ARRAY_BUFFER || !obj->u.array_buffer) continue;
        if (pi_io_sab_attach(ctx, obj->u.array_buffer)) goto rollback;
    }
    rt->pi_io_sab_enabled = 1;
    return 0;
rollback:
    /* No SAB lease can exist while accounting is disabled. Remove every
     * attachment made by this attempt, preserving actual JS/SAB ownership. */
    list_for_each(el, &rt->gc_obj_list) {
        JSGCObjectHeader *header = list_entry(el, JSGCObjectHeader, link);
        if (JS_GC_TYPE(header) != JS_GC_OBJ_TYPE_JS_OBJECT) continue;
        JSObject *obj = (JSObject *)header;
        if (obj->class_id == JS_CLASS_SHARED_ARRAY_BUFFER && obj->u.array_buffer)
            pi_io_sab_detach(rt, obj->u.array_buffer);
    }
    assert(!rt->pi_io_sab_generations);
    return -1;
}
size_t JS_PiSABIOChargedBytes(JSRuntime *rt) {
    size_t bytes = 0;
    for (PiIOSABGeneration *gen = rt->pi_io_sab_generations; gen; gen = gen->next) bytes += gen->capacity;
    return bytes;
}
size_t JS_PiSABIOGenerations(JSRuntime *rt) {
    size_t count = 0;
    for (PiIOSABGeneration *gen = rt->pi_io_sab_generations; gen; gen = gen->next) count++;
    return count;
}
static void pi_io_store_collect(PiIOStore *store) {
    if (!store->attached && !store->generations) js_free_rt(store->rt, store);
}
static void pi_io_generation_collect(PiIOGeneration *gen) {
    if (gen->owned || gen->pins) return;
    PiIOStore *store = gen->store;
    if (gen->mapping) {
        /* Remains charged in BOTH budgets until the last allocation owner. */
        store->rt->malloc_state.malloc_size -= gen->mapping_charge;
        store->rt->pi_io_mapping_charge -= gen->mapping_charge;
        store->rt->malloc_state.malloc_count--;
        store->hooks.release(store->hooks.opaque, gen->mapping);
    } else js_free_rt(store->rt, gen->data);
    store->generations--;
    store->rt->pi_io_owned_generations--;
    js_free_rt(store->rt, gen);
    pi_io_store_collect(store);
}
static void pi_io_generation_trim(PiIOGeneration *gen) {
    if (!gen->mapping) return;
    PiIOStore *store = gen->store;
    pi_io_owner(store->thread);
    size_t retained = gen->owned ? gen->logical : 0;
    for (JSPiIOLease *lease = gen->leases; lease; lease = lease->generation_next) {
        size_t end = lease->offset + lease->length;
        if (end > retained) retained = end;
    }
    size_t charge;
    if (!store->hooks.trim(store->hooks.opaque, gen->mapping, retained, &charge)) return;
    assert(charge <= gen->mapping_charge);
    store->rt->malloc_state.malloc_size -= gen->mapping_charge - charge;
    store->rt->pi_io_mapping_charge -= gen->mapping_charge - charge;
    gen->mapping_charge = charge;
}
static PiIOGeneration *pi_io_generation(JSRuntime *rt, PiIOStore *store,
                                        size_t length, int maximum) {
    PiIOGeneration *gen = js_mallocz_rt(rt, sizeof(*gen));
    if (!gen) return NULL;
    gen->store = store; gen->logical = length; gen->owned = 1;
    if (maximum >= 0) {
        if (!store->hooks.create || !store->hooks.grow || !store->hooks.trim || !store->hooks.release ||
            !store->hooks.allocation_unit || !store->hooks.commit_page_size) goto fail;
        gen->mapping = store->hooks.create(store->hooks.opaque, maximum, length,
              pi_io_available(rt), (void **)&gen->data, &gen->mapping_charge);
        if (!gen->mapping) goto fail;
        rt->malloc_state.malloc_size += gen->mapping_charge;
        rt->pi_io_mapping_charge += gen->mapping_charge;
        rt->malloc_state.malloc_count++;
        gen->capacity = maximum;
        atomic_init(&gen->accessible_end, pi_io_page_end(length, store->hooks.allocation_unit));
    } else {
        gen->capacity = length ? length : 1;
        gen->data = js_mallocz_rt(rt, gen->capacity);
        if (!gen->data) goto fail;
        atomic_init(&gen->accessible_end, length);
    }
    atomic_init(&gen->retired_mapping, 0);
    store->generations++;
    rt->pi_io_owned_generations++;
    return gen;
fail:
    js_free_rt(rt, gen); return NULL;
}
static void *pi_io_realloc(JSRuntime *rt, void *opaque, void *ptr, size_t size) {
    PiIOStore *store = opaque;
    pi_io_owner(store->thread);
    PiIOGeneration *old = store->current;
    assert(rt == store->rt && old->data == ptr && store->attached);
    if (!size) {
        store->attached = 0; store->current = NULL; old->owned = 0;
        if (old->pins) pi_io_generation_trim(old);
        pi_io_generation_collect(old);
        return NULL;
    }
    /* Resize/transfer use their private notifications below. An unexpected
     * new callback route must fail without invalidating any admitted span. */
    return NULL;
}
static int pi_io_resize(JSContext *ctx, JSArrayBuffer *abuf, size_t length) {
    PiIOStore *store = abuf->opaque;
    PiIOGeneration *gen = store->current;
    pi_io_owner(store->thread);
    assert(gen->mapping && length <= gen->capacity);
    size_t charge;
    if (!store->hooks.grow(store->hooks.opaque, gen->mapping, length,
                           pi_io_available(ctx->rt), &charge)) return -1;
    assert(charge >= gen->mapping_charge);
    ctx->rt->malloc_state.malloc_size += charge - gen->mapping_charge;
    ctx->rt->pi_io_mapping_charge += charge - gen->mapping_charge;
    gen->mapping_charge = charge;
    /* Logical shrink erases truncated bytes. Pages covered by live native
     * spans stay committed and charged; only the unleased tail is decommitted. */
    if (length < gen->logical) memset(gen->data + length, 0, gen->logical - length);
    else if (length > gen->logical) memset(gen->data + gen->logical, 0, length - gen->logical);
    gen->logical = length;
    atomic_store_explicit(&gen->accessible_end,
          pi_io_page_end(length, store->hooks.allocation_unit), memory_order_release);
    abuf->data = gen->data; abuf->byte_length = length;
    pi_io_generation_trim(gen);
    return 0;
}
static JSValue pi_io_transfer(JSContext *ctx, JSArrayBuffer *abuf,
                              uint64_t length, uint64_t *maximum, int magic) {
    PiIOStore *store = abuf->opaque;
    PiIOGeneration *old = store->current, *next = old;
    pi_io_owner(store->thread);
    /* V8 reuses backing storage only for equal-length fixed-to-fixed moves.
     * A resizable source copies even when transfer() preserves both lengths;
     * pending native I/O still owns the old reservation, not the recipient.
     * Prepare the complete copy before publishing any ownership transition. */
    if (length != old->logical || old->mapping ||
        magic == JS_ARRAY_BUFFER_TRANSFER_TO_IMMUTABLE) {
        next = pi_io_generation(ctx->rt, store, length, maximum ? (int)*maximum : -1);
        if (!next) return JS_ThrowOutOfMemory(ctx);
        size_t copied = length < old->logical ? (size_t)length : old->logical;
        memcpy(next->data, old->data, copied);
    }
    abuf->data = NULL; abuf->byte_length = 0; abuf->detached = true;
    abuf->realloc_func = NULL; abuf->opaque = NULL;
    js_array_buffer_update_typed_arrays(abuf);
    if (next != old) {
        store->current = next; old->owned = 0;
        /* Retain mapped pages physically, but reject an old native span whose
         * backing reservation Node made inaccessible during this transition.
         * Fixed heap generations remain valid independently of the recipient. */
        if (old->mapping) atomic_store_explicit(&old->retired_mapping, 1, memory_order_release);
        if (old->pins) pi_io_generation_trim(old);
        pi_io_generation_collect(old);
    }
    JSValue result = js_array_buffer_constructor3(ctx, JS_UNDEFINED, length,
          maximum, JS_CLASS_ARRAY_BUFFER, next->data, pi_io_realloc, store, false);
    if (JS_IsException(result)) {
        ctx->rt->pi_io_transfer_cleanups++;
        /* constructor3 has NOT taken supplied backing ownership on failure. */
        pi_io_realloc(ctx->rt, store, next->data, 0);
        return result;
    }
    if (magic == JS_ARRAY_BUFFER_TRANSFER_TO_IMMUTABLE)
        ((JSArrayBuffer *)JS_GetOpaque(result, JS_CLASS_ARRAY_BUFFER))->immutable = true;
    return result;
}
static int pi_io_validate(JSContext *ctx, JSValueConst backing, size_t offset,
                           size_t length, int destination, JSArrayBuffer **out) {
    JSArrayBuffer *abuf = js_get_array_buffer(ctx, backing);
    if (!abuf) return -1;
    if (abuf->detached) { JS_ThrowTypeErrorDetachedArrayBuffer(ctx); return -1; }
    if (destination && abuf->immutable) { JS_ThrowTypeErrorImmutableArrayBuffer(ctx); return -1; }
    if (offset > (size_t)abuf->byte_length || length > (size_t)abuf->byte_length - offset) {
        JS_ThrowRangeError(ctx, "invalid admitted I/O span"); return -1;
    }
    *out = abuf; return 0;
}
static JSPiIOLease *pi_io_lease_new(JSContext *ctx, size_t offset, size_t length) {
    JSPiIOLease *lease = js_mallocz(ctx, sizeof(*lease));
    if (!lease) return NULL;
    lease->rt = ctx->rt; lease->thread = (uintptr_t)&pi_io_thread;
    lease->offset = offset; lease->length = length; lease->root = JS_UNDEFINED;
    return lease;
}
int JS_PiAcquireIOLease(JSContext *ctx, JSValueConst backing, size_t offset,
                        size_t length, int destination, const JSPiIOMapHooks *hooks,
                        JSPiIOLease **out) {
    JSArrayBuffer *abuf;
    *out = NULL;
    if (pi_io_validate(ctx, backing, offset, length, destination, &abuf)) return -1;
    JSPiIOLease *lease = pi_io_lease_new(ctx, offset, length);
    if (!lease) return -1;
    if (abuf->shared) {
        if (!ctx->rt->pi_io_sab_enabled || !abuf->pi_io_sab) {
            JS_ThrowTypeError(ctx, "private SAB I/O policy is inactive"); goto fail;
        }
        /* Pin through the runtime's actual SAB contract, never assume that
         * arbitrary external pointers carry a PiSharedBuffer header. */
        if (ctx->rt->sab_funcs.sab_dup && !ctx->rt->sab_funcs.sab_free) {
            JS_ThrowTypeError(ctx, "incomplete SAB ownership hooks"); goto fail;
        }
        lease->root = JS_DupValue(ctx, backing);
        lease->sab_generation = abuf->pi_io_sab;
        lease->sab_generation->pins++;
        if (ctx->rt->sab_funcs.sab_dup) {
            assert(ctx->rt->sab_funcs.sab_free);
            ctx->rt->sab_funcs.sab_dup(ctx->rt->sab_funcs.sab_opaque, abuf->data);
            lease->sab_data = abuf->data;
        }
        lease->data = abuf->data + offset;
    } else {
        PiIOStore *store;
        if (abuf->realloc_func == pi_io_realloc) {
            store = abuf->opaque; pi_io_owner(store->thread);
        } else if (abuf->realloc_func == js_array_buffer_realloc) {
            store = js_mallocz(ctx, sizeof(*store));
            if (!store) goto fail;
            store->rt = ctx->rt; store->thread = lease->thread; store->attached = 1;
            if (hooks) store->hooks = *hooks;
            PiIOGeneration *gen;
            if (abuf->max_byte_length >= 0) {
                gen = pi_io_generation(ctx->rt, store, abuf->byte_length, abuf->max_byte_length);
                if (!gen) { js_free(ctx, store); JS_ThrowOutOfMemory(ctx); goto fail; }
                memcpy(gen->data, abuf->data, abuf->byte_length);
            } else {
                /* Adopt the original QuickJS allocation, with no pointer
                 * header casts and no transient duplicate of a fixed buffer. */
                gen = js_mallocz(ctx, sizeof(*gen));
                if (!gen) { js_free(ctx, store); goto fail; }
                gen->store = store; gen->data = abuf->data;
                gen->logical = gen->capacity = abuf->byte_length; gen->owned = 1;
                atomic_init(&gen->accessible_end, abuf->byte_length);
                atomic_init(&gen->retired_mapping, 0); store->generations = 1;
                ctx->rt->pi_io_owned_generations++;
            }
            store->current = gen;
            /* No failure after publishing any replacement. */
            if (gen->mapping) js_free_rt(ctx->rt, abuf->data);
            abuf->data = gen->data; abuf->realloc_func = pi_io_realloc; abuf->opaque = store;
            js_array_buffer_update_typed_arrays(abuf);
        } else {
            JS_ThrowTypeError(ctx, "external backing requires an explicit I/O provider"); goto fail;
        }
        lease->generation = store->current;
        lease->generation->pins++;
        lease->generation_next = lease->generation->leases;
        lease->generation->leases = lease;
        lease->data = lease->generation->data + offset;
    }
    *out = lease; return 0;
fail:
    js_free(ctx, lease); return -1;
}
int JS_PiAcquireExternalIOLease(JSContext *ctx, JSValueConst backing, size_t offset,
                                size_t length, int destination,
                                const JSPiIOExternalHooks *hooks, void *opaque,
                                JSPiIOLease **out) {
    JSArrayBuffer *abuf;
    *out = NULL;
    if (pi_io_validate(ctx, backing, offset, length, destination, &abuf)) return -1;
    if (!hooks || !hooks->pin || !hooks->status || !hooks->release) {
        JS_ThrowTypeError(ctx, "incomplete external I/O provider"); return -1;
    }
    JSPiIOLease *lease = pi_io_lease_new(ctx, offset, length);
    if (!lease) return -1;
    lease->external = *hooks;
    lease->external_token = hooks->pin(ctx, opaque, backing, offset, length, destination, &lease->data);
    if (!lease->external_token) {
        if (!JS_HasException(ctx)) JS_ThrowInternalError(ctx, "external I/O provider failed without an exception");
        js_free(ctx, lease); return -1;
    }
    if (length && !lease->data) {
        hooks->release(ctx->rt, lease->external_token);
        js_free(ctx, lease);
        JS_ThrowInternalError(ctx, "external I/O provider returned an empty live span"); return -1;
    }
    lease->root = JS_DupValue(ctx, backing);
    *out = lease; return 0;
}
uint8_t *JS_PiIOLeaseData(const JSPiIOLease *lease) { return lease->data; }
size_t JS_PiIOLeaseLength(const JSPiIOLease *lease) { return lease->length; }
size_t JS_PiIOOwnedGenerations(JSRuntime *rt) { return rt->pi_io_owned_generations; }
size_t JS_PiIOMappingCharge(JSRuntime *rt) { return rt->pi_io_mapping_charge; }
size_t JS_PiIOTransferCleanups(JSRuntime *rt) { return rt->pi_io_transfer_cleanups; }
void JS_PiIOLeaseStatus(const JSPiIOLease *lease, JSPiIOOperation operation,
                        size_t vector_index, JSPiIOStatus *out) {
    *out = (JSPiIOStatus){ .reason = JS_PI_IO_READY, .operation = operation,
        .vector_index = vector_index, .offset = lease->offset,
        .length = lease->length, .available = lease->length };
    if (lease->external_token) {
        lease->external.status(lease->external_token, operation, vector_index, out);
        if (out->available > lease->length || out->operation != operation ||
            out->vector_index != vector_index || out->offset != lease->offset ||
            out->length != lease->length || out->reason > JS_PI_IO_EXTERNAL_PROTOCOL ||
            (out->reason == JS_PI_IO_READY && out->available != lease->length)) {
            *out = (JSPiIOStatus){ .reason = JS_PI_IO_EXTERNAL_PROTOCOL,
                .operation = operation, .vector_index = vector_index,
                .offset = lease->offset, .length = lease->length };
        }
        return;
    }
    PiIOGeneration *gen = lease->generation;
    if (!gen || !gen->mapping || !lease->length) return;
    if (atomic_load_explicit(&gen->retired_mapping, memory_order_acquire)) {
        out->reason = JS_PI_IO_RETIRED_MAPPING; out->available = 0; return;
    }
    size_t end = atomic_load_explicit(&gen->accessible_end, memory_order_acquire);
    size_t available = lease->offset < end ? end - lease->offset : 0;
    if (available < lease->length) {
        out->reason = JS_PI_IO_PAGE_BOUNDARY; out->available = available;
    }
}
void JS_PiReleaseIOLease(JSRuntime *rt, JSPiIOLease *lease) {
    if (!lease) return;
    pi_io_owner(lease->thread); assert(rt == lease->rt);
    if (lease->external_token) lease->external.release(rt, lease->external_token);
    if (lease->sab_data) rt->sab_funcs.sab_free(rt->sab_funcs.sab_opaque, lease->sab_data);
    if (lease->sab_generation) {
        PiIOSABGeneration *gen = lease->sab_generation;
        assert(gen->pins); gen->pins--; pi_io_sab_collect(gen);
    }
    JS_FreeValueRT(rt, lease->root);
    if (lease->generation) {
        PiIOGeneration *gen = lease->generation;
        JSPiIOLease **link = &gen->leases;
        while (*link && *link != lease) link = &(*link)->generation_next;
        assert(*link == lease && gen->pins);
        *link = lease->generation_next;
        gen->pins--;
        if (gen->owned || gen->pins) pi_io_generation_trim(gen);
        pi_io_generation_collect(gen);
    }
    js_free_rt(rt, lease);
}
