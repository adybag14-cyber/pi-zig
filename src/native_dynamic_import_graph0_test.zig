//! Prepared raw C ABI controls. SDK/Graph2 integration and allocation policy
//! require separate controls; these declarations have not been executed.
const std = @import("std");
const em = @import("extensions/engine.zig");
const Scope = @import("extensions/native_models_stream_scope.zig").Scope;
const c = em.c;

fn importGraph0(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    if (argc != 2) return c.JS_ThrowTypeError(context, "expected basename and specifier");
    return c.JS_PiDynamicImportGraph0(context, args[0], args[1]);
}
fn eval(engine: *em.Engine, source: []const u8) !c.JSValue {
    return engine.eval(source, "C:/physical/foreign-caller.js", c.JS_EVAL_TYPE_GLOBAL);
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try eval(engine, source);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}
fn pump(engine: *em.Engine) !void {
    var jobs: usize = 0;
    while (c.JS_IsJobPending(engine.runtime)) {
        if (jobs == 64) return error.DynamicImportJobBudget;
        var context: ?*c.JSContext = null;
        const status = c.JS_ExecutePendingJob(engine.runtime, &context);
        const owner = context orelse engine.context;
        if (status < 0 or c.JS_HasException(owner)) {
            const reason = c.JS_GetException(owner);
            defer c.JS_FreeValue(owner, reason);
            return error.UnexpectedDynamicImportJobException;
        }
        try std.testing.expect(status > 0);
        jobs += 1;
    }
}
fn lazyModule(engine: *em.Engine, scope: *Scope) !void {
    const exports = try scope.own(try eval(engine,
        "globalThis.events=[]; globalThis.moduleInit=0;" ++
        "({get value(){moduleInit++;events.push('init');return 41}})"));
    try engine.registerValueModule("C:/physical/lazy.mjs", exports);
    try engine.bindFunction("queuedImport", importGraph0, 2);
}

test "queued Graph0 import public then read precedes lazy initialization and survives GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try lazyModule(engine, &scope);
    const ignored = try scope.own(try eval(engine,
        "globalThis.originalThen=Promise.prototype.then;" ++
        "Object.defineProperty(Promise.prototype,'then',{configurable:true,get(){events.push('then');return originalThen}});" ++
        "globalThis.rawImport=queuedImport('C:/physical/loader.js','C:/physical/lazy.mjs');" ++
        "globalThis.selected=rawImport.then(ns=>ns.value);" ++
        "Object.defineProperty(Promise.prototype,'then',{configurable:true,writable:true,value:originalThen});"));
    _ = ignored;
    try check(engine, "moduleInit===0 && events.join(',')==='then' && queuedImport.length===2 && rawImport!==selected");
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    c.JS_RunGC(engine.runtime);
    try pump(engine);
    try check(engine, "moduleInit===1 && events.join(',')==='then,init'");
    const selected = try scope.global("selected");
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, selected));
    const value = try scope.own(c.JS_PromiseResult(engine.context, selected));
    var number: i32 = undefined;
    if (c.JS_ToInt32(engine.context, &number, value) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 41), number);
}

test "queued Graph0 import throwing public then getter leaves genuine import queued" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try lazyModule(engine, &scope);
    _ = try scope.own(try eval(engine,
        "globalThis.originalThen=Promise.prototype.then;globalThis.thenReason={};globalThis.observed=null;" ++
        "Object.defineProperty(Promise.prototype,'then',{configurable:true,get(){events.push('then');throw thenReason}});" ++
        "globalThis.rawImport=queuedImport('C:/physical/loader.js','C:/physical/lazy.mjs');" ++
        "try{rawImport.then(ns=>ns.value)}catch(e){observed=e}" ++
        "Object.defineProperty(Promise.prototype,'then',{configurable:true,writable:true,value:originalThen});"));
    try check(engine, "moduleInit===0 && observed===thenReason && events.join(',')==='then'");
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    c.JS_RunGC(engine.runtime);
    try pump(engine);
    const raw = try scope.global("rawImport");
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, raw));
    try check(engine, "moduleInit===1 && events.join(',')==='then,init'");
}

const NormalizeProbe = struct { calls: usize = 0, exact_base: bool = true, exact_specifier: bool = true };
fn normalize(probe_data: ?*anyopaque, allocator: std.mem.Allocator, base: []const u8, specifier: []const u8) ![]u8 {
    const probe: *NormalizeProbe = @ptrCast(@alignCast(probe_data.?));
    probe.calls += 1;
    probe.exact_base = probe.exact_base and std.mem.eql(u8, base, "C:/captured/loader.js");
    probe.exact_specifier = probe.exact_specifier and std.mem.eql(u8, specifier, "./dep.mjs");
    return allocator.dupe(u8, "C:/captured/dep.mjs");
}
fn load(_: ?*anyopaque, allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    if (!std.mem.eql(u8, name, "C:/captured/dep.mjs")) return error.UnexpectedImportName;
    return allocator.dupe(u8, "export const value=37;");
}

test "queued Graph0 import uses explicit captured base with absent and foreign ambient frames" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var probe: NormalizeProbe = .{};
    engine.setSourceLoader(.{ .context = &probe, .normalize = normalize, .load = load });
    try engine.bindFunction("queuedImport", importGraph0, 2);
    // Raw ABI call has no script frame. Release input owners immediately: the
    // ordinary job must own its duplicates independently of the caller.
    const raw = queued: {
        const base = try engine.checked(c.JS_NewString(engine.context, "C:/captured/loader.js"));
        defer engine.freeValue(base);
        const specifier = try engine.checked(c.JS_NewString(engine.context, "./dep.mjs"));
        defer engine.freeValue(specifier);
        break :queued c.JS_PiDynamicImportGraph0(engine.context, base, specifier);
    };
    defer engine.freeValue(raw);
    try std.testing.expect(!c.JS_IsException(raw));
    const foreign = try scope.own(try eval(engine, "queuedImport('C:/captured/loader.js','./dep.mjs')"));
    try std.testing.expectEqual(@as(usize, 0), probe.calls);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, raw, foreign));
    c.JS_RunGC(engine.runtime);
    try pump(engine);
    try std.testing.expect(probe.calls >= 2);
    try std.testing.expect(probe.exact_base and probe.exact_specifier);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, raw));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, foreign));
    const first = try scope.own(c.JS_PromiseResult(engine.context, raw));
    const second = try scope.own(c.JS_PromiseResult(engine.context, foreign));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, second));
}

test "queued Graph0 import concurrent TLA and guest import share namespace without extra completion" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try engine.bindFunction("queuedImport", importGraph0, 2);
    try engine.registerModule("C:/physical/tla.mjs", "globalThis.evaluations++;await Promise.resolve();export const value=19;");
    _ = try scope.own(try eval(engine,
        "globalThis.evaluations=0;" ++
        "globalThis.first=queuedImport('C:/physical/loader.js','C:/physical/tla.mjs');" ++
        "globalThis.second=queuedImport('C:/physical/loader.js','C:/physical/tla.mjs');" ++
        "globalThis.guest=import('C:/physical/tla.mjs');"));
    try check(engine, "evaluations===0 && first!==second && second!==guest && first!==guest");
    c.JS_RunGC(engine.runtime);
    try pump(engine);
    const first = try scope.global("first");
    const second = try scope.global("second");
    const guest = try scope.global("guest");
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, first));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, second));
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, guest));
    const a = try scope.own(c.JS_PromiseResult(engine.context, first));
    const b = try scope.own(c.JS_PromiseResult(engine.context, second));
    const g = try scope.own(c.JS_PromiseResult(engine.context, guest));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, g));
    try check(engine, "evaluations===1");
}

test "queued Graph0 import ordinary coercion and module failure preserve raw rejection identity" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try engine.bindFunction("queuedImport", importGraph0, 2);
    try engine.registerModule("C:/physical/rejected.mjs", "globalThis.evaluations++;throw globalThis.moduleReason;");
    _ = try scope.own(try eval(engine,
        "globalThis.evaluations=0;globalThis.moduleReason={};globalThis.coercionReason={};globalThis.coercions=0;" ++
        "globalThis.coerced=queuedImport('C:/physical/loader.js',{toString(){coercions++;throw coercionReason}});" ++
        "globalThis.first=queuedImport('C:/physical/loader.js','C:/physical/rejected.mjs');" ++
        "globalThis.second=queuedImport('C:/physical/loader.js','C:/physical/rejected.mjs');"));
    const coerced = try scope.global("coerced");
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, coerced));
    const coercion_reason = try scope.own(c.JS_PromiseResult(engine.context, coerced));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, coercion_reason, try scope.global("coercionReason")));
    try check(engine, "coercions===1 && evaluations===0");
    try pump(engine);
    const first = try scope.global("first");
    const second = try scope.global("second");
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, first));
    try std.testing.expectEqual(c.JS_PROMISE_REJECTED, c.JS_PromiseState(engine.context, second));
    const a = try scope.own(c.JS_PromiseResult(engine.context, first));
    const b = try scope.own(c.JS_PromiseResult(engine.context, second));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, b));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, a, try scope.global("moduleReason")));
    try check(engine, "evaluations===1");
    try std.testing.expect(!c.JS_HasException(engine.context));
}

test "queued Graph0 import primitive basename admission and host owned queue teardown" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try lazyModule(engine, &scope);
    _ = try scope.own(try eval(engine,
        "globalThis.baseCoercions=0;globalThis.badBaseCaught=false;" ++
        "try{queuedImport({toString(){baseCoercions++;return 'C:/physical/loader.js'}},'C:/physical/lazy.mjs')}catch(e){badBaseCaught=e instanceof TypeError}"));
    try check(engine, "badBaseCaught && baseCoercions===0 && moduleInit===0");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    _ = try scope.own(try eval(engine, "queuedImport('C:/physical/loader.js','C:/physical/lazy.mjs')"));
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    c.JS_RunGC(engine.runtime);
    try check(engine, "moduleInit===0");
    // Normal host-owned teardown cancels the queued job. No early release of
    // its raw context pointer and no independent context-pin claim is made.
}

const ContextProbe = struct {
    foreign: *c.JSContext,
    marker_a: c.JSValue, // Borrowed only from the queued job after caller release.
    before: usize = 0,
    after: usize = 0,
    exact: bool = true,
};
fn contextHook(context: ?*c.JSContext, before: bool, marker: c.JSValue, hook_data: ?*anyopaque) callconv(.c) void {
    const probe: *ContextProbe = @ptrCast(@alignCast(hook_data.?));
    probe.exact = probe.exact and context == probe.foreign and c.JS_IsStrictEqual(context, marker, probe.marker_a);
    if (before) probe.before += 1 else probe.after += 1;
}
fn realmLoader(context: ?*c.JSContext, name: [*c]const u8, _: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
    if (!std.mem.eql(u8, std.mem.span(name), "C:/realm/dep.mjs")) {
        _ = c.JS_ThrowReferenceError(context, "unexpected realm module");
        return null;
    }
    const source = "globalThis.executions++;export const value=globalThis.realmMarker;";
    const compiled = c.JS_Eval(context, source.ptr, source.len, name, c.JS_EVAL_TYPE_MODULE | c.JS_EVAL_FLAG_COMPILE_ONLY);
    if (c.JS_IsException(compiled)) return null;
    defer c.JS_FreeValue(context, compiled);
    return c.pi_js_module(compiled);
}

test "queued Graph0 import captures distinct VM context and enqueue execution marker through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const foreign = c.JS_NewContext(engine.runtime) orelse return error.OutOfMemory;
    // Both host-owned contexts stay alive through all job and value cleanup.
    defer c.JS_FreeContext(foreign);
    c.JS_SetModuleLoaderFunc(engine.runtime, null, realmLoader, null);
    const primary_setup = try eval(engine, "globalThis.realmMarker=11;globalThis.executions=0;");
    defer engine.freeValue(primary_setup);
    const foreign_source = "globalThis.realmMarker=77;globalThis.executions=0;";
    const foreign_setup = c.JS_Eval(foreign, foreign_source.ptr, foreign_source.len, "C:/realm/setup.js", c.JS_EVAL_TYPE_GLOBAL);
    defer c.JS_FreeValue(foreign, foreign_setup);
    try std.testing.expect(!c.JS_IsException(foreign_setup));
    const marker_a = c.JS_NewObject(foreign);
    if (c.JS_IsException(marker_a)) return error.OutOfMemory;
    var marker_a_owned = true;
    defer if (marker_a_owned) c.JS_FreeValue(foreign, marker_a);
    var probe: ContextProbe = .{ .foreign = foreign, .marker_a = marker_a };
    c.JS_SetExecutionContextHook(engine.runtime, contextHook, &probe);
    defer c.JS_SetExecutionContextHook(engine.runtime, null, null);
    c.JS_SetExecutionContext(engine.runtime, marker_a);
    defer c.JS_SetExecutionContext(engine.runtime, c.pi_js_undefined());
    const raw = queued: {
        const base = c.JS_NewString(foreign, "C:/realm/loader.js");
        if (c.JS_IsException(base)) return error.OutOfMemory;
        defer c.JS_FreeValue(foreign, base);
        const specifier = c.JS_NewString(foreign, "C:/realm/dep.mjs");
        if (c.JS_IsException(specifier)) return error.OutOfMemory;
        defer c.JS_FreeValue(foreign, specifier);
        break :queued c.JS_PiDynamicImportGraph0(foreign, base, specifier);
    };
    defer c.JS_FreeValue(foreign, raw);
    try std.testing.expect(!c.JS_IsException(raw));
    c.JS_FreeValue(foreign, marker_a);
    marker_a_owned = false;
    const marker_b = c.JS_NewObject(engine.context);
    if (c.JS_IsException(marker_b)) return error.OutOfMemory;
    c.JS_SetExecutionContext(engine.runtime, marker_b);
    engine.freeValue(marker_b);
    // marker_a has no host/ambient owner. The queued entry must retain it.
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(c.JS_GetPendingJobContext(engine.runtime) == foreign);
    var job_context: ?*c.JSContext = null;
    const status = c.JS_ExecutePendingJob(engine.runtime, &job_context);
    try std.testing.expect(status > 0 and job_context == foreign);
    try std.testing.expect(!c.JS_HasException(foreign));
    try std.testing.expectEqual(@as(usize, 1), probe.before);
    try std.testing.expectEqual(@as(usize, 1), probe.after);
    try std.testing.expect(probe.exact);
    // The core hook supplies captured metadata; ambient marker activation is
    // host policy. Only this first import job is required to carry marker_a.
    c.JS_SetExecutionContextHook(engine.runtime, null, null);
    c.JS_SetExecutionContext(engine.runtime, c.pi_js_undefined());
    try pump(engine);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(foreign, raw));
    const namespace = c.JS_PromiseResult(foreign, raw);
    defer c.JS_FreeValue(foreign, namespace);
    const value = c.JS_GetPropertyStr(foreign, namespace, "value");
    defer c.JS_FreeValue(foreign, value);
    var number: i32 = undefined;
    if (c.JS_ToInt32(foreign, &number, value) < 0) return error.JavaScriptException;
    try std.testing.expectEqual(@as(i32, 77), number);
    const assertion = "executions===1 && realmMarker===77";
    const foreign_check = c.JS_Eval(foreign, assertion.ptr, assertion.len, "C:/realm/check.js", c.JS_EVAL_TYPE_GLOBAL);
    defer c.JS_FreeValue(foreign, foreign_check);
    try std.testing.expect(!c.JS_IsException(foreign_check) and c.JS_ToBool(foreign, foreign_check) == 1);
    try check(engine, "executions===0 && realmMarker===11");
}
