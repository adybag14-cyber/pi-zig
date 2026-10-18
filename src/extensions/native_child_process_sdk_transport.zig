//! Actual SDK package-manager process dependencies from the canonical public
//! child graph. Bootstrap remains explicit; no placeholder module or fake child.
const js = @import("native_js_values.zig");
const c = js.c;
const public = @import("native_node_child_process_public.zig");
const functions = @import("native_child_process_function.zig");
const completion = @import("native_sdk_owned_completion.zig");
pub const Inputs = public.Inputs;
pub const Exports = struct {
    child: public.Bundle,
    utilities: c.JSValue,
    pub fn deinit(self: Exports, engine: *js.Engine) void { engine.freeValue(self.utilities); self.child.deinit(engine); }
    pub fn retireInto(self: Exports, selected: anytype) void { selected.release(self.utilities); retireChild(selected, self.child); }
};
fn createInner(engine: *js.Engine, inputs: Inputs) !Exports {
    const child = try public.create(engine, inputs);
    errdefer |err| { var failed = completion.Completion.initVoid(engine, err); retireChild(&failed, child); failed.finishVoid() catch {}; }
    const utilities = try @import("native_sdk_child_process_utils.zig").createWithNamespaces(engine, child.node, child.cross_spawn, inputs.process);
    return .{ .child = child, .utilities = utilities };
}
pub fn create(engine: *js.Engine, inputs: Inputs) !Exports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    const generation = engine.native_allocation_generation;
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = createInner(engine, inputs) catch |err| {
        const failure = functions.directFailure(engine, err, generation);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return actual;
        return @as(anyerror!Exports, failure);
    };
    const terminal = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    if (c.JS_IsException(terminal) or c.JS_HasException(engine.context)) {
        var failed = completion.Completion.initVoid(engine, error.JavaScriptException);
        result.retireInto(&failed); try failed.finishVoid(); unreachable;
    }
    return result;
}

pub const ProcessImports = struct {
    spawn_process: c.JSValue, spawn_process_sync: c.JSValue, is_stdout_taken_over: c.JSValue,
    pub fn deinit(self: ProcessImports, engine: *js.Engine) void { inline for (@import("std").meta.fields(ProcessImports)) |field| engine.freeValue(@field(self, field.name)); }
};
pub const FrontendExports = struct {
    transport: Exports,
    output_guard: @import("native_sdk_output_guard.zig").Exports,
    process_imports: ProcessImports,
    pub fn deinit(self: FrontendExports, engine: *js.Engine) void { self.process_imports.deinit(engine); self.output_guard.deinit(engine); self.transport.deinit(engine); }
    pub fn retireInto(self: FrontendExports, selected: anytype) void {
        inline for (@import("std").meta.fields(ProcessImports)) |field| selected.release(@field(self.process_imports, field.name));
        retireGuard(selected, self.output_guard); self.transport.retireInto(selected);
    }
    /// Source main/RPC owns this actual transition. It must supply the real
    /// resolved mode/metadata decision; query never infers a flag from mode.
    pub fn takeOverStdout(self: FrontendExports, engine: *js.Engine) !void {
        var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        _ = try scope.call(self.output_guard.take_over_stdout, c.pi_js_undefined(), &.{});
    }
    pub fn restoreStdout(self: FrontendExports, engine: *js.Engine) !void {
        var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
        _ = try scope.call(self.output_guard.restore_stdout, c.pi_js_undefined(), &.{});
    }
};
fn createFrontendInner(engine: *js.Engine, inputs: Inputs) anyerror!FrontendExports {
    const lease = inputs.stdio_source orelse return error.RequiredActualSdkFrontendLease;
    var scope: @import("native_node_socket_scope.zig").Scope = .{ .engine = engine }; defer scope.deinit(); errdefer |err| scope.captureUnwind(err);
    const output_guard = try @import("native_sdk_output_guard.zig").create(engine, inputs.process, lease);
    errdefer |err| { var failed = completion.Completion.initVoid(engine, err); retireGuard(&failed, output_guard); failed.finishVoid() catch {}; }
    const transport = try create(engine, inputs);
    errdefer |err| { var failed = completion.Completion.initVoid(engine, err); transport.retireInto(&failed); failed.finishVoid() catch {}; }
    errdefer |err| scope.captureUnwind(err);
    const spawn_process = try scope.get(transport.utilities, "spawnProcess");
    const spawn_process_sync = try scope.get(transport.utilities, "spawnProcessSync");
    return .{ .transport = transport, .output_guard = output_guard, .process_imports = .{
        .spawn_process = c.JS_DupValue(engine.context, spawn_process),
        .spawn_process_sync = c.JS_DupValue(engine.context, spawn_process_sync),
        .is_stdout_taken_over = c.JS_DupValue(engine.context, output_guard.is_stdout_taken_over),
    } };
}
/// Real package-manager transport imports include the SAME Source takeover
/// query used by frontend takeOver/restore. No unbound/constantfalse fallback.
pub fn createForFrontend(engine: *js.Engine, inputs: Inputs) anyerror!FrontendExports {
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = createFrontendInner(engine, inputs) catch |err| {
        const failure = functions.directFailure(engine, err, engine.native_allocation_generation);
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |actual| return actual;
        return @as(anyerror!FrontendExports, failure);
    };
    const terminal = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    if (c.JS_IsException(terminal) or c.JS_HasException(engine.context)) {
        var failed = completion.Completion.initVoid(engine, error.JavaScriptException);
        result.retireInto(&failed); try failed.finishVoid(); unreachable;
    }
    return result;
}

fn retireChild(selected: anytype, child: public.Bundle) void {
    inline for (.{ "node", "cross_spawn", "net" }) |name| selected.release(@field(child, name));
}
fn retireGuard(selected: anytype, guard: @import("native_sdk_output_guard.zig").Exports) void {
    inline for (@import("std").meta.fields(@TypeOf(guard))) |field| selected.release(@field(guard, field.name));
}
