/* Genuine libuv filesystem calls; no VM, Engine, JS values or callbacks.
 * The existing FileHandle owner supplies the sole physical CRT fd ownership.
 */
#include "native_uv_fs_write.h"
#include "uv.h"
#include <fcntl.h>
#include <limits.h>

int pi_uv_fs_write_open_flags(int append, int exclusive) {
    return O_WRONLY | O_CREAT | (append ? O_APPEND : O_TRUNC) |
           (exclusive ? O_EXCL : 0);
}

PiUvFileWriteResult pi_uv_fs_write(int descriptor, const uint8_t *bytes,
                                  size_t length, int64_t position) {
    PiUvFileWriteResult result = {0, 0};
    uv_fs_t request = {0};
    /* uv_buf_init takes unsigned int, but synchronous uv_fs_write returns int.
     * Bound success to INT_MAX and return a real partial write for larger
     * spans; Source WriteStream owns the remaining suffix retries. */
    unsigned int count = length > INT_MAX ? INT_MAX : (unsigned int)length;
    uv_buf_t data = uv_buf_init((char *)bytes, count);
    int status = uv_fs_write(NULL, &request, descriptor, &data, 1,
                             position, NULL);
    if (status < 0)
        result.uv_status = status;
    else
        result.bytes_written = (int64_t)request.result;
    uv_fs_req_cleanup(&request);
    return result;
}

int pi_uv_fs_fsync(int descriptor) {
    uv_fs_t request = {0};
    int status = uv_fs_fsync(NULL, &request, descriptor, NULL);
    uv_fs_req_cleanup(&request);
    return status;
}
