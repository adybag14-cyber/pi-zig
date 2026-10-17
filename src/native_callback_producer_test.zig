//! Real native producer/cold-class/Engine ownership controls, prepared only.
const std = @import("std");
const em = @import("extensions/engine.zig");
const functions = @import("extensions/native_node_function.zig");
const classes = @import("extensions/native_class.zig");
const sdk = @import("extensions/native_sdk.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const c = em.c;
fn allocate(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const bytes = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(bytes);
    return c.pi_js_undefined();
}
fn allocateClass(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const bytes = try engine.gpa.alloc(u8, 1); defer engine.gpa.free(bytes);
    return classes.object(engine, target);
}
fn sdkAllocate(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const bytes = engine.gpa.alloc(u8, 1) catch |err| return sdk.fail(engine, err);
    engine.gpa.free(bytes);
    return c.pi_js_undefined();
}
test "native Await DATA producer genuine Node function arrow class and SDK allocation failures cannot enter guest catch" {
    inline for (.{ "function", "arrow", "class", "sdk" }) |kind| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
        const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const function = if (comptime std.mem.eql(u8, kind, "class")) try s.own(try classes.constructor(engine, "Owned", 0, try s.object(), allocateClass, &.{}))
            else if (comptime std.mem.eql(u8, kind, "arrow")) try s.own(try functions.createArrow(engine, "ownedFault", 0, allocate, &.{}))
            else if (comptime std.mem.eql(u8, kind, "sdk")) try s.own(try engine.checked(c.JS_NewCFunction(engine.context, sdkAllocate, "ownedFault", 0)))
            else try s.own(try functions.create(engine, "ownedFault", 0, allocate, &.{}));
        try s.put(global, "ownedFault", function);
        const guest = try s.own(try engine.eval(if (comptime std.mem.eql(u8, kind, "class"))
            "globalThis.ownedCaught=0;(()=>{try{new ownedFault()}catch(e){ownedCaught++}})"
            else "globalThis.ownedCaught=0;(()=>{try{ownedFault()}catch(e){ownedCaught++}})", "actual-native-producer-catch.js", c.JS_EVAL_TYPE_GLOBAL));
        failing.fail_index = failing.alloc_index;
        const result = c.JS_Call(engine.context, guest, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
        failing.fail_index = std.math.maxInt(usize);
        try std.testing.expect(failing.has_induced_failure and c.JS_IsException(result));
        const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
        try std.testing.expect(c.JS_IsUncatchableError(reason));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
        try std.testing.expect(s.equal(try s.global("ownedCaught"), c.JS_NewInt32(engine.context, 0)));
    }
}
const Emission = struct { engine: *em.Engine, reason: c.JSValue, calls: usize = 0 };
fn emit(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const emission: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    emission.calls += 1;
    _ = c.JS_Throw(emission.engine.context, c.JS_DupValue(emission.engine.context, emission.reason));
}
fn token(emission: *Emission) !c.JSValue {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(emission.engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Actual native producer cleanup", .finalizer = emit };
    if (c.JS_NewClass(emission.engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const value = try emission.engine.checked(c.JS_NewObjectClass(emission.engine.context, class));
    _ = c.JS_SetOpaque(value, emission);
    return value;
}
var return_initial: ?*Emission = null;
var return_result: ?*Emission = null;
fn resultAfterCleanup(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    const temporary = try token(return_initial.?);
    defer engine.freeValue(temporary); // Actual typed-body cleanup publishes A.
    return token(return_result.?); // R's last owner is the actual callback exit.
}
test "native Await DATA producer Node and class normalize actual cleanup event before successful result escapes" {
    inline for (.{ false, true }) |class_call| {
        for ([_]bool{ false, true }) |first_fatal| {
            const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
            var s: Scope = .{ .engine = engine }; defer s.deinit();
            const a = try s.own(try engine.checked(c.JS_NewError(engine.context)));
            const b = try s.own(try engine.checked(c.JS_NewError(engine.context)));
            if (first_fatal) c.JS_SetUncatchableError(engine.context, a);
            c.JS_SetUncatchableError(engine.context, b);
            var initial: Emission = .{ .engine = engine, .reason = a };
            var result_emission: Emission = .{ .engine = engine, .reason = b };
            return_initial = &initial; return_result = &result_emission;
            defer { return_initial = null; return_result = null; }
            const function = try s.own(if (class_call) try classes.constructor(engine, "CleanupResult", 0, try s.object(), resultAfterCleanup, &.{}) else try functions.create(engine, "cleanupResult", 0, resultAfterCleanup, &.{}));
            const result = if (class_call) c.JS_CallConstructor(engine.context, function, 0, null) else c.JS_Call(engine.context, function, c.pi_js_undefined(), 0, null);
            defer engine.freeValue(result);
            try std.testing.expect(c.JS_IsException(result));
            const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, if (first_fatal) a else b));
            try std.testing.expect(c.JS_IsUncatchableError(reason));
            try std.testing.expectEqual(@as(usize, 1), initial.calls);
            try std.testing.expectEqual(@as(usize, 1), result_emission.calls);
            try std.testing.expect(!c.JS_HasException(engine.context));
        }
    }
}
test "native Await DATA producer Engine checked preserves actual pending before owned result and diagnostic cleanup" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const ordinary = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    const fatal = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    const later = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, fatal);
    var first_emission: Emission = .{ .engine = engine, .reason = ordinary };
    var result_emission: Emission = .{ .engine = engine, .reason = fatal };
    var captured_emission: Emission = .{ .engine = engine, .reason = later };
    engine.captured_exception = try token(&captured_emission);
    const result = try token(&result_emission);
    const temporary = try token(&first_emission);
    engine.freeValue(temporary); // Genuine native cleanup leaves actual A.
    try std.testing.expectError(error.JavaScriptException, engine.checked(result));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, fatal));
    try std.testing.expectEqual(@as(usize, 1), first_emission.calls);
    try std.testing.expectEqual(@as(usize, 1), result_emission.calls);
    try std.testing.expectEqual(@as(usize, 1), captured_emission.calls);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "native Await DATA producer newborn OOM is marked before old tracking native finalizer and wrap" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const cleanup = try s.own(try engine.checked(c.JS_NewError(engine.context)));
    c.JS_SetUncatchableError(engine.context, cleanup);
    var emission: Emission = .{ .engine = engine, .reason = cleanup };
    const old = try engine.checked(c.JS_NewError(engine.context));
    if (c.JS_DefinePropertyValueStr(engine.context, old, "cleanup", try token(&emission), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    engine.native_allocation_exception = old; // Sole ownership of old tracking.
    engine.native_allocation_generation = std.math.maxInt(u64);
    const result = engine.throwNativeOutOfMemoryFatal();
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.native_allocation_exception.?));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, reason, cleanup));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expectEqual(@as(u64, 1), c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "native Await DATA producer Engine capture owns actual event through diagnostic and displaced error finalizers" {
    for ([_]bool{ false, true }) |first_fatal| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const b = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        const ordinary = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, b);
        var old_emission: Emission = .{ .engine = engine, .reason = b };
        var original_emission: Emission = .{ .engine = engine, .reason = ordinary };
        const original = try engine.checked(c.JS_NewError(engine.context));
        if (first_fatal) c.JS_SetUncatchableError(engine.context, original);
        if (c.JS_DefinePropertyValueStr(engine.context, original, "cleanup", try token(&original_emission), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        engine.captured_exception = try token(&old_emission); // Sole-owned slot.
        engine.native_exception_diagnostics_suppressed += 1;
        const raised = engine.checked(c.JS_Throw(engine.context, original)); // Consumes sole-owned original.
        engine.native_exception_diagnostics_suppressed -= 1;
        try std.testing.expectError(error.JavaScriptException, raised);
        const actual = engine.captured_exception.?;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, if (first_fatal) original else b));
        try std.testing.expectEqual(@as(usize, 1), old_emission.calls);
        try std.testing.expectEqual(@as(usize, if (first_fatal) 0 else 1), original_emission.calls);
        try std.testing.expect(c.JS_IsUncatchableError(actual) and !c.JS_HasException(engine.context));
        engine.captured_exception = null; engine.freeValue(actual);
        if (first_fatal) {
            const cleanup = c.JS_GetException(engine.context); defer engine.freeValue(cleanup);
            try std.testing.expect(c.JS_IsStrictEqual(engine.context, cleanup, ordinary));
        }
        try std.testing.expectEqual(@as(usize, 1), original_emission.calls);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
var string_calls: usize = 0;
fn dataString(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    string_calls += 1;
    return c.JS_NewString(context, "owned rejection DATA");
}
test "native Await DATA producer Engine await capture does not infer fatal from marked rejection DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    c.JS_SetUncatchableError(engine.context, reason);
    string_calls = 0;
    const stringify = try engine.checked(c.JS_NewCFunction(engine.context, dataString, "toString", 0));
    if (c.JS_DefinePropertyValueStr(engine.context, reason, "toString", stringify, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    const promise = try engine.checked(c.JS_NewSettledPromise(engine.context, true, reason)); defer engine.freeValue(promise);
    try std.testing.expectError(error.JavaScriptException, engine.awaitValue(promise));
    try std.testing.expectEqual(@as(usize, 1), string_calls);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason) and !c.JS_HasException(engine.context));
    try std.testing.expectEqualStrings("owned rejection DATA", engine.last_error.?);
}
fn constructObject(engine: *em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue { return classes.object(engine, target); }
var poison_calls: usize = 0;
var poison_reason: c.JSValue = undefined;
fn poisonFunction(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    // Deliberately adversarial native getter control. New factory must NEVER
    // invoke it; this does not claim recovery of extra work inside a bad C ABI.
    poison_calls += 1;
    _ = c.JS_Throw(context, c.JS_DupValue(context, poison_reason));
    return c.JS_NewObject(context);
}
test "native Await DATA producer cold class uses realm intrinsic prototype despite global Function replacement or pending getter" {
    for (0..3) |mode| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var s: Scope = .{ .engine = engine }; defer s.deinit();
        const global = try s.own(c.JS_GetGlobalObject(engine.context));
        const intrinsic = try s.own(try engine.checked(c.JS_GetFunctionProto(engine.context)));
        const poison = try s.object();
        poison_reason = try s.own(try engine.checked(c.JS_NewError(engine.context)));
        c.JS_SetUncatchableError(engine.context, poison_reason);
        poison_calls = 0;
        if (mode == 0) {
            try s.put(poison, "prototype", try s.object());
            try s.set(global, "Function", poison);
        } else {
            const getter = try engine.checked(c.JS_NewCFunction(engine.context, poisonFunction, "get poisoned Function", 0));
            const atom = c.JS_NewAtom(engine.context, if (mode == 1) "Function" else "prototype"); defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, if (mode == 1) global else poison, atom, getter, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
            if (mode == 2) try s.set(global, "Function", poison);
        }
        const prototype = try s.object();
        const constructor = try s.own(try classes.constructor(engine, "OwnedColdClass", 0, prototype, constructObject, &.{}));
        const actual = try s.own(try engine.checked(c.JS_GetPrototype(engine.context, constructor)));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, intrinsic, actual));
        const instance = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null)));
        const instance_prototype = try s.own(try engine.checked(c.JS_GetPrototype(engine.context, instance)));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, prototype, instance_prototype));
        try std.testing.expectEqual(@as(usize, 0), poison_calls);
        try std.testing.expect(!c.JS_HasException(engine.context));
    }
}
test "native Await DATA producer cold class pending entry precedes class id and armed GPA allocation" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const engine = try em.Engine.init(failing.allocator(), .{}); defer engine.deinit();
    const prototype = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(prototype);
    const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
    c.JS_SetUncatchableError(engine.context, reason);
    var before: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &before);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    failing.fail_index = failing.alloc_index;
    const result = classes.constructor(engine, "MustNotAllocate", 0, prototype, constructObject, &.{});
    failing.fail_index = std.math.maxInt(usize);
    try std.testing.expectError(error.JavaScriptException, result);
    var after: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &after);
    try std.testing.expectEqual(before + 1, after);
    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, engine.captured_exception.?));
    try std.testing.expect(!c.JS_HasException(engine.context));
}
