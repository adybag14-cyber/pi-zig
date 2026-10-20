#ifndef PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_TEST_SUPPORT_H
#define PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_TEST_SUPPORT_H
#include "native_node_diagnostic_context.h"
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
uint32_t pi_node_test_diagnostic_context_scope(
    JSContext *outer, JSContext *inner, int return_early);
#ifdef __cplusplus
}
#endif
#endif
