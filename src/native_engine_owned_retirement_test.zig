//! Actual shared Engine retirement controls. Prepared/unrun, no mock Engine.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const Mode = enum { ordinary, old_private, fresh_private, marked_fatal };
const Probe = struct {
    engine: *em.Engine,
    initial: c.JSValue,
    secondary: c.JSValue,
    mode: Mode,
    returned_class: c.JSClassID = 0,
    emitted: ?c.JSValue = null,
    finalized: usize = 0,
    raw_unmarked: bool = false,
    active: bool = true,
    fn finalize(_: ?*c.JSRuntime, object: c.JSValue) callconv(.c) void {
        const self: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(object, c.JS_GetClassID(object)) orelse return));
        self.finalized += 1;
        if (!self.active) return;
        const reason = if (self.mode == .fresh_private) blk: {
            _ = self.engine.throwNativeOutOfMemory(); // Deliberately NOT fatal.
            const actual = c.JS_GetException(self.engine.context);
            self.raw_unmarked = !c.JS_IsUncatchableError(actual);
            break :blk actual;
        } else c.JS_DupValue(self.engine.context, self.secondary);
        self.emitted = c.JS_DupValue(self.engine.context, reason);
        _ = c.JS_Throw(self.engine.context, reason);
    }
    fn produce(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
        if (argc != 1) return c.JS_ThrowTypeError(context, "exact probe argument required");
        const self: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(argv[0], c.JS_GetClassID(argv[0])) orelse return c.JS_ThrowTypeError(context, "actual probe holder required")));
        const returned = c.JS_NewObjectClass(context, self.returned_class);
        if (c.JS_IsException(returned)) return returned;
        _ = c.JS_SetOpaque(returned, self);
        _ = c.JS_Throw(context, c.JS_DupValue(context, self.initial));
        // A genuine raw native convention violation. The real JS_Call must
        // return this sole-owned carrier with actual pending A; assert below.
        return returned;
    }
};
fn verify(mode: Mode, first_fatal: bool, captured_history: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    const initial = try engine.checked(c.JS_NewError(engine.context)); defer engine.freeValue(initial);
    if (first_fatal) c.JS_SetUncatchableError(engine.context, initial);
    const secondary = if (mode == .old_private) blk: {
        _ = engine.throwNativeOutOfMemory(); break :blk c.JS_GetException(engine.context);
    } else try engine.checked(c.JS_NewError(engine.context));
    defer engine.freeValue(secondary);
    if (mode == .marked_fatal) c.JS_SetUncatchableError(engine.context, secondary);
    if (mode == .old_private) {
        try std.testing.expect(c.pi_js_native_allocation_error_generation(secondary) != 0);
        try std.testing.expect(!c.JS_IsUncatchableError(secondary));
    }
    if (captured_history) {
        _ = engine.throwNativeOutOfMemory();
        const data = c.JS_GetException(engine.context);
        c.JS_SetUncatchableError(engine.context, data);
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        const previous = engine.captured_exception; engine.captured_exception = data;
        if (previous) |value| engine.freeValue(value);
    }
    var probe: Probe = .{ .engine = engine, .initial = initial, .secondary = secondary, .mode = mode };
    defer { probe.active = false; if (probe.emitted) |value| engine.freeValue(value); }
    _ = c.JS_NewClassID(engine.runtime, &probe.returned_class);
    const definition: c.JSClassDef = .{ .class_name = "Actual sole Engine retirement carrier", .finalizer = Probe.finalize };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, probe.returned_class, &definition));
    var holder_class: c.JSClassID = 0; _ = c.JS_NewClassID(engine.runtime, &holder_class);
    const holder_definition: c.JSClassDef = .{ .class_name = "Borrowed synchronous Engine probe holder" };
    try std.testing.expectEqual(@as(c_int, 0), c.JS_NewClass(engine.runtime, holder_class, &holder_definition));
    const holder = try engine.checked(c.JS_NewObjectClass(engine.context, holder_class)); defer engine.freeValue(holder);
    _ = c.JS_SetOpaque(holder, &probe);
    const function = try engine.checked(c.JS_NewCFunction(engine.context, Probe.produce, "actualRawRetirement", 1)); defer engine.freeValue(function);
    var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) { _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context)); };
    const generation = engine.native_allocation_generation;
    const raw = c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, @constCast(&[_]c.JSValue{holder}));
    var raw_owned = true;
    defer { probe.active = false; if (raw_owned) engine.freeValue(raw); }
    try std.testing.expect(!c.JS_IsException(raw));
    try std.testing.expect(c.JS_IsObject(raw));
    try std.testing.expect(c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(usize, 0), probe.finalized);
    raw_owned = false; // checked consumes the sole result on failure.
    try std.testing.expectError(error.JavaScriptException, engine.checked(raw));
    const actual = engine.captured_exception orelse return error.MissingActualRetirementReason;
    const expected = if (first_fatal or mode == .ordinary or mode == .old_private) initial else probe.emitted.?;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, actual));
    try std.testing.expectEqual(first_fatal or mode == .fresh_private or mode == .marked_fatal, c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(@as(usize, 1), probe.finalized);
    if (mode == .fresh_private) {
        try std.testing.expect(probe.raw_unmarked);
        try std.testing.expect(engine.native_allocation_generation != generation);
        try std.testing.expect(!c.JS_IsStrictEqual(engine.context, initial, probe.emitted.?));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(probe.emitted.?) != 0);
    } else try std.testing.expect(!c.JS_IsStrictEqual(engine.context, initial, probe.emitted.?));
    const output = engine.leaveNativeInvocation(&invocation, engine.throwCaptured());
    try std.testing.expect(c.JS_IsException(output));
    const final = c.JS_GetException(engine.context); defer engine.freeValue(final);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, expected, final));
}
test "shared Engine retirement promotes fresh raw private OOM from sole returned carrier before ordinary pending reason" {
    try verify(.fresh_private, false, false);
}
test "shared Engine retirement preserves first ordinary reason against ordinary cleanup" {
    try verify(.ordinary, false, false);
}
test "shared Engine retirement does not promote old private tag thrown by cleanup" {
    try verify(.old_private, false, false);
}
test "shared Engine retirement preserves earlier actual fatal and ignores captured flagged private DATA" {
    try verify(.marked_fatal, true, false);
    try verify(.ordinary, false, true);
}
test "shared Engine retirement leaves flagged private actual rejected PromiseResult as DATA" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    _ = engine.throwNativeOutOfMemory();
    const data = c.JS_GetException(engine.context); defer engine.freeValue(data);
    c.JS_SetUncatchableError(engine.context, data);
    try std.testing.expect(c.JS_IsUncatchableError(data));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
    var invocation: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    defer if (invocation.active) { _ = engine.leaveNativeInvocation(&invocation, c.pi_js_undefined()); if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context)); };
    var resolving: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &resolving)); defer engine.freeValue(promise);
    defer { engine.freeValue(resolving[0]); engine.freeValue(resolving[1]); }
    const rejected = try engine.checked(c.JS_Call(engine.context, resolving[1], c.pi_js_undefined(), 1, @constCast(&[_]c.JSValue{data}))); defer engine.freeValue(rejected);
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, promise));
    const payload = try engine.checked(c.JS_PromiseResult(engine.context, promise)); defer engine.freeValue(payload);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, payload));
    try std.testing.expect(c.JS_IsUncatchableError(payload));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(invocation.first == null);
    const returned = engine.leaveNativeInvocation(&invocation, c.JS_DupValue(engine.context, payload)); defer engine.freeValue(returned);
    try std.testing.expect(!c.JS_IsException(returned));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, data, returned));
}