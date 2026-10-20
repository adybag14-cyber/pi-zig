/* Selected native diagnostic admission. See the retained V8/Node source proof.
 * This projects an already-entered caller; it does not enter or own a VM. */
#ifndef PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_H
#define PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_H

typedef struct JSContext JSContext;
#ifdef __cplusplus
extern "C" {
#endif

/* Borrow for this synchronous call only. The caller must restore the returned
 * previous pointer before its supplied context can retire. NULL explicitly
 * masks an outer admission. No value, context or runtime entitlement is taken. */
JSContext *pi_node_diagnostic_context_enter(JSContext *context);
void pi_node_diagnostic_context_leave(JSContext *previous);
JSContext *pi_node_diagnostic_context_current(void);

#ifdef __cplusplus
}
#endif
#endif
