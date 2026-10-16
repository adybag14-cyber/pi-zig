//! Prepared raw-VM integration tests for the reviewed experimental C capability.
//! Fixture callbacks compile real user modules in the actual VM. No SDK,
//! TypeBox checker, registry or Node bridge substitutes for the implementation.
const std = @import("std");
const em = @import("extensions/engine.zig");
const js = @import("extensions/native_js_values.zig");
const c = em.c;
const root_name = "C:/private-module-graph/root.ts";
const dep_name = "C:/private-module-graph/dep.ts";
const shared_name = "C:/private-module-graph/shared.mjs";
const Fixture = struct {
    engine: *em.Engine,
    version: u32 = 1,
    selections: usize = 0,
    bad_return: bool = false,
    dep_override: ?[:0]const u8 = null,
    native_failure: bool = false,
    native_pending_success: bool = false,
    native_original: ?c.JSValue = null,
    last_origin: ?*const c.JSPiModuleOrigin = null,
    fn install(self: *Fixture) void {
        c.JS_SetModuleLoaderFunc(self.engine.runtime, null, sharedLoad, self);
    }
    fn graph(self: *Fixture) !*c.JSPiPrivateModuleGraph {
        return c.JS_PiNewPrivateModuleGraph(self.engine.context, select, privateLoad, self) orelse return js.capture(self.engine);
    }
    fn from(context_data: ?*anyopaque) *Fixture { return @ptrCast(@alignCast(context_data.?)); }
    fn select(context: ?*c.JSContext, origin: ?*const c.JSPiModuleOrigin, name: [*c]const u8, _: c.JSValue, context_data: ?*anyopaque) callconv(.c) c_int {
        const self = from(context_data); self.selections += 1; self.last_origin = origin;
        if (self.native_failure) {
            _ = self.engine.throwNativeOutOfMemory();
            const reason = c.JS_GetException(context);
            self.native_original = c.JS_DupValue(context, reason);
            _ = c.JS_Throw(context, reason);
            return if (self.native_pending_success) 0 else -1;
        }
        if (std.mem.eql(u8, std.mem.span(name), shared_name)) return 0;
        return 1; // Explicit fixture kind table, not production file-kind policy.
    }
    fn privateLoad(context: ?*c.JSContext, graph: ?*c.JSPiPrivateModuleGraph, name: [*c]const u8, attrs: c.JSValue, context_data: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
        const self = from(context_data);
        if (self.bad_return) return @ptrFromInt(16); // Must reject before dereference.
        if (!std.mem.eql(u8, std.mem.span(name), dep_name)) {
            _ = c.JS_ThrowReferenceError(context, "Unknown controlled module: %s", name); return null;
        }
        const source: [:0]const u8 = self.dep_override orelse if (self.version == 1)
            "globalThis.depLoads=(globalThis.depLoads??0)+1;export const version=1;"
        else "globalThis.depLoads=(globalThis.depLoads??0)+1;export const version=2;";
        const compiled = c.JS_PiCompilePrivateModule(context, graph, source.ptr, source.len, name, attrs);
        if (c.JS_IsException(compiled)) return null;
        defer c.JS_FreeValue(context, compiled);
        return c.pi_js_module(compiled);
    }
    fn sharedLoad(context: ?*c.JSContext, name: [*c]const u8, context_data: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
        const self = from(context_data);
        if (!std.mem.eql(u8, std.mem.span(name), shared_name)) {
            _ = c.JS_ThrowReferenceError(context, "Unknown shared controlled module: %s", name); return null;
        }
        const source = "globalThis.sharedLoads=(globalThis.sharedLoads??0)+1;export const shared=true;";
        const compiled = self.engine.eval(source, shared_name, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY) catch {
            _ = self.engine.throwCaptured(); return null;
        };
        defer self.engine.freeValue(compiled);
        return c.pi_js_module(compiled);
    }
};
fn compile(engine: *em.Engine, graph: *c.JSPiPrivateModuleGraph, source: [:0]const u8, name: [:0]const u8, attrs: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiCompilePrivateModule(engine.context, graph, source.ptr, source.len, name.ptr, attrs));
}
fn evaluate(engine: *em.Engine, compiled: c.JSValue) !c.JSValue {
    const module = c.pi_js_module(compiled) orelse return error.ExpectedActualModule;
    const pending = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, compiled)));
    defer engine.freeValue(pending);
    const settled = try engine.awaitValue(pending); defer engine.freeValue(settled);
    return engine.checked(c.JS_GetModuleNamespace(engine.context, module));
}
fn number(engine: *em.Engine, value: c.JSValue) !i32 {
    var result: i32 = 0; if (c.JS_ToInt32(engine.context, &result, value) < 0) return js.capture(engine); return result;
}
fn read(engine: *em.Engine, namespace: c.JSValue) !i32 {
    const pending = try js.invoke(engine, namespace, "read", &.{}); defer engine.freeValue(pending);
    const result = try engine.awaitValue(pending); defer engine.freeValue(result); return number(engine, result);
}
fn marker(engine: *em.Engine, compiled: c.JSValue, value: i32) !void {
    const meta = try engine.checked(c.JS_GetImportMeta(engine.context, c.pi_js_module(compiled).?)); defer engine.freeValue(meta);
    if (c.JS_DefinePropertyValueStr(engine.context, meta, "marker", c.JS_NewInt32(engine.context, value), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
}
test "private live dynamic caches preserve old and first late factory policy" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install();
    const source = "export async function read(){const dep=await import('./dep.ts');return dep.version}";
    const old_compiled = try compile(engine, try fixture.graph(), source, root_name, c.pi_js_undefined()); defer engine.freeValue(old_compiled);
    const late_compiled = try compile(engine, try fixture.graph(), source, root_name, c.pi_js_undefined()); defer engine.freeValue(late_compiled);
    const old = try evaluate(engine, old_compiled); defer engine.freeValue(old);
    const late = try evaluate(engine, late_compiled); defer engine.freeValue(late);
    try std.testing.expectEqual(@as(i32, 1), try read(engine, old));
    const before_hit = fixture.selections;
    try std.testing.expectEqual(@as(i32, 1), try read(engine, old));
    try std.testing.expectEqual(before_hit + 1, fixture.selections); // Selector before cached lookup.
    fixture.version = 2;
    const fresh_compiled = try compile(engine, try fixture.graph(), source, root_name, c.pi_js_undefined()); defer engine.freeValue(fresh_compiled);
    const fresh = try evaluate(engine, fresh_compiled); defer engine.freeValue(fresh);
    try std.testing.expectEqual(@as(i32, 2), try read(engine, fresh));
    c.JS_RunGC(engine.runtime);
    try std.testing.expectEqual(@as(i32, 1), try read(engine, old));
    try std.testing.expectEqual(@as(i32, 2), try read(engine, late));
    const loads = try engine.eval("depLoads", "private-graph-count.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(loads);
    try std.testing.expectEqual(@as(i32, 3), try number(engine, loads));
}
test "private exact nested import meta and attribute snapshot survive same physical name" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install(); const graph = try fixture.graph();
    const attrs1 = try engine.eval("({flavor:'one'})", "attrs-one.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(attrs1);
    const attrs2 = try engine.eval("({flavor:'two'})", "attrs-two.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(attrs2);
    const source = "import './shared.mjs';export function nested(){return()=>import.meta.marker}";
    const first = try compile(engine, graph, source, root_name, attrs1); defer engine.freeValue(first);
    const origin = fixture.last_origin orelse return error.MissingExactOrigin;
    const snapshot = c.JS_PiModuleOriginAttributes(origin); if (snapshot == null) return error.MissingSnapshot;
    const changed = try engine.checked(c.JS_NewString(engine.context, "mutated"));
    if (c.JS_SetPropertyStr(engine.context, attrs1, "flavor", changed) < 0) return js.capture(engine);
    const second = try compile(engine, graph, source, root_name, attrs2); defer engine.freeValue(second);
    try marker(engine, first, 11); try marker(engine, second, 22);
    const n1 = try evaluate(engine, first); defer engine.freeValue(n1);
    const n2 = try evaluate(engine, second); defer engine.freeValue(n2);
    c.JS_RunGC(engine.runtime);
    const flavor = try js.get(engine, snapshot[0], "flavor"); defer engine.freeValue(flavor);
    const text = c.JS_ToCString(engine.context, flavor); if (text == null) return js.capture(engine); defer c.JS_FreeCString(engine.context, text);
    try std.testing.expectEqualStrings("one", std.mem.span(text));
    for ([_]c.JSValue{ n1, n2 }, [_]i32{ 11, 22 }) |ns, expected| {
        const nested = try js.invoke(engine, ns, "nested", &.{}); defer engine.freeValue(nested);
        const value = try js.call(engine, nested, c.pi_js_undefined(), &.{}); defer engine.freeValue(value);
        try std.testing.expectEqual(expected, try number(engine, value));
    }
    const shared_count = try engine.eval("sharedLoads", "shared-graph-count.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(shared_count);
    try std.testing.expectEqual(@as(i32, 1), try number(engine, shared_count));
}
test "private loader foreign pointer rejects without dereferencing controlled address" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine, .bad_return = true }; fixture.install();
    const graph = try fixture.graph();
    try std.testing.expectError(error.JavaScriptException, compile(engine, graph, "import './dep.ts';", root_name, c.pi_js_undefined()));
    var stats: c.JSPiModuleGraphStats = undefined;
    try std.testing.expect(c.JS_PiGetPrivateModuleGraphStats(engine.context, graph, &stats) == 0);
    try std.testing.expectEqual(@as(u64, 1), stats.created);
    try std.testing.expectEqual(@as(u64, 1), stats.quarantined);
}
test "private failed link preserves unrelated earlier compiled definition" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install(); const graph = try fixture.graph();
    const good = try compile(engine, graph, "export const value=7;", "C:/private-module-graph/good.ts", c.pi_js_undefined()); defer engine.freeValue(good);
    const bad = try compile(engine, graph, "import {missing} from './dep.ts';export const value=missing;", root_name, c.pi_js_undefined()); defer engine.freeValue(bad);
    try std.testing.expectError(error.JavaScriptException, evaluate(engine, bad));
    const ns = try evaluate(engine, good); defer engine.freeValue(ns);
    const value = try js.get(engine, ns, "value"); defer engine.freeValue(value);
    try std.testing.expectEqual(@as(i32, 7), try number(engine, value));
    var stats: c.JSPiModuleGraphStats = undefined;
    try std.testing.expect(c.JS_PiGetPrivateModuleGraphStats(engine.context, graph, &stats) == 0);
    try std.testing.expectEqual(@as(u64, 3), stats.created);
    try std.testing.expectEqual(@as(u64, 2), stats.quarantined);
}
test "private evaluated failure keeps escaped nested import meta closure alive" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install();
    const setup = try engine.eval("globalThis.rawMarker={raw:true}", "escaped-setup.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(setup);
    const compiled = try compile(engine, try fixture.graph(), "globalThis.escaped=()=>import.meta.marker;throw rawMarker;", root_name, c.pi_js_undefined()); defer engine.freeValue(compiled);
    try marker(engine, compiled, 99);
    try std.testing.expectError(error.JavaScriptException, evaluate(engine, compiled));
    c.JS_RunGC(engine.runtime);
    const value = try engine.eval("escaped()", "escaped-use.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(value);
    try std.testing.expectEqual(@as(i32, 99), try number(engine, value));
}
test "private static indirect cycle resolves current graph before old physical modules" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine, .dep_override = "import {version} from './root.ts';export function peek(){return version}" }; fixture.install();
    for ([_][:0]const u8{
        "import {peek} from './dep.ts';export const version=1;export function read(){return peek()}",
        "import {peek} from './dep.ts';export const version=2;export function read(){return peek()}",
    }, [_]i32{ 1, 2 }) |source, expected| {
        const compiled = try compile(engine, try fixture.graph(), source, root_name, c.pi_js_undefined()); defer engine.freeValue(compiled);
        const ns = try evaluate(engine, compiled); defer engine.freeValue(ns);
        try std.testing.expectEqual(expected, try read(engine, ns));
    }
}
test "private parallel dynamic top level await evaluates dependency once" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine, .dep_override = "globalThis.tlaLoads=(globalThis.tlaLoads??0)+1;await Promise.resolve();export const version=tlaLoads;" }; fixture.install();
    const compiled = try compile(engine, try fixture.graph(), "export async function read(){const dep=await import('./dep.ts');return dep.version}", root_name, c.pi_js_undefined()); defer engine.freeValue(compiled);
    const ns = try evaluate(engine, compiled); defer engine.freeValue(ns);
    const p1 = try js.invoke(engine, ns, "read", &.{}); defer engine.freeValue(p1);
    const p2 = try js.invoke(engine, ns, "read", &.{}); defer engine.freeValue(p2);
    const r1 = try engine.awaitValue(p1); defer engine.freeValue(r1);
    const r2 = try engine.awaitValue(p2); defer engine.freeValue(r2);
    try std.testing.expectEqual(@as(i32, 1), try number(engine, r1));
    try std.testing.expectEqual(@as(i32, 1), try number(engine, r2));
}
test "private attribute capture preserves original guest getter throw before selector" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install();
    const attrs = try engine.eval("globalThis.attrsReason={raw:true};({get flavor(){throw attrsReason}})", "attrs-throw.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(attrs);
    try std.testing.expectError(error.JavaScriptException, compile(engine, try fixture.graph(), "export const value=1;", root_name, attrs));
    const reason = engine.captured_exception orelse return error.MissingOriginalReason;
    const original = try engine.eval("attrsReason", "attrs-original.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, original));
    try std.testing.expectEqual(@as(usize, 0), fixture.selections);
}
test "private selector native allocation exact identity survives negative and success with pending reason" {
    for ([_]bool{ false, true }) |pending_success| {
        const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
        var fixture: Fixture = .{ .engine = engine, .native_failure = true, .native_pending_success = pending_success }; fixture.install();
        defer if (fixture.native_original) |value| engine.freeValue(value);
        try std.testing.expectError(error.JavaScriptException, compile(engine, try fixture.graph(), "import './dep.ts';", root_name, c.pi_js_undefined()));
        const reason = engine.captured_exception orelse return error.MissingNativeReason;
        try std.testing.expect(c.pi_js_native_allocation_error_generation(reason) != 0);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, fixture.native_original.?));
    }
}
test "shared bytecode serialization stays byte identical and private definitions reject" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install();
    const legacy = try engine.eval("export const value=7;", root_name, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY); defer engine.freeValue(legacy);
    var before_len: usize = 0; const before = c.JS_WriteObject(engine.context, &before_len, legacy, c.JS_WRITE_OBJ_BYTECODE);
    if (before == null) return js.capture(engine); defer c.js_free(engine.context, before);
    const private = try compile(engine, try fixture.graph(), "export const value=9;", root_name, c.pi_js_undefined()); defer engine.freeValue(private);
    var rejected_len: usize = 0; const rejected = c.JS_WriteObject(engine.context, &rejected_len, private, c.JS_WRITE_OBJ_BYTECODE);
    try std.testing.expect(rejected == null);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsError(reason));
    var after_len: usize = 0; const after = c.JS_WriteObject(engine.context, &after_len, legacy, c.JS_WRITE_OBJ_BYTECODE);
    if (after == null) return js.capture(engine); defer c.js_free(engine.context, after);
    try std.testing.expectEqualSlices(u8, before[0..before_len], after[0..after_len]);
    const restored = try engine.checked(c.JS_ReadObject(engine.context, before, before_len, c.JS_READ_OBJ_BYTECODE)); defer engine.freeValue(restored);
    const ns = try evaluate(engine, restored); defer engine.freeValue(ns);
    const value = try js.get(engine, ns, "value"); defer engine.freeValue(value);
    try std.testing.expectEqual(@as(i32, 7), try number(engine, value));
}
test "private pending dynamic job cancels through actual context runtime teardown" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var fixture: Fixture = .{ .engine = engine }; fixture.install();
    const compiled = try compile(engine, try fixture.graph(), "export async function read(){return (await import('./dep.ts')).version}", root_name, c.pi_js_undefined()); defer engine.freeValue(compiled);
    const ns = try evaluate(engine, compiled); defer engine.freeValue(ns);
    const pending = try js.invoke(engine, ns, "read", &.{}); defer engine.freeValue(pending);
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    // Engine frees the queue/context; the strong origin function must retire
    // with job argv on cancellation, not leave a stale ModuleDef pointer.
}
test "private foreign context capability rejects before dereferencing graph fields" {
    const first = try em.Engine.init(std.testing.allocator, .{}); defer first.deinit();
    const second = try em.Engine.init(std.testing.allocator, .{}); defer second.deinit();
    var fixture: Fixture = .{ .engine = first }; fixture.install();
    const graph = try fixture.graph();
    const source = "export const value=1;";
    const result = c.JS_PiCompilePrivateModule(second.context, graph, source.ptr, source.len, root_name, c.pi_js_undefined());
    try std.testing.expect(c.JS_IsException(result));
    const reason = c.JS_GetException(second.context); defer second.freeValue(reason);
    try std.testing.expect(c.JS_IsError(reason));
    var stats: c.JSPiModuleGraphStats = undefined;
    try std.testing.expect(c.JS_PiGetPrivateModuleGraphStats(first.context, graph, &stats) == 0);
    try std.testing.expectEqual(@as(u64, 0), stats.created);
}
