//! One canonical Socket constructor/provider and real Socket export carrier per
//! Engine. No TCP/server API is fabricated, and no public module is selected.
const js = @import("native_js_values.zig");
const c = js.c;
const socket = @import("native_node_net_socket.zig");
const Scope = @import("native_node_socket_scope.zig").Scope;
const key = "\x00native.net.Socket.canonical-provider";
pub const Bundle = struct {
    engine: *js.Engine,
    provider: socket.Provider,
    net: c.JSValue,
    actual_streams: c.JSValue,
    actual_process: c.JSValue,
};
// Host owner-thread recursion guard. A partially initialized provider is never
// put in the VM cache, and an inner getter cannot publish a competing class.
const Entry = struct { engine: *js.Engine, previous: ?*Entry };
threadlocal var initializing: ?*Entry = null;
fn finalize(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
    const self: *Bundle = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ self.provider.constructor, self.provider.states, self.net, self.actual_streams, self.actual_process }) |value| c.JS_FreeValueRT(runtime, value);
    const engine = self.engine;
    engine.gpa.destroy(self);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Bundle));
}
fn mark(runtime: ?*c.JSRuntime, holder: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const self: *Bundle = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
    inline for (.{ self.provider.constructor, self.provider.states, self.net, self.actual_streams, self.actual_process }) |value| c.JS_MarkValue(runtime, value, visitor);
}
/// Trusted native composition entry. Inputs are the actual Stream namespace and
/// process object. The returned pointer stays rooted in the private Engine cache
/// until runtime teardown; callers do not free it. Clone provider for owned roots.
pub fn acquire(engine: *js.Engine, actual_streams: c.JSValue, actual_process: c.JSValue) !*Bundle {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try engine.checkNativeEntry();
    var invocation: js.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&invocation);
    const result = acquireInner(engine, actual_streams, actual_process) catch |err| {
        // Direct factory entry preserves its error union, while the genuine
        // producer owns a current fatal B before cleanup/direct OOM can create C.
        if (err == error.OutOfMemory) _ = engine.throwNativeOutOfMemoryFatal()
        else if (err == error.JavaScriptException) _ = engine.throwCaptured();
        _ = try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()));
        return err;
    };
    _ = try engine.checked(engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()));
    return result;
}
fn acquireInner(engine: *js.Engine, actual_streams: c.JSValue, actual_process: c.JSValue) !*Bundle {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    if (engine.native_module_values.get(key)) |holder| {
        // This exact unregistered cache cell is native-only. Root's qualified
        // requireBuiltin/normalizeRequire excludes unregistered private entries.
        const existing: *Bundle = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return error.NativeCanonicalSocketCacheBrand));
        if (existing.engine != engine or !c.JS_IsStrictEqual(engine.context, existing.actual_streams, actual_streams) or !c.JS_IsStrictEqual(engine.context, existing.actual_process, actual_process)) return error.NativeCanonicalSocketDependencyMismatch;
        return existing;
    }
    var cursor = initializing;
    while (cursor) |entry| { if (entry.engine == engine) return error.NativeCanonicalSocketInitializationInProgress; cursor = entry.previous; }
    var entry: Entry = .{ .engine = engine, .previous = initializing };
    initializing = &entry; defer initializing = entry.previous;
    var provider = try socket.createProvider(engine, actual_streams, actual_process);
    var provider_owned = true; defer if (provider_owned) provider.deinit();
    // Declared AFTER the provider defer: own the primary reason before either
    // actual provider root can run a finalizer during failed-cache rollback.
    errdefer |err| scope.captureUnwind(err);
    try engine.checkNativeEntry();
    const net = try scope.object();
    // These are real exported constructor aliases, not module-name shims. TCP,
    // Server, connect and createConnection are outside this admitted surface.
    inline for (.{ "Socket", "Stream" }) |name| {
        const status = c.JS_DefinePropertyValueStr(engine.context, net, name, c.JS_DupValue(engine.context, provider.constructor), c.JS_PROP_C_W_E);
        try engine.checkNativeEntry(); if (status < 0) return @as(anyerror!*Bundle, js.capture(engine));
    }
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Canonical native Socket provider", .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const holder = try scope.own(c.JS_NewObjectClass(engine.context, id));
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Bundle)) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Bundle));
    const self = try engine.gpa.create(Bundle);
    self.* = .{ .engine = engine, .provider = provider, .net = c.JS_DupValue(engine.context, net), .actual_streams = c.JS_DupValue(engine.context, actual_streams), .actual_process = c.JS_DupValue(engine.context, actual_process) };
    _ = c.JS_SetOpaque(holder, self);
    attached = true; provider_owned = false;
    const retained = c.JS_DupValue(engine.context, holder);
    engine.native_module_values.put(engine.gpa, key, retained) catch |err| { engine.freeValue(retained); return @as(anyerror!*Bundle, err); };
    return self;
}

test "canonical Socket cache rejects actual incoming pending completion before dependency effects" {
    const std = @import("std");
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, acquire(engine, c.pi_js_undefined(), c.pi_js_undefined()));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, reason));
    try std.testing.expect(!engine.native_module_values.contains(key));
    engine.freeValue(engine.captured_exception.?); engine.captured_exception = null;
}

test "actual stream lookup ordinary failure survives sole native holder cleanup and promotes real cleanup fatal" {
    const std = @import("std");
    const functions = @import("native_node_function.zig");
    const Fixture = struct {
        engine: *js.Engine,
        allocator: *std.testing.FailingAllocator,
        primary: c.JSValue,
        cleanup: c.JSValue,
        raw_c: ?c.JSValue = null,
        witness: ?c.JSValue = null,
        mode: u8,
        armed: bool = true,
        finalized: usize = 0,
        getter_calls: usize = 0,
        diagnostic_calls: usize = 0,
        unexpected_allocation_success: bool = false,
        fn from(roots: []const c.JSValue) *@This() {
            return @ptrCast(@alignCast(c.JS_GetOpaque(roots[0], c.JS_GetClassID(roots[0])).?));
        }
        fn contextMark(runtime: ?*c.JSRuntime, holder: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
            c.JS_MarkValue(runtime, self.primary, visitor); c.JS_MarkValue(runtime, self.cleanup, visitor);
            if (self.raw_c) |value| c.JS_MarkValue(runtime, value, visitor);
            if (self.witness) |value| c.JS_MarkValue(runtime, value, visitor);
        }
        fn contextFinal(runtime: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
            self.armed = false;
            if (self.witness) |value| { self.witness = null; c.JS_FreeValueRT(runtime, value); }
            if (self.raw_c) |value| c.JS_FreeValueRT(runtime, value);
            c.JS_FreeValueRT(runtime, self.primary); c.JS_FreeValueRT(runtime, self.cleanup);
        }
        fn finalizedWitness(_: ?*c.JSRuntime, holder: c.JSValue) callconv(.c) void {
            const self: *@This() = @ptrCast(@alignCast(c.JS_GetOpaque(holder, c.JS_GetClassID(holder)) orelse return));
            self.finalized += 1;
            if (!self.armed) return;
            if (self.mode == 2) {
                const prior_fail = self.allocator.fail_index;
                self.allocator.fail_index = self.allocator.alloc_index;
                const bytes = self.engine.gpa.alloc(u8, 1) catch {
                    self.allocator.fail_index = prior_fail;
                    _ = self.engine.throwNativeOutOfMemoryFatal();
                    self.raw_c = c.JS_DupValue(self.engine.context, self.engine.native_allocation_exception.?);
                    return;
                };
                self.allocator.fail_index = prior_fail;
                self.unexpected_allocation_success = true; self.engine.gpa.free(bytes); return;
            }
            _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.cleanup));
        }
        fn duplex(_: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const self = from(roots); self.getter_calls += 1;
            const result = self.witness orelse return error.SocketControlWitnessAlreadyTransferred;
            self.witness = null; return result;
        }
        fn prototype(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, from(roots).primary)));
        }
        fn stringify(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            const self = from(roots); self.diagnostic_calls += 1;
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, self.cleanup)));
        }
    };
    for ([_]u8{ 0, 1, 2 }) |mode| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try js.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
        try @import("native_process.zig").install(engine, std.testing.io, &environment, &.{});
        const process = (try engine.requireBuiltin("node:process")).?; defer engine.freeValue(process);
        try @import("native_node_stream.zig").install(engine, process);
        const streams = (try engine.requireBuiltin("node:stream")).?; defer engine.freeValue(streams);
        const original = try engine.checked(c.JS_GetPropertyStr(engine.context, streams, "Duplex")); defer engine.freeValue(original);
        defer { _ = c.JS_DefinePropertyValueStr(engine.context, streams, "Duplex", c.JS_DupValue(engine.context, original), c.JS_PROP_C_W_E); }
        const primary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(primary);
        const cleanup = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(cleanup);
        if (mode == 1) c.JS_SetUncatchableError(engine.context, cleanup);
        var fixture: Fixture = .{ .engine = engine, .allocator = &allocator, .primary = c.JS_DupValue(engine.context, primary), .cleanup = c.JS_DupValue(engine.context, cleanup), .mode = mode };
        defer fixture.armed = false;
        var fixture_attached = false;
        defer if (!fixture_attached) { engine.freeValue(fixture.primary); engine.freeValue(fixture.cleanup); };
        var context_id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &context_id);
        const context_def: c.JSClassDef = .{ .class_name = "Owned Socket cleanup control context", .finalizer = Fixture.contextFinal, .gc_mark = Fixture.contextMark };
        if (c.JS_NewClass(engine.runtime, context_id, &context_def) < 0) return error.OutOfMemory;
        const context = try engine.checked(c.JS_NewObjectClass(engine.context, context_id)); defer engine.freeValue(context);
        _ = c.JS_SetOpaque(context, &fixture);
        fixture_attached = true;
        const stringify = try functions.createMethod(engine, "toString", 0, Fixture.stringify, &.{context}); defer engine.freeValue(stringify);
        if (c.JS_DefinePropertyValueStr(engine.context, primary, "toString", c.JS_DupValue(engine.context, stringify), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        var witness_id: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &witness_id);
        const witness_def: c.JSClassDef = .{ .class_name = "Actual sole-owned Socket getter witness", .finalizer = Fixture.finalizedWitness };
        if (c.JS_NewClass(engine.runtime, witness_id, &witness_def) < 0) return error.OutOfMemory;
        const witness = try engine.checked(c.JS_NewObjectClass(engine.context, witness_id));
        _ = c.JS_SetOpaque(witness, &fixture); fixture.witness = witness;
        const get_prototype = try functions.createMethod(engine, "get prototype", 0, Fixture.prototype, &.{context}); defer engine.freeValue(get_prototype);
        const proto_atom = c.JS_NewAtom(engine.context, "prototype"); defer c.JS_FreeAtom(engine.context, proto_atom);
        if (c.JS_DefinePropertyGetSet(engine.context, witness, proto_atom, c.JS_DupValue(engine.context, get_prototype), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        const get_duplex = try functions.createMethod(engine, "get Duplex", 0, Fixture.duplex, &.{context}); defer engine.freeValue(get_duplex);
        const duplex_atom = c.JS_NewAtom(engine.context, "Duplex"); defer c.JS_FreeAtom(engine.context, duplex_atom);
        if (c.JS_DefinePropertyGetSet(engine.context, streams, duplex_atom, c.JS_DupValue(engine.context, get_duplex), c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        const generation = engine.native_allocation_generation;
        try std.testing.expectError(error.JavaScriptException, acquire(engine, streams, process));
        const expected = if (mode == 0) primary else if (mode == 1) cleanup else fixture.raw_c.?;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, expected));
        try std.testing.expectEqual(@as(usize, 1), fixture.getter_calls);
        try std.testing.expectEqual(@as(usize, 1), fixture.finalized);
        try std.testing.expectEqual(@as(usize, 0), fixture.diagnostic_calls);
        try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
        try std.testing.expect(!engine.native_module_values.contains(key));
        try std.testing.expectEqual(generation + @as(u64, if (mode == 2) 1 else 0), engine.native_allocation_generation);
        try std.testing.expect(!fixture.unexpected_allocation_success);
        if (mode == 2) try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
