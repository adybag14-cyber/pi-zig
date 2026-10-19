/* Real Node v24.13.0 libuv TCP transport. No JS/Engine pointers cross this ABI.
 * Every function except retain/release and error names runs on the owning host
 * thread. uv_* handle operations run only on the service's native loop thread.
 * All negative statuses are the actual libuv status, including UV_ENOMEM.
 */
#ifndef PI_NATIVE_UV_TCP_H
#define PI_NATIVE_UV_TCP_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct PiUvService PiUvService;
typedef struct PiUvEndpoint PiUvEndpoint;
typedef struct PiUvEvent PiUvEvent;
/* Caller retains this already-owned native wake generation until stop joins. */
typedef void (*PiUvWake)(uint32_t slot, uint64_t generation);

enum PiUvEventKind {
    PI_UV_ACCEPT = 1,
    PI_UV_LISTEN_ERROR,
    PI_UV_READ,
    PI_UV_EOF,
    PI_UV_WRITE,
    PI_UV_SHUTDOWN,
    PI_UV_CONNECT,
    PI_UV_CLOSE,
    PI_UV_NATIVE_ALLOCATION_FAILURE
};
typedef struct PiUvEventInfo {
    int kind;
    int status;
    uint64_t token;
    PiUvEndpoint *source;  /* borrowed until event_release */
    const unsigned char *bytes; /* read payload, borrowed until event_release */
    size_t length; /* read bytes / successfully completed write bytes */
} PiUvEventInfo;

typedef struct PiUvAddress {
    int family; /* 4 or 6, independent of the platform's AF_* integer */
    unsigned int port;
    unsigned int scope_id;
    char address[46];
} PiUvAddress;

/* A wrapper reserve/malloc failure is a distinct producer from libuv's own
 * ordinary negative status (including UV_ENOMEM). The owner must publish its
 * native allocation fatal only when allocation_failed is set.
 */
typedef struct PiUvResult {
    int status;
    int allocation_failed;
} PiUvResult;

typedef struct PiUvSnapshot {
    size_t live_handles;
    size_t pending_requests;
    size_t queued_events;
    size_t referenced_handles;
    int close_requested;
    int thread_joined;
    int loop_close_status;
} PiUvSnapshot;

/* Retains memory_owner, which is the actual independent pi_js memory owner.
 * This owner charges all wrapper objects and owned payloads. The unchanged
 * libuv library retains its own allocator; no process-global allocator swap.
 * create returns one owned service. stop must succeed before its last release.
 */
PiUvResult pi_uv_service_create(void *memory_owner, PiUvWake wake, uint32_t wake_slot,
                         uint64_t wake_generation, PiUvService **result);
void pi_uv_service_retain(PiUvService *service);
void pi_uv_service_release(PiUvService *service);
/* Stops admission, uv_closes every owned handle, drains real request/close
 * callbacks, joins the worker, and closes its loop. Does not enter JS.
 * Queued event ownership remains available to the owner for discard/drain.
 */
int pi_uv_service_stop(PiUvService *service);
int pi_uv_service_has_referenced(PiUvService *service);
PiUvSnapshot pi_uv_service_snapshot(PiUvService *service);
PiUvEvent *pi_uv_service_next(PiUvService *service); /* one owned event, or NULL */
PiUvEventInfo pi_uv_event_info(const PiUvEvent *event);
/* Only on ACCEPT. Transfers one newly retained endpoint to the caller.
 * Releasing an unclaimed accept event closes the real accepted connection.
 */
PiUvEndpoint *pi_uv_event_take_accepted(PiUvEvent *event);
void pi_uv_event_release(PiUvEvent *event);

/* One owned endpoint. Dropping an external reference does not fabricate a
 * native close; abandon/close own that operation and its actual callback.
 */
PiUvResult pi_uv_tcp_create(PiUvService *service, PiUvEndpoint **result);
void pi_uv_endpoint_retain(PiUvEndpoint *endpoint);
void pi_uv_endpoint_release(PiUvEndpoint *endpoint);
void pi_uv_endpoint_abandon(PiUvEndpoint *endpoint);
/* This native layer accepts numeric addresses only. DNS lookup is a separate
 * actual owner, not a hostname-to-loopback fallback.
 */
int pi_uv_tcp_bind(PiUvEndpoint *endpoint, const char *address,
                   unsigned int port, unsigned int flags);
int pi_uv_tcp_listen(PiUvEndpoint *endpoint, int backlog);
PiUvResult pi_uv_tcp_connect(PiUvEndpoint *endpoint, const char *address,
                      unsigned int port, uint64_t token);
int pi_uv_tcp_read_start(PiUvEndpoint *endpoint);
int pi_uv_tcp_read_stop(PiUvEndpoint *endpoint);
/* Copies all bytes before returning; status 0 promises one later WRITE event.
 * Immediate negative status promises no completion for the supplied token.
 */
PiUvResult pi_uv_tcp_write(PiUvEndpoint *endpoint, const unsigned char *bytes,
                    size_t length, uint64_t token);
PiUvResult pi_uv_tcp_shutdown(PiUvEndpoint *endpoint, uint64_t token);
/* Returns 0 for a pending actual close, 1 only after observed native closure,
 * or an actual negative status. A later destroy token can attach to an already
 * requested close; it never causes a second uv_close.
 */
int pi_uv_tcp_close(PiUvEndpoint *endpoint, uint64_t token);
int pi_uv_tcp_set_referenced(PiUvEndpoint *endpoint, int referenced);
int pi_uv_tcp_nodelay(PiUvEndpoint *endpoint, int enabled);
int pi_uv_tcp_keepalive(PiUvEndpoint *endpoint, int enabled, unsigned int delay);
int pi_uv_tcp_address(PiUvEndpoint *endpoint, int peer, PiUvAddress *result);
const char *pi_uv_error_name(int status);
const char *pi_uv_error_message(int status);

#ifdef __cplusplus
}
#endif
#endif
