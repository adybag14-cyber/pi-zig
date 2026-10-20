#include "native_node_diagnostic_context.hpp"
#include "native_node_diagnostic_context_test_support.h"

namespace {
struct ObserveRetirement {
    JSContext *expected;
    uint32_t *observed;
    uint32_t bit;
    ~ObserveRetirement() {
        if (pi_node_diagnostic_context_current() == expected)
            *observed |= bit;
    }
};
void scoped(JSContext *outer, JSContext *inner, bool return_early,
            uint32_t *observed) {
    pi::node::DiagnosticContextScope outer_scope(outer);
    ObserveRetirement outer_retirement{outer, observed, 4};
    if (pi_node_diagnostic_context_current() == outer) *observed |= 1;
    {
        pi::node::DiagnosticContextScope inner_scope(inner);
        ObserveRetirement inner_retirement{inner, observed, 8};
        if (pi_node_diagnostic_context_current() == inner) *observed |= 2;
        if (return_early) return;
    }
    if (pi_node_diagnostic_context_current() == outer) *observed |= 16;
}
}
extern "C" uint32_t pi_node_test_diagnostic_context_scope(
    JSContext *outer, JSContext *inner, int return_early) {
    JSContext *before = pi_node_diagnostic_context_current();
    uint32_t observed = 0;
    scoped(outer, inner, return_early != 0, &observed);
    if (pi_node_diagnostic_context_current() == before) observed |= 32;
    return observed;
}
