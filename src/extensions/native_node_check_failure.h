/* Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
 * Native Node default failure path. These functions never dispatch guest events.
 * The exported declarations deliberately omit a noreturn attribute so that
 * native stack collection retains a real caller frame, as in Node util.h. */
#ifndef PI_NATIVE_NODE_CHECK_FAILURE_H
#define PI_NATIVE_NODE_CHECK_FAILURE_H
#include "quickjs.h"
#ifdef __cplusplus
extern "C" {
#endif
typedef void (*PiNodeFatalReport)(void *opaque, JSContext *context,
                                  const char *message, const char *trigger,
                                  const char *filename);
typedef struct PiNodeFatalDiagnostics {
    /* NULL selects the actual default report-on-fatalerror=false branch.
       A non-NULL callback is the embedding's genuine native report owner. */
    PiNodeFatalReport report;
    void *report_opaque;
} PiNodeFatalDiagnostics;
typedef struct PiNodeAssertionInfo {
    const char *file_line;
    const char *message;
    const char *function;
} PiNodeAssertionInfo;
/* Only for an actual failed intrinsic allocation whose current occurrence is
 * established by the caller. No Error value or historical flag is accepted. */
void pi_node_heap_out_of_memory(JSContext *context,
                                const PiNodeFatalDiagnostics *diagnostics);
/* Terminal callback for actual external BackingStore allocation failure after
 * the embedding's native retry policy. This entry does not perform retries. */
void pi_node_backing_store_out_of_memory(JSContext *context,
                                         const PiNodeFatalDiagnostics *diagnostics);
void pi_node_maybe_check_failure(JSContext *context,
                                 const PiNodeFatalDiagnostics *diagnostics);
void pi_node_assert_failure(JSContext *context,
                            const PiNodeAssertionInfo *info);
void pi_node_default_fatal_error(JSContext *context, const char *location,
                                 const char *message,
                                 const PiNodeFatalDiagnostics *diagnostics);
void pi_node_corrupted_async_stack(JSContext *context, double actual,
                                   double expected, int abort_on_uncaught);
#ifdef __cplusplus
}
#endif
#endif
