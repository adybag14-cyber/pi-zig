//! Thirty authored controls over the genuine Node v24.14 Module creation
//! component. Seventeen observers have a separate pinned-Node runner; thirteen
//! native controls observe actual retained values/producers. Install only.
const std = @import("std");
const a = @import("extensions/native_node_argument_values.zig");
const c = a.c;
const core = @import("extensions/native_node_commonjs_module_core.zig");
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
    owner: ?c.JSValue = null,
    probe: Probe,
    fn init(self: *Fixture, pending_deprecation: bool) !void { return self.initMode(pending_deprecation, true); }
    fn initMode(self: *Fixture, pending_deprecation: bool, create_core: bool) !void {
        self.environment = .init(std.testing.allocator);
        errdefer self.environment.deinit();
        // Explicit feature admission for this pinned Node v24.14 fixture;
        // production startup must supply its own actual build configuration.
        self.engine = try a.v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .exec_arguments = if (pending_deprecation) &.{"--pending-deprecation"} else &.{},
            .features = .{ .strip_types = true, .quic = false },
        } });
        errdefer self.engine.deinit();
        self.owner = null;
        self.probe = .{ .engine = self.engine, .first = c.pi_js_undefined() };
        for (&self.probe.holders, 0..) |*holder, position| holder.* = .{ .probe = &self.probe, .position = position };
        active_probe = &self.probe;
        errdefer active_probe = null;
        try @import("extensions/timers.zig").install(self.engine, std.testing.io);
        try @import("extensions/native_process.zig").install(self.engine, std.testing.io, &self.environment, &.{"native-module-creation-control"});
        try @import("extensions/native_node_os.zig").install(self.engine);
        if (create_core) {
            self.owner = try core.create(self.engine);
        } else {
            const prepared = try @import("extensions/native_node_argument_bootstrap.zig").prepare(self.engine);
            prepared.deinit(self.engine);
        }
        errdefer if (self.owner) |owner| self.engine.freeValue(owner);
        _ = c.JS_NewClassID(self.engine.runtime, &self.probe.holder_class);
        const definition: c.JSClassDef = .{ .class_name = "Actual Module expression temporary", .finalizer = releaseHolder };
        if (c.JS_NewClass(self.engine.runtime, self.probe.holder_class, &definition) < 0) return error.OutOfMemory;
        try self.engine.bindFunction("actualModuleHolder", makeHolder, 1);
        try self.engine.bindFunction("actualModuleFreedCount", freedCount, 1);
        try self.engine.bindFunction("actualModuleFatal", nativeFatal, 0);
        try self.engine.bindFunction("actualModulePrivateData", privateData, 0);
        try self.engine.bindFunction("actualModuleFlaggedData", flaggedData, 0);
        if (self.owner) |owner| {
            var s = a.Scope.init(self.engine);
            _ = try s.finish(installView(&s, owner));
        }
    }
    fn installView(s: *a.Scope, owner: c.JSValue) !c.JSValue {
        const view = try s.object();
        try s.put(view, "Module", owner);
        try s.put(view, "path", try s.own((try s.engine.requireBuiltin("node:path")) orelse return error.ActualModulePathsRequired));
        try s.put(view, "process", try s.own((try s.engine.requireBuiltin("node:process")) orelse return error.ActualModuleProcessRequired));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.put(global, "actualModuleCreation", view);
        return c.pi_js_undefined();
    }
    fn exposeOptions(self: *Fixture) !void {
        _ = try a.expression(self.engine, exposeOptionsBody, .{});
    }
    fn exposeOptionsBody(s: *a.Scope) !c.JSValue {
        const record = try s.own(try @import("extensions/native_node_options.zig").acquire(s.engine));
        const get_option = try s.get(record, "getOptionValue");
        // This test-only view calls the actual retained getCLIOptionsFromBinding
        // declaration. It neither substitutes its binding nor creates a cache.
        const roots = try @import("extensions/native_node_module_callable.zig").capturedRoots(s.engine, get_option);
        if (roots.len != 1) return error.ActualModuleOptionGetterRootsRequired;
        const dictionary = try s.own(try a.call(s.engine, roots[0], c.pi_js_undefined(), &.{}));
        const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
        try s.define(global, "actualModuleOptions", record, c.JS_PROP_C_W_E);
        try s.define(global, "actualModuleOptionCache", dictionary, c.JS_PROP_C_W_E);
        return c.pi_js_undefined();
    }
    fn deinit(self: *Fixture) void {
        self.probe.fatal_slot = null;
        self.engine.freeValue(self.probe.first);
        if (self.owner) |owner| self.engine.freeValue(owner);
        self.engine.deinit();
        active_probe = null;
        self.environment.deinit();
    }
    fn run(self: *Fixture, tail: []const u8) !void {
        const source = try std.mem.concat(self.engine.gpa, u8, &.{ @embedFile("extensions/fixtures/native-node-module-creation-observer.mjs"), "\n", tail });
        defer self.engine.gpa.free(source);
        const result = try self.engine.evalModule(source, "actual-node-module-creation-observer.mjs");
        self.engine.freeValue(result);
    }
    fn value(self: *Fixture, name: [*:0]const u8) !c.JSValue {
        const global = try self.engine.checked(c.JS_GetGlobalObject(self.engine.context));
        defer self.engine.freeValue(global);
        return self.engine.checked(c.JS_GetPropertyStr(self.engine.context, global, name));
    }
};
fn observe(comptime name: []const u8, pending_deprecation: bool) !void {
    var fixture: Fixture = undefined; try fixture.init(pending_deprecation); defer fixture.deinit();
    try fixture.run(name ++ "(actualModuleCreation);");
}
test "native actual Module creation constructor fields cache and ordinary call shape" { try observe("observeModuleConstructor", false); }
test "native actual Module creation public assignments and own exports preserve order" { try observe("observeModuleAssignments", false); }
test "native actual Module creation actual parent children and parent setter" { try observe("observeModuleParent", false); }
test "native actual Module creation accessor flags and ordinary versus shorthand shapes" { try observe("observeModuleDescriptors", false); }
test "native actual Module creation reverse path scan roots and UTF16" { try observe("observeModulePaths", false); }
test "native actual Module creation nmChars observes inherited index beyond twelve" { try observe("observeModulePathIndexedPrototype", false); }
test "native actual Module creation nmChars indexed getter ordinary throw" { try observe("observeModulePathIndexedThrow", false); }
test "native actual Module creation retains actual path scan primordials" { try observe("observeModulePathsPrimordials", false); }
test "native actual Module creation createRequire captures the real Module and directory" { try observe("observeCreateRequireContexts", false); }
test "native actual Module creation createRequire preserves Node24 URL context" { try observe("observeCreateRequireURL", false); }
test "native actual Module creation createRequire live path callee precedes arguments" { try observe("observeCreateRequirePathCallees", false); }
test "native actual Module creation createRequire genuine errors and outside catch gate" { try observe("observeCreateRequireFailures", false); }
test "native actual Module creation createRequire uses original URL and suffix callable" { try observe("observeCreateRequireCapturedURL", false); }
test "native actual Module creation require main own definition and following assignments" { try observe("observeRequireCopiedFields", false); }
test "native actual Module creation require dispatches actual live Module methods" { try observe("observeRequireLiveDispatch", false); }
test "native actual Module creation pending parent warning uses original code owner" { try observe("observeModuleWarnings", true); }
test "native actual Module creation warned flag precedes failed warning call" { try observe("observeModuleWarningFailure", true); }

test "native actual Module creation completed core shares immutable constructor and cache" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const again = try core.create(fixture.engine); defer fixture.engine.freeValue(again);
    const lexical = try modules.actualConstructor(fixture.engine); defer fixture.engine.freeValue(lexical);
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, fixture.owner.?, again));
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, lexical, again));
    var s = a.Scope.init(fixture.engine);
    _ = try s.finish(verifyCache(&s, again));
}
fn verifyCache(s: *a.Scope, constructor: c.JSValue) !c.JSValue {
    try std.testing.expect(s.equal(try s.get(constructor, "_cache"), s.engine.commonjs_cache));
    return c.pi_js_undefined();
}
test "native actual Module creation callee and child lexical retire before next statement" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.run(
        \\const M = actualModuleCreation.Module, path = actualModuleCreation.path;
        \\const dirname = Object.getOwnPropertyDescriptor(path,"dirname");
        \\const pathSlot = Object.getOwnPropertyDescriptor(M.prototype,"path");
        \\const filenameSlot = Object.getOwnPropertyDescriptor(M.prototype,"filename");
        \\try {
        \\  Object.defineProperty(path,"dirname",{configurable:true,get(){
        \\    const holder = actualModuleHolder(0);
        \\    return function(){ void holder; return "selected"; };
        \\  }});
        \\  Object.defineProperty(M.prototype,"path",{configurable:true,set(value){
        \\    moduleAssert(actualModuleFreedCount(0) === 1,"actual dirname callee retired before path assignment");
        \\    Object.defineProperty(this,"path",{value,writable:true,enumerable:true,configurable:true});
        \\  }});
        \\  Object.defineProperty(M.prototype,"filename",{configurable:true,set(value){
        \\    moduleAssert(actualModuleFreedCount(1) === 1,"actual updateChildren local retired before filename assignment");
        \\    Object.defineProperty(this,"filename",{value,writable:true,enumerable:true,configurable:true});
        \\  }});
        \\  const parent = {get children(){
        \\    const holder = actualModuleHolder(1);
        \\    Object.defineProperty(holder,"length",{value:0,writable:true,configurable:true});
        \\    return holder;
        \\  }};
        \\  const child = new M("input",parent);
        \\  moduleAssert(child.path === "selected" && child.filename === null && child.loaded === false,"normal constructor continues");
        \\} finally {
        \\  Object.defineProperty(path,"dirname",dirname);
        \\  moduleRestore(M.prototype,"path",pathSlot);
        \\  moduleRestore(M.prototype,"filename",filenameSlot);
        \\}
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[1]);
    try fixture.engine.checkNativeEntry();
}
fn retainProgress(fixture: *Fixture) !c.JSValue {
    try fixture.run("globalThis.actualModuleProgress = {dirname:0,path:0,caught:0};");
    return fixture.value("actualModuleProgress");
}
fn verifyFatal(fixture: *Fixture, result: anyerror!void, progress: c.JSValue) !void {
    try std.testing.expectError(error.JavaScriptException, result);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualModuleFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // This owner was retained before the operation and has only own number
    // data properties. No guest observer is run after the selected fatal.
    inline for (.{ .{ "dirname", @as(u32, 1) }, .{ "path", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
test "native actual Module creation callee cleanup fatal stops before next setter and catch" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const progress = try retainProgress(&fixture); defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_slot = 0;
    const result = fixture.run(
        \\const M = actualModuleCreation.Module;
        \\Object.defineProperty(actualModuleCreation.path,"dirname",{configurable:true,get(){
        \\  actualModuleProgress.dirname++;
        \\  const holder = actualModuleHolder(0);
        \\  return function(){ void holder; return "selected"; };
        \\}});
        \\Object.defineProperty(M.prototype,"path",{configurable:true,set(){actualModuleProgress.path++;}});
        \\try { new M("input"); } catch { actualModuleProgress.caught++; }
    );
    try verifyFatal(&fixture, result, progress);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
}
test "native actual Module creation actual getter fatal stops before next setter and catch" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const progress = try retainProgress(&fixture); defer fixture.engine.freeValue(progress);
    const result = fixture.run(
        \\const M = actualModuleCreation.Module;
        \\Object.defineProperty(actualModuleCreation.path,"dirname",{configurable:true,get(){
        \\  actualModuleProgress.dirname++; return actualModuleFatal();
        \\}});
        \\Object.defineProperty(M.prototype,"path",{configurable:true,set(){actualModuleProgress.path++;}});
        \\try { new M("input"); } catch { actualModuleProgress.caught++; }
    );
    try verifyFatal(&fixture, result, progress);
    try std.testing.expectEqual(@as(u32, 0), fixture.probe.freed[0]);
}
test "native actual Module creation ordinary private dirname DATA keeps exact identity" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.actualModuleSavedData = undefined;
        \\const saved = Object.getOwnPropertyDescriptor(actualModuleCreation.path,"dirname");
        \\try {
        \\  Object.defineProperty(actualModuleCreation.path,"dirname",{configurable:true,get(){
        \\    actualModuleSavedData = actualModulePrivateData(); throw actualModuleSavedData;
        \\  }});
        \\  moduleAssert(moduleThrown(() => new actualModuleCreation.Module("input")) === actualModuleSavedData,"ordinary private getter DATA");
        \\} finally { Object.defineProperty(actualModuleCreation.path,"dirname",saved); }
    );
    const value = try fixture.value("actualModuleSavedData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(!c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module creation successful flagged dirname DATA is assigned unchanged" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    const generation = fixture.engine.native_allocation_generation;
    try fixture.run(
        \\globalThis.actualModuleSavedData = undefined;
        \\const saved = Object.getOwnPropertyDescriptor(actualModuleCreation.path,"dirname");
        \\try {
        \\  Object.defineProperty(actualModuleCreation.path,"dirname",{configurable:true,value:function(){
        \\    return actualModuleSavedData = actualModuleFlaggedData();
        \\  }});
        \\  const value = new actualModuleCreation.Module("input");
        \\  moduleAssert(value.path === actualModuleSavedData && value.filename === null && value.loaded === false,"successful flagged return stays DATA through later statements");
        \\} finally { Object.defineProperty(actualModuleCreation.path,"dirname",saved); }
    );
    const value = try fixture.value("actualModuleSavedData"); defer fixture.engine.freeValue(value);
    try std.testing.expect(c.JS_IsUncatchableError(value));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(fixture.engine.context));
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module creation suffix primordial reuses completed argument owner" {
    var fixture: Fixture = undefined; try fixture.initMode(false, false); defer fixture.deinit();
    try fixture.run(
        \\globalThis.actualModuleSavedEndsWith = Object.getOwnPropertyDescriptor(String.prototype,"endsWith");
        \\Object.defineProperty(String.prototype,"endsWith",{configurable:true,get(){throw Error("late core endsWith snapshot");}});
    );
    fixture.owner = try core.create(fixture.engine);
    try fixture.run(
        \\Object.defineProperty(String.prototype,"endsWith",actualModuleSavedEndsWith);
        \\delete globalThis.actualModuleSavedEndsWith;
    );
    var s = a.Scope.init(fixture.engine);
    _ = try s.finish(Fixture.installView(&s, fixture.owner.?));
    try fixture.run(
        \\const captured = moduleCapture(actualModuleCreation, () => actualModuleCreation.Module.createRequire(moduleFilename(actualModuleCreation,"")));
        \\moduleAssert(captured.module().filename === actualModuleCreation.path.join(moduleFilename(actualModuleCreation,""),"noop.js"),"real createRequire uses earlier actual suffix primordial");
    );
    try fixture.engine.checkNativeEntry();
}

test "native actual Module creation original from argument retires before returned length getter" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.run(
        \\const M = actualModuleCreation.Module, paths = actualModuleCreation.path;
        \\const original = Object.getOwnPropertyDescriptor(paths,"resolve"), stopped = {};
        \\let resolveVisits = 0, lengthVisits = 0;
        \\try {
        \\  Object.defineProperty(paths,"resolve",{configurable:true,value:function(input){
        \\    resolveVisits++;
        \\    return {get length(){
        \\      lengthVisits++;
        \\      moduleAssert(actualModuleFreedCount(0) === 1,"original from argument retired before length getter");
        \\      throw stopped;
        \\    }};
        \\  }});
        \\  moduleAssert(moduleThrown(() => M._nodeModulePaths({owned:actualModuleHolder(0)})) === stopped,"actual returned length throws its ordinary reason");
        \\  moduleAssert(resolveVisits === 1 && lengthVisits === 1,"actual resolve and selected length each visited");
        \\} finally { Object.defineProperty(paths,"resolve",original); }
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    try fixture.engine.checkNativeEntry();
}
test "native actual Module creation original from retirement B prevents length getter and catch" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.run("globalThis.actualModuleArgumentProgress = {resolve:0,length:0,caught:0};");
    const progress = try fixture.value("actualModuleArgumentProgress");
    defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_slot = 0;
    const attempted = fixture.run(
        \\Object.defineProperty(actualModuleCreation.path,"resolve",{configurable:true,value:function(input){
        \\  actualModuleArgumentProgress.resolve++;
        \\  return {get length(){ actualModuleArgumentProgress.length++; return 0; }};
        \\}});
        \\try { actualModuleCreation.Module._nodeModulePaths({owned:actualModuleHolder(0)}); }
        \\catch { actualModuleArgumentProgress.caught++; }
    );
    try std.testing.expectError(error.JavaScriptException, attempted);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualModuleArgumentFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // Retained before the call; all values are own primitive data. There is no
    // guest callback after fatal selection, and each guest visit records first.
    inline for (.{ .{ "resolve", @as(u32, 1) }, .{ "length", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}

test "native actual Module creation pending warning follows genuine options refresh" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.exposeOptions();
    try fixture.run(
        \\globalThis.actualModuleOptionWarnings = 0;
        \\globalThis.actualModuleOriginalWarning = Object.getOwnPropertyDescriptor(actualModuleCreation.process,"emitWarning");
        \\Object.defineProperty(actualModuleCreation.process,"emitWarning",{configurable:true,value(){
        \\  actualModuleOptionWarnings++;
        \\}});
        \\const getter = Object.getOwnPropertyDescriptor(actualModuleCreation.Module.prototype,"parent").get;
        \\moduleAssert(actualModuleOptions.getOptionValue("--pending-deprecation") === false,"actual configured initial pending option");
        \\getter.call(new actualModuleCreation.Module("first"));
        \\moduleAssert(actualModuleOptionWarnings === 0,"disabled predicate leaves this wrapper unwarned");
    );
    // Change the actual native startup-value owner, then invoke its original
    // refresh declaration. No callback or independently built flag map replaces
    // the genuine serializer or its JavaScript lazy cell in this control.
    fixture.engine.node_options.?.values.pending_deprecation = true;
    try fixture.run(
        \\try {
        \\  actualModuleOptions.refreshOptions();
        \\  moduleAssert(actualModuleOptions.getOptionValue("--pending-deprecation") === true,"real serializer sees current native option after refresh");
        \\  const getter = Object.getOwnPropertyDescriptor(actualModuleCreation.Module.prototype,"parent").get;
        \\  getter.call(new actualModuleCreation.Module("second"));
        \\  getter.call(new actualModuleCreation.Module("third"));
        \\  moduleAssert(actualModuleOptionWarnings === 1,"same Module wrapper observes refreshed option and then warns once");
        \\} finally {
        \\  moduleRestore(actualModuleCreation.process,"emitWarning",actualModuleOriginalWarning);
        \\}
    );
    try fixture.engine.checkNativeEntry();
}

test "native actual Module creation pending option calls short circuit and retain original declaration" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.exposeOptions();
    try fixture.run(
        \\const process = actualModuleCreation.process, values = actualModuleOptionCache;
        \\const emit = Object.getOwnPropertyDescriptor(process,"emitWarning");
        \\const original = Object.getOwnPropertyDescriptor(actualModuleOptions,"getOptionValue");
        \\const pending = Object.getOwnPropertyDescriptor(values,"--pending-deprecation");
        \\const noDeprecation = Object.getOwnPropertyDescriptor(values,"--no-deprecation");
        \\const trace = []; let enabled = false, suppressed = true;
        \\const getter = Object.getOwnPropertyDescriptor(actualModuleCreation.Module.prototype,"parent").get;
        \\const receiver = new actualModuleCreation.Module("selected");
        \\try {
        \\  Object.defineProperty(actualModuleOptions,"getOptionValue",{configurable:true,get(){throw Error("late option export lookup");}});
        \\  Object.defineProperty(values,"--pending-deprecation",{configurable:true,get(){trace.push("pending");return enabled;}});
        \\  Object.defineProperty(values,"--no-deprecation",{configurable:true,get(){trace.push("no");return suppressed;}});
        \\  Object.defineProperty(process,"emitWarning",{configurable:true,value(){trace.push("warning");}});
        \\  getter.call(receiver);
        \\  moduleAssert(JSON.stringify(trace) === '["pending"]',"false first option skips second real getter");
        \\  enabled = true;
        \\  getter.call(receiver);
        \\  moduleAssert(JSON.stringify(trace) === '["pending","pending","no"]',"no-deprecation suppresses before warned publication");
        \\  suppressed = false;
        \\  getter.call(receiver);
        \\  getter.call(receiver);
        \\  moduleAssert(JSON.stringify(trace) === '["pending","pending","no","pending","no","warning"]',"real repeated calls precede warning and warned short circuits later lookup");
        \\} finally {
        \\  Object.defineProperty(values,"--pending-deprecation",pending);
        \\  Object.defineProperty(values,"--no-deprecation",noDeprecation);
        \\  Object.defineProperty(actualModuleOptions,"getOptionValue",original);
        \\  moduleRestore(process,"emitWarning",emit);
        \\}
    );
    try fixture.engine.checkNativeEntry();
}

test "native actual Module creation pending option holder retires before second option" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.exposeOptions();
    try fixture.run(
        \\const process = actualModuleCreation.process, values = actualModuleOptionCache;
        \\const emit = Object.getOwnPropertyDescriptor(process,"emitWarning");
        \\const pending = Object.getOwnPropertyDescriptor(values,"--pending-deprecation");
        \\const noDeprecation = Object.getOwnPropertyDescriptor(values,"--no-deprecation");
        \\let first = 0, second = 0, warnings = 0;
        \\try {
        \\  Object.defineProperty(values,"--pending-deprecation",{configurable:true,get(){first++;return actualModuleHolder(0);}});
        \\  Object.defineProperty(values,"--no-deprecation",{configurable:true,get(){
        \\    second++;
        \\    moduleAssert(actualModuleFreedCount(0) === 1,"actual first option value retires before second property getter");
        \\    return false;
        \\  }});
        \\  Object.defineProperty(process,"emitWarning",{configurable:true,value(){warnings++;}});
        \\  const getter = Object.getOwnPropertyDescriptor(actualModuleCreation.Module.prototype,"parent").get;
        \\  getter.call(new actualModuleCreation.Module("selected"));
        \\  moduleAssert(first === 1 && second === 1 && warnings === 1,"all original predicate and warning operations reached exactly once");
        \\} finally {
        \\  Object.defineProperty(values,"--pending-deprecation",pending);
        \\  Object.defineProperty(values,"--no-deprecation",noDeprecation);
        \\  moduleRestore(process,"emitWarning",emit);
        \\}
    );
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    try fixture.engine.checkNativeEntry();
}

test "native actual Module creation pending option retirement B prevents next option warning and catch" {
    var fixture: Fixture = undefined; try fixture.init(false); defer fixture.deinit();
    try fixture.exposeOptions();
    try fixture.run("globalThis.actualModuleOptionProgress = {first:0,second:0,warning:0,caught:0};");
    const progress = try fixture.value("actualModuleOptionProgress");
    defer fixture.engine.freeValue(progress);
    fixture.probe.fatal_slot = 0;
    const attempted = fixture.run(
        \\Object.defineProperty(actualModuleOptionCache,"--pending-deprecation",{configurable:true,get(){
        \\  actualModuleOptionProgress.first++;
        \\  return actualModuleHolder(0);
        \\}});
        \\Object.defineProperty(actualModuleOptionCache,"--no-deprecation",{configurable:true,get(){
        \\  actualModuleOptionProgress.second++; return false;
        \\}});
        \\Object.defineProperty(actualModuleCreation.process,"emitWarning",{configurable:true,value(){
        \\  actualModuleOptionProgress.warning++;
        \\}});
        \\const getter = Object.getOwnPropertyDescriptor(actualModuleCreation.Module.prototype,"parent").get;
        \\try { getter.call(new actualModuleCreation.Module("selected")); }
        \\catch { actualModuleOptionProgress.caught++; }
    );
    try std.testing.expectError(error.JavaScriptException, attempted);
    try std.testing.expectEqual(@as(u32, 1), fixture.probe.freed[0]);
    const reason = fixture.engine.captured_exception orelse return error.MissingActualModuleOptionFatalReason;
    try std.testing.expect(c.JS_IsStrictEqual(fixture.engine.context, reason, fixture.probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
    try std.testing.expect(fixture.engine.native_fatal_invocation == null);
    // This retained record has only own numeric data properties; no guest
    // callback is evaluated after the actual fatal has selected its reason.
    inline for (.{ .{ "first", @as(u32, 1) }, .{ "second", @as(u32, 0) },
        .{ "warning", @as(u32, 0) }, .{ "caught", @as(u32, 0) } }) |field| {
        const value = c.JS_GetPropertyStr(fixture.engine.context, progress, field[0]);
        defer fixture.engine.freeValue(value);
        try std.testing.expect(c.JS_IsNumber(value));
        var count: u32 = 0;
        try std.testing.expectEqual(@as(c_int, 0), c.JS_ToUint32(fixture.engine.context, &count, value));
        try std.testing.expectEqual(field[1], count);
    }
}
