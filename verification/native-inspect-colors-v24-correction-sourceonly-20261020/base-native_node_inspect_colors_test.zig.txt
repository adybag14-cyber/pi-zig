//! Genuine selected inspect color Source/native controls and actual entry paths.
//! Source projection keeps the original tables/functions and receives the same
//! real inspector/primordials as lexical imports. No tests run from build.zig.
const std = @import("std");
const v = @import("extensions/native_ai_provider_values.zig");
const c = v.c;
const inspector = @import("extensions/native_node_util_inspect.zig");
const functions = @import("extensions/native_node_module_callable.zig");
const owned = @import("extensions/native_sdk_owned_completion.zig");

const Token = struct { probe: *Probe, index: usize };
const Probe = struct {
    engine: ?*v.em.Engine = null,
    class_id: c.JSClassID = 0,
    enabled: bool = false,
    fail_on: ?usize = null,
    counts: [4]u32 = @splat(0),
    tokens: [4]Token = undefined,
    fn init(self: *Probe, engine: *v.em.Engine) !void {
        self.* = .{ .engine = engine };
        for (&self.tokens, 0..) |*token, index| token.* = .{ .probe = self, .index = index };
        _ = c.JS_NewClassID(engine.runtime, &self.class_id);
        const definition: c.JSClassDef = .{ .class_name = "Actual inspect color operand", .finalizer = finalize };
        if (c.JS_NewClass(engine.runtime, self.class_id, &definition) < 0)
            return error.ActualInspectColorClassFailed;
        self.enabled = true;
    }
    fn finalize(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
        const raw = c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return;
        const token: *Token = @ptrCast(@alignCast(raw));
        _ = c.JS_SetOpaque(value, null);
        const self = token.probe;
        self.counts[token.index] += 1;
        if (!self.enabled or self.fail_on == null or self.fail_on.? != token.index) return;
        self.fail_on = null;
        const engine = self.engine orelse return;
        _ = engine.throwNativeOutOfMemoryFatal();
        engine.freeValue(c.JS_GetException(engine.context));
    }
};
var active_probe: ?*Probe = null;
fn indexOf(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) ?usize {
    if (argc < 1) return null;
    var index: u32 = 0;
    if (c.JS_ToUint32(context, &index, argv[0]) < 0 or index >= 4) return null;
    return index;
}
fn make(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_probe orelse return c.pi_js_undefined();
    const index = indexOf(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "color holder index");
    const value = c.JS_NewObjectProtoClass(context, c.pi_js_null(), probe.class_id);
    if (!c.JS_IsException(value)) _ = c.JS_SetOpaque(value, &probe.tokens[index]);
    return value;
}
fn count(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_probe orelse return c.pi_js_undefined();
    const index = indexOf(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "color count index");
    return c.JS_NewUint32(context, probe.counts[index]);
}
fn failOn(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_probe orelse return c.pi_js_undefined();
    probe.fail_on = indexOf(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "color failure index");
    return c.pi_js_undefined();
}
fn fatal(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    return c.pi_js_undefined();
}
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
fn publish(engine: *v.em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
    defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, name,
        c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0)
        return error.ActualInspectColorPublicationFailed;
}

const Fixture = struct {
    engine: ?*v.em.Engine = null,
    exports: ?inspector.Exports = null,
    probe: ?*Probe = null,
    progress: c.JSValue = undefined,
    fn init(self: *Fixture, probe: *Probe, source_mode: bool) !void {
        self.* = .{};
        const engine = try v.em.Engine.init(std.testing.allocator, .{});
        self.engine = engine;
        self.progress = c.pi_js_undefined();
        errdefer self.deinit();
        const inputs = try inspector.capturePrimordials(engine);
        const created = inspector.create(engine, inputs);
        var completion = owned.Completion.initVoid(engine, if (created) |_| {} else |err| @as(anyerror!void, err));
        inline for (std.meta.fields(inspector.Inputs)) |field| completion.release(@field(inputs, field.name));
        completion.finishVoid() catch |err| {
            if (created) |result| result.deinit(engine) else |_| {}
            return err;
        };
        self.exports = try created;
        try publish(engine, "actualInspect", self.exports.?.inspect);
        const roots = try functions.capturedRoots(engine, self.exports.?.inspect);
        try std.testing.expectEqual(@as(usize, 13), roots.len);
        const stylizer = try engine.checked(c.JS_GetPropertyStr(engine.context, roots[0], "stylizeWithColor"));
        defer engine.freeValue(stylizer);
        try publish(engine, "actualColor", stylizer);
        self.probe = probe;
        try probe.init(engine);
        active_probe = probe;
        try engine.bindFunction("colorMake", make, 1);
        try engine.bindFunction("colorCount", count, 1);
        try engine.bindFunction("colorFailOn", failOn, 1);
        try engine.bindFunction("colorFatal", fatal, 0);
        try engine.bindFunction("colorPrivateData", privateData, 0);
        try engine.bindFunction("colorFlaggedData", flaggedData, 0);
        if (source_mode) try self.runText(
            @embedFile("extensions/fixtures/native-node-inspect-colors-v24-source.mjs") ++
            "\nglobalThis.actualColor=installInspectColorsSource(actualInspect,Object.assign,Object.defineProperty);",
            "actual-inspect-color-source-install.mjs");
        try self.runText("globalThis.colorProgress={entered:false,later:false};", "actual-inspect-color-progress.mjs");
        const global = try engine.checked(c.JS_GetGlobalObject(engine.context));
        defer engine.freeValue(global);
        self.progress = try engine.checked(c.JS_GetPropertyStr(engine.context, global, "colorProgress"));
    }
    fn deinit(self: *Fixture) void {
        if (self.probe) |probe| {
            probe.enabled = false;
            probe.fail_on = null;
            if (active_probe == probe) active_probe = null;
            self.probe = null;
        }
        if (self.engine) |engine| {
            engine.freeValue(self.progress);
            if (self.exports) |result| { self.exports = null; result.deinit(engine); }
            self.engine = null;
            engine.deinit();
        }
    }
    fn runText(self: *Fixture, source: []const u8, filename: [:0]const u8) !void {
        const engine = self.engine.?;
        const result = try engine.evalModule(source, filename);
        engine.freeValue(result);
    }
    fn run(self: *Fixture, comptime name: []const u8) !void {
        try self.runText(@embedFile("extensions/fixtures/native-node-inspect-colors-observer.mjs") ++
            "\n" ++ name ++ "(actualInspect,actualColor);", "actual-inspect-colors-observer.mjs");
    }
    fn expectNoGuest(self: *Fixture) !void {
        const engine = self.engine.?;
        // Retained fixture-created own Boolean data only: no guest method,
        // descriptor trap or postfatal Engine entry is used for these checks.
        inline for (.{ "entered", "later" }) |name| {
            const value = c.JS_GetPropertyStr(engine.context, self.progress, name);
            defer c.JS_FreeValue(engine.context, value);
            try std.testing.expect(c.JS_IsBool(value));
            try std.testing.expect(c.JS_ToBool(engine.context, value) == 0);
        }
    }
};
fn both(comptime name: []const u8) !void {
    for ([_]bool{ false, true }) |source_mode| {
        var probe: Probe = .{};
        var fixture: Fixture = .{};
        try fixture.init(&probe, source_mode);
        defer fixture.deinit();
        try fixture.run(name);
        try std.testing.expect(!c.JS_HasException(fixture.engine.?.context));
    }
}
fn actualFatal(comptime name: []const u8, retired: u32) !void {
    for ([_]bool{ false, true }) |source_mode| {
        var probe: Probe = .{};
        var fixture: Fixture = .{};
        try fixture.init(&probe, source_mode);
        defer fixture.deinit();
        const engine = fixture.engine.?;
        const generation = engine.native_allocation_generation;
        try std.testing.expectError(error.JavaScriptException, fixture.run(name));
        const first = engine.native_allocation_exception orelse return error.MissingActualInspectColorFatal;
        const captured = engine.captured_exception orelse return error.MissingActualInspectColorCaptured;
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, captured));
        try std.testing.expect(c.JS_IsUncatchableError(captured));
        try std.testing.expectEqual(generation +% 1, engine.native_allocation_generation);
        try std.testing.expectEqual(retired, probe.counts[0]);
        try fixture.expectNoGuest();
    }
}
test "native actual inspect color original tables arrays style order and function shape" { try both("observeColorTables"); }
test "native actual inspect color aliases use real captured targets and call receivers" { try both("observeColorAliases"); }
test "native actual inspect color style and code guards are exactly undefined-only" { try both("observeColorValues"); }
test "native actual inspect color reads live styles colors and computed keys in order" { try both("observeColorLiveOrder"); }
test "native actual inspect color templates use eager string hints and intrinsic additions" { try both("observeColorTemplate"); }
test "native actual inspect color template abrupt substitutions stop before later getters" { try both("observeColorAbrupt"); }
test "native actual inspect color ordinary private DATA throw retains exact identity" { try both("observeColorPrivateData"); }
test "native actual inspect color successful flagged key remains ordinary DATA" { try both("observeColorFlaggedData"); }
test "native actual inspect color style receiver retires before live color table" { try both("observeColorReceiverRetirement"); }
test "native actual inspect color code temporary retires before later substitutions" { try both("observeColorSubstitutionRetirement"); }
test "native actual inspect color original local holders survive until actual terminal" { try both("observeColorLocalRetirement"); }
test "native actual inspect color current native fatal prevents guest catch and later reads" { try actualFatal("observeColorCurrentFatal", 0); }
test "native actual inspect color receiver retirement fatal prevents guest catch and later reads" { try actualFatal("observeColorRetirementFatal", 1); }
test "native actual inspect color genuine inspector shares live tables and typed layout" {
    var probe: Probe = .{}; var fixture: Fixture = .{}; try fixture.init(&probe, false); defer fixture.deinit();
    try fixture.run("observeColorInspectorIntegration");
}
test "native actual inspect color option overrides supplied stylizer after actual getter" {
    var probe: Probe = .{}; var fixture: Fixture = .{}; try fixture.init(&probe, false); defer fixture.deinit();
    try fixture.run("observeColorOverride");
}
