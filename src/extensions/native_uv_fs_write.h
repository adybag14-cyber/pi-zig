/* Borrowed-descriptor write operations over the admitted Node libuv graph. */
#ifndef PI_NATIVE_UV_FS_WRITE_H
#define PI_NATIVE_UV_FS_WRITE_H
#include <stddef.h>
#include <stdint.h>
#include "native_uv_file_handle.h"
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int64_t bytes_written;
    int uv_status;
} PiUvFileWriteResult;

/* These flags are the actual host O_* macros used by uv_fs_open. */
int pi_uv_fs_write_open_flags(int append, int exclusive);
/* The caller retains its native file entitlement and stable byte storage until
 * the synchronous libuv request returns. No descriptor ownership is acquired. */
PiUvFileWriteResult pi_uv_fs_write(int descriptor, const uint8_t *bytes,
                                  size_t length, int64_t position);
int pi_uv_fs_fsync(int descriptor);

#ifdef __cplusplus
}
#endif
#endif
