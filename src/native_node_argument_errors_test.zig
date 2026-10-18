//! Twenty-one declared controls over the genuine shared Node argument owner.
//! Sixteen observers also run against pinned Node internal/errors/validators.
//! This root installs real process/Stream dependencies and never spawns a child,
//! reads stdin, publishes a public util facade, or substitutes a message handler.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const bootstrap = @import("extensions/native_node_argument_bootstrap.zig");
const errors = @import("extensions/native_node_argument_errors.zig");
const system = @import("extensions/native_node_system_errors.zig");
const owned = a.owned;

fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const value = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, value);
    return value;
}
fn fatalCleared(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    return c.pi_js_undefined();
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    prepared: ?bootstrap.Prepared = null,
    fn init(self: *Fixture, prepare: bool) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        self.prepared = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-argument-control"});
        // This actual OS owner installs the genuine Stream owner against the
        // same process. The existing SystemErrors registry supplies its marker.
        try @import("extensions/native_node_os.zig").install(self.engine);
        if (prepare) {
            self.prepared = try bootstrap.prepare(self.engine);
            errdefer self.prepared.?.deinit(self.engine);
            var scope = a.Scope.init(self.engine);
            _ = try scope.finish(installView(&scope, self.prepared.?));
            try self.engine.bindFunction("actualArgumentPrivateData", privateData, 0);
            try self.engine.bindFunction("actualArgumentFlaggedData", flaggedData, 0);
            try self.engine.bindFunction("actualArgumentFatalCleared", fatalCleared, 0);
        }
    }
    fn installView(s: *a.Scope, prepared: bootstrap.Prepared) !c.JSValue {
        // Test-only selected export view; every callable is the real completed
        // production owner. It is never registered as a public Node namespace.
        const view = try s.object();
        const codes = try s.object();
        try s.put(codes, "ERR_INVALID_ARG_TYPE", prepared.arguments.invalid_arg_type);
        try s.put(codes, "ERR_INVALID_ARG_VALUE", prepared.arguments.invalid_arg_value);
        try s.put(codes, "ERR_INTERNAL_ASSERTION", prepared.arguments.internal_assertion);
        try s.put(view, "codes", codes);
        try s.put(view, "assert", prepared.assert_function);
        try s.put(view, "validateString", prepared.arguments.validate_string);
        try s.put(view, "validateAbortSignal", try s.own(try errors.validateAbortSignal(s.engine)));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.put(global, "actualArguments", view);
        try s.put(global, "actualArgumentMarker", try s.get(try system.registry(s.engine), "marker"));
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        if (self.prepared) |prepared| prepared.deinit(self.engine);
        self.engine.deinit();
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{@embedFile("extensions/fixtures/native-node-argument-observer.mjs"), "\n", tail});
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-argument-observer.mjs");
        self.engine.freeValue(result);
    }
    fn data(self: *Fixture) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, "savedArgumentData"));
    }
};
fn observe(comptime name: []const u8) !void {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    try fixture.run(name ++ "(actualArguments);");
}
test "native actual argument class descriptors marker and constructor identity" { try observe("observeArgumentShape"); }
test "native actual argument primitive and string-specific messages" { try observe("observeArgumentPrimitiveMessages"); }
test "native actual argument expected type instance and literal lists" { try observe("observeArgumentExpectedLists"); }
test "native actual argument value and RangeError specializations" { try observe("observeArgumentValueRange"); }
test "native actual argument lazy internal assert uses the same owner" { try observe("observeArgumentInternalAssert"); }
test "native actual argument validateString wrapper and raw arrow" { try observe("observeArgumentValidators"); }
test "native actual argument AbortSignal validation uses actual has operation" { try observe("observeArgumentAbortSignal"); }
test "native actual argument three constructor reads and name coercion" { try observe("observeArgumentConstructorReads"); }
test "native actual argument primitive second constructor rejects at in" { try observe("observeArgumentPrimitiveInOperand"); }
test "native actual argument hidden superclass spreads the real rest array" { try observe("observeArgumentHiddenRest"); }
test "native actual argument hidden superclass selection and actual new target" { try observe("observeArgumentHiddenSuperTarget"); }
test "native actual argument hidden writable accessor and nonwritable limits" { try observe("observeArgumentHiddenLimits"); }
test "native actual argument throwing super preserves Source missing finally" { try observe("observeArgumentHiddenThrow"); }
test "native actual argument plain rest and retained Reflect apply ignore late mutation" { try observe("observeArgumentCapturedApplyAndRest"); }
test "native actual argument invalid expected entry closes the real iterator" { try observe("observeArgumentExpectedIteratorClose"); }
test "native actual argument lazy inspector keeps ordinary thrown value identity" { try observe("observeArgumentInspectThrow"); }

test "native actual argument repeated bootstrap shares classes inspector assert and original marker" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const second = try bootstrap.prepare(fixture.engine); defer second.deinit(fixture.engine);
    const first = fixture.prepared.?;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first.internal_inspect, second.internal_inspect));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first.assert_function, second.assert_function));
    inline for (std.meta.fields(errors.Exports)) |field|
        try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, @field(first.arguments, field.name), @field(second.arguments, field.name)));
    try fixture.run(
        \\const prototype = actualArguments.codes.ERR_INVALID_ARG_TYPE.prototype;
        \\const marker = Object.getOwnPropertySymbols(prototype).find(value => value.description === "kIsNodeError");
        \\argumentAssert(marker === actualArgumentMarker, "same existing SystemError marker");
    );
}
test "native actual argument incoming ordinary pending stops before new owner publication" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const reason = try fixture.engine.checked(c.JS_NewObject(fixture.engine.context));
    defer fixture.engine.freeValue(reason);
    _ = c.JS_Throw(fixture.engine.context, c.JS_DupValue(fixture.engine.context, reason));
    try std.testing.expectError(error.JavaScriptException, bootstrap.prepare(fixture.engine));
    const selected = fixture.engine.captured_exception orelse return error.MissingActualArgumentPendingReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, selected));
    try std.testing.expect(!fixture.engine.native_module_values.contains("pi-native:private/argument-error-owner"));
    try std.testing.expect(!fixture.engine.native_module_values.contains("pi-native:private/internal-inspect-binding"));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
}
test "native actual argument fresh private constructor-getter DATA throw stays ordinary" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedArgumentData = undefined;
        \\const input = Object.defineProperty({}, "constructor", {get() {
        \\  savedArgumentData = actualArgumentPrivateData(); throw savedArgumentData;
        \\}});
        \\const reason = argumentThrown(() => new actualArguments.codes.ERR_INVALID_ARG_TYPE("x","string",input));
        \\argumentAssert(reason === savedArgumentData, "exact ordinary private DATA");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual argument successful flagged constructor-name value remains DATA" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedArgumentData = undefined;
        \\const constructor = {};
        \\Object.defineProperty(constructor, "name", {get() {
        \\  savedArgumentData = actualArgumentFlaggedData();
        \\  Object.defineProperty(savedArgumentData, Symbol.toPrimitive, {value() { return "Flagged"; }});
        \\  return savedArgumentData;
        \\}});
        \\const result = new actualArguments.codes.ERR_INVALID_ARG_TYPE("x","string",{constructor});
        \\argumentAssert(result.message.endsWith("Received an instance of Flagged"), "successful flagged name DATA");
    );
    const value = try fixture.data(); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual argument retained allocator B1 stops after constructor getter" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    try fixture.run("globalThis.savedArgumentData = {constructor:0, name:0, caught:0};");
    const progress = try fixture.data(); defer fixture.engine.freeValue(progress);
    const result = fixture.run(
        \\const constructor = Object.defineProperty({}, "name", {get() {
        \\  savedArgumentData.name++; return "Unreachable";
        \\}});
        \\const input = Object.defineProperty({}, "constructor", {get() {
        \\  savedArgumentData.constructor++;
        \\  actualArgumentFatalCleared(); return constructor;
        \\}});
        \\try { new actualArguments.codes.ERR_INVALID_ARG_TYPE("x","string",input); }
        \\catch { savedArgumentData.caught++; }
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const first = fixture.engine.native_allocation_exception orelse return error.MissingActualArgumentAllocatorReason;
    const reason = fixture.engine.captured_exception orelse return error.MissingActualArgumentCapturedReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // These are known own numeric data fields on the retained plain record.
    // Inspect them directly without a new guest call or boundary admission.
    inline for (.{ .{ "constructor", @as(u32, 1) }, .{ "name", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
