//! Twenty authored controls over actual Node v24.14 lookup/_initPaths linkage.
//! Twelve genuine-Node observers and eight native identity/retirement controls.
//! Selected Windows process.env branch; install only, no Source/runtime claim.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const search = @import("extensions/native_node_commonjs_search_paths.zig");
const modules = @import("extensions/native_node_module_constructor.zig");

const Holder = struct { probe: *Probe, position: usize };
const Probe = struct {
    engine: *a.v.em.Engine,
    holder_class: c.JSClassID = 0,
    freed: [2]u32 = .{ 0, 0 },
    fatal_slot: ?usize = null,
    first: c.JSValue,
    holders: [2]Holder = undefined,
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
    holder.probe.freed[holder.position] += 1;
    if (holder.probe.fatal_slot == holder.position) _ = preserveFatal(holder.probe);
}
fn holderPosition(context: ?*c.JSContext, argc: c_int, argv: [*c]c.JSValue) ?u32 {
    if (argc < 1) return null;
    var position: u32 = 0;
    if (c.JS_ToUint32(context, &position, argv[0]) < 0 or position >= 2) return null;
    return position;
}
fn makeHolder(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const position = holderPosition(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual holder position required");
    const probe = active_probe.?;
    const value = c.JS_NewObjectClass(context, probe.holder_class);
    if (c.JS_IsException(value)) return value;
    _ = c.JS_SetOpaque(value, &probe.holders[position]);
    return value;
}
fn freedCount(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const position = holderPosition(context, argc, argv) orelse return c.JS_ThrowTypeError(context, "actual holder position required");
    return c.JS_NewUint32(context, active_probe.?.freed[position]);
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
    const value = privateData(context, receiver, argc, argv);
    c.JS_SetUncatchableError(context, value);
    return value;
}
const Fixture = struct {
    environment: std.process.Environ.Map,
    engine: *a.v.em.Engine,
    owner: c.JSValue,
    probe: Probe,
    fn init(self: *Fixture) !void {
        if (@import("builtin").os.tag != .windows) return error.SkipZigTest;
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        // Same explicitly admitted original feature branch as Module creation.
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .features = .{ .strip_types = true, .quic = false },
        } });
        errdefer self.engine.deinit();
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        for (&self.probe.holders, 0..) |*holder, position| holder.* = .{ .probe = &self.probe, .position = position };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-module-search-path-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        self.owner = try search.acquire(self.engine, .{});
        errdefer self.engine.freeValue(self.owner);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{ .class_name = "Actual Module search-path temporary", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0) return error.OutOfMemory;
        try self.engine.bindFunction("actualSearchHolder", makeHolder, 1);
        try self.engine.bindFunction("actualSearchFreedCount", freedCount, 1);
        try self.engine.bindFunction("actualSearchFatal", nativeFatal, 0);
        try self.engine.bindFunction("actualSearchPrivateData", privateData, 0);
        try self.engine.bindFunction("actualSearchFlaggedData", flaggedData, 0);
        var s = a.Scope.init(self.engine);
        _ = try s.finish(installView(&s, self.owner));
    }
    fn installView(s: *a.Scope, owner: c.JSValue) !c.JSValue {
        const view = try s.object();
        try s.define(view, "Module", try s.get(owner, "Module"), c.JS_PROP_C_W_E);
        try s.define(view, "path", try s.own((try s.engine.requireBuiltin("node:path")) orelse return error.ActualSearchPathsRequired), c.JS_PROP_C_W_E);
        try s.define(view, "process", try s.own((try s.engine.requireBuiltin("node:process")) orelse return error.ActualSearchProcessRequired), c.JS_PROP_C_W_E);
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.define(global, "actualModuleSearch", view, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_slot = null;
        self.engine.freeValue(self.probe.first);
        self.engine.freeValue(self.owner);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{ @embedFile("extensions/fixtures/native-node-module-search-paths-observer.mjs"), "\n", tail });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-module-search-paths-observer.mjs");
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
    try fixture.run(name ++ "(actualModuleSearch);");
}
test "native actual Module search paths ordinary shapes and private binding" { try observe("observeSearchPathShapes"); }
test "native actual Module search paths original builtin normalizer coercion" { try observe("observeLookupBuiltinCoercion"); }
test "native actual Module search paths repeated parent paths and array-like prepend" { try observe("observeLookupParentArrayLike"); }
test "native actual Module search paths optional chain raw truthiness" { try observe("observeLookupOptionalPaths"); }
test "native actual Module search paths relative debug operand and dirname order" { try observe("observeLookupRelativeOrder"); }
test "native actual Module search paths relative parent short circuits" { try observe("observeLookupRelativeShortCircuit"); }
test "native actual Module search paths ordinary getter failures retain order" { try observe("observeLookupAbruptOrder"); }
test "native actual Module search paths actual Windows lookup spelling" { try observe("observeLookupWindowsSpelling"); }
test "native actual Module search paths public clone and private replacement" { try observe("observeInitPathsClone"); }
test "native actual Module search paths init environment resolve filter and publication order" { try observe("observeInitPathsEvaluation"); }
test "native actual Module search paths init failure before and after private assignment" { try observe("observeInitPathsFailurePublication"); }
test "native actual Module search paths retain bootstrap primordials" { try observe("observeSearchCapturedPrimordials"); }

test "native actual Module search paths completed linkage keeps actual Module cache and inputs" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const again = try search.acquire(fixture.engine, .{}); defer fixture.engine.freeValue(again);
    const module = try modules.actualConstructor(fixture.engine); defer fixture.engine.freeValue(module);
    const environment = try modules.loaderEnvironment(fixture.engine, module); defer fixture.engine.freeValue(environment);
    const inputs = try search.lookupInputs(fixture.engine, again);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.owner, again));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, module, inputs.module_constructor));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, environment, inputs.state));
    var s = a.Scope.init(fixture.engine);
    _ = try s.finish(verifyActualOwners(&s, again, inputs));
}
fn verifyActualOwners(s: *a.Scope, record: c.JSValue, inputs: @import("extensions/native_node_commonjs_lookup.zig").Inputs) !c.JSValue {
    const module = try s.get(record, "Module");
    try std.testing.expect(s.equal(module, inputs.module_constructor));
    try std.testing.expect(s.equal(try s.get(module, "_cache"), s.engine.commonjs_cache));
    try std.testing.expect(s.equal(try s.get(record, "_resolveLookupPaths"), try s.get(module, "_resolveLookupPaths")));
    try std.testing.expect(s.equal(try s.get(record, "_initPaths"), try s.get(module, "_initPaths")));
    try std.testing.expect(s.equal(try s.get(record, "normalizeRequirableId"), inputs.is_builtin));
    try std.testing.expect(!s.equal(try s.get(inputs.state, "modulePaths"), try s.get(module, "globalPaths")));
    return c.pi_js_undefined();
}
test "native actual Module search paths predicate receiver and result retire before repeated getter" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(
        \\let reads = 0;
        \\const parent = {get paths() {
        \\  if (++reads === 1) return {holder:actualSearchHolder(0),get length(){return actualSearchHolder(1);}};
        \\  searchAssert(actualSearchFreedCount(0) === 1 && actualSearchFreedCount(1) === 1,"both actual predicate owners retired");
        \\  return ["parent"];
        \\}};
        \\const value = actualModuleSearch.Module._resolveLookupPaths("missing", parent);
        \\searchAssert(reads === 2 && value[0] === "parent","actual lookup continued after temporary release");
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[1]);
    try fixture.engine.checkNativeEntry();
}
fn retainProgress(fixture: *Fixture) !c.JSValue {
    try fixture.run("globalThis.actualSearchProgress = {first:0,later:0,caught:0};");
    return fixture.value("actualSearchProgress");
}
fn verifyFatal(fixture: *Fixture, result: anyerror!void, progress: c.JSValue) !void {
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualSearchFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // This exact own-data record was retained before the operation. No guest
    // observer or accessor is called after the selected fatal.
    inline for (.{ .{ "first", @as(u32, 1) }, .{ "later", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
test "native actual Module search paths predicate retirement fatal stops repeated getter and catch" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const progress = try retainProgress(&fixture); defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_slot = 0;
    const result = fixture.run(
        \\const parent = {get paths() {
        \\  if (actualSearchProgress.first++ === 0) return {holder:actualSearchHolder(0),length:1};
        \\  actualSearchProgress.later++; return [];
        \\}};
        \\try { actualModuleSearch.Module._resolveLookupPaths("missing", parent); } catch { actualSearchProgress.caught++; }
    );
    try verifyFatal(&fixture, result, progress);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
}
test "native actual Module search paths actual getter fatal stops later guest work" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const progress = try retainProgress(&fixture); defer fixture.engine.freeValue(progress);
    const result = fixture.run(
        \\const parent = {get paths() {
        \\  if (actualSearchProgress.first++ === 0) return actualSearchFatal();
        \\  actualSearchProgress.later++; return [];
        \\}};
        \\try { actualModuleSearch.Module._resolveLookupPaths("missing", parent); } catch { actualSearchProgress.caught++; }
    );
    try verifyFatal(&fixture, result, progress);
    try std.testing.expectEqual(@as(u32, 0), fixture.probe.freed[0]);
}
test "native actual Module search paths same-operation private DATA remains ordinary" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.actualSearchSavedData = undefined;
        \\const parent = {get paths(){throw actualSearchSavedData = actualSearchPrivateData();}};
        \\const caught = searchThrown(() => actualModuleSearch.Module._resolveLookupPaths("missing", parent));
        \\searchAssert(caught === actualSearchSavedData,"ordinary same-operation DATA identity");
    );
    const value = try fixture.value("actualSearchSavedData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module search paths successful flagged dirname DATA remains an array element" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.actualSearchSavedData = undefined;
        \\const saved = Object.getOwnPropertyDescriptor(actualModuleSearch.path,"dirname");
        \\try {
        \\  Object.defineProperty(actualModuleSearch.path,"dirname",{configurable:true,value:function(){return actualSearchSavedData = actualSearchFlaggedData();}});
        \\  const result = actualModuleSearch.Module._resolveLookupPaths("./child",{id:"id",filename:"file"});
        \\  searchAssert(result.length === 1 && result[0] === actualSearchSavedData,"successful flagged result is retained as DATA");
        \\} finally { Object.defineProperty(actualModuleSearch.path,"dirname",saved); }
    );
    const value = try fixture.value("actualSearchSavedData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module search paths init receiver retires while original home local survives publication" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    try fixture.run(
        \\withSearchInit(actualModuleSearch, () => {
        \\  let reads = 0, published = false;
        \\  Object.defineProperty(actualModuleSearch.process,"env",{configurable:true,get(){
        \\    if (++reads === 1) return {holder:actualSearchHolder(0),USERPROFILE:actualSearchHolder(1)};
        \\    searchAssert(actualSearchFreedCount(0) === 1 && actualSearchFreedCount(1) === 0,"environment receiver retired, original home local remains");
        \\    return {NODE_PATH:""};
        \\  }});
        \\  Object.defineProperty(actualModuleSearch.process,"execPath",{configurable:true,value:"exe"});
        \\  Object.defineProperty(actualModuleSearch.path,"resolve",{configurable:true,value:function(){return "resolved";}});
        \\  Object.defineProperty(actualModuleSearch.Module,"globalPaths",{configurable:true,set(){
        \\    published = true; searchAssert(actualSearchFreedCount(1) === 0,"Source home local survives public assignment");
        \\  }});
        \\  actualModuleSearch.Module._initPaths();
        \\  searchAssert(reads === 2 && published && actualSearchFreedCount(1) === 1,"original home local retires at actual function exit");
        \\});
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[1]);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module search paths init receiver retirement fatal stops next environment getter" {
    var fixture: Fixture = undefined; try fixture.init(); defer fixture.deinit();
    const progress = try retainProgress(&fixture); defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_slot = 0;
    const result = fixture.run(
        \\Object.defineProperty(actualModuleSearch.process,"env",{configurable:true,get(){
        \\  if (actualSearchProgress.first++ === 0) return {holder:actualSearchHolder(0),USERPROFILE:"home"};
        \\  actualSearchProgress.later++; return {NODE_PATH:""};
        \\}});
        \\Object.defineProperty(actualModuleSearch.path,"resolve",{configurable:true,value:function(){actualSearchProgress.later++;return "unreachable";}});
        \\try { actualModuleSearch.Module._initPaths(); } catch { actualSearchProgress.caught++; }
    );
    try verifyFatal(&fixture, result, progress);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
}
