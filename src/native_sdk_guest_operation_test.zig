//! Prepared real guest-operation/producer contrasts, not expected captures.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const guest = @import("extensions/native_sdk_guest_operation.zig");
const owned = @import("extensions/native_sdk_owned_completion.zig");
const native = @import("extensions/native_node_function.zig");
const Prompt = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const Provider = @import("extensions/native_models_stream_scope.zig").Scope;

fn makeData(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // A genuine privileged native birth, returned SUCCESSFULLY as DATA. This
    // is deliberately not a real failing GPA allocation or a fatal producer.
    _ = engine.throwNativeOutOfMemory();
    const value = c.JS_GetException(engine.context);
    std.debug.assert(!c.JS_IsUncatchableError(value));
    return value;
}
fn failAllocation(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    // The actual Node callback wrapper publishes typed allocator failure only
    // AFTER this callback has restored the real Engine allocator.
    var failing = std.testing.FailingAllocator.init(engine.gpa, .{ .fail_index = 0 });
    const original = engine.gpa;
    engine.gpa = failing.allocator();
    defer engine.gpa = original;
    const bytes = try engine.gpa.alloc(u8, 1);
    engine.gpa.free(bytes);
    return error.RequiredActualFailingAllocation;
}
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const make = try native.create(engine, "actualDataBirth", 0, makeData, &.{});
    if (c.JS_DefinePropertyValueStr(engine.context, global, "actualDataBirth", make, c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
    const fail = try native.create(engine, "actualGpaFailure", 0, failAllocation, &.{});
    if (c.JS_DefinePropertyValueStr(engine.context, global, "actualGpaFailure", fail, c.JS_PROP_C_W_E) < 0) return @import("extensions/native_js_values.zig").capture(engine);
}
fn same(engine: *em.Engine, a: c.JSValue, b: c.JSValue) !void { try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b)); }
fn balanced(engine: *em.Engine) !void {
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(!c.JS_HasException(engine.context));
}
test "SDK guest boundary same getter or call born private DATA remains ordinary" {
    inline for (.{ Prompt, Provider }) |Scope| {
        for ([_]bool{ false, true }) |getter| {
            const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
            try install(engine);
            var s: Scope = .{ .engine = engine };
            const source = if (getter) "({get value(){const a=actualDataBirth();throw a}})" else "(()=>{const a=actualDataBirth();throw a})";
            const target = try owned.ownRoot(&s, try engine.eval(source, "same-operation-private-data.js", c.JS_EVAL_TYPE_GLOBAL));
            const result = if (getter) guest.get(&s, target, "value") else guest.call(&s, target, c.pi_js_undefined(), &.{});
            try std.testing.expectError(error.JavaScriptException, owned.finishValue(&s, result));
            const reason = engine.captured_exception orelse return error.RequiredOrdinaryData;
            try same(engine, reason, engine.native_allocation_exception orelse return error.RequiredNativeBirth);
            try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
            try std.testing.expect(!c.JS_IsUncatchableError(reason));
            try balanced(engine);
        }
    }
}
test "SDK guest boundary historical successful native DATA later thrown preserves identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    var s: Prompt = .{ .engine = engine };
    const target = try owned.ownRoot(&s, try engine.eval("globalThis.savedActualData=actualDataBirth();({get value(){throw savedActualData}})", "earlier-operation-private-data.js", c.JS_EVAL_TYPE_GLOBAL));
    const reason = engine.native_allocation_exception orelse return error.RequiredNativeBirth;
    const tag = c.pi_js_native_allocation_error_generation(reason);
    try std.testing.expectError(error.JavaScriptException, owned.finishValue(&s, guest.get(&s, target, "value")));
    try same(engine, reason, engine.captured_exception orelse return error.RequiredOrdinaryData);
    try std.testing.expectEqual(tag, c.pi_js_native_allocation_error_generation(reason));
    try std.testing.expect(!c.JS_IsUncatchableError(reason));
    try balanced(engine);
}
test "SDK guest boundary real callback GPA failure is actual current fatal not prior private DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    var s: Prompt = .{ .engine = engine };
    const target = try owned.ownRoot(&s, try engine.eval("globalThis.savedActualData=actualDataBirth();globalThis.afterActualFatal=false;(()=>{try{actualGpaFailure()}catch(e){afterActualFatal=true}afterActualFatal=true})", "actual-producer-failure.js", c.JS_EVAL_TYPE_GLOBAL));
    const old = c.JS_DupValue(engine.context, engine.native_allocation_exception orelse return error.RequiredNativeBirth); defer engine.freeValue(old);
    try std.testing.expectError(error.JavaScriptException, owned.finishValue(&s, guest.call(&s, target, c.pi_js_undefined(), &.{})));
    const reason = engine.captured_exception orelse return error.RequiredFatalProducer;
    try same(engine, reason, engine.native_allocation_exception orelse return error.RequiredFatalProducer);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, old, reason));
    try std.testing.expect(!c.JS_IsUncatchableError(old));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    const after = c.JS_GetPropertyStr(engine.context, global, "afterActualFatal"); defer engine.freeValue(after);
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, after));
    try balanced(engine);
}
test "SDK guest boundary direct status and constructor keep ordinary diagnostic uncoerced" {
    for ([_]bool{ false, true }) |constructor| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try install(engine);
        var s: Provider = .{ .engine = engine };
        const source = if (constructor) "(function Actual(){globalThis.selectedActualData=actualDataBirth();throw selectedActualData})" else "new Proxy({},{defineProperty(){globalThis.selectedActualData=actualDataBirth();throw selectedActualData}})";
        const target = try owned.ownRoot(&s, try engine.eval(source, "actual-status-constructor-data.js", c.JS_EVAL_TYPE_GLOBAL));
        if (constructor) try std.testing.expectError(error.JavaScriptException, owned.finishValue(&s, guest.construct(&s, target, &.{})))
        else try std.testing.expectError(error.JavaScriptException, owned.finishVoid(&s, guest.put(&s, target, "x", c.pi_js_undefined())));
        const reason = engine.captured_exception orelse return error.RequiredOrdinaryData;
        try same(engine, reason, engine.native_allocation_exception orelse return error.RequiredNativeBirth);
        try std.testing.expect(!c.JS_IsUncatchableError(reason));
        try balanced(engine);
    }
}
test "SDK guest boundary definitions assignment receiver binary and scope-root ownership" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Provider = .{ .engine = engine };
    const target = try owned.ownRoot(&s, try engine.eval("({base:4,method(n){return this.base+n},set assigned(v){this.received=v}})", "actual-guest-receiver.js", c.JS_EVAL_TYPE_GLOBAL));
    try guest.put(&s, target, "literal", c.JS_NewInt32(engine.context, 7));
    try guest.index(&s, target, 2, c.JS_NewInt32(engine.context, 9));
    try guest.set(&s, target, "assigned", c.JS_NewInt32(engine.context, 11));
    const called = try guest.invoke(&s, target, "method", &.{c.JS_NewInt32(engine.context, 3)});
    const compared = try guest.binary(&s, 6, called, c.JS_NewInt32(engine.context, 6));
    try std.testing.expectEqual(@as(c_int, 1), c.JS_ToBool(engine.context, compared));
    try same(engine, try guest.get(&s, target, "literal"), called);
    try same(engine, try guest.at(&s, target, 2), c.JS_NewInt32(engine.context, 9));
    try same(engine, try guest.get(&s, target, "received"), c.JS_NewInt32(engine.context, 11));
    try owned.finishVoid(&s, {});
    try balanced(engine);
}
test "SDK guest boundary negative status without reason and actual pending precede host error" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const historical = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(historical);
    engine.captured_exception = c.JS_DupValue(engine.context, historical);
    var missing: guest.Boundary = .{ .engine = engine }; try missing.begin();
    try std.testing.expectError(error.JavaScriptException, missing.finishStatus(-1));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, historical, engine.captured_exception orelse return error.RequiredContractFailure));
    try balanced(engine);
    for ([_]bool{ false, true }) |fatal| {
        const reason = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(reason);
        if (fatal) c.JS_SetUncatchableError(engine.context, reason);
        var boundary: guest.Boundary = .{ .engine = engine }; try boundary.begin();
        // Actual native pending error, not a tagged argument/diagnostic. The
        // marked variant is a privileged native fatal-event fixture.
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        const generation = engine.native_allocation_generation;
        try std.testing.expectError(error.JavaScriptException, boundary.finishVoid(error.OutOfMemory));
        try same(engine, reason, engine.captured_exception orelse return error.RequiredOriginalPending);
        try std.testing.expectEqual(generation, engine.native_allocation_generation);
        try balanced(engine);
    }
}
