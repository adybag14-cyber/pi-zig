#ifndef PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_HPP
#define PI_NATIVE_NODE_DIAGNOSTIC_CONTEXT_HPP
#include "native_node_diagnostic_context.h"

namespace pi::node {
/* Declare first in the immediate synchronous ABI body, so all later locals
 * retire before the borrowed diagnostic context is restored. */
class DiagnosticContextScope final {
 public:
    explicit DiagnosticContextScope(JSContext *context) noexcept
        : previous_(pi_node_diagnostic_context_enter(context)) {}
    ~DiagnosticContextScope() noexcept {
        pi_node_diagnostic_context_leave(previous_);
    }
    DiagnosticContextScope(const DiagnosticContextScope&) = delete;
    DiagnosticContextScope& operator=(const DiagnosticContextScope&) = delete;
    DiagnosticContextScope(DiagnosticContextScope&&) = delete;
    DiagnosticContextScope& operator=(DiagnosticContextScope&&) = delete;
 private:
    JSContext *const previous_;
};
}
#endif
