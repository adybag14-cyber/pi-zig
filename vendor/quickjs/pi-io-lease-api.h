/* Private embedding capability. REVIEW ONLY; no existing caller is switched. */
typedef struct JSPiIOLease JSPiIOLease;
typedef enum {
    JS_PI_IO_READ, JS_PI_IO_WRITE, JS_PI_IO_READV, JS_PI_IO_WRITEV
} JSPiIOOperation;
typedef enum {
    JS_PI_IO_READY, JS_PI_IO_PAGE_BOUNDARY, JS_PI_IO_RETIRED_MAPPING,
    JS_PI_IO_EXTERNAL_UNAVAILABLE, JS_PI_IO_EXTERNAL_PROTOCOL
} JSPiIOReason;
typedef struct {
    JSPiIOReason reason;
    JSPiIOOperation operation;
    size_t vector_index, offset, length, available;
} JSPiIOStatus;
/* Explicit qualification-only activation; all existing SAB wrappers are
 * attached transactionally before enabling new constructor accounting. */
int JS_PiEnableSABIOAccounting(JSContext *);
size_t JS_PiSABIOChargedBytes(JSRuntime *);
size_t JS_PiSABIOGenerations(JSRuntime *);
size_t JS_PiIOOwnedGenerations(JSRuntime *);
size_t JS_PiIOMappingCharge(JSRuntime *);
size_t JS_PiIOTransferCleanups(JSRuntime *);
typedef struct {
    void *opaque;
    size_t allocation_unit;
    size_t commit_page_size;
    void *(*create)(void *, size_t maximum, size_t initial, size_t qjs_available,
                    void **data, size_t *exact_charge);
    int (*grow)(void *, void *handle, size_t logical, size_t qjs_available,
                size_t *exact_charge);
    int (*trim)(void *, void *handle, size_t retained_end, size_t *exact_charge);
    void (*release)(void *, void *handle);
} JSPiIOMapHooks;
/* External providers must retain the ACTUAL admitted allocation, including
 * across the original callback's resize/detach/free. No copying fallback.
 * pin/release execute on the VM owner; status is worker-safe and must not
 * allocate, call JS, or dereference reclaimed storage. Its token owns its span. */
typedef struct {
    void *(*pin)(JSContext *, void *opaque, JSValueConst backing,
                  size_t offset, size_t length, int destination, uint8_t **data);
    void (*status)(void *token, JSPiIOOperation, size_t vector_index, JSPiIOStatus *);
    void (*release)(JSRuntime *, void *token);
} JSPiIOExternalHooks;
int JS_PiAcquireIOLease(JSContext *, JSValueConst backing, size_t offset,
                        size_t length, int destination, const JSPiIOMapHooks *,
                        JSPiIOLease **out);
int JS_PiAcquireExternalIOLease(JSContext *, JSValueConst backing, size_t offset,
                                size_t length, int destination,
                                const JSPiIOExternalHooks *, void *opaque,
                                JSPiIOLease **out);
uint8_t *JS_PiIOLeaseData(const JSPiIOLease *);
size_t JS_PiIOLeaseLength(const JSPiIOLease *);
void JS_PiIOLeaseStatus(const JSPiIOLease *, JSPiIOOperation, size_t vector_index,
                        JSPiIOStatus *);
void JS_PiReleaseIOLease(JSRuntime *, JSPiIOLease *);
