//! Eighteen declared controls over genuine internal/fs/utils path helpers.
//! Twelve observers are shared with pinned Node Source. No filesystem access,
//! process spawning, stdin reader or public module facade is used by this root.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const bootstrap = @import("extensions/native_node_fs_path_bootstrap.zig");

const Probe = struct {
    engine: *a.v.em.Engine,
    holder_class: c.JSClassID = 0,
    freed: u32 = 0,
    fatal_on_release: bool = false,
    first: c.JSValue,
};
var active_probe: ?*Probe = null;
fn releaseHolder(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Probe = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.freed += 1;
    if (probe.fatal_on_release) {
        _ = probe.engine.throwNativeOutOfMemoryFatal();
        const reason = c.JS_GetException(probe.engine.context);
        if (c.JS_IsUndefined(probe.first)) probe.first = c.JS_DupValue(probe.engine.context, reason);
        _ = c.JS_Throw(probe.engine.context, reason);
    }
}
fn makeHolder(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = active_probe.?;
    const value = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(value)) return value;
    _ = c.JS_SetOpaque(value, probe);
    return value;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_NewUint32(context, active_probe.?.freed);
}
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
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    owner: ?c.JSValue = null,
    probe: Probe,
    fn init(self: *Fixture) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        errdefer self.engine.deinit();
        self.owner = null;
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-fs-path-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.owner = try bootstrap.prepare(self.engine);
        errdefer self.engine.freeValue(self.owner.?);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{ .class_name = "Actual filesystem predicate temporary", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0) return error.OutOfMemory;
        var scope = a.Scope.init(self.engine);
        _ = try scope.finish(installView(&scope, self.owner.?));
        try self.engine.bindFunction("actualFsPredicateHolder", makeHolder, 0);
        try self.engine.bindFunction("actualFsFreedCount", freedCount, 0);
        try self.engine.bindFunction("actualFsPrivateData", privateData, 0);
        try self.engine.bindFunction("actualFsFlaggedData", flaggedData, 0);
    }
    fn installView(s: *a.Scope, owner: c.JSValue) !c.JSValue {
        const actual_helpers = try s.get(owner, "helpers");
        const view = try s.object();
        inline for (.{ "getOptions", "validatePath" }) |name| try s.put(view, name, try s.get(actual_helpers, name));
        inline for (.{ "Buffer", "kEmptyObject", "realpathCacheKey" }) |name| try s.put(view, name, try s.get(owner, name));
        // Actual base classes expose the same live hidden-member binding used
        // by internal/fs/utils; this remains only a selected control view.
        inline for (.{ "invalid_arg_type", "invalid_arg_value" }) |name|
            try s.put(view, name, try s.get(actual_helpers, name));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.put(global, "actualFsPath", view);
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_on_release = false;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{ @embedFile("extensions/fixtures/native-node-fs-path-observer.mjs"), "\n", tail });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-fs-path-observer.mjs");
        self.engine.freeValue(result);
    }
    fn value(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
};
fn observe(comptime name: []const u8) !void {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(name ++ "(actualFsPath);");
}
test "native actual fs path default empty object and options identities" { try observe("observeFsPathDefaults"); }
test "native actual fs path default spread preserves descriptor getter and assignment order" { try observe("observeFsPathStringSpread"); }
test "native actual fs path rejects actual option types and exact buffer sentinel" { try observe("observeFsPathOptionTypes"); }
test "native actual fs path repeated encoding signal reads preserve live receiver order" { try observe("observeFsPathEncodingReads"); }
test "native actual fs path buffer and falsy encoding short circuits" { try observe("observeFsPathBufferSentinel"); }
test "native actual fs path consumes the live Buffer encoding predicate" { try observe("observeFsPathLiveBuffer"); }
test "native actual fs path validates the second actual signal value" { try observe("observeFsPathSignalReads"); }
test "native actual fs path ordinary option Buffer and spread throws retain identity" { try observe("observeFsPathOrdinaryFailures"); }
test "native actual fs path hidden validator and raw arrow accept genuine strings and views" { try observe("observeFsPathValidateShape"); }
test "native actual fs path hidden validator rejects incompatible view brands" { try observe("observeFsPathValidateInvalid"); }
test "native actual fs path hidden validator rejects actual null bytes" { try observe("observeFsPathValidateNul"); }
test "native actual fs path retained original includes methods survive later poisoning" { try observe("observeFsPathCapturedIncludes"); }

test "native actual fs path repeated bootstrap retains the same complete helper and Symbol owners" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const second = try bootstrap.prepare(fixture.engine); defer fixture.engine.freeValue(second);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, second, fixture.owner.?));
    try fixture.run(
        \\fsPathAssert(typeof actualFsPath.realpathCacheKey === "symbol" && actualFsPath.realpathCacheKey.description === "realpathCacheKey", "actual private Symbol");
        \\fsPathAssert(Object.isFrozen(actualFsPath.kEmptyObject) && Object.getPrototypeOf(actualFsPath.kEmptyObject) === null, "same genuine empty owner");
    );
}
test "native actual fs path encoding comparison retires its getter result before the second read" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(
        \\let reads = 0;
        \\const options = {get encoding() {
        \\  reads++;
        \\  if (reads === 1) return actualFsPredicateHolder();
        \\  fsPathAssert(actualFsFreedCount() === 1, "first predicate value retired before read two");
        \\  return "utf8";
        \\}};
        \\fsPathAssert(actualFsPath.getOptions(options) === options && reads === 2, "normal comparison continues");
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try fixture.engine.checkNativeEntry();
}
test "native actual fs path predicate finalizer fatal stops before later encoding signal and guest catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run("globalThis.actualFsProgress = {encoding:0, signal:0, caught:0};");
    const progress = try fixture.value("actualFsProgress"); defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_on_release = true;
    const result = fixture.run(
        \\const options = {
        \\  get encoding() { actualFsProgress.encoding++; return actualFsProgress.encoding === 1 ? actualFsPredicateHolder() : "utf8"; },
        \\  get signal() { actualFsProgress.signal++; return undefined; },
        \\};
        \\try { actualFsPath.getOptions(options); } catch { actualFsProgress.caught++; }
    );
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualFsPathReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.probe.first, reason));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // Observe only retained own numeric data, without entering guest code.
    inline for (.{ .{ "encoding", @as(u32, 1) }, .{ "signal", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
test "native actual fs path fresh private encoding getter DATA throw remains ordinary" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedFsPathData = undefined;
        \\const options = {get encoding() { savedFsPathData = actualFsPrivateData(); throw savedFsPathData; }};
        \\fsPathAssert(fsPathThrown(() => actualFsPath.getOptions(options)) === savedFsPathData, "ordinary private getter DATA");
    );
    const value = try fixture.value("savedFsPathData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual fs path successful flagged Buffer predicate result remains DATA" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.savedFsPathData = undefined;
        \\const prior = actualFsPath.Buffer.isEncoding;
        \\actualFsPath.Buffer.isEncoding = function() { return savedFsPathData = actualFsFlaggedData(); };
        \\try { const options = {encoding:"selected"}; fsPathAssert(actualFsPath.getOptions(options) === options, "successful flagged predicate DATA"); }
        \\finally { actualFsPath.Buffer.isEncoding = prior; }
    );
    const value = try fixture.value("savedFsPathData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try fixture.engine.checkNativeEntry();
}
test "native actual fs path detached Uint8Array reaches the genuine typed includes failure" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run("globalThis.savedFsPathData = new Uint8Array([1]);");
    const value = try fixture.value("savedFsPathData"); defer fixture.engine.freeValue(value);
    var offset: usize = 0; var length: usize = 0; var element_size: usize = 0;
    const backing = try fixture.engine.checked(c.JS_GetTypedArrayBuffer(fixture.engine.context, value, &offset, &length, &element_size));
    defer fixture.engine.freeValue(backing);
    c.JS_DetachArrayBuffer(fixture.engine.context, backing);
    try fixture.run(
        \\const reason = fsPathThrown(() => actualFsPath.validatePath(savedFsPathData));
        \\fsPathAssert(reason instanceof TypeError && reason.code === undefined, "intrinsic detached-view failure");
    );
}
