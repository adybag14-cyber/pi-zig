//! Prepared real guest-operation provenance controls. Not executed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const p = @import("extensions/native_agent_af_values.zig");
const functions = @import("extensions/native_node_function.zig");
const c = em.c;

fn dataMaker(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // RAW transport is deliberately unmarked and never checked/captured.
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(engine.context);
}
fn fatalMaker(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // Actual producer checked inside a native callback; VM pending is emptied
    // here, so only the enclosing live invocation can retain the event.
    _ = engine.checked(engine.throwNativeOutOfMemoryFatal()) catch {};
    return c.pi_js_undefined();
}
fn setup(s: *p.Scope) !void {
    const object = try s.own(c.JS_GetGlobalObject(s.engine.context));
    try s.put(object, "makePrivateData", try s.own(try functions.create(s.engine, "makePrivateData", 0, dataMaker, &.{})));
    try s.put(object, "makeActualFatal", try s.own(try functions.create(s.engine, "makeActualFatal", 0, fatalMaker, &.{})));
}
fn eval(s: *p.Scope, source: []const u8) !c.JSValue {
    return s.own(try s.engine.eval(source, "agent-guest-provenance.js", c.JS_EVAL_TYPE_GLOBAL));
}
fn sameData(s: *p.Scope) !void {
    const owned = try p.caught(s.engine, error.JavaScriptException);
    defer s.engine.freeValue(owned);
    const expected = try p.global(s, "lastData");
    try std.testing.expect(c.JS_IsStrictEqual(s.engine.context, owned, expected));
    try std.testing.expect(!c.JS_IsUncatchableError(owned));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(owned) != 0);
    try std.testing.expect(!c.JS_HasException(s.engine.context));
}

test "native Agent guest provenance same getter private DATA maker then ordinary throw" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
    const object = try eval(&s, "({get value(){const a=makePrivateData();globalThis.lastData=a;throw a}})");
    try std.testing.expectError(error.JavaScriptException, p.get(&s, object, "value"));
    try sameData(&s);
}
test "native Agent guest provenance same call private DATA maker then ordinary throw" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
    const function = try eval(&s, "(function(){const a=makePrivateData();globalThis.lastData=a;throw a})");
    try std.testing.expectError(error.JavaScriptException, p.call(&s, function, c.pi_js_undefined(), &.{}));
    try sameData(&s);
}
test "native Agent guest provenance same constructor private DATA maker then ordinary throw" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
    const constructor = try eval(&s, "(function C(){const a=makePrivateData();globalThis.lastData=a;throw a})");
    try std.testing.expectError(error.JavaScriptException, p.construct(&s, constructor, &.{}));
    try sameData(&s);
}
test "native Agent guest provenance key coercion and setter DATA stay ordinary" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
    const object = try eval(&s, "({set value(v){const a=makePrivateData();globalThis.lastData=a;throw a}})");
    const key = try eval(&s, "({[Symbol.toPrimitive](){const a=makePrivateData();globalThis.lastData=a;throw a}})");
    try std.testing.expectError(error.JavaScriptException, p.getKey(&s, object, key)); try sameData(&s);
    try std.testing.expectError(error.JavaScriptException, p.set(&s, object, "value", c.pi_js_undefined())); try sameData(&s);
}
test "native Agent guest provenance actual producer survives caught callback and constructor" {
    inline for (.{ false, true }) |constructing| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
        const function = try eval(&s, "(function C(){try{makeActualFatal()}catch(e){};return {ordinary:true}})");
        if (constructing) try std.testing.expectError(error.JavaScriptException, p.construct(&s, function, &.{}))
        else try std.testing.expectError(error.JavaScriptException, p.call(&s, function, c.pi_js_undefined(), &.{}));
        const reason = engine.captured_exception orelse return error.MissingActualProducer;
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
test "native Agent guest provenance pending entry aborts before getter effects" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit();
    const object = try eval(&s, "(globalThis.entryReads=0,{get value(){entryReads++;return 1}})");
    _ = engine.throwNativeOutOfMemoryFatal();
    try std.testing.expectError(error.JavaScriptException, p.get(&s, object, "value"));
    try std.testing.expect(engine.native_fatal_invocation == null);
    // Read plain data with raw VM API: no new guest-operation entry can run
    // while the intentionally retained test fatal remains in diagnostics.
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const reads = c.JS_GetPropertyStr(engine.context, global, "entryReads"); defer engine.freeValue(reads);
    var count: i32 = -1; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &count, reads));
    try std.testing.expectEqual(@as(i32, 0), count);
}
test "native Agent guest provenance captured-only flagged DATA is not current producer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try std.testing.expectError(error.JavaScriptException, engine.checked(engine.throwNativeOutOfMemory()));
    const expected = engine.captured_exception orelse return error.MissingDiagnostic;
    c.JS_SetUncatchableError(engine.context, expected);
    const reason = try p.caught(engine, error.JavaScriptException); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, expected));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expect(!c.JS_HasException(engine.context));
}

test "native Agent guest provenance production emitter rejects same-call private DATA unchanged" {
    const engine = try em.Engine.init(std.testing.allocator, .{ .host_await_timeout_ms = 10000 }); defer engine.deinit();
    var s: p.Scope = .{ .engine = engine }; defer s.deinit(); try setup(&s);
    const stream = try eval(&s, "({push(){const a=makePrivateData();globalThis.lastData=a;throw a}})");
    const emit = try s.own(try @import("extensions/native_agent_stream.zig").createEmitter(engine, stream));
    try s.put(try s.own(c.JS_GetGlobalObject(engine.context)), "actualEmit", emit);
    const result = try engine.evalModule(
        \\let escaped=false,promise;try{promise=actualEmit({})}catch(e){escaped=true}if(escaped)throw Error('sync escape');
        \\let same=false;try{await promise}catch(e){same=e===lastData}if(!same)throw Error('DATA identity');
    , "agent-producer-emitter.mjs");
    engine.freeValue(result);
}

const Cleanup = struct { engine: *em.Engine, ordinary: c.JSValue, fatal: bool };
var append_allocator: ?*std.testing.FailingAllocator = null;
var cleanup_fatal = false;
var cleanup_count: usize = 0;
fn cleanupFinalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *Cleanup = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    cleanup_count += 1;
    if (owner.fatal) {
        _ = owner.engine.checked(owner.engine.throwNativeOutOfMemoryFatal()) catch {};
    } else {
        _ = c.JS_Throw(owner.engine.context, c.JS_DupValue(owner.engine.context, owner.ordinary));
    }
    owner.engine.freeValue(owner.ordinary);
    owner.engine.gpa.destroy(owner);
}
fn soleOutput(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, captures: []const c.JSValue) !c.JSValue {
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Agent guest owned output", .finalizer = cleanupFinalizer };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const owner = try engine.gpa.create(Cleanup);
    errdefer engine.gpa.destroy(owner);
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, class));
    owner.* = .{ .engine = engine, .ordinary = c.JS_DupValue(engine.context, captures[0]), .fatal = cleanup_fatal };
    _ = c.JS_SetOpaque(value, owner);
    const allocator = append_allocator.?;
    allocator.fail_index = allocator.alloc_index;
    allocator.resize_fail_index = allocator.resize_index;
    return value;
}
test "native Agent guest provenance actual root append OOM precedes sole-output finalizers" {
    inline for (.{ false, true }) |fatal_cleanup| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        defer { append_allocator = null; allocator.fail_index = std.math.maxInt(usize); allocator.resize_fail_index = std.math.maxInt(usize); }
        var setup_scope: p.Scope = .{ .engine = engine }; defer setup_scope.deinit();
        const ordinary = try setup_scope.object();
        const function = try setup_scope.own(try functions.create(engine, "soleOutput", 0, soleOutput, &.{ordinary}));
        var s: p.Scope = .{ .engine = engine }; defer s.deinit();
        _ = try s.own(c.pi_js_undefined());
        while (s.values.items.len < s.values.capacity) _ = try s.own(c.pi_js_undefined());
        append_allocator = &allocator; cleanup_fatal = fatal_cleanup; cleanup_count = 0;
        engine.native_exception_diagnostics_suppressed += 1;
        defer engine.native_exception_diagnostics_suppressed -= 1;
        try std.testing.expectError(error.JavaScriptException, p.call(&s, function, c.pi_js_undefined(), &.{}));
        allocator.fail_index = std.math.maxInt(usize); allocator.resize_fail_index = std.math.maxInt(usize);
        try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expectEqual(@as(usize, 1), cleanup_count);
        const actual = engine.captured_exception orelse return error.MissingAppendFatal;
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(actual) != 0);
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, actual, ordinary));
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
