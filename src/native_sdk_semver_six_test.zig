//! Real VM controls for the private SDK supplier, prepared and unrun.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const supplier = @import("extensions/native_semver785.zig");
const c = em.c;
fn install(engine: *em.Engine) !void {
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    try js.define(engine, global, "privateSdkSemver", try supplier.create(engine));
}
test "private SDK semver exposes only six ordinary nonconstructible functions" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(
        \\const names=['valid','validRange','gt','rcompare','satisfies','maxSatisfying'];if(Object.keys(privateSdkSemver).sort().join()!==names.slice().sort().join())throw Error('private namespace shape');for(const name of names){const fn=privateSdkSemver[name];if(fn.name!==name||fn.length!==(name==='valid'||name==='validRange'?2:3)||Object.hasOwn(fn,'prototype'))throw Error('actual function metadata');let rejected=false;try{Reflect.construct(fn,[])}catch(e){rejected=e instanceof TypeError}if(!rejected)throw Error('arrow construction')}
    , "private-sdk-semver-shape.mjs"); engine.freeValue(result);
}
test "private SDK semver actual factory preserves pending entry before namespace publication" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    _ = c.JS_Throw(engine.context, c.JS_NewInt32(engine.context, 718));
    try std.testing.expectError(error.JavaScriptException, supplier.create(engine));
    const reason = engine.captured_exception orelse return error.MissingPendingSemverReason;
    var number: i32 = 0; try std.testing.expectEqual(@as(c_int, 0), c.JS_ToInt32(engine.context, &number, reason));
    try std.testing.expectEqual(@as(i32, 718), number);
}
test "private SDK semver captured marked history remains DATA on a successful call" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    _ = engine.throwNativeOutOfMemory();
    const data = c.JS_GetException(engine.context); defer engine.freeValue(data);
    c.JS_SetUncatchableError(engine.context, data);
    try std.testing.expect(c.JS_IsUncatchableError(data));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
    const previous = engine.captured_exception; engine.captured_exception = c.JS_DupValue(engine.context, data);
    if (previous) |value| engine.freeValue(value);
    const result = try engine.evalModule("if(privateSdkSemver.valid('v1.2.3+build')!=='1.2.3')throw Error('valid result')", "private-sdk-semver-captured-data.mjs");
    engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, engine.captured_exception orelse return error.LostSemverDiagnosticData));
}
test "private SDK semver explicit unsupported options do not masquerade as loose matching" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const result = try engine.evalModule(
        \\for(const [name,args] of [['valid',['01.2.3',true]],['validRange',['01.x',{loose:true}]],['satisfies',['1.2.3-a','*',{includePrerelease:true}]]]){let rejected=false;try{privateSdkSemver[name](...args)}catch(e){rejected=e instanceof TypeError&&e.message.includes('default options only')}if(!rejected)throw Error('unsupported option silently accepted')}if(privateSdkSemver.valid('01.2.3')!==null)throw Error('default strict grammar changed')
    , "private-sdk-semver-options-boundary.mjs"); engine.freeValue(result);
}
const FinalizerProbe = struct {
    engine: *em.Engine,
    reason: c.JSValue,
    count: *usize,
    active: bool = true,
    fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const self: *FinalizerProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
        self.count.* += 1;
        if (self.active) _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.reason));
    }
};
test "private SDK semver actual per-root retirement retains first fatal across two native finalizers" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const first = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(first);
    const second = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(second);
    c.JS_SetUncatchableError(engine.context, first); c.JS_SetUncatchableError(engine.context, second);
    var count: usize = 0;
    var one: FinalizerProbe = .{ .engine = engine, .reason = first, .count = &count };
    var two: FinalizerProbe = .{ .engine = engine, .reason = second, .count = &count };
    defer { one.active = false; two.active = false; }
    var class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "SemverOwnedRetirementProbe", .finalizer = FinalizerProbe.finalize };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, class, &definition));
    var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) { _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context)); };
    var scope: @import("extensions/native_semver785_scope.zig").Scope = .{ .engine = engine };
    var retired = false; defer if (!retired) scope.deinit();
    const value_one = try engine.checked(c.JS_NewObjectClass(engine.context, class)); _ = c.JS_SetOpaque(value_one, &one); _ = try scope.own(value_one);
    const value_two = try engine.checked(c.JS_NewObjectClass(engine.context, class)); _ = c.JS_SetOpaque(value_two, &two); _ = try scope.own(value_two);
    scope.deinit(); retired = true;
    const result = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined());
    try std.testing.expect(c.JS_IsException(result));
    const actual = c.JS_GetException(engine.context); defer engine.freeValue(actual);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, actual));
    try std.testing.expect(c.JS_IsUncatchableError(actual)); try std.testing.expectEqual(@as(usize, 2), count);
}

fn rawAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "rawSemverAllocation", c.JS_DupValue(context, reason), c.JS_PROP_C_W_E) < 0) {
        engine.freeValue(reason);
        return c.JS_Throw(context, c.JS_GetException(context));
    }
    return c.JS_Throw(context, reason);
}
test "private SDK semver raw private allocation getter escapes forgiving catches with exact identity" {
    for ([_][]const u8{ "valid", "validRange" }) |method| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try install(engine);
        const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
        try js.define(engine, global, "rawSemverGetter", try engine.checked(c.JS_NewCFunction(engine.context, rawAllocation, "rawSemverGetter", 0)));
        try js.define(engine, global, "rawSemverMethod", try engine.checked(c.JS_NewStringLen(engine.context, method.ptr, method.len)));
        try std.testing.expectError(error.JavaScriptException, engine.evalModule(
            \\const original=Object.getOwnPropertyDescriptor(String.prototype,'trim');globalThis.rawSemverCaught=false;Object.defineProperty(String.prototype,'trim',{configurable:true,get:rawSemverGetter});try{try{privateSdkSemver[rawSemverMethod]('1.2.3')}catch{rawSemverCaught=true}}finally{Object.defineProperty(String.prototype,'trim',original)}
        , "private-sdk-semver-raw-getter.mjs"));
        const expected = try js.get(engine, global, "rawSemverAllocation"); defer engine.freeValue(expected);
        const actual = engine.captured_exception orelse return error.MissingRawSemverReason;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, actual));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        const caught = try js.get(engine, global, "rawSemverCaught"); defer engine.freeValue(caught);
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToBool(engine.context, caught));
    }
}
const RawCleanupProbe = struct {
    engine: *em.Engine,
    ordinary: c.JSValue,
    later: c.JSValue,
    mode: bool,
    class: c.JSClassID = 0,
    initial: ?c.JSValue = null,
    cleanup: ?c.JSValue = null,
    finalized: usize = 0,
    active: bool = true,
    fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const self: *RawCleanupProbe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
        self.finalized += 1;
        if (!self.active) return;
        _ = if (self.mode) c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.later)) else self.engine.throwNativeOutOfMemory();
        const reason = c.JS_GetException(self.engine.context);
        self.cleanup = c.JS_DupValue(self.engine.context, reason);
        _ = c.JS_Throw(self.engine.context, reason);
    }
    fn produce(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        if (argc < 1) return c.JS_ThrowTypeError(context, "probe argument required");
        const self: *RawCleanupProbe = @ptrCast(@alignCast(c.JS_GetOpaque(argv[0], c.JS_GetClassID(argv[0])) orelse return c.JS_ThrowTypeError(context, "probe identity required")));
        const result = c.JS_NewObjectClass(context, self.class);
        if (c.JS_IsException(result)) return result;
        _ = c.JS_SetOpaque(result, self);
        _ = if (self.mode) self.engine.throwNativeOutOfMemoryFatal() else c.JS_Throw(context, c.JS_DupValue(context, self.ordinary));
        const reason = c.JS_GetException(context);
        self.initial = c.JS_DupValue(context, reason);
        _ = c.JS_Throw(context, reason);
        // Deliberate native convention violation tests the raw-result guard.
        // The sole-owned returned carrier's finalizer publishes another event.
        return result;
    }
};
test "private SDK semver raw result cleanup promotes actual fresh OOM and preserves earlier raw OOM" {
    for ([_]bool{ false, true }) |mode| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        const ordinary = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(ordinary);
        const later = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(later);
        c.JS_SetUncatchableError(engine.context, later);
        var probe: RawCleanupProbe = .{ .engine = engine, .ordinary = ordinary, .later = later, .mode = mode };
        defer { probe.active = false; if (probe.initial) |value| engine.freeValue(value); if (probe.cleanup) |value| engine.freeValue(value); }
        _ = c.JS_NewClassID(engine.runtime, &probe.class);
        const definition: c.JSClassDef = .{ .class_name = "SemverRawCleanupProbe", .finalizer = RawCleanupProbe.finalize };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, probe.class, &definition));
        // Separate holder has no finalizer: it only carries a borrowed stack
        // pointer while the synchronous actual C callback is running.
        var holder_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &holder_class);
        const holder_definition: c.JSClassDef = .{ .class_name = "SemverRawProbeHolder" };
        try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, holder_class, &holder_definition));
        const holder = try engine.checked(c.JS_NewObjectClass(engine.context, holder_class)); defer engine.freeValue(holder);
        _ = c.JS_SetOpaque(holder, &probe);
        const function = try engine.checked(c.JS_NewCFunction(engine.context, RawCleanupProbe.produce, "semverRawProducer", 1)); defer engine.freeValue(function);
        var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
        defer if (invocation.active) { _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context)); };
        var scope: @import("extensions/native_semver785_scope.zig").Scope = .{ .engine = engine };
        defer scope.deinit();
        try std.testing.expectError(error.JavaScriptException, scope.call(function, c.pi_js_undefined(), &.{holder}));
        const actual = engine.captured_exception orelse return error.MissingRawCleanupReason;
        const expected = if (mode) probe.initial.? else probe.cleanup.?;
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, probe.initial.?, probe.cleanup.?));
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, actual));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(@as(usize, 1), probe.finalized);
        _ = engine.leaveNativeInvocation(&invocation, engine.throwCaptured());
        const final = c.JS_GetException(engine.context); defer engine.freeValue(final);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, final));
    }
}
fn rethrowOldAllocation(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context); defer c.JS_FreeValue(context, global);
    const old = c.JS_GetPropertyStr(context, global, "oldSemverAllocation");
    if (c.JS_IsException(old)) return old;
    return c.JS_Throw(context, old);
}
test "private SDK semver old private allocation rethrow remains ordinary in forgiving catch" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try install(engine);
    const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
    _ = engine.throwNativeOutOfMemory();
    const old = c.JS_GetException(engine.context); defer engine.freeValue(old);
    try std.testing.expect(!c.JS_IsUncatchableError(old));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(old) != 0);
    try js.define(engine, global, "oldSemverAllocation", c.JS_DupValue(engine.context, old));
    try js.define(engine, global, "rethrowOldSemverAllocation", try engine.checked(c.JS_NewCFunction(engine.context, rethrowOldAllocation, "rethrowOldSemverAllocation", 0)));
    const result = try engine.evalModule(
        \\const original=String.prototype.trim;String.prototype.trim=rethrowOldSemverAllocation;try{if(privateSdkSemver.valid('1.2.3')!==null)throw Error('ordinary rethrow not caught')}finally{String.prototype.trim=original}
    , "private-sdk-semver-old-private-rethrow.mjs"); engine.freeValue(result);
    try std.testing.expect(!c.JS_IsUncatchableError(old));
}
fn createAllocationData(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    const data = c.JS_GetException(context);
    const global = c.JS_GetGlobalObject(context); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(context, global, "oldSemverAllocation", data, c.JS_PROP_C_W_E) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    return c.JS_DupValue(context, receiver);
}
test "private SDK semver allocation DATA born in earlier successful operation stays ordinary in later throw" {
    for ([_][]const u8{ "valid", "validRange" }) |method| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        try install(engine);
        const global = c.JS_GetGlobalObject(engine.context); defer engine.freeValue(global);
        try js.define(engine, global, "createSemverAllocationData", try engine.checked(c.JS_NewCFunction(engine.context, createAllocationData, "createSemverAllocationData", 0)));
        try js.define(engine, global, "rethrowOldSemverAllocation", try engine.checked(c.JS_NewCFunction(engine.context, rethrowOldAllocation, "rethrowOldSemverAllocation", 0)));
        try js.define(engine, global, "dataSemverMethod", try engine.checked(c.JS_NewStringLen(engine.context, method.ptr, method.len)));
        const result = try engine.evalModule(
            \\const later=dataSemverMethod==='valid'?'match':'replace',trim=String.prototype.trim,method=String.prototype[later];String.prototype.trim=createSemverAllocationData;String.prototype[later]=rethrowOldSemverAllocation;try{if(privateSdkSemver[dataSemverMethod]('1.2.3')!==null)throw Error('older DATA became fatal')}finally{String.prototype.trim=trim;String.prototype[later]=method}
        , "private-sdk-semver-earlier-operation-data.mjs"); engine.freeValue(result);
        const data = try js.get(engine, global, "oldSemverAllocation"); defer engine.freeValue(data);
        try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        try std.testing.expect(!c.JS_IsUncatchableError(data));
    }
}

test "private SDK semver same-operation private DATA survives actual forgiving catches" {
    inline for (.{ "valid", "validRange" }) |method| {
        inline for ([_]bool{ false, true }) |getter| {
            const engine = try em.Engine.init(std.testing.allocator, .{});
            defer engine.deinit();
            try install(engine);
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            try js.define(engine, global, "createSemverAllocationData", try engine.checked(c.JS_NewCFunction(engine.context, createAllocationData, "createSemverAllocationData", 0)));
            try js.define(engine, global, "sameSemverMethod", try engine.checked(c.JS_NewString(engine.context, method)));
            try js.define(engine, global, "sameSemverGetter", c.pi_js_bool(engine.context, @intFromBool(getter)));
            const result = try engine.evalModule(
                \\const original=Object.getOwnPropertyDescriptor(String.prototype,'trim');
                \\const fail=function(){createSemverAllocationData.call(this);throw oldSemverAllocation};
                \\Object.defineProperty(String.prototype,'trim',sameSemverGetter?{configurable:true,get:fail}:{configurable:true,writable:true,value:fail});
                \\try{if(privateSdkSemver[sameSemverMethod]('1.2.3')!==null)throw Error('same-operation DATA escaped forgiving catch')}finally{Object.defineProperty(String.prototype,'trim',original)}
            , "private-sdk-semver-same-operation-data.mjs");
            engine.freeValue(result);
            const data = try js.get(engine, global, "oldSemverAllocation");
            defer engine.freeValue(data);
            try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
            try std.testing.expect(!c.JS_IsUncatchableError(data));
            try std.testing.expect(engine.native_fatal_invocation == null);
        }
    }
}
