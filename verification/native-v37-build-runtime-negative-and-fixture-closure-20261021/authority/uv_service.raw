/* The libuv sources are unchanged pinned Node v24.13.0 sources. This adapter
 * owns only a native loop, native requests, byte storage and counted native
 * events. Its wake callback carries a generation token, never an Engine.
 */
#include "native_uv_tcp.h"
#include "native_uv_fs.h"
#include "engine_abi.h"
#include "uv.h"
#include <assert.h>
#include <limits.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

typedef struct PiUvAllocation {
    size_t charge;
    max_align_t alignment;
} PiUvAllocation;
static void *pi_uv_alloc(void *owner, size_t size) {
    if (size > SIZE_MAX - sizeof(PiUvAllocation)) return NULL;
    size_t charge = sizeof(PiUvAllocation) + size;
    if (!pi_js_native_memory_reserve(owner, charge)) return NULL;
    PiUvAllocation *allocation = malloc(charge);
    if (!allocation) {
        pi_js_native_memory_release(owner, charge);
        return NULL;
    }
    allocation->charge = charge;
    void *result = allocation + 1;
    memset(result, 0, size);
    return result;
}
static void pi_uv_free(void *owner, void *pointer) {
    if (!pointer) return;
    PiUvAllocation *allocation = (PiUvAllocation *)pointer - 1;
    size_t charge = allocation->charge;
    free(allocation);
    pi_js_native_memory_release(owner, charge);
}

enum PiUvStorage { PI_UV_EMBED_READ, PI_UV_EMBED_CLOSE, PI_UV_EMBED_ACCEPT,
                   PI_UV_REQUEST, PI_UV_HEAP_EVENT, PI_UV_EMBED_OOM,
                   PI_UV_FS_REQUEST };
struct PiUvEvent {
    PiUvEvent *next;
    PiUvService *service;
    PiUvEndpoint *keeper;
    PiUvEndpoint *accepted;
    PiUvEventInfo info;
    enum PiUvStorage storage;
    void *allocation;
    int in_use;
};
typedef struct PiUvRequest {
    union {
        uv_write_t write;
        uv_shutdown_t shutdown;
        uv_connect_t connect;
    } uv;
    PiUvEndpoint *endpoint;
    PiUvEvent event;
    uv_buf_t buffer;
} PiUvRequest;
/* The real uv_fs_t survives its native callback until the owner executes
 * FSReqAfterScope::Clear. Neither this request nor its backing entitlement
 * contains a JS value, Engine pointer, or guest callback. */
struct PiUvFsRequest {
    PiUvService *service;
    _Atomic size_t references;
    uv_fs_t uv;
    uv_buf_t buffer;
    JSPiArrayBufferLease backing;
    PiUvEvent event;
    PiUvFsRequest *previous;
    PiUvFsRequest *next;
    int kind;
    int storage_kind; /* immutable generic/typed native allocation admission */
    int descriptor;
    int flags;
    int mode;
    int64_t position;
    int submitted;
    int entered;
    int accepted;
    _Atomic int completed;
    _Atomic int cleaned;
    _Atomic int event_queued;
};
enum PiUvCommandKind { PI_UV_CMD_INIT, PI_UV_CMD_BIND, PI_UV_CMD_LISTEN,
    PI_UV_CMD_CONNECT, PI_UV_CMD_READ_START, PI_UV_CMD_READ_STOP,
    PI_UV_CMD_READ_ACK, PI_UV_CMD_WRITE, PI_UV_CMD_SHUTDOWN,
    PI_UV_CMD_CLOSE, PI_UV_CMD_REF, PI_UV_CMD_NODELAY, PI_UV_CMD_KEEPALIVE,
    PI_UV_CMD_ADDRESS, PI_UV_CMD_FS_READ, PI_UV_CMD_FS_OPEN,
    PI_UV_CMD_FS_CLOSE, PI_UV_CMD_FS_CANCEL, PI_UV_CMD_STOP };
typedef struct PiUvCommand {
    enum PiUvCommandKind kind;
    PiUvEndpoint *endpoint;
    PiUvRequest *request;
    PiUvFsRequest *fs_request;
    const char *path;
    struct sockaddr_storage address;
    PiUvAddress *address_result;
    uint64_t token;
    unsigned int number;
    int flag;
    int result;
    int done;
} PiUvCommand;
struct PiUvEndpoint {
    PiUvService *service;
    _Atomic size_t references;
    uv_tcp_t tcp;
    PiUvEndpoint *previous;
    PiUvEndpoint *next;
    PiUvEvent read_event;
    PiUvEvent close_event;
    PiUvEvent accept_event;
    uint64_t close_token;
    int initialized;
    int exposed;
    int closing;
    int closed;
    int reading;
    int read_wanted;
    int read_ended;
};
struct PiUvService {
    void *memory_owner;
    _Atomic size_t references;
    PiUvWake wake;
    uint32_t wake_slot;
    uint64_t wake_generation;
    uv_loop_t loop;
    uv_async_t command_async;
    uv_thread_t thread;
    uv_mutex_t command_mutex;
    uv_cond_t command_condition;
    uv_mutex_t event_mutex;
    PiUvCommand *command;
    PiUvEndpoint *endpoints;
    PiUvFsRequest *fs_requests;
    PiUvEvent *event_head;
    PiUvEvent *event_tail;
    PiUvEvent allocation_event;
    _Atomic size_t live_handles;
    _Atomic size_t pending_requests;
    _Atomic size_t queued_events;
    _Atomic size_t referenced_handles;
    _Atomic int close_requested;
    _Atomic int thread_joined;
    int loop_close_status;
};

static PiUvResult pi_uv_result(int status, int allocation_failed) {
    PiUvResult result = { status, allocation_failed };
    return result;
}
static int pi_uv_submit(PiUvService *, PiUvCommand *);
static void pi_uv_close_worker(PiUvEndpoint *);
static void pi_uv_read_allocate(uv_handle_t *, size_t, uv_buf_t *);
static void pi_uv_read_completed(uv_stream_t *, ssize_t, const uv_buf_t *);
static void pi_uv_refresh_referenced(PiUvService *service) {
    size_t count = 0;
    for (PiUvEndpoint *endpoint = service->endpoints; endpoint; endpoint = endpoint->next)
        if (!endpoint->closing && uv_is_active((uv_handle_t *)&endpoint->tcp) &&
            uv_has_ref((uv_handle_t *)&endpoint->tcp)) count++;
    atomic_store_explicit(&service->referenced_handles, count, memory_order_release);
}
void pi_uv_service_retain(PiUvService *service) {
    atomic_fetch_add_explicit(&service->references, 1, memory_order_relaxed);
}
void pi_uv_service_release(PiUvService *service) {
    if (atomic_fetch_sub_explicit(&service->references, 1, memory_order_acq_rel) != 1) return;
    assert(atomic_load_explicit(&service->thread_joined, memory_order_acquire));
    assert(service->endpoints == NULL && service->fs_requests == NULL &&
           service->event_head == NULL);
    uv_mutex_destroy(&service->event_mutex);
    uv_cond_destroy(&service->command_condition);
    uv_mutex_destroy(&service->command_mutex);
    void *owner = service->memory_owner;
    pi_uv_free(owner, service);
    pi_js_release_memory_owner(owner);
}
void pi_uv_endpoint_retain(PiUvEndpoint *endpoint) {
    atomic_fetch_add_explicit(&endpoint->references, 1, memory_order_relaxed);
}
void pi_uv_endpoint_release(PiUvEndpoint *endpoint) {
    if (atomic_fetch_sub_explicit(&endpoint->references, 1, memory_order_acq_rel) != 1) return;
    assert(!endpoint->initialized || endpoint->closed);
    PiUvService *service = endpoint->service;
    pi_uv_free(service->memory_owner, endpoint);
    pi_uv_service_release(service);
}
static PiUvEndpoint *pi_uv_endpoint_allocate(PiUvService *service) {
    PiUvEndpoint *endpoint = pi_uv_alloc(service->memory_owner, sizeof(*endpoint));
    if (!endpoint) return NULL;
    endpoint->service = service;
    atomic_init(&endpoint->references, 1);
    pi_uv_service_retain(service);
    return endpoint;
}
static void pi_uv_event_prepare(PiUvEvent *event, PiUvService *service,
        PiUvEndpoint *source, PiUvEndpoint *keeper, enum PiUvStorage storage,
        int kind, int status, uint64_t token) {
    assert(!event->in_use);
    memset(event, 0, sizeof(*event));
    event->service = service;
    event->keeper = keeper;
    event->storage = storage;
    event->info.source = source;
    event->info.kind = kind;
    event->info.status = status;
    event->info.token = token;
}
static void pi_uv_event_queue(PiUvEvent *event) {
    PiUvService *service = event->service;
    assert(!event->in_use);
    event->in_use = 1;
    pi_uv_service_retain(service);
    if (event->info.source) pi_uv_endpoint_retain(event->info.source);
    if (event->keeper && event->keeper != event->info.source)
        pi_uv_endpoint_retain(event->keeper);
    uv_mutex_lock(&service->event_mutex);
    if (service->event_tail) service->event_tail->next = event;
    else service->event_head = event;
    service->event_tail = event;
    atomic_fetch_add_explicit(&service->queued_events, 1, memory_order_release);
    uv_mutex_unlock(&service->event_mutex);
    service->wake(service->wake_slot, service->wake_generation);
}
/* No allocation is required to report a real wrapper allocation failure.
 * Coalescing only repeated outstanding failures is sufficient: the owner
 * publishes the first actual fatal before any later guest operation.
 */
static void pi_uv_allocation_failed(PiUvService *service) {
    if (service->allocation_event.in_use) return;
    pi_uv_event_prepare(&service->allocation_event, service, NULL, NULL,
        PI_UV_EMBED_OOM, PI_UV_NATIVE_ALLOCATION_FAILURE, UV_ENOMEM, 0);
    pi_uv_event_queue(&service->allocation_event);
}
static void pi_uv_listener_error(PiUvEndpoint *endpoint, int status) {
    PiUvService *service = endpoint->service;
    PiUvEvent *event = pi_uv_alloc(service->memory_owner, sizeof(*event));
    if (!event) { pi_uv_allocation_failed(service); return; }
    pi_uv_event_prepare(event, service, endpoint, endpoint, PI_UV_HEAP_EVENT,
        PI_UV_LISTEN_ERROR, status, 0);
    event->allocation = event;
    pi_uv_event_queue(event);
}
static int pi_uv_initialize_worker(PiUvEndpoint *endpoint) {
    PiUvService *service = endpoint->service;
    int result = uv_tcp_init(&service->loop, &endpoint->tcp);
    if (result < 0) return result;
    endpoint->tcp.data = endpoint;
    endpoint->initialized = 1;
    endpoint->next = service->endpoints;
    if (endpoint->next) endpoint->next->previous = endpoint;
    service->endpoints = endpoint;
    pi_uv_endpoint_retain(endpoint); /* actual initialized uv handle */
    atomic_fetch_add_explicit(&service->live_handles, 1, memory_order_release);
    return 0;
}
static void pi_uv_closed(uv_handle_t *handle) {
    PiUvEndpoint *endpoint = handle->data;
    PiUvService *service = endpoint->service;
    endpoint->closed = 1;
    endpoint->reading = 0;
    if (endpoint->previous) endpoint->previous->next = endpoint->next;
    else service->endpoints = endpoint->next;
    if (endpoint->next) endpoint->next->previous = endpoint->previous;
    endpoint->previous = endpoint->next = NULL;
    atomic_fetch_sub_explicit(&service->live_handles, 1, memory_order_release);
    if (endpoint->exposed) {
        pi_uv_event_prepare(&endpoint->close_event, service, endpoint, endpoint,
            PI_UV_EMBED_CLOSE, PI_UV_CLOSE, 0, endpoint->close_token);
        pi_uv_event_queue(&endpoint->close_event);
    }
    pi_uv_refresh_referenced(service);
    pi_uv_endpoint_release(endpoint); /* uv_close callback is the terminal fact */
}
static void pi_uv_close_worker(PiUvEndpoint *endpoint) {
    if (endpoint->closing || endpoint->closed || !endpoint->initialized) return;
    endpoint->closing = 1;
    endpoint->read_wanted = 0;
    if (endpoint->reading) {
        (void)uv_read_stop((uv_stream_t *)&endpoint->tcp);
        endpoint->reading = 0;
    }
    uv_close((uv_handle_t *)&endpoint->tcp, pi_uv_closed);
}
static void pi_uv_connection(uv_stream_t *server, int status) {
    PiUvEndpoint *listener = server->data;
    PiUvService *service = listener->service;
    if (status < 0) { pi_uv_listener_error(listener, status); return; }
    PiUvEndpoint *accepted = pi_uv_endpoint_allocate(service);
    if (!accepted) { pi_uv_allocation_failed(service); return; }
    status = pi_uv_initialize_worker(accepted);
    if (status < 0) {
        pi_uv_endpoint_release(accepted);
        pi_uv_listener_error(listener, status);
        return;
    }
    status = uv_accept(server, (uv_stream_t *)&accepted->tcp);
    if (status < 0) {
        pi_uv_close_worker(accepted);
        pi_uv_endpoint_release(accepted);
        pi_uv_listener_error(listener, status);
        return;
    }
    accepted->exposed = 1;
    pi_uv_event_prepare(&accepted->accept_event, service, listener, accepted,
        PI_UV_EMBED_ACCEPT, PI_UV_ACCEPT, 0, 0);
    accepted->accept_event.accepted = accepted;
    pi_uv_event_queue(&accepted->accept_event);
    pi_uv_endpoint_release(accepted); /* event + real uv handle now own it */
    pi_uv_refresh_referenced(service);
}
static int pi_uv_resume_read_worker(PiUvEndpoint *endpoint) {
    if (endpoint->closing || endpoint->closed) return UV_EBADF;
    if (!endpoint->read_wanted || endpoint->read_ended || endpoint->reading ||
        endpoint->read_event.in_use) return 0;
    int result = uv_read_start((uv_stream_t *)&endpoint->tcp,
        pi_uv_read_allocate, pi_uv_read_completed);
    if (result == 0) endpoint->reading = 1;
    return result;
}
static void pi_uv_read_allocate(uv_handle_t *handle, size_t suggested, uv_buf_t *buffer) {
    PiUvEndpoint *endpoint = handle->data;
    (void)suggested;
    /* Same maximum native segment used by the actual Socket owner. One pending
     * payload per endpoint; native demand resumes after its owner checkpoint.
     */
    unsigned char *bytes = pi_uv_alloc(endpoint->service->memory_owner, 64 * 1024);
    *buffer = uv_buf_init((char *)bytes, bytes ? 64 * 1024 : 0);
    if (!bytes) pi_uv_allocation_failed(endpoint->service);
}
static void pi_uv_read_completed(uv_stream_t *stream, ssize_t count, const uv_buf_t *buffer) {
    PiUvEndpoint *endpoint = stream->data;
    PiUvService *service = endpoint->service;
    if (count == 0) { pi_uv_free(service->memory_owner, buffer->base); return; }
    (void)uv_read_stop(stream);
    endpoint->reading = 0;
    endpoint->read_wanted = 0;
    if (count < 0) endpoint->read_ended = 1;
    pi_uv_event_prepare(&endpoint->read_event, service, endpoint, endpoint,
        PI_UV_EMBED_READ, count == UV_EOF ? PI_UV_EOF : PI_UV_READ,
        count < 0 ? (int)count : 0, 0);
    if (count > 0) {
        endpoint->read_event.allocation = buffer->base;
        endpoint->read_event.info.bytes = (const unsigned char *)buffer->base;
        endpoint->read_event.info.length = (size_t)count;
    } else pi_uv_free(service->memory_owner, buffer->base);
    pi_uv_event_queue(&endpoint->read_event);
    pi_uv_refresh_referenced(service);
}
static PiUvRequest *pi_uv_request_allocate(PiUvEndpoint *endpoint, int kind,
                                           uint64_t token, size_t extra) {
    if (extra > SIZE_MAX - sizeof(PiUvRequest)) return NULL;
    PiUvRequest *request = pi_uv_alloc(endpoint->service->memory_owner,
                                      sizeof(*request) + extra);
    if (!request) return NULL;
    request->endpoint = endpoint;
    pi_uv_endpoint_retain(endpoint);
    pi_uv_event_prepare(&request->event, endpoint->service, endpoint, endpoint,
        PI_UV_REQUEST, kind, 0, token);
    request->event.allocation = request;
    return request;
}
static void pi_uv_request_discard(PiUvRequest *request) {
    PiUvEndpoint *endpoint = request->endpoint;
    pi_uv_free(endpoint->service->memory_owner, request);
    pi_uv_endpoint_release(endpoint);
}
static void pi_uv_request_completed(PiUvRequest *request, int status) {
    PiUvEndpoint *endpoint = request->endpoint;
    PiUvService *service = endpoint->service;
    request->event.info.status = status;
    if (request->event.info.kind == PI_UV_WRITE && status == 0)
        request->event.info.length = request->buffer.len;
    atomic_fetch_sub_explicit(&service->pending_requests, 1, memory_order_release);
    pi_uv_event_queue(&request->event);
    pi_uv_refresh_referenced(service);
    pi_uv_endpoint_release(endpoint); /* event has taken the request's owner */
}
static void pi_uv_written(uv_write_t *request, int status) {
    pi_uv_request_completed(request->data, status);
}
static void pi_uv_shutdown_completed(uv_shutdown_t *request, int status) {
    pi_uv_request_completed(request->data, status);
}
static void pi_uv_connected(uv_connect_t *request, int status) {
    pi_uv_request_completed(request->data, status);
}
void pi_uv_fs_request_retain(PiUvFsRequest *request) {
    atomic_fetch_add_explicit(&request->references, 1, memory_order_relaxed);
}
void pi_uv_fs_request_cleanup(PiUvFsRequest *request) {
    assert(!request->submitted || atomic_load_explicit(&request->completed, memory_order_acquire));
    if (atomic_exchange_explicit(&request->cleaned, 1, memory_order_acq_rel))
        return;
    /* Actual uv cleanup is delayed until the original AfterScope cutpoint.
     * The independent backing entitlement is no longer used by native work. */
    if (request->entered) uv_fs_req_cleanup(&request->uv);
    JS_PiReleaseArrayBufferLease(&request->backing);
}
void pi_uv_fs_request_release(PiUvFsRequest *request) {
    if (!request || atomic_fetch_sub_explicit(&request->references, 1,
                                              memory_order_acq_rel) != 1)
        return;
    assert(!request->submitted || atomic_load_explicit(&request->completed, memory_order_acquire));
    pi_uv_fs_request_cleanup(request);
    PiUvService *service = request->service;
    pi_uv_free(service->memory_owner, request);
    pi_uv_service_release(service);
}
static PiUvFsRequest *pi_uv_fs_request_allocate(PiUvService *service,
                                               int kind, uint64_t token) {
    PiUvFsRequest *request = pi_uv_alloc(service->memory_owner, sizeof(*request));
    if (!request) return NULL;
    request->service = service;
    request->kind = kind;
    request->storage_kind = kind;
    atomic_init(&request->references, 1);
    atomic_init(&request->completed, 0);
    atomic_init(&request->cleaned, 0);
    atomic_init(&request->event_queued, 0);
    pi_uv_service_retain(service);
    pi_uv_event_prepare(&request->event, service, NULL, NULL,
        PI_UV_FS_REQUEST, PI_UV_FS_COMPLETION, 0, token);
    request->event.allocation = request;
    return request;
}
static void pi_uv_fs_completed(uv_fs_t *actual) {
    PiUvFsRequest *request = actual->data;
    PiUvService *service = request->service;
    if (request->previous) request->previous->next = request->next;
    else service->fs_requests = request->next;
    if (request->next) request->next->previous = request->previous;
    request->previous = request->next = NULL;
    request->event.info.status = actual->result < 0 ? (int)actual->result : 0;
    if (request->kind == PI_UV_FS_READ && actual->result >= 0)
        request->event.info.length = (size_t)actual->result;
    atomic_fetch_sub_explicit(&service->pending_requests, 1, memory_order_release);
    /* Publish the queued state before completed: observing completed must
     * never admit Reset in the interval before FIFO publication. Only actual
     * dequeue clears this state for an accepted operation. */
    atomic_store_explicit(&request->event_queued, 1, memory_order_release);
    atomic_store_explicit(&request->completed, 1, memory_order_release);
    pi_uv_fs_request_retain(request); /* actual queued event entitlement */
    pi_uv_event_queue(&request->event);
    /* The owner may already have drained the event. Keep this native callback
     * entitlement until all callback accesses have completed. */
    pi_uv_fs_request_release(request);
}
static int pi_uv_fs_run(PiUvService *service, PiUvCommand *command) {
    PiUvFsRequest *request = command->fs_request;
    if (command->kind == PI_UV_CMD_FS_CANCEL) {
        if (!request->accepted ||
            atomic_load_explicit(&request->completed, memory_order_acquire))
            return UV_EINVAL;
        return uv_cancel((uv_req_t *)&request->uv);
    }
    request->uv.data = request;
    request->entered = 1;
    int status;
    switch (command->kind) {
    case PI_UV_CMD_FS_READ:
        status = uv_fs_read(&service->loop, &request->uv, request->descriptor,
            &request->buffer, 1, request->position, pi_uv_fs_completed);
        break;
    case PI_UV_CMD_FS_OPEN:
        status = uv_fs_open(&service->loop, &request->uv, command->path,
            request->flags, request->mode, pi_uv_fs_completed);
        break;
    case PI_UV_CMD_FS_CLOSE:
        status = uv_fs_close(&service->loop, &request->uv, request->descriptor,
                            pi_uv_fs_completed);
        break;
    default:
        return UV_EINVAL;
    }
    if (status >= 0) {
        request->accepted = 1;
        request->next = service->fs_requests;
        if (request->next) request->next->previous = request;
        service->fs_requests = request;
        pi_uv_fs_request_retain(request); /* actual in-flight uv request */
        atomic_fetch_add_explicit(&service->pending_requests, 1, memory_order_release);
    } else {
        /* AsyncDestCall sets the failed result/path before directly invoking
         * the original after callback. No queued event or waiting count. */
        request->uv.result = status;
        request->uv.path = NULL;
        atomic_store_explicit(&request->completed, 1, memory_order_release);
    }
    return status;
}
static int pi_uv_numeric_address(const char *text, unsigned int port,
                                 struct sockaddr_storage *storage) {
    if (!text || port > 65535) return UV_EINVAL;
    memset(storage, 0, sizeof(*storage));
    int result = uv_ip4_addr(text, (int)port, (struct sockaddr_in *)storage);
    if (result == 0) return 0;
    return uv_ip6_addr(text, (int)port, (struct sockaddr_in6 *)storage);
}
static int pi_uv_address_worker(PiUvEndpoint *endpoint, int peer, PiUvAddress *result) {
    struct sockaddr_storage storage;
    int size = sizeof(storage);
    int status = peer
        ? uv_tcp_getpeername(&endpoint->tcp, (struct sockaddr *)&storage, &size)
        : uv_tcp_getsockname(&endpoint->tcp, (struct sockaddr *)&storage, &size);
    if (status < 0) return status;
    PiUvAddress actual;
    memset(&actual, 0, sizeof(actual));
    if (storage.ss_family == AF_INET) {
        const struct sockaddr_in *address = (const struct sockaddr_in *)&storage;
        actual.family = 4;
        actual.port = ntohs(address->sin_port);
        status = uv_ip4_name(address, actual.address, sizeof(actual.address));
    } else if (storage.ss_family == AF_INET6) {
        const struct sockaddr_in6 *address = (const struct sockaddr_in6 *)&storage;
        actual.family = 6;
        actual.port = ntohs(address->sin6_port);
        actual.scope_id = address->sin6_scope_id;
        status = uv_ip6_name(address, actual.address, sizeof(actual.address));
    } else return UV_EAFNOSUPPORT;
    if (status == 0) *result = actual;
    return status;
}
static int pi_uv_command_run(PiUvService *service, PiUvCommand *command) {
    PiUvEndpoint *endpoint = command->endpoint;
    PiUvRequest *request = command->request;
    if (command->kind == PI_UV_CMD_STOP) {
        atomic_store_explicit(&service->close_requested, 1, memory_order_release);
        for (PiUvEndpoint *item = service->endpoints; item; item = item->next)
            pi_uv_close_worker(item);
        for (PiUvFsRequest *item = service->fs_requests; item; item = item->next)
            (void)uv_cancel((uv_req_t *)&item->uv);
        uv_close((uv_handle_t *)&service->command_async, NULL);
        return 0;
    }
    if (command->kind == PI_UV_CMD_FS_READ || command->kind == PI_UV_CMD_FS_OPEN ||
        command->kind == PI_UV_CMD_FS_CLOSE || command->kind == PI_UV_CMD_FS_CANCEL)
        return pi_uv_fs_run(service, command);
    if (command->kind == PI_UV_CMD_INIT) return pi_uv_initialize_worker(endpoint);
    if (command->kind == PI_UV_CMD_READ_ACK) {
        endpoint->read_event.in_use = 0;
        if (endpoint->closing || endpoint->closed) return 0;
        int status = pi_uv_resume_read_worker(endpoint);
        if (status < 0) {
            endpoint->read_ended = 1;
            endpoint->read_wanted = 0;
            pi_uv_event_prepare(&endpoint->read_event, service, endpoint, endpoint,
                PI_UV_EMBED_READ, PI_UV_READ, status, 0);
            pi_uv_event_queue(&endpoint->read_event);
        }
        return 0;
    }
    if (command->kind == PI_UV_CMD_CLOSE) {
        if (endpoint->closed) return 1;
        if (command->token) endpoint->close_token = command->token;
        pi_uv_close_worker(endpoint);
        return 0;
    }
    if (endpoint->closing || endpoint->closed) return UV_EBADF;
    int status;
    switch (command->kind) {
    case PI_UV_CMD_BIND:
        return uv_tcp_bind(&endpoint->tcp, (const struct sockaddr *)&command->address,
                           command->number);
    case PI_UV_CMD_LISTEN:
        return uv_listen((uv_stream_t *)&endpoint->tcp, command->flag, pi_uv_connection);
    case PI_UV_CMD_READ_START:
        endpoint->read_wanted = 1;
        return pi_uv_resume_read_worker(endpoint);
    case PI_UV_CMD_READ_STOP:
        endpoint->read_wanted = 0;
        status = uv_read_stop((uv_stream_t *)&endpoint->tcp);
        if (status == 0) endpoint->reading = 0;
        return status;
    case PI_UV_CMD_WRITE:
        request->uv.write.data = request;
        status = uv_write(&request->uv.write, (uv_stream_t *)&endpoint->tcp,
                          &request->buffer, 1, pi_uv_written);
        break;
    case PI_UV_CMD_SHUTDOWN:
        request->uv.shutdown.data = request;
        status = uv_shutdown(&request->uv.shutdown, (uv_stream_t *)&endpoint->tcp,
                             pi_uv_shutdown_completed);
        break;
    case PI_UV_CMD_CONNECT:
        request->uv.connect.data = request;
        status = uv_tcp_connect(&request->uv.connect, &endpoint->tcp,
                    (const struct sockaddr *)&command->address, pi_uv_connected);
        break;
    case PI_UV_CMD_REF:
        if (command->flag) uv_ref((uv_handle_t *)&endpoint->tcp);
        else uv_unref((uv_handle_t *)&endpoint->tcp);
        return 0;
    case PI_UV_CMD_NODELAY:
        return uv_tcp_nodelay(&endpoint->tcp, command->flag);
    case PI_UV_CMD_KEEPALIVE:
        return uv_tcp_keepalive(&endpoint->tcp, command->flag, command->number);
    case PI_UV_CMD_ADDRESS:
        return pi_uv_address_worker(endpoint, command->flag, command->address_result);
    default:
        return UV_EINVAL;
    }
    if (status == 0)
        atomic_fetch_add_explicit(&service->pending_requests, 1, memory_order_release);
    return status;
}
static void pi_uv_command_ready(uv_async_t *async) {
    PiUvService *service = async->data;
    uv_mutex_lock(&service->command_mutex);
    PiUvCommand *command = service->command;
    uv_mutex_unlock(&service->command_mutex);
    if (!command) return;
    int result = pi_uv_command_run(service, command);
    pi_uv_refresh_referenced(service);
    uv_mutex_lock(&service->command_mutex);
    command->result = result;
    command->done = 1;
    service->command = NULL;
    uv_cond_broadcast(&service->command_condition);
    uv_mutex_unlock(&service->command_mutex);
}
static int pi_uv_submit(PiUvService *service, PiUvCommand *command) {
    command->done = 0;
    uv_mutex_lock(&service->command_mutex);
    while (service->command &&
           !atomic_load_explicit(&service->close_requested, memory_order_acquire))
        uv_cond_wait(&service->command_condition, &service->command_mutex);
    if (atomic_load_explicit(&service->close_requested, memory_order_acquire)) {
        uv_mutex_unlock(&service->command_mutex);
        return UV_ECANCELED;
    }
    service->command = command;
    int status = uv_async_send(&service->command_async);
    if (status < 0) {
        service->command = NULL;
        uv_cond_broadcast(&service->command_condition);
        uv_mutex_unlock(&service->command_mutex);
        return status;
    }
    while (!command->done)
        uv_cond_wait(&service->command_condition, &service->command_mutex);
    status = command->result;
    uv_mutex_unlock(&service->command_mutex);
    return status;
}
static void pi_uv_thread_main(void *opaque) {
    PiUvService *service = opaque;
    (void)uv_run(&service->loop, UV_RUN_DEFAULT);
    service->loop_close_status = uv_loop_close(&service->loop);
    pi_uv_service_release(service); /* owner is retained until stop joins */
}
PiUvResult pi_uv_service_create(void *memory_owner, PiUvWake wake, uint32_t wake_slot,
                         uint64_t wake_generation, PiUvService **result) {
    if (!memory_owner || !wake || !result) return pi_uv_result(UV_EINVAL, 0);
    *result = NULL;
    pi_js_retain_memory_owner(memory_owner);
    PiUvService *service = pi_uv_alloc(memory_owner, sizeof(*service));
    if (!service) { pi_js_release_memory_owner(memory_owner); return pi_uv_result(UV_ENOMEM, 1); }
    service->memory_owner = memory_owner;
    service->wake = wake;
    service->wake_slot = wake_slot;
    service->wake_generation = wake_generation;
    atomic_init(&service->references, 1);
    atomic_init(&service->live_handles, 0);
    atomic_init(&service->pending_requests, 0);
    atomic_init(&service->queued_events, 0);
    atomic_init(&service->referenced_handles, 0);
    atomic_init(&service->close_requested, 0);
    atomic_init(&service->thread_joined, 0);
    int status = uv_mutex_init(&service->command_mutex);
    if (status < 0) goto fail_service;
    status = uv_cond_init(&service->command_condition);
    if (status < 0) goto fail_command_mutex;
    status = uv_mutex_init(&service->event_mutex);
    if (status < 0) goto fail_condition;
    status = uv_loop_init(&service->loop);
    if (status < 0) goto fail_event_mutex;
    status = uv_async_init(&service->loop, &service->command_async, pi_uv_command_ready);
    if (status < 0) goto fail_loop;
    service->command_async.data = service;
    pi_uv_service_retain(service);
    status = uv_thread_create(&service->thread, pi_uv_thread_main, service);
    if (status < 0) {
        /* No worker exists. Close only the already initialized native async. */
        atomic_fetch_sub_explicit(&service->references, 1, memory_order_relaxed);
        uv_close((uv_handle_t *)&service->command_async, NULL);
        (void)uv_run(&service->loop, UV_RUN_DEFAULT);
        goto fail_loop;
    }
    *result = service;
    return pi_uv_result(0, 0);
fail_loop:
    (void)uv_loop_close(&service->loop);
fail_event_mutex:
    uv_mutex_destroy(&service->event_mutex);
fail_condition:
    uv_cond_destroy(&service->command_condition);
fail_command_mutex:
    uv_mutex_destroy(&service->command_mutex);
fail_service:
    pi_uv_free(memory_owner, service);
    pi_js_release_memory_owner(memory_owner);
    return pi_uv_result(status, 0);
}
int pi_uv_service_stop(PiUvService *service) {
    if (atomic_load_explicit(&service->thread_joined, memory_order_acquire))
        return service->loop_close_status;
    int status = 0;
    if (!atomic_load_explicit(&service->close_requested, memory_order_acquire)) {
        PiUvCommand command = { .kind = PI_UV_CMD_STOP };
        status = pi_uv_submit(service, &command);
        if (status < 0) return status;
    }
    status = uv_thread_join(&service->thread);
    if (status < 0) return status;
    atomic_store_explicit(&service->thread_joined, 1, memory_order_release);
    return service->loop_close_status;
}
int pi_uv_service_has_referenced(PiUvService *service) {
    return atomic_load_explicit(&service->queued_events, memory_order_acquire) != 0 ||
           atomic_load_explicit(&service->pending_requests, memory_order_acquire) != 0 ||
           atomic_load_explicit(&service->referenced_handles, memory_order_acquire) != 0;
}
PiUvSnapshot pi_uv_service_snapshot(PiUvService *service) {
    PiUvSnapshot result = {
        .live_handles = atomic_load_explicit(&service->live_handles, memory_order_acquire),
        .pending_requests = atomic_load_explicit(&service->pending_requests, memory_order_acquire),
        .queued_events = atomic_load_explicit(&service->queued_events, memory_order_acquire),
        .referenced_handles = atomic_load_explicit(&service->referenced_handles, memory_order_acquire),
        .close_requested = atomic_load_explicit(&service->close_requested, memory_order_acquire),
        .thread_joined = atomic_load_explicit(&service->thread_joined, memory_order_acquire),
        .loop_close_status = 0
    };
    if (result.thread_joined) result.loop_close_status = service->loop_close_status;
    return result;
}
PiUvEvent *pi_uv_service_next(PiUvService *service) {
    uv_mutex_lock(&service->event_mutex);
    PiUvEvent *event = service->event_head;
    if (event) {
        service->event_head = event->next;
        if (!service->event_head) service->event_tail = NULL;
        event->next = NULL;
        if (event->storage == PI_UV_FS_REQUEST) {
            PiUvFsRequest *request = event->allocation;
            /* Only actual FS dequeue admits reuse of this embedded slot.
             * Older host tickets retain independent release-only owners. */
            event->in_use = 0;
            atomic_store_explicit(&request->event_queued, 0, memory_order_release);
        }
        atomic_fetch_sub_explicit(&service->queued_events, 1, memory_order_release);
    }
    uv_mutex_unlock(&service->event_mutex);
    return event;
}
PiUvEventInfo pi_uv_event_info(const PiUvEvent *event) { return event->info; }
PiUvEndpoint *pi_uv_event_take_accepted(PiUvEvent *event) {
    if (event->info.kind != PI_UV_ACCEPT || !event->accepted) return NULL;
    PiUvEndpoint *accepted = event->accepted;
    event->accepted = NULL;
    pi_uv_endpoint_retain(accepted);
    return accepted;
}
void pi_uv_event_release(PiUvEvent *event) {
    PiUvService *service = event->service;
    PiUvEndpoint *source = event->info.source;
    PiUvEndpoint *keeper = event->keeper;
    PiUvEndpoint *unclaimed = event->accepted;
    enum PiUvStorage storage = event->storage;
    void *allocation = event->allocation;
    if (unclaimed) pi_uv_endpoint_abandon(unclaimed);
    if (storage == PI_UV_EMBED_READ) {
        event->allocation = NULL;
        event->info.bytes = NULL;
        pi_uv_free(service->memory_owner, allocation);
        PiUvCommand command = { .kind = PI_UV_CMD_READ_ACK, .endpoint = source };
        int status = pi_uv_submit(service, &command);
        assert(status == 0 || status == UV_ECANCELED);
        /* No further access to event: worker may have reused this read slot. */
    } else if (storage == PI_UV_FS_REQUEST) {
        pi_uv_fs_request_release(allocation);
    } else if (storage == PI_UV_REQUEST || storage == PI_UV_HEAP_EVENT) {
        pi_uv_free(service->memory_owner, allocation);
    } else if (storage == PI_UV_EMBED_OOM) {
        /* A fatal owner publication closes the environment before later work.
         * Clearing only through the worker would need a fresh command after
         * stop; this outstanding record is intentionally one-shot per service.
         */
    }
    if (keeper && keeper != source) pi_uv_endpoint_release(keeper);
    if (source) pi_uv_endpoint_release(source);
    pi_uv_service_release(service);
}
PiUvFsRequest *pi_uv_event_fs_request(const PiUvEvent *event) {
    return event->storage == PI_UV_FS_REQUEST ? event->allocation : NULL;
}
PiUvFsPreparationInfo pi_uv_fs_request_preparation_info(
    const PiUvFsRequest *request) {
    assert(request != NULL);
    assert(!request->submitted);
    PiUvFsPreparationInfo result = {
        .kind = request->kind,
        .accepted = request->accepted,
        .cleaned = atomic_load_explicit(&request->cleaned, memory_order_acquire),
        .completed = atomic_load_explicit(&request->completed, memory_order_acquire)
    };
    return result;
}
PiUvFsInfo pi_uv_fs_request_info(const PiUvFsRequest *request) {
    assert(atomic_load_explicit(&request->completed, memory_order_acquire));
    const int cleaned = atomic_load_explicit(&request->cleaned, memory_order_acquire);
    PiUvFsInfo result = {
        .kind = request->kind, .result = (int64_t)request->uv.result,
        .path = cleaned ? NULL : request->uv.path,
        .accepted = request->accepted, .cleaned = cleaned
    };
    return result;
}
PiUvResult pi_uv_fs_request_create(PiUvService *service, int kind,
                                     uint64_t token, PiUvFsRequest **out) {
    if (!out) return pi_uv_result(UV_EINVAL, 0);
    *out = NULL;
    if (!service || (kind != PI_UV_FS_UNASSIGNED && kind != PI_UV_FS_READ &&
                     kind != PI_UV_FS_OPEN && kind != PI_UV_FS_CLOSE))
        return pi_uv_result(UV_EINVAL, 0);
    PiUvFsRequest *request = pi_uv_fs_request_allocate(service, kind, token);
    if (!request) return pi_uv_result(UV_ENOMEM, 1);
    *out = request;
    return pi_uv_result(0, 0);
}
static int pi_uv_fs_submit(PiUvFsRequest *request, PiUvCommand *command, int kind) {
    /* Generic FSReqCallback storage receives its actual operation only after
     * all native input/state checks, at the same real admission cutpoint. */
    assert(request->storage_kind == PI_UV_FS_UNASSIGNED || request->storage_kind == kind);
    request->kind = kind;
    request->submitted = 1;
    const int status = pi_uv_submit(request->service, command);
    if (status < 0 && !request->entered) {
        request->uv.result = status;
        request->uv.path = NULL;
        atomic_store_explicit(&request->completed, 1, memory_order_release);
    }
    return status;
}
static int pi_uv_fs_unsubmitted(PiUvFsRequest *request, int kind) {
    return request && (request->storage_kind == PI_UV_FS_UNASSIGNED ||
                       request->storage_kind == kind) && !request->submitted &&
        !atomic_load_explicit(&request->cleaned, memory_order_acquire);
}
int pi_uv_fs_request_reset(PiUvFsRequest *request) {
    if (!request) return UV_EINVAL;
    /* Initial ReqWrap::Reset has no completed native operation to clean. */
    if (!request->submitted)
        return atomic_load_explicit(&request->cleaned, memory_order_acquire)
            ? UV_EBUSY : 0;
    if (!atomic_load_explicit(&request->completed, memory_order_acquire) ||
        !atomic_load_explicit(&request->cleaned, memory_order_acquire) ||
        atomic_load_explicit(&request->event_queued, memory_order_acquire))
        return UV_EBUSY;
    assert(request->previous == NULL && request->next == NULL);
    assert(request->backing.owner == NULL);
    /* The prior event was taken from the FIFO. Its independent entitlement
     * may still be alive in the host callback, but release reads only stable
     * service/storage/allocation/source fields. Do not reinitialize that event
     * or clear its next link: a new completion can already occupy the FIFO
     * when the prior event entitlement is finally retired. */
    request->uv.data = NULL;
    request->submitted = 0;
    request->entered = 0;
    request->accepted = 0;
    request->event.info.status = 0;
    request->event.info.length = 0;
    atomic_store_explicit(&request->completed, 0, memory_order_release);
    atomic_store_explicit(&request->cleaned, 0, memory_order_release);
    return 0;
}
int pi_uv_fs_read_buffer(PiUvFsRequest *request, int descriptor,
    char *base, size_t length, int64_t position) {
    if (!pi_uv_fs_unsubmitted(request, PI_UV_FS_READ) ||
        (!base && length)) return UV_EINVAL;
#if defined(_WIN32)
    if (length > ULONG_MAX) return UV_EINVAL;
#endif
    /* Copy the actual caller's uv_buf_t fields without a JS lease or wrapper.
     * Its native owner, normally Environment's managed table, retains these
     * bytes through the real uv callback and native request cleanup. */
    request->descriptor = descriptor;
    request->buffer.base = base;
    request->buffer.len = length;
    request->position = position;
    PiUvCommand command = { .kind = PI_UV_CMD_FS_READ, .fs_request = request };
    return pi_uv_fs_submit(request, &command, PI_UV_FS_READ);
}
int pi_uv_fs_read(PiUvFsRequest *request, int descriptor,
    const JSPiArrayBufferLease *backing, size_t offset, uint32_t length,
    int64_t position) {
    if (!pi_uv_fs_unsubmitted(request, PI_UV_FS_READ) ||
        !backing || !backing->owner || length > INT_MAX ||
        offset > backing->byte_length || length > backing->byte_length - offset)
        return UV_EINVAL;
    JS_PiDupArrayBufferLease(&request->backing, backing);
    unsigned char *bytes = request->backing.data;
    if (offset) bytes += offset;
    request->descriptor = descriptor;
    request->buffer = uv_buf_init((char *)bytes, length);
    request->position = position;
    PiUvCommand command = { .kind = PI_UV_CMD_FS_READ, .fs_request = request };
    return pi_uv_fs_submit(request, &command, PI_UV_FS_READ);
}
int pi_uv_fs_open(PiUvFsRequest *request, const char *path, int flags,
                  int mode) {
    if (!pi_uv_fs_unsubmitted(request, PI_UV_FS_OPEN) || !path) return UV_EINVAL;
    request->flags = flags;
    request->mode = mode;
    PiUvCommand command = { .kind = PI_UV_CMD_FS_OPEN, .fs_request = request,
                            .path = path };
    /* Command completion proves libuv has copied every path byte it needs.
     * The borrowed input does not escape this synchronous admission call. */
    return pi_uv_fs_submit(request, &command, PI_UV_FS_OPEN);
}
int pi_uv_fs_close(PiUvFsRequest *request, int descriptor) {
    if (!pi_uv_fs_unsubmitted(request, PI_UV_FS_CLOSE)) return UV_EINVAL;
    request->descriptor = descriptor;
    PiUvCommand command = { .kind = PI_UV_CMD_FS_CLOSE, .fs_request = request };
    return pi_uv_fs_submit(request, &command, PI_UV_FS_CLOSE);
}
int pi_uv_fs_close_sync(PiUvService *service, struct uv_fs_s *request,
                        int descriptor) {
    assert(service != NULL && request != NULL);
    /* cb == NULL follows the actual synchronous libuv FS implementation.
     * No service command, queued completion, callback, or waiting count is
     * involved. The original caller traces and cleans its own stack request. */
    return uv_fs_close(&service->loop, request, descriptor, NULL);
}
int pi_uv_fs_cancel(PiUvFsRequest *request) {
    PiUvCommand command = { .kind = PI_UV_CMD_FS_CANCEL, .fs_request = request };
    return pi_uv_submit(request->service, &command);
}
PiUvResult pi_uv_tcp_create(PiUvService *service, PiUvEndpoint **result) {
    if (!result) return pi_uv_result(UV_EINVAL, 0);
    *result = NULL;
    PiUvEndpoint *endpoint = pi_uv_endpoint_allocate(service);
    if (!endpoint) return pi_uv_result(UV_ENOMEM, 1);
    PiUvCommand command = { .kind = PI_UV_CMD_INIT, .endpoint = endpoint };
    int status = pi_uv_submit(service, &command);
    if (status < 0) { pi_uv_endpoint_release(endpoint); return pi_uv_result(status, 0); }
    endpoint->exposed = 1; /* worker is idle until the next admitted command */
    *result = endpoint;
    return pi_uv_result(0, 0);
}
void pi_uv_endpoint_abandon(PiUvEndpoint *endpoint) {
    PiUvCommand command = { .kind = PI_UV_CMD_CLOSE, .endpoint = endpoint };
    (void)pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_bind(PiUvEndpoint *endpoint, const char *address,
                   unsigned int port, unsigned int flags) {
    PiUvCommand command = { .kind = PI_UV_CMD_BIND, .endpoint = endpoint, .number = flags };
    int status = pi_uv_numeric_address(address, port, &command.address);
    return status < 0 ? status : pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_listen(PiUvEndpoint *endpoint, int backlog) {
    PiUvCommand command = { .kind = PI_UV_CMD_LISTEN, .endpoint = endpoint, .flag = backlog };
    return pi_uv_submit(endpoint->service, &command);
}
PiUvResult pi_uv_tcp_connect(PiUvEndpoint *endpoint, const char *address,
                      unsigned int port, uint64_t token) {
    PiUvCommand command = { .kind = PI_UV_CMD_CONNECT, .endpoint = endpoint };
    int status = pi_uv_numeric_address(address, port, &command.address);
    if (status < 0) return pi_uv_result(status, 0);
    command.request = pi_uv_request_allocate(endpoint, PI_UV_CONNECT, token, 0);
    if (!command.request) return pi_uv_result(UV_ENOMEM, 1);
    status = pi_uv_submit(endpoint->service, &command);
    if (status < 0) pi_uv_request_discard(command.request);
    return pi_uv_result(status, 0);
}
int pi_uv_tcp_read_start(PiUvEndpoint *endpoint) {
    PiUvCommand command = { .kind = PI_UV_CMD_READ_START, .endpoint = endpoint };
    return pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_read_stop(PiUvEndpoint *endpoint) {
    PiUvCommand command = { .kind = PI_UV_CMD_READ_STOP, .endpoint = endpoint };
    return pi_uv_submit(endpoint->service, &command);
}
PiUvResult pi_uv_tcp_write(PiUvEndpoint *endpoint, const unsigned char *bytes,
                    size_t length, uint64_t token) {
    if (length > UINT_MAX || (!bytes && length)) return pi_uv_result(UV_EINVAL, 0);
    PiUvRequest *request = pi_uv_request_allocate(endpoint, PI_UV_WRITE, token, length);
    if (!request) return pi_uv_result(UV_ENOMEM, 1);
    unsigned char *copy = (unsigned char *)(request + 1);
    if (length) memcpy(copy, bytes, length);
    request->buffer = uv_buf_init((char *)copy, (unsigned int)length);
    PiUvCommand command = { .kind = PI_UV_CMD_WRITE, .endpoint = endpoint, .request = request };
    int status = pi_uv_submit(endpoint->service, &command);
    if (status < 0) pi_uv_request_discard(request);
    return pi_uv_result(status, 0);
}
PiUvResult pi_uv_tcp_shutdown(PiUvEndpoint *endpoint, uint64_t token) {
    PiUvRequest *request = pi_uv_request_allocate(endpoint, PI_UV_SHUTDOWN, token, 0);
    if (!request) return pi_uv_result(UV_ENOMEM, 1);
    PiUvCommand command = { .kind = PI_UV_CMD_SHUTDOWN, .endpoint = endpoint, .request = request };
    int status = pi_uv_submit(endpoint->service, &command);
    if (status < 0) pi_uv_request_discard(request);
    return pi_uv_result(status, 0);
}
int pi_uv_tcp_close(PiUvEndpoint *endpoint, uint64_t token) {
    PiUvCommand command = { .kind = PI_UV_CMD_CLOSE, .endpoint = endpoint, .token = token };
    return pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_set_referenced(PiUvEndpoint *endpoint, int referenced) {
    PiUvCommand command = { .kind = PI_UV_CMD_REF, .endpoint = endpoint, .flag = referenced };
    return pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_nodelay(PiUvEndpoint *endpoint, int enabled) {
    PiUvCommand command = { .kind = PI_UV_CMD_NODELAY, .endpoint = endpoint, .flag = enabled };
    return pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_keepalive(PiUvEndpoint *endpoint, int enabled, unsigned int delay) {
    PiUvCommand command = { .kind = PI_UV_CMD_KEEPALIVE, .endpoint = endpoint,
                            .flag = enabled, .number = delay };
    return pi_uv_submit(endpoint->service, &command);
}
int pi_uv_tcp_address(PiUvEndpoint *endpoint, int peer, PiUvAddress *result) {
    if (!result) return UV_EINVAL;
    PiUvCommand command = { .kind = PI_UV_CMD_ADDRESS, .endpoint = endpoint,
                            .flag = peer, .address_result = result };
    return pi_uv_submit(endpoint->service, &command);
}
const char *pi_uv_error_name(int status) { return uv_err_name(status); }
const char *pi_uv_error_message(int status) { return uv_strerror(status); }
