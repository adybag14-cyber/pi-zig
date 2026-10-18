//! Actual ordinary callable/constructor with RootBfb producer ownership plus
//! public-child ordinary-reason escrow over the WHOLE invoke/receiver cleanup.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_node_socket_scope.zig").Scope;
pub const Callback = @import("native_node_function.zig").Callback;
const State = struct { engine: *js.Engine, callback: Callback, values: []c.JSValue, charged: usize, constructible: bool, arrow: bool, new_only: bool };
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_FreeValueRT(runtime, root);
    const engine = state.engine; const charged = state.charged;
    engine.gpa.free(state.values); engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, charged);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visitor: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    for (state.values) |root| c.JS_MarkValue(runtime, root, visitor);
}
fn fail(engine: *js.Engine, err: anyerror) c.JSValue {
    engine.checkNativeEntry() catch return engine.throwCaptured();
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return engine.throwNativeOutOfMemoryFatal();
    if (c.JS_HasException(engine.context)) return engine.throwCaptured();
    return c.JS_ThrowTypeError(engine.context, "Native child function: %s", @as([*:0]const u8, @errorName(err)));
}
fn call(_: ?*c.JSContext, function: c.JSValue, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const state: *State = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    const engine = state.engine;
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1; defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: js.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    const result = invoke(engine, state, receiver, if (argc > 0) argv[0..@intCast(argc)] else &.{}, flags & c.JS_CALL_FLAG_CONSTRUCTOR != 0) catch |err| fail(engine, err);
    return engine.leaveNativeInvocation(&invocation, result);
}
fn invoke(engine: *js.Engine, state: *State, target: c.JSValue, args: []const c.JSValue, constructing: bool) !c.JSValue {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    if (state.new_only and !constructing) return @as(anyerror!c.JSValue, js.typeError(engine, "Native constructor requires new"));
    if (constructing and !state.constructible) return @as(anyerror!c.JSValue, js.typeError(engine, "Socket accessor is not a constructor"));
    const receiver = if (constructing) try scope.receiver(target) else if (state.arrow) c.pi_js_undefined() else target;
    const result = try scope.own(try state.callback(engine, receiver, args, state.values));
    return c.JS_DupValue(engine.context, if (constructing and !c.JS_IsObject(result)) receiver else result);
}
pub fn create(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, true, false, false);
}
pub fn createMethod(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, false, false);
}
pub fn createArrow(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, values, false, true, false);
}
fn createKind(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, values: []const c.JSValue, constructible: bool, arrow: bool, new_only: bool) !c.JSValue {
    try engine.checkNativeEntry();
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    errdefer |err| scope.captureUnwind(err);
    var id: c.JSClassID = 0; if (c.JS_NewClassID(engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Native Child Function", .call = call, .finalizer = finalize, .gc_mark = mark };
    if (c.JS_NewClass(engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const prototype = try scope.own(c.JS_GetFunctionProto(engine.context));
    const generation = try scope.beforeAllocation();
    const function = try scope.ownAllocationSince(c.JS_NewObjectProtoClass(engine.context, prototype, id), generation);
    const roots_bytes = std.math.mul(usize, values.len, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    const charged = std.math.add(usize, @sizeOf(State), roots_bytes) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, charged) == 0) return error.OutOfMemory;
    var attached = false; errdefer if (!attached) c.pi_js_native_memory_release(engine.native_memory_owner, charged);
    const roots = try engine.gpa.alloc(c.JSValue, values.len); errdefer if (!attached) engine.gpa.free(roots);
    const state = try engine.gpa.create(State);
    for (values, roots) |value, *root| root.* = c.JS_DupValue(engine.context, value);
    state.* = .{ .engine = engine, .callback = callback, .values = roots, .charged = charged, .constructible = constructible, .arrow = arrow, .new_only = new_only };
    _ = c.JS_SetOpaque(function, state); attached = true;
    _ = c.JS_SetConstructorBit(engine.context, function, constructible);
    if (c.JS_DefinePropertyValueStr(engine.context, function, "length", c.JS_NewInt32(engine.context, length), c.JS_PROP_CONFIGURABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    const actual_name = try scope.text(std.mem.span(name));
    if (c.JS_DefinePropertyValueStr(engine.context, function, "name", c.JS_DupValue(engine.context, actual_name), c.JS_PROP_CONFIGURABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    if (constructible) {
        const instance = try scope.object();
        if (c.JS_DefinePropertyValueStr(engine.context, instance, "constructor", c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
        if (c.JS_DefinePropertyValueStr(engine.context, function, "prototype", c.JS_DupValue(engine.context, instance), c.JS_PROP_WRITABLE) < 0) return @as(anyerror!c.JSValue, js.capture(engine));
    }
    return c.JS_DupValue(engine.context, function);
}

pub fn freshAllocation(engine: *js.Engine, reason: c.JSValue, generation: u64) bool {
    const tag = c.pi_js_native_allocation_error_generation(reason);
    const distance = tag -% generation;
    return tag != 0 and distance != 0 and distance <= engine.native_allocation_generation -% generation;
}
pub fn directFailure(engine: *js.Engine, err: anyerror, _: u64) anyerror {
    if (err == error.JavaScriptException or err == error.OutOfMemory or c.JS_HasException(engine.context)) {
        _ = engine.checked(fail(engine, err)) catch |actual| return actual; unreachable;
    }
    return err;
}
pub fn createClass(engine: *js.Engine, name: [*:0]const u8, length: c_int, callback: Callback, roots: []const c.JSValue) !c.JSValue {
    return createKind(engine, name, length, callback, roots, true, false, true);
}
test "child local callable transfers ordinary capture and covers constructor prototype getter" {
    const Fixture = struct {
        fn reason(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    const function = try create(engine, "ChildLocalFixture", 0, Fixture.reason, &.{reason}); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "childLocalFixture", c.JS_DupValue(engine.context, function)); try js.define(engine, global, "childLocalReason", c.JS_DupValue(engine.context, reason));
    const result = try engine.eval(
        "for(let i=0;i<3;i++){let caught=false;try{childLocalFixture()}catch(e){if(e!==childLocalReason)throw Error('ordinary identity');caught=true}if(!caught)throw Error('missing failure')}" ++
        "const target=new Proxy(function(){},{get(t,k,r){if(k==='prototype')throw childLocalReason;return Reflect.get(t,k,r)}});" ++
        "try{Reflect.construct(childLocalFixture,[],target);throw Error('missing getter failure')}catch(e){if(e!==childLocalReason)throw e}",
        "child-local-owned-ordinary-constructor", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try std.testing.expect(engine.captured_exception == null);
}

test "child local callable preserves fresh allocation identity and old ordinary reasons" {
    const Fixture = struct {
        fn fail(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            if (roots.len == 0) return error.OutOfMemory;
            return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0])));
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const function = try create(engine, "ChildAllocationFixture", 0, Fixture.fail, &.{}); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "childAllocationFixture", c.JS_DupValue(engine.context, function));
    try std.testing.expectError(error.JavaScriptException, engine.eval("try{childAllocationFixture()}catch(e){globalThis.caughtChildAllocation=true}", "child-local-fatal", c.JS_EVAL_TYPE_GLOBAL));
    const original = engine.captured_exception.?;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, original, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(original));
    // A later deliberate rethrow of an old native allocation is ordinary once
    // its original trusted boundary has ended; no tag-name heuristics apply.
    c.JS_ClearUncatchableError(engine.context, original);
    const old = try create(engine, "ChildOldAllocation", 0, Fixture.fail, &.{original}); defer engine.freeValue(old);
    try js.define(engine, global, "childOldAllocation", c.JS_DupValue(engine.context, old)); try js.define(engine, global, "oldChildReason", c.JS_DupValue(engine.context, original));
    engine.captured_exception = null; engine.freeValue(original);
    const result = try engine.eval("try{childOldAllocation();throw Error('missing')}catch(e){if(e!==oldChildReason)throw e}", "child-local-old-ordinary", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result); try std.testing.expect(engine.captured_exception == null);
}

test "child local callable normalizes success with actual pending completion" {
    const Fixture = struct {
        fn successPending(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0]));
            return c.JS_NewInt32(engine.context, 7);
        }
    };
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.eval("globalThis.childPendingFormatted=0;({toString(){childPendingFormatted++;throw Error('must not format')}})", "child-pending-reason", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(reason);
    const function = try create(engine, "ChildPendingFixture", 0, Fixture.successPending, &.{reason}); defer engine.freeValue(function);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "childPendingFixture", c.JS_DupValue(engine.context, function));
    try js.define(engine, global, "childPendingReason", c.JS_DupValue(engine.context, reason));
    const result = try engine.eval("for(const construct of [false,true]){try{if(construct)new childPendingFixture();else childPendingFixture();throw Error('missing pending failure')}catch(e){if(e!==childPendingReason)throw e}}if(childPendingFormatted!==0)throw Error('reason formatted')", "child-pending-call-and-construction", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
    try std.testing.expect(engine.captured_exception == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "public child actual callable provider retains new captured fatal over success and subsequent real GPA failure" {
    const Fixture = struct {
        fn callback(engine: *js.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
            if (c.JS_ToBool(engine.context, roots[1]) == 0) return c.pi_js_undefined();
            _ = engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, roots[0]))) catch {};
            if (c.JS_ToBool(engine.context, roots[2]) == 1) {
                const actual = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(actual);
            }
            return c.pi_js_undefined();
        }
    };
    inline for (.{ false, true }) |real_gpa_failure| {
        var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try js.Engine.init(allocator.allocator(), .{}); defer engine.deinit();
        const history = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(history);
        const current = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(current);
        c.JS_SetUncatchableError(engine.context, history); c.JS_SetUncatchableError(engine.context, current);
        const plain = try create(engine, "childOldHistoryControl", 0, Fixture.callback, &.{ history, c.pi_js_bool(engine.context, 0), c.pi_js_bool(engine.context, 0) }); defer engine.freeValue(plain);
        engine.captured_exception = c.JS_DupValue(engine.context, history);
        const ignored_history = c.JS_Call(engine.context, plain, c.pi_js_undefined(), 0, null); defer engine.freeValue(ignored_history);
        try std.testing.expect(c.JS_IsUndefined(ignored_history) and !c.JS_HasException(engine.context));
        // Same producer used by actual Socket constructor/method creation.
        const function = try create(engine, "childCurrentProducerControl", 0, Fixture.callback, &.{ current, c.pi_js_bool(engine.context, 1), c.pi_js_bool(engine.context, @intFromBool(real_gpa_failure)) }); defer engine.freeValue(function);
        const generation = engine.native_allocation_generation;
        if (real_gpa_failure) allocator.fail_index = allocator.alloc_index;
        const result = c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
        allocator.fail_index = std.math.maxInt(usize);
        if (real_gpa_failure) try std.testing.expect(allocator.has_induced_failure);
        try std.testing.expect(c.JS_IsException(result));
        const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, current));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(generation, engine.native_allocation_generation);
        try std.testing.expect(engine.native_fatal_invocation == null);
    }
}
