//! Thirteen declared actual Node inspector entry/ownership controls.
//! The first ten observers also accept the pinned Source node:util inspector.
//! Build installation, metadata, Source capture and runtime are separate steps.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const inspect = @import("extensions/native_node_util_inspect.zig");
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, value);
    return value;
}
fn fatalCleared(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    return c.pi_js_undefined();
}
fn publish(engine: *v.em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0)
        return error.ActualInspectControlPublicationFailed;
}
const Fixture = struct {
    engine: *v.em.Engine,
    exports: inspect.Exports,
    fn init() !Fixture {
        const engine = try v.em.Engine.init(std.testing.allocator, .{});
        errdefer engine.deinit();
        const inputs = try inspect.capturePrimordials(engine);
        const created = inspect.create(engine, inputs);
        var completion = owned.Completion.initVoid(engine, if (created) |_| {} else |err| @as(anyerror!void, err));
        inline for (std.meta.fields(inspect.Inputs)) |field| completion.release(@field(inputs, field.name));
        completion.finishVoid() catch |err| {
            if (created) |result| result.deinit(engine) else |_| {}
            return err;
        };
        const result = try created;
        errdefer result.deinit(engine);
        try publish(engine, "actualInspect", result.inspect);
        try engine.bindFunction("actualInspectPrivateData", privateData, 0);
        try engine.bindFunction("actualInspectFlaggedData", flaggedData, 0);
        try engine.bindFunction("actualInspectFatalCleared", fatalCleared, 0);
        return .{ .engine = engine, .exports = result };
    }
    fn deinit(self: Fixture) void { self.exports.deinit(self.engine); self.engine.deinit(); }
    fn run(self: Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{@embedFile("extensions/fixtures/native-node-inspect-observer.mjs"), "\n", tail});
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-inspect-observer.mjs");
        self.engine.freeValue(result);
    }
    fn data(self: Fixture) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "savedInspectData"));
    }
};
fn observe(comptime name: []const u8) !void {
    const fixture = try Fixture.init(); defer fixture.deinit();
    try fixture.run(name ++ "(actualInspect);");
}
test "native actual inspect ordinary callable shape and retained original defaults" { try observe("observeInspectShape"); }
test "native actual inspect primitive UTF16 negative zero Symbol and BigInt" { try observe("observeInspectPrimitives"); }
test "native actual inspect numeric separators and actual string truncation" { try observe("observeInspectNumeric"); }
test "native actual inspect captured primordial ignores late global replacement" { try observe("observeInspectCapturedPrimordials"); }
test "native actual inspect custom callback receiver arguments and same inspector" { try observe("observeInspectCustomArguments"); }
test "native actual inspect custom ordinary throw keeps exact reason" { try observe("observeInspectOrdinaryCustomThrow"); }
test "native actual inspect actual toStringTag getter ordinary catch" { try observe("observeInspectTagCatch"); }
test "native actual inspect actual instance operator ordinary catch" { try observe("observeInspectInstanceCatch"); }
test "native actual inspect genuine proxy unwrap and revoked status" { try observe("observeInspectProxyDetails"); }
test "native actual inspect default assignment descriptor and getter order" { try observe("observeInspectDefaultAssignment"); }
test "native actual inspect same tag getter private DATA throw stays ordinary" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=undefined;
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){savedInspectData=actualInspectPrivateData();throw savedInspectData;}});
        \\inspectAssert(actualInspect(input)==="{}","private tag error was caught");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual inspect successful flagged private tag value remains DATA" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedInspectData=undefined;
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){savedInspectData=actualInspectFlaggedData();return savedInspectData;}});
        \\inspectAssert(actualInspect(input)==="{}","successful flagged tag DATA");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual inspect retained allocator B1 bypasses ordinary tag catch" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    const result = fixture.run(
        \\const input={};Object.defineProperty(input,Symbol.toStringTag,{get(){actualInspectFatalCleared();return "";}});
        \\actualInspect(input);
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const first = fixture.engine.native_allocation_exception orelse return error.MissingActualInspectAllocationReason;
    const reason = fixture.engine.captured_exception orelse return error.MissingActualInspectCapturedReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
