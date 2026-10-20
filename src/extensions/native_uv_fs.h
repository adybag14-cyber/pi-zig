/* Typed real filesystem operations on the one native UV service.
 * Asynchronous uv_fs_t and the loop remain private to their actual owner.
 * The selected synchronous close borrows its caller's native stack uv_fs_t.
 * No JS value, Engine pointer or guest callback is accepted by this API. */
#ifndef PI_NATIVE_UV_FS_H
#define PI_NATIVE_UV_FS_H
#include "native_uv_tcp.h"
#include "quickjs.h"
#ifdef __cplusplus
extern "C" {
#endif

typedef struct PiUvFsRequest PiUvFsRequest;
enum PiUvFsKind { PI_UV_FS_UNASSIGNED = 0, PI_UV_FS_READ, PI_UV_FS_OPEN, PI_UV_FS_CLOSE };
typedef struct PiUvFsInfo {
    int kind;
    int64_t result; /* actual uv_fs_t::result, never a synthesized Promise value */
    const char *path; /* borrowed until request_cleanup */
    int accepted;
    int cleaned;
} PiUvFsInfo;
typedef struct PiUvFsPreparationInfo {
    int kind;
    int accepted;
    int cleaned;
    int completed;
} PiUvFsPreparationInfo;

/* Allocate the native request storage during the original ReqWrap allocation,
 * before its actual constructor/init hooks and SetReturnValue. A proven
 * wrapper allocation failure sets allocation_failed and leaves *out NULL.
 * Success transfers one request; an unsubmitted request can be released.
 * UNASSIGNED reserves the genuine generic FSReqCallback storage before its
 * operation is known. Only a validated actual admission selects its operation;
 * typed READ/OPEN/CLOSE storage keeps its original operation restriction.
 * Reuse requires successful request_reset after actual completion/dequeue and
 * cleanup; submitted or cleaned storage cannot be passed directly to admission.
 */
PiUvResult pi_uv_fs_request_create(PiUvService *service, int kind,
    uint64_t token, PiUvFsRequest **out);
/* These calls perform the actual asynchronous libuv admission. They allocate
 * no second wrapper. Validated inputs and the matching unsubmitted request
 * are required. status >= 0 promises one PI_UV_FS_COMPLETION; a negative
 * actual admission status promises none and requires the original direct
 * after callback. No count is inferred from a task or Promise allocation.
 * READ duplicates the actual native backing lease before admission.
 */
/* Reset the same native request after its actual completion was removed from
 * the FIFO and request_cleanup ran. A new/unsubmitted request also admits its
 * initial Reset. In-flight, still-queued or uncleaned operations return
 * UV_EBUSY without changing state. No wrapper, event, backing or request is
 * allocated by Reset.
 *
 * The previous dequeued event entitlement may remain owned while the request
 * is submitted again, as in FileHandleReadWrap's original completion callback.
 * After Reset the old event may ONLY be released: its mutable completion info
 * now belongs to the next operation. Stable event release fields never change,
 * and its next link must not be touched by the old owner. Each actual queued
 * completion still transfers one independent request and service entitlement.
 */
int pi_uv_fs_request_reset(PiUvFsRequest *request);
/* Native FileHandle/StreamResource span: the caller supplies the exact
 * uv_buf_t base/length and keeps its native storage owner alive through actual
 * completion and request_cleanup. This call borrows bytes and makes no JS
 * wrapper/lease, copy or extra native allocation. The library does not infer
 * or extend that external buffer lifetime. Wrong state/invalid native span
 * returns UV_EINVAL before admission. Windows requires its real ULONG extent.
 */
int pi_uv_fs_read_buffer(PiUvFsRequest *request, int descriptor,
    char *base, size_t length, int64_t position);
int pi_uv_fs_read(PiUvFsRequest *request, int descriptor,
    const JSPiArrayBufferLease *backing, size_t offset, uint32_t length,
    int64_t position);
int pi_uv_fs_open(PiUvFsRequest *request, const char *path, int flags, int mode);
int pi_uv_fs_close(PiUvFsRequest *request, int descriptor);
/* Original FileHandle GC close: synchronous calling-thread uv_fs_close with
 * cb == NULL and the retained service's actual loop. The caller owns a full
 * canonical uv_fs_t on its stack and performs uv_fs_req_cleanup after its
 * trace-end operation. This call queues no command/event and allocates no
 * PiUvFsRequest. Pinned libuv's synchronous path does not dereference the loop;
 * retaining the service keeps its address/storage valid even after stop/join.
 */
struct uv_fs_s;
int pi_uv_fs_close_sync(PiUvService *service, struct uv_fs_s *request,
    int descriptor);
/* Actual uv_cancel runs on the service thread only for an accepted request
 * whose callback is still pending. A no-in-flight command returns UV_EINVAL.
 * It never clears the request or suppresses an accepted operation's callback. */
int pi_uv_fs_cancel(PiUvFsRequest *request);
void pi_uv_fs_request_retain(PiUvFsRequest *request);
void pi_uv_fs_request_release(PiUvFsRequest *request);
/* Observe actual native storage during its caller-owned unsubmitted phase:
 * before first admission, or after request_reset returned successfully.
 * The caller must retain the request and invoke this on its dispatch/owner
 * thread, with no concurrent admission, cleanup, reset or release. This is
 * not a concurrent lifecycle snapshot. The unsubmitted assertion guards the
 * phase; it does not establish thread ownership. No uv.result/path is read,
 * no completion is inferred, and no request state or entitlement is changed.
 */
PiUvFsPreparationInfo pi_uv_fs_request_preparation_info(
    const PiUvFsRequest *request);
/* Info is available after immediate negative admission or actual event
 * acquisition, and before a successful request_reset invalidates that result.
 * Cleanup is idempotent and occurs at FSReqAfterScope::Clear;
 * release also handles an unsubmitted native construction rollback.
 * Cleanup does not close a descriptor returned by OPEN: the selected original
 * FileHandle/descriptor consumer owns that independent native resource.
 */
PiUvFsInfo pi_uv_fs_request_info(const PiUvFsRequest *request);
void pi_uv_fs_request_cleanup(PiUvFsRequest *request);
/* Borrowed actual request for an FS completion event, NULL for TCP events.
 * The caller may retain it; the event holds an independent entitlement. */
PiUvFsRequest *pi_uv_event_fs_request(const PiUvEvent *event);

#ifdef __cplusplus
}
#endif
#endif
