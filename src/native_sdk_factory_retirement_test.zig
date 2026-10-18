//! Actual constructor native-retirement controls. No package supplier, child,
//! Completed graph or successful session is substituted.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const js = @import("extensions/native_js_values.zig");
const Scope = @import("extensions/native_sdk_prompt_scope.zig").Scope;
const owned = @import("extensions/native_sdk_owned_completion.zig");
const manager = @import("extensions/native_sdk_package_manager.zig");
const Emission = struct { engine: *em.Engine, ordinary: c.JSValue, fatal: bool, emitted: ?c.JSValue = null, calls: usize = 0 };
fn emit(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const self: *Emission = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    self.calls += 1;
    if (self.fatal) {
        _ = self.engine.throwNativeOutOfMemory();
        self.emitted = self.engine.native_allocation_exception;
    } else _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, self.ordinary));
}
fn token(self: *Emission) !c.JSValue {
    var id: c.JSClassID = 0; _ = c.JS_NewClassID(self.engine.runtime, &id);
    const definition: c.JSClassDef = .{ .class_name = "Actual PackageManager temporary carrier", .finalizer = emit };
    if (c.JS_NewClass(self.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const result = try self.engine.checked(c.JS_NewObjectClass(self.engine.context, id));
    _ = c.JS_SetOpaque(result, self); return result;
}
fn getter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const ctx = context.?;
    if (magic != 0) return c.JS_Throw(ctx, c.JS_DupValue(ctx, roots[0]));
    const result = c.JS_GetPropertyStr(ctx, roots[0], "value");
    if (c.JS_IsException(result)) return result;
    const atom = c.JS_NewAtom(ctx, "value");
    if (atom == c.JS_ATOM_NULL) return failGetter(ctx, result);
    defer c.JS_FreeAtom(ctx, atom);
    if (c.JS_DeleteProperty(ctx, roots[0], atom, c.JS_PROP_THROW) < 0) return failGetter(ctx, result);
    return result; // Sole legal user-option carrier transfers to constructor.
}
fn failGetter(context: *c.JSContext, result: c.JSValue) c.JSValue {
    const engine = em.Engine.fromContext(context);
    var completion = owned.Completion.initValue(engine, js.capture(engine));
    completion.release(result);
    return completion.finishValue() catch |err| @import("extensions/native_sdk.zig").fail(engine, err);
}
fn accessor(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, source: c.JSValue, magic: c_int) !void {
    var data = [_]c.JSValue{source};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, getter, "get", 0, magic, 1, &data));
    const atom = c.JS_NewAtom(engine.context, name);
    if (atom == c.JS_ATOM_NULL) { engine.freeValue(function); return js.capture(engine); }
    defer c.JS_FreeAtom(engine.context, atom);
    if (c.JS_DefinePropertyGetSet(engine.context, object, atom, function, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
}
fn constructorCase(fatal: bool) !void {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"actual-native-package-constructor-control"});
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first = try s.object();
    const later = try s.object();
    var emission: Emission = .{ .engine = engine, .ordinary = later, .fatal = fatal };
    const prototype = try s.object();
    const constructor = try s.own(try manager.constructor(engine, prototype));
    const options = try s.object();
    const cwd = try s.invoke(try s.global("process"), "cwd", &.{});
    try s.put(options, "cwd", cwd); try s.put(options, "agentDir", cwd);
    const holder = try s.object();
    // A legal user options object: Source stores settingsManager without
    // invoking a method, then builtinExtensions throws before construction can
    // complete. No fake manager is returned as a successful dependency graph.
    try js.define(engine, holder, "value", try token(&emission));
    try accessor(engine, options, "settingsManager", holder, 0);
    try accessor(engine, options, "builtinExtensions", first, 1);
    var args = [_]c.JSValue{options};
    try std.testing.expectError(error.JavaScriptException, engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args)));
    try std.testing.expectEqual(@as(usize, 1), emission.calls);
    const actual = engine.captured_exception orelse return error.RequiredActualConstructorReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, if (fatal) emission.emitted.? else first));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "SDK factory retirement actual PackageManager error beats ordinary sole option cleanup" { try constructorCase(false); }
test "SDK factory retirement actual PackageManager fresh cleanup native OOM promotes" { try constructorCase(true); }

test "SDK factory retirement actual progress setter suppresses ordinary catch diagnostics" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator); defer environment.deinit();
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    try @import("extensions/timers.zig").install(engine, std.testing.io);
    try @import("extensions/native_process.zig").install(engine, std.testing.io, &environment, &.{"actual-package-progress-control"});
    try @import("extensions/node_path.zig").install(engine, std.testing.io);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const prototype = try s.object();
    try manager.installProgress(engine, prototype);
    const constructor = try s.own(try manager.constructor(engine, prototype));
    const actual_managers = try s.own(try @import("extensions/native_sdk.zig").managerImports(engine));
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    try s.put(global, "ActualPackageConstructor", constructor);
    try s.put(global, "ActualSettingsConstructor", try s.get(actual_managers, "SettingsManager"));
    const observed = try engine.evalModule(
        \\const options={cwd:process.cwd(),agentDir:process.cwd(),settingsManager:ActualSettingsConstructor.inMemory()};
        \\const manager=new ActualPackageConstructor(options),reason=new Error('actual setter');let calls=0,coercions=0,caught;
        \\reason.toString=()=>{coercions++;throw Error('unexpected catch diagnostic')};
        \\Object.defineProperty(manager,'progressCallback',{configurable:true,set(){calls++;throw reason}});
        \\try{manager.setProgressCallback(undefined)}catch(error){caught=error}
        \\if(caught!==reason||calls!==1||coercions!==0)throw Error('progress raw reason/diagnostic suppression');
        \\export const passed=true;
    , "actual-package-progress-diagnostic-control.mjs");
    engine.freeValue(observed);
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

test "SDK factory retirement direct progress installation suppresses definition diagnostics" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const global = try s.own(c.JS_GetGlobalObject(engine.context));
    const initialized = try engine.evalModule(
        \\globalThis.installReason=new Error('actual install');globalThis.installCoercions=0;globalThis.installDefinitions=0;
        \\installReason.toString=()=>{installCoercions++;throw Error('unexpected direct-host diagnostic')};
        \\globalThis.actualInstallTarget=new Proxy({}, {defineProperty(){installDefinitions++;throw installReason}});
        \\export const prepared=true;
    , "actual-package-install-diagnostic-input.mjs");
    engine.freeValue(initialized);
    const target = try s.get(global, "actualInstallTarget");
    const original = try s.get(global, "installReason");
    try std.testing.expectError(error.JavaScriptException, manager.installProgress(engine, target));
    const actual = engine.captured_exception orelse return error.RequiredActualInstallReason;
    try std.testing.expect(s.equal(actual, original));
    try std.testing.expect(s.equal(try s.get(global, "installCoercions"), c.JS_NewInt32(engine.context, 0)));
    try std.testing.expect(s.equal(try s.get(global, "installDefinitions"), c.JS_NewInt32(engine.context, 1)));
    try std.testing.expect(engine.native_fatal_invocation == null);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}

/// Genuine complete supplier profile; caller supplies its actual package Inputs
/// from the canonical owner. This is not counted as a registered native test.
pub fn createActualPackage(engine: *em.Engine, inputs: @import("extensions/native_sdk_package_assembly.zig").Inputs) !c.JSValue {
    return @import("extensions/native_sdk_package_assembly.zig").create(engine, inputs);
}
/// Actual loader input graph must contain the real queued import, Node Module,
/// physical loader metadata and namespaces. No unused fake capability is made.
pub fn createActualLoader(engine: *em.Engine, inputs: @import("extensions/native_sdk_extension_loader_assembly.zig").Inputs) !c.JSValue {
    return @import("extensions/native_sdk_extension_loader_assembly.zig").create(engine, inputs);
}
