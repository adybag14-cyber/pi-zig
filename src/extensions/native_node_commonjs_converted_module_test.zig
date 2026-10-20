//! Actual constructor/cache/publication controls, not a composed Node namespace
//! or jiti bootstrap. The old real createRequire is retained but never invoked.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const ctor = @import("native_node_module_constructor.zig");
const converted = @import("native_node_commonjs_converted_module.zig");
const provider = @import("native_node_commonjs_converted_provider.zig");
const Fixture = struct {
    engine: *v.em.Engine,
    module_constructor: c.JSValue,
    fn init() !Fixture {
        const engine = try v.em.Engine.init(std.testing.allocator, .{ .node_options = .{
            .features = .{ .strip_types = true, .quic = false },
        } });
        errdefer engine.deinit();
        var environment: std.process.Environ.Map = .init(std.testing.allocator);
        defer environment.deinit();
        try @import("native_process.zig").install(engine, std.testing.io,
            &environment, &.{"converted-module-lifecycle"});
        try @import("node_path.zig").install(engine, std.testing.io);
        try @import("commonjs.zig").install(engine);
        var s: v.Scope = .{ .engine = engine }; defer s.deinit();
        const old_module = engine.native_module_values.get("node:module") orelse return error.RequiredActualModuleImplementation;
        const process = try s.own((try engine.requireBuiltin("node:process")) orelse
            return error.ActualConvertedModuleProcessRequired);
        const options = try s.own(try @import("native_node_options.zig").acquire(engine));
        const graph = try ctor.create(engine, .{ .paths = engine.native_module_values.get("node:path").?,
            .create_require = try s.get(old_module, "createRequire"), .process = process,
            .get_option_value = try s.get(options, "getOptionValue") });
        engine.freeValue(graph.namespace_exports);
        return .{ .engine = engine, .module_constructor = graph.module_constructor };
    }
    fn deinit(self: Fixture) void { self.engine.freeValue(self.module_constructor); self.engine.deinit(); }
};
fn evaluate(s: *v.Scope, code: []const u8) !c.JSValue { return s.own(try s.engine.eval(code, "converted-module-lifecycle.js", c.JS_EVAL_TYPE_GLOBAL)); }
fn fresh(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue { return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory(); }
fn globals(s: *v.Scope, fixture: Fixture) !c.JSValue {
    const global = try s.own(try fixture.engine.checked(c.JS_GetGlobalObject(fixture.engine.context)));
    try s.put(global, "OwnedModule", fixture.module_constructor);
    try s.put(global, "ownedFilename", try s.text(if (builtin.os.tag == .windows) "C:\\owned-converted\\dist\\babel.cjs" else "/owned-converted/dist/babel.cjs"));
    try s.put(global, "ownedFresh", try s.own(try fixture.engine.checked(c.JS_NewCFunction(fixture.engine.context, fresh, "ownedFresh", 0))));
    _ = try evaluate(s, "globalThis.ownedExports=function actualNativeBackend(){return 42};globalThis.ownedParent=new OwnedModule(ownedFilename);globalThis.ownedReason={ordinary:true};");
    return global;
}
fn inputs(s: *v.Scope, fixture: Fixture, global: c.JSValue) !converted.Inputs {
    return .{ .module_constructor = fixture.module_constructor, .filename = try s.get(global, "ownedFilename"), .parent = try s.get(global, "ownedParent"), .exports = try s.get(global, "ownedExports") };
}
test "converted CommonJS module uses actual canonical constructor cache parent paths and export snapshot" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    const values = try inputs(&s, fixture, global);
    const module = try s.own(try converted.publish(fixture.engine, values));
    try s.put(global, "ownedPublished", module);
    try std.testing.expect(s.truthy(try evaluate(&s, "ownedPublished instanceof OwnedModule && OwnedModule._cache[ownedFilename]===ownedPublished && ownedPublished.filename===ownedFilename && ownedPublished.exports===ownedExports && ownedPublished.loaded===true && ownedPublished.parent===ownedParent && ownedParent.children.length===1 && ownedParent.children[0]===ownedPublished && Array.isArray(ownedPublished.paths)")));
    const snapshot = try s.own(try ctor.exportsSnapshot(fixture.engine, fixture.module_constructor, module));
    try std.testing.expect(s.equal(snapshot, values.exports));
    c.JS_RunGC(fixture.engine.runtime);
    const again = try s.own(try converted.publish(fixture.engine, values));
    try std.testing.expect(s.equal(again, module));
    try std.testing.expect(s.truthy(try evaluate(&s, "ownedParent.children.length===1")));
    const first = try s.own(try ctor.firstParent(fixture.engine, fixture.module_constructor, module));
    try std.testing.expect(s.equal(first, values.parent));
    _ = try evaluate(&s, "globalThis.ownedOtherParent=new OwnedModule(ownedFilename)");
    var other = values;
    other.parent = try s.get(global, "ownedOtherParent");
    const reused = try s.own(try converted.publish(fixture.engine, other));
    try std.testing.expect(s.equal(reused, module));
    try std.testing.expect(s.equal(try s.own(try ctor.firstParent(fixture.engine, fixture.module_constructor, module)), values.parent));
    try std.testing.expect(s.equal(try s.own(try ctor.lastParent(fixture.engine, fixture.module_constructor, module)), other.parent));
    const key_a = try s.own(try ctor.loaderKey(fixture.engine, fixture.module_constructor, .is_main));
    const key_b = try s.own(try ctor.loaderKey(fixture.engine, fixture.module_constructor, .is_main));
    try std.testing.expect(s.equal(key_a, key_b));
}
test "converted CommonJS module cache publication precedes body and captures live paths callee first" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    // Constructor child publication is genuine guest-visible lifecycle. Its
    // parent push trap installs observers on the actual new Module, no fake.
    _ = try evaluate(&s, "globalThis.ownedOrder=[];globalThis.ownedBacking=[];ownedParent.children=new Proxy(ownedBacking,{set(t,k,x,r){if(k==='0'){Object.defineProperty(x,'paths',{configurable:true,get(){if(OwnedModule._cache[ownedFilename]!==x||x.loaded!==false||typeof x.exports!=='object')throw Error('publication order');ownedOrder.push('paths-read');return undefined},set(v){Object.defineProperty(x,'paths',{value:v,writable:true,configurable:true,enumerable:true})}})}return Reflect.set(t,k,x,r)}});globalThis.ownedNodePaths=OwnedModule._nodeModulePaths;Object.defineProperty(OwnedModule,'_nodeModulePaths',{configurable:true,get(){ownedOrder.push('callee');return function(path){ownedOrder.push('paths');return Reflect.apply(ownedNodePaths,this,[path])}}});");
    _ = try s.own(try converted.publish(fixture.engine, try inputs(&s, fixture, global)));
    try std.testing.expect(s.truthy(try evaluate(&s, "ownedOrder.join(',')==='paths-read,callee,paths'")));
}
const Failure = enum { ordinary, fresh_private };
fn failure(mode: Failure) !void {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    defer if (fixture.engine.captured_exception) |reason| c.JS_ClearUncatchableError(fixture.engine.context, reason);
    const global = try globals(&s, fixture);
    _ = try evaluate(&s, "globalThis.ownedCoercions=0;ownedReason.toString=function(){ownedCoercions++;throw Error('must not diagnose raw reason')}");
    _ = try evaluate(&s, if (mode == .ordinary)
        "OwnedModule._nodeModulePaths=function(){throw ownedReason}"
    else "OwnedModule._nodeModulePaths=function(){return ownedFresh()}");
    const values = try inputs(&s, fixture, global);
    const generation = fixture.engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, converted.publish(fixture.engine, values));
    const actual = fixture.engine.captured_exception orelse return error.MissingConvertedReason;
    if (mode == .ordinary) {
        try std.testing.expect(s.equal(actual, try s.get(global, "ownedReason")));
        try std.testing.expect(s.truthy(try evaluate(&s, "ownedCoercions===0&&!Object.hasOwn(OwnedModule._cache,ownedFilename)&&ownedParent.children.length===0")));
    } else {
        try std.testing.expect(s.equal(actual, fixture.engine.native_allocation_exception.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
        try std.testing.expect(s.truthy(try evaluate(&s, "Object.hasOwn(OwnedModule._cache,ownedFilename)&&ownedParent.children.length===1&&OwnedModule._cache[ownedFilename].loaded===false")));
    }
    try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
}
test "converted CommonJS module ordinary initialization failure removes actual cache and child" { try failure(.ordinary); }
test "converted CommonJS module fresh private initialization failure bypasses guest cleanup" { try failure(.fresh_private); }
test "converted CommonJS module entry classifies fresh cache getter fatal without external suppression" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    defer if (fixture.engine.captured_exception) |reason| c.JS_ClearUncatchableError(fixture.engine.context, reason);
    const global = try globals(&s, fixture);
    _ = try evaluate(&s, "Object.defineProperty(OwnedModule,'_cache',{get(){return ownedFresh()},configurable:true})");
    const values = try inputs(&s, fixture, global);
    const generation = fixture.engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, converted.publish(fixture.engine, values));
    const actual = fixture.engine.captured_exception orelse return error.MissingEntryReason;
    try std.testing.expect(s.equal(actual, fixture.engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
}
test "converted CommonJS module refuses forged constructor cache records and conflicting actual exports" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    var values = try inputs(&s, fixture, global);
    _ = try evaluate(&s, "globalThis.ownedForged={get _cache(){throw Error('must not read forged cache')}};OwnedModule._cache[ownedFilename]={filename:ownedFilename,exports:ownedExports,loaded:true};");
    const actual_constructor = values.module_constructor;
    values.module_constructor = try s.get(global, "ownedForged");
    try std.testing.expectError(error.InvalidKnownModuleConstructor, converted.publish(fixture.engine, values));
    values.module_constructor = actual_constructor;
    try std.testing.expectError(error.ConvertedModuleCacheCollision, converted.publish(fixture.engine, values));
    _ = try evaluate(&s, "delete OwnedModule._cache[ownedFilename]");
    _ = try s.own(try converted.publish(fixture.engine, values));
    values.exports = try s.object();
    try std.testing.expectError(error.ConvertedModuleCacheCollision, converted.publish(fixture.engine, values));
}
test "converted CommonJS provider readiness is private and lazy without cache or parent publication" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    const values = try inputs(&s, fixture, global);
    const admission: provider.Inputs = .{ .module_constructor = values.module_constructor, .filename = values.filename, .exports = values.exports };
    try std.testing.expect(!try provider.ready(fixture.engine, admission));
    try provider.register(fixture.engine, admission);
    try std.testing.expect(try provider.ready(fixture.engine, admission));
    const body = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, values.filename, try s.text("commonjs"), true, false));
    try std.testing.expect(c.JS_IsFunction(fixture.engine.context, body));
    try std.testing.expect(!c.JS_IsAsyncFunction(body));
    try std.testing.expect(s.equal(try s.get(body, "length"), c.JS_NewInt32(fixture.engine.context, 5)));
    try provider.register(fixture.engine, admission);
    c.JS_RunGC(fixture.engine.runtime);
    const again = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, values.filename, try s.text("commonjs"), true, false));
    try std.testing.expect(s.equal(body, again));
    try std.testing.expect(s.truthy(try evaluate(&s, "Object.keys(OwnedModule._cache).length===0&&ownedParent.children.length===0")));
    var conflict = admission;
    conflict.exports = try evaluate(&s, "(function conflictingBackend(){})");
    try std.testing.expectError(error.ConflictingConvertedCJSProvider, provider.register(fixture.engine, conflict));
}
test "converted CommonJS provider actual compile selector respects format filenames and patched wrappers" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    const values = try inputs(&s, fixture, global);
    try provider.register(fixture.engine, .{ .module_constructor = values.module_constructor, .filename = values.filename, .exports = values.exports });
    inline for (.{ .{ false, false }, .{ true, true } }) |flags| {
        const absent = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, values.filename, try s.text("commonjs"), flags[0], flags[1]));
        try std.testing.expect(c.JS_IsUndefined(absent));
    }
    const module_format = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, values.filename, try s.text("module"), true, false));
    try std.testing.expect(c.JS_IsUndefined(module_format));
    const other_file = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, try s.text("other.cjs"), try s.text("commonjs"), true, false));
    try std.testing.expect(c.JS_IsUndefined(other_file));
}
test "converted CommonJS provider real CJS initializer assigns exact backend without pretending to finish load" {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    const global = try globals(&s, fixture);
    const values = try inputs(&s, fixture, global);
    try provider.register(fixture.engine, .{ .module_constructor = values.module_constructor, .filename = values.filename, .exports = values.exports });
    const body = try s.own(try provider.compiledBody(fixture.engine, values.module_constructor, values.filename, try s.text("commonjs"), true, false));
    var args = [_]c.JSValue{ values.filename, values.parent };
    const module = try s.own(try fixture.engine.checked(c.JS_CallConstructor(fixture.engine.context, values.module_constructor, args.len, &args)));
    const result = try s.call(body, try s.get(module, "exports"), &.{ try s.get(module, "exports"), c.pi_js_undefined(), module, values.filename, try s.text("owned-dir") });
    try std.testing.expect(c.JS_IsUndefined(result));
    try std.testing.expect(s.equal(try s.get(module, "exports"), values.exports));
    try std.testing.expect(!s.truthy(try s.get(module, "loaded")));
    try std.testing.expect(s.truthy(try evaluate(&s, "Object.keys(OwnedModule._cache).length===0")));
    // _load/cache/newModule, surrounding _compile and .load publication are
    // deliberately not simulated here. Their real callsite remains required.
}
fn pendingPath(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const getter_mode = c.JS_GetPropertyStr(context, global, "ownedPendingGetter");
    defer c.JS_FreeValue(context, getter_mode);
    const fresh_mode = c.JS_GetPropertyStr(context, global, "ownedPendingFresh");
    defer c.JS_FreeValue(context, fresh_mode);
    const output = if (c.JS_ToBool(context, getter_mode) == 1) c.JS_GetPropertyStr(context, global, "ownedAbsoluteObserver") else c.pi_js_bool(context, 1);
    if (c.JS_IsException(output)) return output;
    if (c.JS_ToBool(context, fresh_mode) == 1) {
        _ = engine.throwNativeOutOfMemory();
    } else {
        const reason = c.JS_GetPropertyStr(context, global, "ownedReason");
        if (c.JS_IsException(reason)) { c.JS_FreeValue(context, output); return reason; }
        _ = c.JS_Throw(context, reason);
    }
    return output; // Deliberate genuine native success with actual pending reason.
}
fn pendingPathSubject(getter: bool, fresh_private: bool) !void {
    const fixture = try Fixture.init(); defer fixture.deinit();
    var s: v.Scope = .{ .engine = fixture.engine }; defer s.deinit();
    defer if (fixture.engine.captured_exception) |reason| c.JS_ClearUncatchableError(fixture.engine.context, reason);
    const global = try globals(&s, fixture);
    const values = try inputs(&s, fixture, global);
    const admission: provider.Inputs = .{ .module_constructor = values.module_constructor, .filename = values.filename, .exports = values.exports };
    try s.put(global, "ownedPendingGetter", c.pi_js_bool(fixture.engine.context, @intFromBool(getter)));
    try s.put(global, "ownedPendingFresh", c.pi_js_bool(fixture.engine.context, @intFromBool(fresh_private)));
    try s.put(global, "ownedPendingPath", try s.own(try fixture.engine.checked(c.JS_NewCFunction(fixture.engine.context, pendingPath, "ownedPendingPath", 1))));
    try s.put(global, "ownedPath", try s.own(try ctor.pathObject(fixture.engine, values.module_constructor)));
    _ = try evaluate(&s, "globalThis.ownedAbsoluteCalls=0;globalThis.ownedCoercions=0;ownedReason.toString=function(){ownedCoercions++;throw Error('must not coerce')};globalThis.ownedAbsoluteObserver=function(){ownedAbsoluteCalls++;return true};");
    _ = try evaluate(&s, if (getter) "Object.defineProperty(ownedPath,'isAbsolute',{get:ownedPendingPath,configurable:true})" else "ownedPath.isAbsolute=ownedPendingPath");
    const generation = fixture.engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, provider.register(fixture.engine, admission));
    const actual = fixture.engine.captured_exception orelse return error.MissingPendingProviderReason;
    if (fresh_private) {
        try std.testing.expect(s.equal(actual, fixture.engine.native_allocation_exception.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(generation +% 1, fixture.engine.native_allocation_generation);
    } else try std.testing.expect(s.equal(actual, try s.get(global, "ownedReason")));
    try std.testing.expect(!try provider.ready(fixture.engine, admission));
    try std.testing.expect(s.truthy(try evaluate(&s, "ownedCoercions===0&&ownedAbsoluteCalls===0&&Object.keys(OwnedModule._cache).length===0&&ownedParent.children.length===0")));
    try std.testing.expectEqual(@as(usize, 0), fixture.engine.native_exception_diagnostics_suppressed);
}
test "converted CommonJS provider stops actual pending ordinary getter before callee and publication" { try pendingPathSubject(true, false); }
test "converted CommonJS provider stops actual pending fresh getter before callee and publication" { try pendingPathSubject(true, true); }
test "converted CommonJS provider stops actual pending ordinary callee before publication" { try pendingPathSubject(false, false); }
test "converted CommonJS provider stops actual pending fresh callee before publication" { try pendingPathSubject(false, true); }
