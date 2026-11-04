//! A persistent worker turn retains actual native producers across callback
//! cleanup. A captured guest diagnostic alone never establishes fatality.
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_operation_scope.zig").Scope;

fn body(stage: *Scope, comptime action: anytype, args: anytype) !c.JSValue {
    // Start the stack NativeInvocation before the actual owner operation.
    try stage.pending();
    if (@import("native_tui_win32_clipboard_promise.zig").hasFailed(stage.engine))
        return error.NativeClipboardCompletionFailed;
    try @call(.auto, action, args);
    if (@import("native_tui_win32_clipboard_promise.zig").hasFailed(stage.engine))
        return error.NativeClipboardCompletionFailed;
    return c.pi_js_undefined();
}
pub fn run(engine: *js.Engine, comptime action: anytype, args: anytype) !void {
    var stage = Scope.init(engine);
    const returned = stage.finish(body(&stage, action, args)) catch |err| {
        // Boundary.fatal was set only by owned actual pending events or its
        // independently retained NativeInvocation. Escaping diagnostic DATA
        // cannot set it. A private termination keeps its explicit error union.
        // A failed private delivery is terminal ownership even when a guest
        // reason remains ordinary. Do not infer fatality from that diagnostic.
        if (@import("native_tui_win32_clipboard_promise.zig").hasFailed(engine) or
            err == error.NativeClipboardCompletionFailed or
            stage.boundary.fatal or err == error.ExecutionTerminated or err == error.OutOfMemory)
            return error.NativeWorkerFatal;
        return err;
    };
    engine.freeValue(returned);
}
