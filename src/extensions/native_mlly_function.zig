//! Leaf-local ordinary/arrow/method invocation boundary for mlly. In particular
//! construction setup is inside the SAME trusted boundary as the Source body.
//! No shared Node callable, Engine or C policy is changed by this adapter.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const allocation = @import("native_async_body.zig");
pub const Callback = *const fn (*js.Engine, c.JSValue, []const c.JSValue, []const c.JSValue) anyerror!c.JSValue;
const State = struct { engine: *js.Engine, callback: Callback, values: []c.JSValue, constructible: bool, arrow: bool, reserved: usize };
// Synchronous invocation provenance only: no JS root, allocation or cross-thread
// Engine state. An ordinary, freshly checked completion must not be reclassified
// using an enclosing loop/call's older generation when it crosses that frame.
const Invocation = struct { engine: *js.Engine, previous: ?*Invocation, ordinary_floor: ?u64 = null };
threadlocal var invocation: ?*Invocation = null;
pub fn trustedGeneration(engine: *js.Engine, generation: u64) u64 {
    var result = generation; var current = invocation;
    while (current) |frame| : (current = frame.previous) if (frame.engine == engine) if (frame.ordinary_floor) |floor| {
        const distance = floor -% result;
        if (distance != 0 and distance <= engine.native_allocation_generation -% result) result = floor;
    };
    return result;
}
pub fn ordinaryBoundary(engine: *js.Engine) void {
    var current = invocation;
    while (current) |frame| : (current = frame.previous) if (frame.engine == engine) { frame.ordinary_floor = engine.native_allocation_generation; };
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = owned.engine; const reserved = owned.reserved;
    for (owned.values) |item| c.JS_FreeValueRT(runtime, item);
    engine.gpa.free(owned.values); engine.gpa.destroy(owned);
    c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, marker: ?*const c.JS_MarkFunc) callconv(.c) void {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (owned.values) |item| c.JS_MarkValue(runtime, item, marker);
}
fn clearCaptured(engine: *js.Engine) void {
    const previous = engine.captured_exception; engine.captured_exception = null;
    if (previous) |reason| engine.freeValue(reason);
}
/// The owned pending reason outranks an older diagnostic capture. Direct OOM
/// marks an existing Error without replacing it; a pending primitive combined
/// with direct OOM is explicitly outside this leaf's supported host contract.
pub fn failure(engine: *js.Engine, err: anyerror, generation: u64) c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    if (c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        if (err == error.OutOfMemory and c.JS_IsError(reason)) c.JS_SetUncatchableError(engine.context, reason);
        return throwOwned(engine, reason, generation);
    }
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        engine.captured_exception = null;
        return throwOwned(engine, reason, generation);
    };
    if (err == error.OutOfMemory) {
        _ = engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, reason);
        return throwOwned(engine, reason, generation);
    }
    clearCaptured(engine);
    if (err == error.JavaScriptException) return c.JS_ThrowInternalError(engine.context, "mlly callback failed without an exception value");
    return c.JS_ThrowTypeError(engine.context, "Native mlly function: %s", @as([*:0]const u8, @errorName(err)));
}
fn throwOwned(engine: *js.Engine, reason: c.JSValue, generation: u64) c.JSValue {
    // reason is one owned reference, either taken from pending VM state or
    // transferred from captured_exception. Remove every prior diagnostic root
    // before classifying/rethrowing, retaining this exact reference throughout.
    clearCaptured(engine);
    allocation.rethrowRecognizedAllocation(engine, reason, trustedGeneration(engine, generation)) catch |err| {
        if (err != error.JavaScriptException) { engine.freeValue(reason); return failure(engine, err, generation); }
        // The recognized-error helper owns a fresh duplicate capture. The
        // original reason below is still owned; free only that duplicate.
        clearCaptured(engine);
    };
    return c.JS_Throw(engine.context, reason);
}
fn call(_: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const owned: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = owned.engine; const generation = engine.native_allocation_generation;
    var frame: Invocation = .{ .engine = engine, .previous = invocation };
    invocation = &frame; defer invocation = frame.previous;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return invoke(engine, owned, target, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| failure(engine, err, generation);
}
fn invoke(engine: *js.Engine, owned: *State, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    if (!owned.constructible) return owned.callback(engine, if (owned.arrow) c.pi_js_undefined() else target, args, owned.values);
    if (!constructing) return owned.callback(engine, target, args, owned.values);
    const receiver = try @import("native_class.zig").object(engine, target); defer engine.freeValue(receiver);
    const returned = try owned.callback(engine, receiver, args, owned.values);
    if (c.JS_IsObject(returned)) return returned;
    engine.freeValue(returned); return c.JS_DupValue(engine.context, receiver);
}
pub fn create(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue { return createKind(engine, name, length, callback, values, true, false); }
pub fn createArrow(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue { return createKind(engine, name, length, callback, values, false, true); }
pub fn createMethod(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue { return createKind(engine, name, length, callback, values, false, false); }
fn createKind(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue, constructible: bool, arrow: bool) !c.JSValue {
    const root_bytes = std.math.mul(usize, values.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const reserved = std.math.add(usize, @sizeOf(State), root_bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, reserved) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, reserved);
    const owned = try engine.gpa.create(State); errdefer if (!attached) engine.gpa.destroy(owned);
    const owned_values = try engine.gpa.alloc(c.JSValue, values.len); errdefer if (!attached) engine.gpa.free(owned_values);
    var class: c.JSClassID = 0;
    if (c.JS_NewClassID(engine.runtime, &class) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native mlly Function", .call = call, .finalizer = finalizer, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const prototype = try engine.checked(c.JS_GetFunctionProto(engine.context)); defer engine.freeValue(prototype);
    const function = try engine.checked(c.JS_NewObjectProtoClass(engine.context, prototype, class)); errdefer engine.freeValue(function);
    for (values, owned_values) |value, *slot| slot.* = c.JS_DupValue(engine.context, value);
    owned.* = .{ .engine=engine,.callback=callback,.values=owned_values,.constructible=constructible,.arrow=arrow,.reserved=reserved };
    _ = c.JS_SetOpaque(function, owned); attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, constructible);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", try engine.checked(c.JS_NewString(engine.context, name)), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (constructible) {
        const instance_prototype = try js.object(engine); defer engine.freeValue(instance_prototype);
        if (c.JS_DefinePropertyValueStr(engine.context, instance_prototype, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
        if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, instance_prototype), c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    return function;
}

test "mlly provenance wrap ordering and cross Engine isolation are exact" {
    const first = try js.Engine.init(std.testing.allocator, .{}); defer first.deinit();
    const second = try js.Engine.init(std.testing.allocator, .{}); defer second.deinit();
    const saved = invocation; defer invocation = saved;
    const first_generation = first.native_allocation_generation; defer first.native_allocation_generation = first_generation;
    const second_generation = second.native_allocation_generation; defer second.native_allocation_generation = second_generation;
    first.native_allocation_generation = 2; second.native_allocation_generation = 19;
    var parent: Invocation = .{ .engine = first, .previous = saved, .ordinary_floor = std.math.maxInt(u64) };
    var foreign: Invocation = .{ .engine = second, .previous = &parent, .ordinary_floor = 17 };
    invocation = &foreign;
    try std.testing.expectEqual(std.math.maxInt(u64), trustedGeneration(first, std.math.maxInt(u64) - 2));
    ordinaryBoundary(second);
    try std.testing.expectEqual(std.math.maxInt(u64), parent.ordinary_floor.?);
    var nested: Invocation = .{ .engine = first, .previous = &foreign };
    invocation = &nested; ordinaryBoundary(first);
    try std.testing.expectEqual(@as(u64, 2), parent.ordinary_floor.?);
    try std.testing.expectEqual(@as(u64, 2), nested.ordinary_floor.?);
    try std.testing.expectEqual(@as(u64, 19), foreign.ordinary_floor.?);
    try std.testing.expectEqual(@as(u64, 2), trustedGeneration(first, std.math.maxInt(u64) - 2));
}
test "mlly real callback and constructor failures pop the invocation frame" {
    const Fixture = struct {
        fn body(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            try std.testing.expect(invocation != null);
            ordinaryBoundary(engine);
            return js.typeError(engine, "controlled callback failure");
        }
    };
    try std.testing.expect(invocation == null);
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const function = try create(engine, "MllyFrameProbe", 0, Fixture.body, &.{}); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "MllyFrameProbe", c.JS_DupValue(engine.context, function));
    const value = try engine.evalModule(
        "for(const run of [()=>MllyFrameProbe(),()=>new MllyFrameProbe(),()=>Reflect.construct(MllyFrameProbe,[],new Proxy(function(){},{get(target,key,receiver){if(key==='prototype')throw 71;return Reflect.get(target,key,receiver)}}))]){let caught=false;try{run()}catch(reason){caught=true}if(!caught)throw Error('missing controlled failure')}",
        "mlly-balanced-invocation-frames.mjs");
    engine.freeValue(value); try std.testing.expect(invocation == null); try std.testing.expect(engine.captured_exception == null);
}
test "mlly actual cross Engine reentry cannot hide a caller fresh allocation" {
    const Fixture = struct {
        var other: ?*js.Engine = null;
        fn foreign(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            ordinaryBoundary(engine);
            return js.typeError(engine, "controlled foreign ordinary completion");
        }
        fn parent(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            _ = engine.throwNativeOutOfMemory(); const primary = c.JS_GetException(engine.context); defer engine.freeValue(primary);
            const value = try other.?.evalModule("try{MllyForeignProbe()}catch(reason){if(!(reason instanceof TypeError))throw reason}", "mlly-real-foreign-reentry.mjs"); other.?.freeValue(value);
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, primary)));
        }
    };
    const first = try js.Engine.init(std.testing.allocator, .{}); defer first.deinit();
    const second = try js.Engine.init(std.testing.allocator, .{}); defer second.deinit();
    Fixture.other = second; defer Fixture.other = null;
    const foreign = try create(second, "MllyForeignProbe", 0, Fixture.foreign, &.{}); defer second.freeValue(foreign);
    const foreign_global = c.JS_GetGlobalObject(second.context); defer second.freeValue(foreign_global);
    try js.define(second, foreign_global, "MllyForeignProbe", c.JS_DupValue(second.context, foreign));
    const parent = try create(first, "MllyParentProbe", 0, Fixture.parent, &.{}); defer first.freeValue(parent);
    const parent_global = c.JS_GetGlobalObject(first.context); defer first.freeValue(parent_global);
    try js.define(first, parent_global, "MllyParentProbe", c.JS_DupValue(first.context, parent));
    try std.testing.expectError(error.JavaScriptException, first.evalModule("globalThis.mllyCrossCaught=false;try{MllyParentProbe()}catch{globalThis.mllyCrossCaught=true}", "mlly-cross-engine-fatal.mjs"));
    try std.testing.expect(c.JS_IsUncatchableError(first.captured_exception.?));
    const caught = try js.get(first, parent_global, "mllyCrossCaught"); defer first.freeValue(caught);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(first.context, caught));
    try std.testing.expect(invocation == null); try std.testing.expect(second.captured_exception == null);
}
