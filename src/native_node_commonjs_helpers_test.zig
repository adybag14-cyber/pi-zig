//! Twenty-four authored controls over actual Node24.14 CommonJS helpers.
//! Fresh Source/native branches consume the same genuine FS, options and
//! primordial owners; the selected Source body is retained verbatim.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const core = @import("extensions/native_node_commonjs_module_core.zig");
const modules = @import("extensions/native_node_module_constructor.zig");
const helpers = @import("extensions/native_node_commonjs_helpers_bootstrap.zig");

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
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual CommonJS helper holder index required");
    const probe = active_probe.?;
    const result = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(result)) return result;
    _ = c.JS_SetOpaque(result, &probe.holders[index]);
    return result;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const index = holderIndex(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual CommonJS helper holder index required");
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
    module_owner: ?c.JSValue = null,
    owner: ?c.JSValue = null,
    probe: Probe,
    native: bool,
    alive: bool = false,

    fn init(self: *Fixture, native: bool) !void { return self.initMode(native, true); }
    fn initMode(self: *Fixture, native: bool, complete_owner: bool) !void {
        self.* = .{ .environment = .init(std.testing.allocator), .engine = undefined,
            .probe = undefined, .native = native };
        errdefer self.environment.deinit();
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .values = .{ .conditions = &.{"native-condition"} },
            .features = .{ .strip_types = true, .quic = false },
        } });
        self.alive = true;
        errdefer { self.engine.deinit(); self.alive = false; }
        errdefer if (self.module_owner) |owner| self.engine.freeValue(owner);
        errdefer if (self.owner) |owner| self.engine.freeValue(owner);
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        for (&self.probe.holders, 0..) |*holder, index|
            holder.* = .{ .probe = &self.probe, .index = index };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io,
            &self.environment, &.{"actual-commonjs-helpers"});
        try @import("extensions/node_path.zig").install(self.engine, std.testing.io);
        try @import("extensions/node_url.zig").install(self.engine);
        try @import("extensions/native_node_os.zig").install(self.engine);
        const process = (try self.engine.requireBuiltin("node:process")) orelse
            return error.ActualCommonJSHelperProcessRequired;
        defer self.engine.freeValue(process);
        try @import("extensions/node_fs.zig").installWithStreams(self.engine, std.testing.io, process);
        // The real Module bootstrap captures all primordials before any
        // observer mutation. Later helper acquisition consumes those roots.
        self.module_owner = try core.create(self.engine);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{
            .class_name = "Actual CommonJS helper expression holder", .finalizer = releaseHolder,
        };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0)
            return error.OutOfMemory;
        try self.engine.bindFunction("actualHelpersHolder", makeHolder, 1);
        try self.engine.bindFunction("actualHelpersFreedCount", freedCount, 1);
        try self.engine.bindFunction("actualHelpersFatal", nativeFatal, 0);
        try self.engine.bindFunction("actualHelpersPrivateData", privateData, 0);
        try self.engine.bindFunction("actualHelpersFlaggedData", flaggedData, 0);
        _ = try a.expression(self.engine, installView, .{self.module_owner.?});
        if (complete_owner) try self.complete();
    }
    fn installView(s: *a.Scope, constructor: c.JSValue) !c.JSValue {
        const lexical = try s.own(try modules.loaderEnvironment(s.engine, constructor));
        const fs = try s.own((try s.engine.requireBuiltin("node:fs")) orelse
            return error.ActualCommonJSHelperFilesystemRequired);
        const internal_fs = try s.own(try @import("extensions/native_node_fs_path_bootstrap.zig").prepare(s.engine));
        const options = try s.own(try @import("extensions/native_node_options.zig").acquire(s.engine));
        const get_option = try s.get(lexical, "getOptionValue");
        const roots = try @import("extensions/native_node_module_callable.zig").capturedRoots(s.engine, get_option);
        if (roots.len != 1) return error.ActualCommonJSHelperOptionsRootsRequired;
        const dictionary = try s.own(try a.call(s.engine, roots[0], c.pi_js_undefined(), &.{}));
        const imports = try s.object();
        try s.define(imports, "fs", fs, c.JS_PROP_C_W_E);
        try s.define(imports, "internalFS", internal_fs, c.JS_PROP_C_W_E);
        try s.define(imports, "SafeMap", try s.get(lexical, "safeMap"), c.JS_PROP_C_W_E);
        try s.define(imports, "SafeSet", try s.get(lexical, "safeSet"), c.JS_PROP_C_W_E);
        try s.define(imports, "ObjectFreeze", try s.get(lexical, "objectFreeze"), c.JS_PROP_C_W_E);
        try s.define(imports, "getOptionValue", get_option, c.JS_PROP_C_W_E);
        const view = try s.object();
        inline for (.{ "fs", "internalFS", "SafeMap", "SafeSet" }) |name|
            try s.define(view, name, try s.get(imports, name), c.JS_PROP_C_W_E);
        try s.define(view, "options", options, c.JS_PROP_C_W_E);
        try s.define(view, "cache", dictionary, c.JS_PROP_C_W_E);
        try s.define(view, "Module", constructor, c.JS_PROP_C_W_E);
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.define(global, "actualHelperImports", imports, c.JS_PROP_C_W_E);
        try s.define(global, "actualHelperView", view, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn complete(self: *Fixture) !void {
        if (self.owner != null) return error.ActualHelperFixtureAlreadyCompleted;
        if (self.native) {
            self.owner = try helpers.acquire(self.engine);
            _ = try a.expression(self.engine, publishBody, .{ "actualHelpers", self.owner.? });
        } else {
            const result = try self.engine.evalModule(
                @embedFile("extensions/fixtures/native-node-commonjs-helpers-source.mjs") ++
                "\nglobalThis.actualHelpers = createCommonJSHelpersSource(actualHelperImports);\n",
                "actual-node-commonjs-helpers-source.mjs");
            self.engine.freeValue(result);
            self.owner = try self.value("actualHelpers");
        }
    }
    fn deinit(self: *Fixture) void {
        if (!self.alive) return;
        self.probe.fatal_slot = null;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        if (self.module_owner) |owner| self.engine.freeValue(owner);
        self.owner = null;
        self.module_owner = null;
        self.engine.deinit();
        self.alive = false;
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{
            @embedFile("extensions/fixtures/native-node-commonjs-helpers-observer.mjs"), "\n", tail,
        });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-commonjs-helpers-observer.mjs");
        self.engine.freeValue(result);
    }
    fn runExpected(self: *Fixture, tail: []const u8) !void {
        self.run(tail) catch |err| {
            std.debug.print("actual CommonJS helpers native={any}, observer={s}, failure={s}, captured={s}\n",
                .{ self.native, tail, @errorName(err), self.engine.last_error orelse "<no captured source>" });
            return err;
        };
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
        try fixture.runExpected(name ++ "(actualHelpers,actualHelperView);");
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers ordinary function descriptors and actual construction" { try observe("observeHelpersShape"); }
test "native actual CommonJS helpers raw condition order freeze and real SafeSet identities" { try observe("observeHelpersConditions"); }
test "native actual CommonJS helpers lazy cells and explicit reinitialization retain separate snapshots" { try observe("observeHelpersLazyAndReinitialize"); }
test "native actual CommonJS helpers option spread flag freeze and Set iterable order" { try observe("observeHelpersOrder"); }
test "native actual CommonJS helpers spread failure precedes assignment and lazy retry" { try observe("observeHelpersSpreadFailure"); }
test "native actual CommonJS helpers flag failure preserves assigned unfrozen array" { try observe("observeHelpersFlagFailure"); }
test "native actual CommonJS helpers live push failure occurs before freeze and Set" { try observe("observeHelpersPushFailure"); }
test "native actual CommonJS helpers real SafeSet failure follows freezing and permits retry" { try observe("observeHelpersSetFailure"); }
test "native actual CommonJS helpers realpath selects live fs before raw computed cache key" { try observe("observeHelpersRealpath"); }
test "native actual CommonJS helpers computed key getter and conversion failures prevent selected call" { try observe("observeHelpersKeyFailure"); }

test "native actual CommonJS helpers first late acquisition uses original captured primordials" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.initMode(native, false); defer fixture.deinit();
        try fixture.runExpected("installHelpersPrimordialPoison();");
        try fixture.complete();
        try fixture.runExpected("observeHelpersPoisonedImports(actualHelpers,actualHelperView);");
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers ordinary private DATA preserves six fresh failure identities" {
    inline for (.{ false, true }) |native| {
        inline for (0..6) |route| {
            var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
            try fixture.runExpected(std.fmt.comptimePrint(
                "observeHelpersPrivateData(actualHelpers,actualHelperView,{d});", .{route}));
            try fixture.engine.checkNativeEntry();
        }
    }
}
test "native actual CommonJS helpers successful flagged fs result remains returned DATA" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.runExpected("observeHelpersFlaggedReturn(actualHelpers,actualHelperView);");
        const data = try fixture.value("actualHelpersSelectedData"); defer fixture.engine.freeValue(data);
        try std.testing.expect(c.JS_IsUncatchableError(data));
        try std.testing.expect(c.pi_js_native_allocation_error_generation(data) != 0);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers original user and addon locals survive final Set call" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.runExpected("observeHelpersLocalRetention(actualHelpers,actualHelperView);");
        try std.testing.expectEqual([3]u32{ 1, 1, 0 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers flag predicate holder retires before live push getter" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.runExpected("observeHelpersFlagRetirement(actualHelpers,actualHelperView);");
        try std.testing.expectEqual([3]u32{ 0, 0, 1 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers raw computed key holder retires before real fs call" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.runExpected("observeHelpersKeyRetirement(actualHelpers,actualHelperView);");
        try std.testing.expectEqual([3]u32{ 1, 0, 0 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers selected fs callee retires before caller continuation" {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        try fixture.runExpected("observeHelpersCalleeRetirement(actualHelpers,actualHelperView);");
        try std.testing.expectEqual([3]u32{ 1, 0, 0 }, fixture.probe.freed);
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers failed reinitialization retains previous Set and new partial array" {
    try observe("observeHelpersFailedReinitialize");
}
fn publishFile(s: *a.Scope, path: []const u8) !c.JSValue {
    return publishBody(s, "actualHelpersFile", try s.text(path));
}
test "native actual CommonJS helpers completed owner delegates to the actual physical classic realpath" {
    var temporary = std.testing.tmpDir(.{}); defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "actual.txt", .data = "actual helper\n" });
    var root: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const count = try temporary.dir.realPath(std.testing.io, &root);
    const path = try std.fs.path.join(std.testing.allocator, &.{ root[0..count], "actual.txt" });
    defer std.testing.allocator.free(path);
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        if (native) {
            const again = try helpers.acquire(fixture.engine); defer fixture.engine.freeValue(again);
            try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.owner.?, again));
        }
        _ = try a.expression(fixture.engine, publishFile, .{path});
        try fixture.runExpected(
            \\helperAssert(actualHelpers.toRealPath(actualHelpersFile) === actualHelpersFile, "actual physical file result");
            \\helperAssert(actualHelpers.toRealPath(actualHelpersFile) === actualHelpersFile, "actual cached physical file result");
        );
        try fixture.engine.checkNativeEntry();
    }
}
test "native actual CommonJS helpers retained options declaration observes genuine refresh" {
    try observe("observeHelpersRefresh");
}
fn progress(fixture: *Fixture) !c.JSValue {
    try fixture.runExpected("globalThis.actualHelpersProgress={selected:0,later:0,after:0,caught:0};");
    return fixture.value("actualHelpersProgress");
}
fn verifyFatal(fixture: *Fixture, result: anyerror!void, record: c.JSValue, expected: [4]u32) !void {
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualHelperFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    inline for (.{ "selected", "later", "after", "caught" }, 0..) |name, index| {
        // These are only the retained record's known own numeric data fields.
        const value = c.JS_GetPropertyStr(fixture.engine.context, record, name);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var number: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &number, value));
        try std.testing.expectEqual(expected[index], number);
    }
}
fn fatalRoute(comptime route: u32) !void {
    inline for (.{ false, true }) |native| {
        var fixture: Fixture = undefined; try fixture.init(native); defer fixture.deinit();
        const record = try progress(&fixture); defer fixture.engine.freeValue(record);
        if (route == 1) fixture.probe.fatal_slot = 2;
        if (route == 2) fixture.probe.fatal_slot = 0;
        try fixture.runExpected(std.fmt.comptimePrint("installHelpersFatal(actualHelperView,{d});", .{route}));
        const result = fixture.run(if (route == 2)
            "try { actualHelpers.toRealPath('fatal'); actualHelpersProgress.after++; } catch { actualHelpersProgress.caught++; }"
        else
            "try { actualHelpers.initializeCjsConditions(); actualHelpersProgress.after++; } catch { actualHelpersProgress.caught++; }");
        try verifyFatal(&fixture, result, record, .{ 1, 0, 0, 0 });
        if (route == 1) try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[2]);
        if (route == 2) try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    }
}
test "native actual CommonJS helpers actual option fatal prevents later body and guest catch" { try fatalRoute(0); }
test "native actual CommonJS helpers actual flag retirement fatal prevents push and guest catch" { try fatalRoute(1); }
test "native actual CommonJS helpers actual key retirement fatal prevents fs call and guest catch" { try fatalRoute(2); }
fn callPending(fixture: *Fixture, function: c.JSValue) !void {
    const result = try a.call(fixture.engine, function, c.pi_js_undefined(), &.{});
    fixture.engine.freeValue(result);
}
test "native actual CommonJS helpers current fatal prevents original callable entry" {
    var fixture: Fixture = undefined; try fixture.init(true); defer fixture.deinit();
    const record = try progress(&fixture); defer fixture.engine.freeValue(record);
    try fixture.runExpected("installHelpersFatal(actualHelperView,0);");
    const function = try a.field(fixture.engine, fixture.owner.?, "initializeCjsConditions");
    defer fixture.engine.freeValue(function);
    _ = preserveFatal(&fixture.probe);
    try verifyFatal(&fixture, callPending(&fixture, function), record, .{ 0, 0, 0, 0 });
}
