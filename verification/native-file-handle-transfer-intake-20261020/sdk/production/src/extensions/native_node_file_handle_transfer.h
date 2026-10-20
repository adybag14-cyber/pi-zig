/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Actual native descriptor storage for the selected FileHandle TransferData.
 * This packet owns no JSValue, Engine, Environment, service or native lease.
 */
#ifndef PI_NATIVE_NODE_FILE_HANDLE_TRANSFER_H
#define PI_NATIVE_NODE_FILE_HANDLE_TRANSFER_H

typedef struct JSContext JSContext;
typedef struct PiNodeFileHandleTransferData PiNodeFileHandleTransferData;

/* Required process-lifetime entrypoints for the original global
 * FS_SYNC_TRACE_BEGIN(close) / FS_SYNC_TRACE_END(close) operations.
 * Each invocation must consult the genuine global tracing owner. These
 * function addresses may outlive every sender/receiver Environment; they
 * cannot capture an Environment, Engine, service, or a temporary raw pointer.
 * The process tracing/bootstrap owner is a separate explicit dependency.
 */
typedef struct PiNodeFileHandleTransferTrace {
    void (*begin_sync_close)(void);
    void (*end_sync_close)(void);
} PiNodeFileHandleTransferTrace;

#ifdef __cplusplus
extern "C" {
#endif

/* Borrow context and memory_owner only for this synchronous allocation.
 * The actual allocation prefix independently retains the native memory owner.
 * Native standard new/new_handler failure policy is preserved.
 */
PiNodeFileHandleTransferData *pi_node_file_handle_transfer_data_create(
    JSContext *context, void *memory_owner, int descriptor,
    const PiNodeFileHandleTransferTrace *trace);

/* Borrow context only for this synchronous call; NULL masks any outer
 * diagnostic admission. This is safe after the sending Engine has retired.
 * The original destructor closes only descriptor > 0, with NULL loop and
 * callback, then cleans its caller-owned uv_fs_t after trace end.
 */
void pi_node_file_handle_transfer_data_delete(
    JSContext *context, PiNodeFileHandleTransferData *packet);

/* Actual native member access. Taking writes -1 before returning the value;
 * a subsequent failed receiver construction does not restore ownership.
 */
int pi_node_file_handle_transfer_data_descriptor(
    JSContext *context, const PiNodeFileHandleTransferData *packet);
int pi_node_file_handle_transfer_data_take_descriptor(
    JSContext *context, PiNodeFileHandleTransferData *packet);

#ifdef __cplusplus
}
#endif
#endif
