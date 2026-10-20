/* Native projection of the selected current-isolate/current-context guards.
 * The entering ABI already knows the live caller. Workers start with no
 * admission, and no Agent, task or callback stores this borrowed pointer. */
#include "native_node_diagnostic_context.h"
#include <stddef.h>

static _Thread_local JSContext *pi_node_current_diagnostic_context = NULL;

JSContext *pi_node_diagnostic_context_enter(JSContext *context) {
    JSContext *previous = pi_node_current_diagnostic_context;
    pi_node_current_diagnostic_context = context;
    return previous;
}

void pi_node_diagnostic_context_leave(JSContext *previous) {
    pi_node_current_diagnostic_context = previous;
}

JSContext *pi_node_diagnostic_context_current(void) {
    return pi_node_current_diagnostic_context;
}
