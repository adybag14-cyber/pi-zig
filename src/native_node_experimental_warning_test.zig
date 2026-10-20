//! Actual Node24.14 internal/util experimental-warning controls.
//! Both selected Source and native branches retain the real process wrapper
//! input and the same genuine SafeSet primordial owner. Install only.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const warnings = @import("extensions/native_node_experimental_warning.zig");
const collections = @import("extensions/native_node_fs_collections.zig");

const Holder = struct { probe: *Probe, index: usize };
const Probe = struct {
    engine: *a.v.em.Engine,
    holder_class: c.JSClassID = 0,
    freed: [3]u32 = .{ 0, 0, 0 },
    fatal_slot: ?usize = null,
    first: c.JSValue,
    holders: [3]Holder = undefined,
};
var active_probe: ?*Probe = null;
fn preserveFatal(probe: *Probe) c.JSValue {
    _ = probe.engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(probe.engine.context);
    if (c.JS_IsUndefined(probe.first)) probe.first = a.duplicate(probe.engine, reason);
    return c.JS_Throw(probe.engine.context, reason);
}
fn releaseHolder(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const holder: *Holder = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    holder.probe.freed[holder.index] += 1;
    if (holder.probe.fatal_slot == holder.index) _ = preserveFatal(holder.probe);
}
fn holderIndex(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) ?u32 {
    if (argc < 1) return null;
    var index: u32 = 0;
    if (c.JS_ToUint32(context, &index, argv[0]) < 0 or index >= 3) return null;
    return index;
}
fn makeHolder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual experimental warning holder index required");
    const probe = active_probe.?;
    const result = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(result)) return result;
    _ = c.JS_SetOpaque(result, &probe.holders[index]);
    return result;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual experimental warning holder index required");
    return c.JS_NewUint32(context, active_probe.?.freed[index]);
}
fn nativeFatal(_: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return preserveFatal(active_probe.?);
}
fn privateData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = a.v.em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemory();
    return c.JS_GetException(context);
}
fn flaggedData(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const result = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, result);
    return result;
}
fn publishBody(s: *a.Scope, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    try s.define(global, name, value, c.JS_PROP_C_W_E);
    return c.pi_js_undefined();
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    owner: ?c.JSValue = null,
    probe: Probe,
    alive: bool = false,

    fn init(self: *Fixture, native: bool) !void {
        self.* = .{
            .environment = .init(std.testing.allocator),
            .engine = undefined, .probe = undefined,
        };
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{});
        self.alive = true;
        errdefer { self.engine.deinit(); self.alive = false; }
        errdefer if (self.owner) |owner| self.engine.freeValue(owner);
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        for (&self.probe.holders, 0..) |*holder, index|
            holder.* = .{ .probe = &self.probe, .index = index };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/native_process.zig").install(
            self.engine, std.testing.io, &self.environment, &.{"actual-experimental-warning"});
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{
            .class_name = "Actual warning expression holder", .finalizer = releaseHolder,
        };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0)
            return error.OutOfMemory;
        try self.engine.bindFunction("actualWarningHolder", makeHolder, 1);
        try self.engine.bindFunction("actualWarningFreedCount", freedCount, 1);
        try self.engine.bindFunction("actualWarningFatal", nativeFatal, 0);
        try self.engine.bindFunction("actualWarningPrivateData", privateData, 0);
        try self.engine.bindFunction("actualWarningFlaggedData", flaggedData, 0);
        // The same real primordial is completed before either selected body
        // and before any observer mutates public constructors/prototypes.
        const safe_set = try collections.acquireSafeSet(self.engine);
        defer self.engine.freeValue(safe_set);
        if (native) {
            self.owner = try warnings.acquire(self.engine);
            _ = try a.expression(self.engine, publishBody, .{ "actualWarning", self.owner.? });
        } else {
            _ = try a.expression(self.engine, publishBody, .{ "actualWarningSafeSet", safe_set });
            const evaluated = try self.engine.evalModule(
                @embedFile("extensions/fixtures/native-node-experimental-warning-source.mjs") ++
                "\nimport originalWarningProcess from 'node:process';\n" ++
                "globalThis.actualWarning = createExperimentalWarningSource(actualWarningSafeSet, originalWarningProcess);\n",
                "actual-node-experimental-warning-source.mjs");
            self.engine.freeValue(evaluated);
            self.owner = try self.value("actualWarning");
        }
    }
    fn deinit(self: *Fixture) void {
        if (!self.alive) return;
        self.probe.fatal_slot = null;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        self.owner = null;
        self.engine.deinit();
        self.alive = false;
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{
            @embedFile("extensions/fixtures/native-node-experimental-warning-observer.mjs"),
            "\n", tail,
        });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-experimental-warning-observer.mjs");
        self.engine.freeValue(result);
    }
    fn runGlobal(self: *Fixture, source: []const u8) !void {
        const result = try self.engine.eval(source, "actual-node-experimental-warning-global.js",
            c.JS_EVAL_TYPE_GLOBAL | c.JS_EVAL_FLAG_STRICT);
        self.engine.freeValue(result);
    }
    fn value(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
};
fn observe(comptime name: []const u8) !void {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        fixture.run(name ++ "(actualWarning);") catch |err| {
            std.debug.print("actual experimental warning native={any}, observer={s}, failure={s}, captured={s}\n",
                .{ native, name, @errorName(err), fixture.engine.last_error orelse "<no captured source>" });
            return err;
        };
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual experimental warning ordinary function and constructor shape" { try observe("observeExperimentalWarningShape"); }
test "native actual experimental warning eager feature and ordinary prefix coercion precede live callee selection" { try observe("observeExperimentalWarningMessage"); }
test "native actual experimental warning private SafeSet preserves SameValueZero and original object identity" { try observe("observeExperimentalWarningMembership"); }
test "native actual experimental warning membership survives actual feature and Symbol conversion failures" { try observe("observeExperimentalWarningConversionFailure"); }
test "native actual experimental warning prefix predicate and failed default-hint addition follow original order" { try observe("observeExperimentalWarningPrefix"); }
test "native actual experimental warning membership precedes both live warning getter and callback failure" { try observe("observeExperimentalWarningEmissionFailure"); }
test "native actual experimental warning same-feature reentry observes the already published membership" { try observe("observeExperimentalWarningReentry"); }
test "native actual experimental warning completed primordial owner survives late public Set poisoning" { try observe("observeExperimentalWarningPrimordials"); }
test "native actual experimental warning retained builtin process survives late global getter and object replacement" { try observe("observeExperimentalWarningProcess"); }

test "native actual experimental warning retains process through a real global lexical TDZ" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.run("installExperimentalWarningTdz();");
        try fixture.runGlobal(
            \\try {
            \\  try { void process; }
            \\  catch (reason) {
            \\    if (!(reason instanceof ReferenceError)) throw reason;
            \\    globalThis.actualWarningTdzRecord.tdz = true;
            \\  }
            \\  globalThis.actualWarningTdzRecord.result = actualWarning("global lexical TDZ") === undefined;
            \\} finally { globalThis.actualWarningRestoreTdz(); }
            \\let process;
        );
        try fixture.run(
            \\const record = globalThis.actualWarningTdzRecord;
            \\warningAssert(record.tdz === true && record.result === true && record.calls === 1,
            \\  "actual TDZ does not replace the original builtin wrapper argument");
        );
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual experimental warning selected callee and discarded result retire before caller continuation" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.run("observeExperimentalWarningRetirement(actualWarning);");
        try std.testing.expectEqual([3]u32{ 1, 1, 0 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual experimental warning ordinary private DATA preserves identity in four fresh routes" {
    inline for (.{ false, true }) |native| {
        inline for (0..4) |route| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try fixture.run(std.fmt.comptimePrint("observeExperimentalWarningPrivateData(actualWarning,{d});", .{route}));
            try fixture.engine.checkNativeEntry();
        }
    }
}
test "native actual experimental warning successful flagged callback result remains discarded DATA" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.run("observeExperimentalWarningFlaggedReturn(actualWarning);");
        const data = try fixture.value("actualWarningSelectedData"); defer fixture.engine.freeValue(data);
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        try fixture.engine.checkNativeEntry();
    }
}
fn progress(fixture: *Fixture) !c.JSValue {
    try fixture.run("globalThis.actualWarningProgress={conversion:0,getter:0,callback:0,after:0,caught:0};");
    return fixture.value("actualWarningProgress");
}
fn verifyFatal(fixture: *Fixture, outcome: anyerror!void, record: c.JSValue, expected: [5]u32) !void {
    try std.testing.expectError(error.JavaScriptException, outcome);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualWarningFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    inline for (.{ "conversion", "getter", "callback", "after", "caught" }, 0..) |name, index| {
        // Only retained known own numeric data is read after the fatal event.
        const value = c.JS_GetPropertyStr(fixture.engine.context, record, name);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(expected[index], count);
    }
}
test "native actual experimental warning getter fatal stops callback continuation and guest catch" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        const record = try progress(&fixture); defer fixture.engine.freeValue(record);
        const result = fixture.run(
            \\installExperimentalWarningFatal(false);
            \\try { actualWarning(actualWarningFeature); actualWarningProgress.after++; }
            \\catch { actualWarningProgress.caught++; }
        );
        try verifyFatal(&fixture, result, record, .{ 1, 1, 0, 0, 0 });
    }
}
test "native actual experimental warning real callee retirement fatal stops caller continuation and catch" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        const record = try progress(&fixture); defer fixture.engine.freeValue(record);
        fixture.probe.fatal_slot = 0;
        const result = fixture.run(
            \\installExperimentalWarningFatal(true);
            \\try { actualWarning(actualWarningFeature); actualWarningProgress.after++; }
            \\catch { actualWarningProgress.caught++; }
        );
        try verifyFatal(&fixture, result, record, .{ 1, 1, 1, 0, 0 });
        try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    }
}
fn callAlreadyPending(fixture: *Fixture) !void {
    const result = try a.call(fixture.engine, fixture.owner.?, c.pi_js_undefined(), &.{});
    fixture.engine.freeValue(result);
}
test "native actual experimental warning already current fatal prevents original callable entry" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const record = try progress(&fixture); defer fixture.engine.freeValue(record);
    try fixture.run("installExperimentalWarningFatal(false);");
    _ = preserveFatal(&fixture.probe);
    try verifyFatal(&fixture, callAlreadyPending(&fixture), record, .{ 0, 0, 0, 0, 0 });
}
test "native actual experimental warning one completed owner retains actual feature keys until teardown" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        if (native) {
            const again = try warnings.acquire(fixture.engine); defer fixture.engine.freeValue(again);
            try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.owner.?, again));
        }
        try fixture.run("observeExperimentalWarningRetainedFeature(actualWarning);");
        try std.testing.expectEqual(@as(u32, 0), fixture.probe.freed[2]);
        fixture.deinit();
        try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[2]);
    }
}
