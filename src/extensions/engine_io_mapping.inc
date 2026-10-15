/* REVIEW ONLY: included after pi_reserve in engine_abi.c. No default activation.
 * Raw mappings never enter the arena allocator or assume PiAllocation headers. */
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <sys/mman.h>
#include <unistd.h>
#endif

typedef struct {
    PiMemoryOwner *owner;
    void *data;
    size_t reservation, committed, charge, allocation_unit, commit_page;
} PiIOMapping;

static int pi_io_round(size_t value, size_t alignment, size_t *out) {
    if (value > SIZE_MAX - (alignment - 1)) return 0;
    *out = (value + alignment - 1) / alignment * alignment;
    return 1;
}
static size_t pi_io_page(void) {
#if defined(_WIN32)
    SYSTEM_INFO info; GetSystemInfo(&info); return info.dwPageSize;
#else
    long page = sysconf(_SC_PAGESIZE); return page > 0 ? (size_t)page : 0;
#endif
}
static size_t pi_io_allocation_unit(void) {
#if defined(_WIN32)
    SYSTEM_INFO info; GetSystemInfo(&info); return info.dwAllocationGranularity;
#else
    return pi_io_page();
#endif
}
static int pi_io_reserve_virtual(PiMemoryOwner *owner, size_t bytes) {
    size_t used = atomic_load_explicit(&owner->virtual_used, memory_order_relaxed);
    do {
        if (!owner->virtual_limit || bytes > owner->virtual_limit ||
            used > owner->virtual_limit - bytes) return 0;
    } while (!atomic_compare_exchange_weak_explicit(&owner->virtual_used,
              &used, used + bytes, memory_order_relaxed, memory_order_relaxed));
    return 1;
}
static void pi_io_unmap(PiIOMapping *map) {
#if defined(_WIN32)
    if (!VirtualFree(map->data, 0, MEM_RELEASE)) abort();
#else
    if (munmap(map->data, map->reservation)) abort();
#endif
}
static int pi_io_commit_pages(PiIOMapping *map, size_t end) {
    if (end <= map->committed) return 1;
#if defined(_WIN32)
    return VirtualAlloc((unsigned char *)map->data + map->committed,
                        end - map->committed, MEM_COMMIT, PAGE_READWRITE) != NULL;
#else
    return mprotect((unsigned char *)map->data + map->committed,
                    end - map->committed, PROT_READ | PROT_WRITE) == 0;
#endif
}
/* qjs_available is the independent QuickJS budget available NOW, not an
 * increased JS_SetMemoryLimit. The caller accounts the returned exact charge. */
static void *pi_io_map_create(void *opaque, size_t maximum, size_t initial,
                              size_t qjs_available, void **data,
                              size_t *charge) {
    PiMemoryOwner *owner = opaque;
    size_t page = pi_io_page(), reservation, committed, granularity = pi_io_allocation_unit();
    if (!page || !granularity || granularity % page || initial > maximum) return NULL;
    if (!pi_io_round(maximum ? maximum : 1, granularity, &reservation) ||
        !pi_io_round(initial, granularity, &committed) ||
        committed > SIZE_MAX - sizeof(PiIOMapping)) return NULL;
    size_t total = committed + sizeof(PiIOMapping);
    if (total > qjs_available || !pi_io_reserve_virtual(owner, reservation)) return NULL;
    if (!pi_reserve(owner, total)) goto fail_virtual;
    PiIOMapping *map = malloc(sizeof(*map));
    if (!map) goto fail_charge;
    *map = (PiIOMapping){ .owner = owner, .reservation = reservation,
                         .charge = total, .allocation_unit = granularity, .commit_page = page };
#if defined(_WIN32)
    map->data = VirtualAlloc(NULL, reservation, MEM_RESERVE, PAGE_NOACCESS);
#else
    map->data = mmap(NULL, reservation, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (map->data == MAP_FAILED) map->data = NULL;
#endif
    if (!map->data) { free(map); goto fail_charge; }
    if (!pi_io_commit_pages(map, committed)) { pi_io_unmap(map); free(map); goto fail_charge; }
    map->committed = committed;
    atomic_fetch_add_explicit(&owner->references, 1, memory_order_relaxed);
    *data = map->data; *charge = total;
    return map;
fail_charge:
    atomic_fetch_sub_explicit(&owner->used, total, memory_order_relaxed);
fail_virtual:
    atomic_fetch_sub_explicit(&owner->virtual_used, reservation, memory_order_relaxed);
    return NULL;
}
static int pi_io_map_grow(void *opaque, void *handle, size_t logical,
                          size_t qjs_available, size_t *charge) {
    (void)opaque;
    PiIOMapping *map = handle;
    size_t end;
    if (!pi_io_round(logical, map->allocation_unit, &end) ||
        end > map->reservation) return 0;
    if (end <= map->committed) { *charge = map->charge; return 1; }
    size_t delta = end - map->committed;
    if (delta > qjs_available || !pi_reserve(map->owner, delta)) return 0;
    if (!pi_io_commit_pages(map, end)) {
        atomic_fetch_sub_explicit(&map->owner->used, delta, memory_order_relaxed);
        return 0;
    }
    map->committed = end; map->charge += delta; *charge = map->charge;
    return 1;
}
/* VM owner only, after calculating the maximum end of every live lease.
 * A failure leaves the physical charge intact; no leased page is decommitted. */
static int pi_io_map_trim(void *opaque, void *handle, size_t retained_end,
                          size_t *charge) {
    (void)opaque;
    PiIOMapping *map = handle;
    size_t keep;
    if (!pi_io_round(retained_end, map->allocation_unit, &keep) || keep > map->committed) return 0;
    if (keep % map->commit_page || map->committed % map->commit_page) abort();
    if (keep == map->committed) { *charge = map->charge; return 1; }
    unsigned char *tail = (unsigned char *)map->data + keep;
    size_t removed = map->committed - keep;
#if defined(_WIN32)
    if (!VirtualFree(tail, removed, MEM_DECOMMIT)) return 0;
#else
    if (mprotect(tail, removed, PROT_NONE)) return 0;
    if (madvise(tail, removed, MADV_DONTNEED)) {
        if (mprotect(tail, removed, PROT_READ | PROT_WRITE)) abort();
        return 0;
    }
#endif
    map->committed = keep; map->charge -= removed;
    atomic_fetch_sub_explicit(&map->owner->used, removed, memory_order_relaxed);
    *charge = map->charge;
    return 1;
}
static void pi_io_map_release(void *opaque, void *handle) {
    (void)opaque;
    PiIOMapping *map = handle;
    PiMemoryOwner *owner = map->owner;
    pi_io_unmap(map);
    atomic_fetch_sub_explicit(&owner->used, map->charge, memory_order_relaxed);
    atomic_fetch_sub_explicit(&owner->virtual_used, map->reservation, memory_order_relaxed);
    free(map);
    pi_js_release_memory_owner(owner);
}
/* Configure once on the VM owner. A later caller cannot silently raise the
 * aggregate virtual reservation cap. There is deliberately no default cap. */
int pi_js_io_map_hooks(void *opaque, size_t virtual_limit, JSPiIOMapHooks *out) {
    PiMemoryOwner *owner = opaque;
    if (!virtual_limit || (owner->virtual_limit && owner->virtual_limit != virtual_limit)) return -1;
    owner->virtual_limit = virtual_limit;
    *out = (JSPiIOMapHooks){ .opaque = owner,
        .allocation_unit = pi_io_allocation_unit(), .commit_page_size = pi_io_page(),
        .create = pi_io_map_create, .grow = pi_io_map_grow,
        .trim = pi_io_map_trim, .release = pi_io_map_release };
    return out->allocation_unit && out->commit_page_size ? 0 : -1;
}
size_t pi_js_native_virtual_reserved(void *opaque) {
    PiMemoryOwner *owner = opaque;
    return atomic_load_explicit(&owner->virtual_used, memory_order_relaxed);
}
