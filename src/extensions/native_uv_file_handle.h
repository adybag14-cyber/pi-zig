/* Direct Node v24.13.0 libuv file operations. No JavaScript enters this ABI. */
#ifndef PI_NATIVE_UV_FILE_HANDLE_H
#define PI_NATIVE_UV_FILE_HANDLE_H
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct PiUvFileHandle PiUvFileHandle;

/* The caller retains its actual native memory owner throughout open().
 * uv_status is a genuine libuv result; native_allocation_failure describes
 * only this wrapper's independently charged handle allocation. */
typedef struct {
    PiUvFileHandle *handle;
    int uv_status;
    int native_allocation_failure;
    int rollback_close_status;
} PiUvFileOpenResult;

typedef struct {
    int64_t bytes_read;
    int uv_status;
} PiUvFileReadResult;

/* Last-owner cleanup mirrors the native FileHandle destructor's synchronous
 * close. The VM owner uses this report for the separate Source warning path;
 * this native layer never calls a logger, Promise, or JavaScript callback. */
typedef struct {
    int closed_by_release;
    int descriptor;
    int uv_status;
} PiUvFileReleaseResult;

/* These synchronous physical operations run in the actual Env I/O worker.
 * The already validated, namespaced path remains borrowed until return. */
PiUvFileOpenResult pi_uv_file_open(void *memory_owner, const char *path,
                                  int flags, int mode);
/* buffer is borrowed stable native storage for the entire call. A VM object
 * root alone is not a backing-storage lease; callers must provide the actual
 * native lease before scheduling a read. No copy-back staging occurs here. */
PiUvFileReadResult pi_uv_file_read(int descriptor, uint8_t *buffer,
                                  uint32_t length, int64_t position);

/* Each in-flight close ticket and each published native owner holds one
 * reference. The descriptor's physical state is independent of the Engine. */
void pi_uv_file_retain(PiUvFileHandle *handle);
PiUvFileReleaseResult pi_uv_file_release(PiUvFileHandle *handle);
int pi_uv_file_descriptor(const PiUvFileHandle *handle);
int pi_uv_file_begin_close(PiUvFileHandle *handle);
int pi_uv_file_close_work(PiUvFileHandle *handle);
/* Owner-thread completion publishes fd=-1 after the real physical close,
 * preserving the native object's observable descriptor until that callback. */
void pi_uv_file_finish_close(PiUvFileHandle *handle);

/* Native ownership controls only; no public module exports these counters. */
size_t pi_uv_file_live_handles(void);

#ifdef __cplusplus
}
#endif
#endif
