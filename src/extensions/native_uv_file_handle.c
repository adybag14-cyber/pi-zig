/* Direct C interoperability with the admitted, unchanged Node v24.13 libuv.
 * Source authority: node_file.cc OpenFileHandle/Read/FileHandle::ClosePromise,
 * AfterClose and destructor. The caller owns JS validation and async jobs.
 */
#include "native_uv_file_handle.h"
#include "engine_abi.h"
#include "uv.h"
#include <stdatomic.h>
#include <stdlib.h>

struct PiUvFileHandle {
    atomic_uint references;
    atomic_int physical_descriptor;
    atomic_int published_descriptor;
    atomic_int closing;
    void *memory_owner;
};
static atomic_size_t live_handles;

static int close_descriptor(int descriptor) {
    uv_fs_t request = {0};
    const int status = uv_fs_close(NULL, &request, descriptor, NULL);
    uv_fs_req_cleanup(&request);
    return status;
}

PiUvFileOpenResult pi_uv_file_open(void *memory_owner, const char *path,
                                  int flags, int mode) {
    PiUvFileOpenResult result = {NULL, 0, 0, 0};
    uv_fs_t request = {0};
    const int descriptor = uv_fs_open(NULL, &request, path, flags, mode, NULL);
    uv_fs_req_cleanup(&request);
    if (descriptor < 0) {
        result.uv_status = descriptor;
        return result;
    }

    /* This is the actual handle allocation after a successful open, not a
     * synthetic failure inferred from an earlier guest operation. */
    if (!pi_js_native_memory_reserve(memory_owner, sizeof(PiUvFileHandle))) {
        result.native_allocation_failure = 1;
        result.rollback_close_status = close_descriptor(descriptor);
        return result;
    }
    PiUvFileHandle *handle = calloc(1, sizeof(*handle));
    if (!handle) {
        pi_js_native_memory_release(memory_owner, sizeof(PiUvFileHandle));
        result.native_allocation_failure = 1;
        result.rollback_close_status = close_descriptor(descriptor);
        return result;
    }
    pi_js_retain_memory_owner(memory_owner);
    handle->memory_owner = memory_owner;
    atomic_init(&handle->references, 1);
    atomic_init(&handle->physical_descriptor, descriptor);
    atomic_init(&handle->published_descriptor, descriptor);
    atomic_init(&handle->closing, 0);
    atomic_fetch_add_explicit(&live_handles, 1, memory_order_relaxed);
    result.handle = handle;
    return result;
}

PiUvFileReadResult pi_uv_file_read(int descriptor, uint8_t *buffer,
                                  uint32_t length, int64_t position) {
    PiUvFileReadResult result = {0, 0};
    uv_fs_t request = {0};
    uv_buf_t data = uv_buf_init((char *)buffer, length);
    const int status = uv_fs_read(NULL, &request, descriptor, &data, 1,
                                  position, NULL);
    if (status < 0) {
        result.uv_status = status;
    } else {
        result.bytes_read = (int64_t)request.result;
    }
    uv_fs_req_cleanup(&request);
    return result;
}

void pi_uv_file_retain(PiUvFileHandle *handle) {
    atomic_fetch_add_explicit(&handle->references, 1, memory_order_relaxed);
}

PiUvFileReleaseResult pi_uv_file_release(PiUvFileHandle *handle) {
    PiUvFileReleaseResult result = {0, -1, 0};
    if (!handle ||
        atomic_fetch_sub_explicit(&handle->references, 1,
                                  memory_order_acq_rel) != 1)
        return result;

    /* Close tickets retain the owner until work has stopped. Exchanging the
     * physical descriptor prevents a completed but not-yet-published close
     * from closing a subsequently reused descriptor during abandonment. */
    const int descriptor = atomic_exchange_explicit(
        &handle->physical_descriptor, -1, memory_order_acq_rel);
    if (descriptor >= 0) {
        result.closed_by_release = 1;
        result.descriptor = descriptor;
        result.uv_status = close_descriptor(descriptor);
    }
    void *memory_owner = handle->memory_owner;
    free(handle);
    atomic_fetch_sub_explicit(&live_handles, 1, memory_order_relaxed);
    pi_js_native_memory_release(memory_owner, sizeof(PiUvFileHandle));
    pi_js_release_memory_owner(memory_owner);
    return result;
}

int pi_uv_file_descriptor(const PiUvFileHandle *handle) {
    return atomic_load_explicit(&handle->published_descriptor,
                                memory_order_acquire);
}

int pi_uv_file_begin_close(PiUvFileHandle *handle) {
    if (pi_uv_file_descriptor(handle) < 0)
        return 0;
    int expected = 0;
    return atomic_compare_exchange_strong_explicit(
        &handle->closing, &expected, 1, memory_order_acq_rel,
        memory_order_acquire);
}

int pi_uv_file_close_work(PiUvFileHandle *handle) {
    const int descriptor = atomic_exchange_explicit(
        &handle->physical_descriptor, -1, memory_order_acq_rel);
    if (descriptor < 0)
        return UV_EBADF;
    return close_descriptor(descriptor);
}

void pi_uv_file_finish_close(PiUvFileHandle *handle) {
    atomic_store_explicit(&handle->published_descriptor, -1,
                          memory_order_release);
    atomic_store_explicit(&handle->closing, 0, memory_order_release);
}

size_t pi_uv_file_live_handles(void) {
    return atomic_load_explicit(&live_handles, memory_order_acquire);
}
