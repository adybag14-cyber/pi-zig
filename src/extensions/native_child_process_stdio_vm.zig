//! Actual asynchronous getValidStdio VM descriptors. Pipe handles are genuine
//! unbound native records consumed/bound by native Process.spawn later.
const js = @import("native_js_values.zig");
const c = js.c;
const frontier = @import("native_child_process_scope.zig");
const Scope = frontier.Scope;
const fnc = @import("native_child_process_function.zig");
const pipe = @import("native_child_process_pipe_record.zig");
pub const Inputs = struct {
    pipes: *pipe.Provider,
    array_push: c.JSValue, array_reduce: c.JSValue, is_view: c.JSValue,
};
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn equal(scope: *Scope, value: c.JSValue, text: []const u8) !bool { return scope.equal(value, try scope.text(text)); }
fn length(scope: *Scope, array: c.JSValue) !u32 { var value: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &value, try scope.get(array, "length")) < 0) return @as(anyerror!u32, js.capture(scope.engine)); try frontier.pending(scope.engine); return value; }
fn element(scope: *Scope, array: c.JSValue, index: u32) !c.JSValue { return scope.getIndex(array, index); }
fn cleanup(scope: *Scope, array: c.JSValue) !void {
    var index: u32 = 0;
    while (index < try length(scope, array)) : (index += 1) {
        const item = try element(scope, array, index); const kind = try scope.get(item, "type");
        if ((try equal(scope, kind, "pipe")) or (try equal(scope, kind, "ipc"))) {
            const handle = try scope.get(item, "handle");
            if (scope.truthy(handle)) _ = try scope.invoke(handle, "close", &.{});
        }
    }
}
fn wrap(scope: *Scope, value: c.JSValue, brand: c.JSValue) !bool {
    var id: u32 = 0; if (c.JS_ToUint32(scope.engine.context, &id, brand) < 0) return @as(anyerror!bool, js.capture(scope.engine));
    const state: *pipe.State = @ptrCast(@alignCast(c.JS_GetOpaque(value, id) orelse return false));
    return state.engine == scope.engine and scope.equal(state.handle, value);
}
fn invalid(engine: *js.Engine, code: []const u8, message: []const u8) anyerror { return @import("node_events.zig").codedError(engine, "TypeError", code, message); }
fn reduce(engine: *js.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const accumulator = arg(args, 0); var value = arg(args, 1); const index_value = arg(args, 2);
    var index: u32 = 0; if (c.JS_ToUint32(engine.context, &index, index_value) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    if (c.JS_IsNull(value) or c.JS_IsUndefined(value)) value = try scope.text(if (index < 3) "pipe" else "ignore");
    var descriptor: c.JSValue = undefined;
    if (try equal(&scope, value, "ignore")) {
        descriptor = try scope.object(); try scope.put(descriptor, "type", try scope.text("ignore"));
    } else if ((try equal(&scope, value, "pipe")) or (try equal(&scope, value, "overlapped")) or (c.JS_IsNumber(value) and scope.truthy(try frontier.binary(&scope, 4, value, c.JS_NewInt32(engine.context, 0))))) {
        descriptor = try scope.object();
        try scope.put(descriptor, "type", if (try equal(&scope, value, "overlapped")) value else try scope.text("pipe"));
        try scope.put(descriptor, "readable", c.pi_js_bool(engine.context, @intFromBool(index == 0)));
        try scope.put(descriptor, "writable", c.pi_js_bool(engine.context, @intFromBool(index != 0)));
        const handle = try scope.construct(roots[0], &.{});
        try scope.put(descriptor, "handle", handle);
    } else if (try equal(&scope, value, "ipc")) {
        try cleanup(&scope, accumulator);
        return error.RequiredGenuineNativeIpcPipeProvider;
    } else if (try equal(&scope, value, "inherit")) {
        descriptor = try scope.object(); try scope.put(descriptor, "type", value); try scope.put(descriptor, "fd", index_value);
    } else if (c.JS_IsNumber(value) or c.JS_IsNumber(try scope.get(value, "fd"))) {
        descriptor = try scope.object(); try scope.put(descriptor, "type", try scope.text("fd"));
        try scope.put(descriptor, "fd", if (c.JS_IsNumber(value)) value else try scope.get(value, "fd"));
    } else {
        // Match the Source short-circuit getter order. Only genuine Pipe record
        // brands are available here; other native wrap providers remain explicit.
        const direct = try wrap(&scope, value, roots[1]);
        const nested = if (direct) c.pi_js_undefined() else try scope.get(value, "handle");
        const nested_pipe = if (direct) false else try wrap(&scope, nested, roots[1]);
        const private = if (direct or nested_pipe) c.pi_js_undefined() else try scope.get(value, "_handle");
        if (direct or nested_pipe or try wrap(&scope, private, roots[1])) {
            // Source re-reads the selected live accessors after the condition.
            const handle = if (try wrap(&scope, value, roots[1])) value else if (try wrap(&scope, try scope.get(value, "handle"), roots[1])) try scope.get(value, "handle") else try scope.get(value, "_handle");
            descriptor = try scope.object(); try scope.put(descriptor, "type", try scope.text("wrap"));
            try scope.put(descriptor, "wrapType", try scope.text("pipe")); try scope.put(descriptor, "handle", handle); try scope.put(descriptor, "_stdio", value);
        } else {
            const view = scope.truthy(try scope.call(roots[3], c.pi_js_undefined(), &.{value}));
            try cleanup(&scope, accumulator);
            if (view or c.JS_IsString(value)) return @as(anyerror!c.JSValue, invalid(engine, "ERR_INVALID_SYNC_FORK_INPUT", "Asynchronous child stdio cannot contain input data"));
            return @as(anyerror!c.JSValue, invalid(engine, "ERR_INVALID_ARG_VALUE", "Invalid child stdio value"));
        }
    }
    _ = try scope.call(roots[2], accumulator, &.{descriptor});
    return c.JS_DupValue(engine.context, accumulator);
}
pub fn normalize(engine: *js.Engine, supplied: c.JSValue, inputs: Inputs) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try frontier.pending(engine);
    if (inputs.pipes.engine != engine) return error.NativePipeRecordOwner;
    var scope: Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err); var stdio = supplied;
    if (c.JS_IsString(stdio)) {
        if (!(try equal(&scope, stdio, "pipe")) and !(try equal(&scope, stdio, "ignore")) and !(try equal(&scope, stdio, "inherit")) and !(try equal(&scope, stdio, "overlapped"))) return @as(anyerror!c.JSValue, invalid(engine, "ERR_INVALID_ARG_VALUE", "Invalid child stdio shortcut"));
        const shortcut = stdio; stdio = try scope.array();
        if (try equal(&scope, shortcut, "inherit")) _ = try scope.call(inputs.array_push, stdio, &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewInt32(engine.context, 1), c.JS_NewInt32(engine.context, 2) })
        else _ = try scope.call(inputs.array_push, stdio, &.{ shortcut, shortcut, shortcut });
    } else if (!c.JS_IsArray(stdio)) return @as(anyerror!c.JSValue, invalid(engine, "ERR_INVALID_ARG_VALUE", "Child stdio must be an Array or supported shortcut"));
    while (scope.truthy(try frontier.binary(&scope, 4, try scope.get(stdio, "length"), c.JS_NewInt32(engine.context, 3)))) {
        _ = try scope.call(inputs.array_push, stdio, &.{c.pi_js_undefined()});
    }
    const roots = [_]c.JSValue{ inputs.pipes.constructor, c.JS_NewUint32(engine.context, inputs.pipes.brand), inputs.array_push, inputs.is_view };
    const callback = try scope.own(try fnc.createArrow(engine, "", 3, reduce, &roots));
    const accumulator = try scope.array();
    const value = try scope.call(inputs.array_reduce, stdio, &.{ callback, accumulator });
    const result = try scope.object(); try scope.put(result, "stdio", value);
    try scope.put(result, "ipc", c.pi_js_undefined()); try scope.put(result, "ipcFd", c.pi_js_undefined());
    return c.JS_DupValue(engine.context, result);
}
