//! Trusted bootstrap capture for the actual public child/SDK frontend graph.
//! Invoke before guest code can replace realm intrinsics. This does not install
//! modules, fabricate providers, publish child_process, or launch a process.
const js = @import("native_js_values.zig");
const c = js.c;
const local = @import("native_node_socket_scope.zig");
const public = @import("native_node_child_process_public.zig");
const descriptors = @import("native_child_process_stdio_frontend.zig");
const canonical = @import("native_node_net_socket_provider.zig");
const vm = @import("native_child_process_vm_options.zig");
const Entry = struct { engine: *js.Engine, previous: ?*Entry };
threadlocal var capturing: ?*Entry = null;

pub const Host = struct {
    /// Genuine internal builtin loader passed to Node internal/errors by
    /// compileForInternalLoader (realm.js), not public Module.createRequire or
    /// a physical filename/config URL/global require/public _load hook wrapper.
    /// ErrnoException retains this exact callable for lazy require('util').
    internal_require: c.JSValue,
    /// Explicit embedding policy, never inferred from missing guest properties.
    permission: vm.Permission,
    inherited_environment: ?*const fn (*js.Engine) anyerror!@import("native_child_process_environment.zig").Environment = null,
    linux_handshake_budget_ms: u32 = 10_000,
};

/// Move-only roots. Do not copy or deinit twice. Inputs returned by view borrow
/// these roots until public.create/createForFrontend has retained its own graph.
/// The actual native Frontend/bridge and host capabilities must outlive Engine;
/// keeping a JavaScript value alive does not retain a native frontend pointer.
pub const Owned = struct {
    engine: *js.Engine,
    roots: local.Scope,
    inputs: public.Inputs,
    captured: descriptors.Captured,
    live: bool = true,

    pub fn view(self: *const Owned, engine: *js.Engine) anyerror!public.Inputs {
        if (!self.live or self.engine != engine) return error.NativeChildFrontendInputsRetired;
        try engine.checkNativeEntry();
        try @import("native_process_streams.zig").assertLease(engine, self.captured.source);
        return self.inputs;
    }
    /// Does not unbind the frontend or close the Hub-owned descriptor map.
    /// Child admissions duplicate from that exact map and revalidate its lease.
    pub fn deinit(self: *Owned) anyerror!void {
        if (!self.live) return error.NativeChildFrontendInputsAlreadyRetired;
        self.engine.native_exception_diagnostics_suppressed += 1;
        defer self.engine.native_exception_diagnostics_suppressed -= 1;
        self.live = false;
        self.roots.deinit();
        try self.engine.checkNativeEntry();
    }
    /// Consume into the SAME Engine's caller-owned, already-recorded
    /// completion. Its releaseScope owns pending/event precedence and must be
    /// finished by that caller. No SDK policy/import is embedded in this leaf.
    /// A successfully returned capture has no local operation in flight and
    /// no hidden unwind reason; all roots are ordinary temporary ownership.
    pub fn retireInto(self: *Owned, collector: anytype) void {
        @import("std").debug.assert(self.live);
        @import("std").debug.assert(self.roots.unwind == null);
        self.live = false;
        collector.releaseScope(&self.roots);
    }
};

fn installed(scope: *local.Scope, name: []const u8) anyerror!c.JSValue {
    const engine = scope.engine;
    // A private map entry or source module is not an installed builtin.
    if (!engine.native_module_names.contains(name) or engine.modules.contains(name)) return error.RequiredInstalledChildFrontendProvider;
    const record = engine.native_module_values.get(name) orelse return error.RequiredInstalledChildFrontendProvider;
    const value = try scope.get(record, "default");
    if (!c.JS_IsObject(value)) return error.RequiredActualChildFrontendDefault;
    return value;
}
fn callable(scope: *local.Scope, object: c.JSValue, name: [*:0]const u8) anyerror!c.JSValue {
    const value = try scope.get(object, name);
    if (!c.JS_IsFunction(scope.engine.context, value)) return error.RequiredActualChildFrontendCallable;
    return value;
}
fn assemble(engine: *js.Engine, frontend: *@import("native_stdio_frontend.zig").Frontend, host: Host) anyerror!Owned {
    var roots: local.Scope = .{ .engine = engine };
    var transferred = false;
    defer if (!transferred) roots.deinit();
    errdefer |err| roots.captureUnwind(err);
    if (engine.native_io == null or engine.host_scheduler == null) return error.RequiredActualChildFrontendIoAndTimers;
    if (!c.JS_IsFunction(engine.context, host.internal_require)) return error.RequiredActualChildFrontendInternalRequire;
    const process = try installed(&roots, "node:process");
    if (!roots.equal(process, try roots.global("process"))) return error.NativeChildFrontendProcessMismatch;
    _ = try callable(&roots, process, "nextTick");
    const streams = try installed(&roots, "node:stream");
    const actual_core = try @import("native_node_stream.zig").owner(engine);
    try engine.checkNativeEntry();
    // owner() returns a borrowed private record; retain a separate root.
    _ = try roots.own(c.JS_DupValue(engine.context, actual_core));
    if (!roots.equal(process, try roots.get(actual_core, "process")) or !roots.equal(streams, try roots.get(actual_core, "Stream"))) return error.NativeChildFrontendStreamMismatch;
    const timers = try installed(&roots, "node:timers");
    _ = try callable(&roots, timers, "setTimeout");
    _ = try callable(&roots, timers, "clearTimeout");
    const os = try installed(&roots, "node:os");
    const signals = try roots.get(try roots.get(os, "constants"), "signals");
    if (!c.JS_IsObject(signals)) return error.RequiredActualChildFrontendSignals;

    const array = try roots.get(try roots.global("Array"), "prototype");
    const string = try roots.get(try roots.global("String"), "prototype");
    const object = try roots.get(try roots.global("Object"), "prototype");
    const regexp = try roots.global("RegExp");
    if (!c.JS_IsFunction(engine.context, regexp)) return error.RequiredActualChildFrontendCallable;
    const primordials: vm.Primordials = .{
        .array_slice = try callable(&roots, array, "slice"),
        .array_unshift = try callable(&roots, array, "unshift"),
        .array_join = try callable(&roots, array, "join"),
        .array_sort = try callable(&roots, array, "sort"),
        .array_filter = try callable(&roots, array, "filter"),
        .array_push = try callable(&roots, array, "push"),
        .string_upper = try callable(&roots, string, "toUpperCase"),
        .has_own = try callable(&roots, object, "hasOwnProperty"),
        .iterator_symbol = try roots.get(try roots.global("Symbol"), "iterator"),
        .regexp_constructor = regexp,
        .regexp_exec = try callable(&roots, try roots.get(regexp, "prototype"), "exec"),
    };
    if (!c.JS_IsSymbol(primordials.iterator_symbol)) return error.RequiredActualChildFrontendIteratorSymbol;
    const reduce = try callable(&roots, array, "reduce");
    const is_view = try callable(&roots, try roots.global("ArrayBuffer"), "isView");
    const shared = try canonical.acquire(engine, streams, process);
    try engine.checkNativeEntry();
    const reason = try roots.own(try @import("native_node_errno_exception.zig").acquire(engine, .{
        .error_type = try roots.get(actual_core, "Error"), .require = host.internal_require,
    }));
    try engine.checkNativeEntry();
    var inputs: public.Inputs = .{
        .streams = streams, .process = process, .signals = signals,
        .array_prototype_slice = primordials.array_slice,
        .string_prototype_to_upper_case = primordials.string_upper,
        .timers = timers, .errno_exception = reason, .primordials = primordials,
        .array_prototype_reduce = reduce, .array_buffer_is_view = is_view,
        .permission = host.permission, .inherited_environment = host.inherited_environment,
        .socket_provider = &shared.provider,
        .linux_handshake_budget_ms = host.linux_handshake_budget_ms,
    };
    // Capture actual OS descriptor capabilities only AFTER every fallible VM
    // lookup. No guest operation follows successful map ownership transfer.
    const captured = try descriptors.capture(engine, frontend);
    try captured.apply(engine, &inputs);
    transferred = true;
    return .{ .engine = engine, .roots = roots, .inputs = inputs, .captured = captured };
}

pub fn capture(engine: *js.Engine, frontend: *@import("native_stdio_frontend.zig").Frontend, host: Host) anyerror!Owned {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var cursor = capturing;
    while (cursor) |entry| : (cursor = entry.previous) if (entry.engine == engine) return error.NativeChildFrontendInputsCaptureInProgress;
    var entry: Entry = .{ .engine = engine, .previous = capturing };
    capturing = &entry;
    defer capturing = entry.previous;
    var invocation: js.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    var result = assemble(engine, frontend, host) catch |err| {
        const actual: anyerror = if (err == error.OutOfMemory) failure: {
            _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch |escaped| break :failure escaped;
            unreachable;
        } else if (err == error.JavaScriptException) failure: {
            _ = engine.checked(engine.throwCaptured()) catch |escaped| break :failure escaped;
            unreachable;
        } else err;
        _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |escaped| return @as(anyerror!Owned, escaped);
        return @as(anyerror!Owned, actual);
    };
    _ = engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined())) catch |err| {
        var cleanup: local.Cleanup = .{ .engine = engine, .generation = engine.native_allocation_generation };
        cleanup.captureEntry(err);
        result.deinit() catch {};
        cleanup.collect(); cleanup.publish();
        try engine.checkNativeEntry();
        return @as(anyerror!Owned, err);
    };
    return result;
}
