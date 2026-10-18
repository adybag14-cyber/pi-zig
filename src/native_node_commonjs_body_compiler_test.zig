//! Real linked-C API controls, prepared without a Node/bootstrap facade.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const compiler = @import("extensions/native_node_commonjs_body_compiler.zig");
const Owner = struct {
    first: c.JSValue,
    fn init(self: *Owner, engine: *em.Engine) void {
        self.* = .{ .first = c.pi_js_undefined() };
        c.JS_SetNativeErrorStackHook(engine.runtime, capture, self);
    }
    fn deinit(self: *Owner, engine: *em.Engine) void {
        c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
        engine.freeValue(self.first);
    }
    fn capture(context: ?*c.JSContext, reason: c.JSValue, phase: c_int, _: c.JSValue, _: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
        const self: *Owner = @ptrCast(@alignCast(data.?));
        if (phase == c.JS_ERROR_STACK_CAPTURE and c.JS_IsUndefined(self.first)) self.first = c.JS_DupValue(context, reason);
        return 0; // Real native capture only: no guest formatting or reentry.
    }
};
fn text(engine: *em.Engine, value: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
}
fn compile(engine: *em.Engine, source: []const u8) !compiler.Completion {
    const body = try text(engine, source); defer engine.freeValue(body);
    const filename = try text(engine, "C:/compiler/provider.cjs"); defer engine.freeValue(filename);
    return compiler.compile(engine, body, filename);
}
fn publish(engine: *em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0) return error.ControlPublicationFailed;
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "C:/compiler/provider-observer.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}

test "native CJS raw provider returns actual ordinary function without body execution and preserves raw Promise completion" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const completion = try compile(engine, "globalThis.providerRuns=(globalThis.providerRuns||0)+1;return exports"); defer completion.deinit(engine);
    if (completion != .function) return error.ExpectedActualCompiledFunction;
    const function = completion.function;
    try std.testing.expect(c.JS_IsFunction(engine.context, function));
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    try std.testing.expect(c.JS_IsConstructor(engine.context, function));
    try publish(engine, "actualBody", function);
    try check(engine, "typeof providerRuns==='undefined'&&actualBody.length===5&&actualBody.constructor===Function");
    const promise = try engine.eval("Promise.resolve(3)", "C:/compiler/provider-promise.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(promise);
    var args = [_]c.JSValue{promise};
    const result = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), args.len, &args)); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, promise));
    try check(engine, "providerRuns===1");
}

test "native CJS raw provider distinguishes actual syntax categories from actual detached module completion" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const ordinary = try compile(engine, "void /(/;"); defer ordinary.deinit(engine);
    if (ordinary != .syntax) return error.ExpectedActualSyntaxCompletion;
    try std.testing.expectEqual(compiler.SyntaxCategory.ordinary, ordinary.syntax.category);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, ordinary.syntax.reason, owner.first));
    const direct = try compile(engine, "export {; definitely invalid module tail"); defer direct.deinit(engine);
    if (direct != .syntax) return error.ExpectedActualSyntaxCompletion;
    try std.testing.expectEqual(compiler.SyntaxCategory.direct_module, direct.syntax.category);
    const source = try text(engine, "import 'fixture:absent';if(false)await 0;globalThis.probeRan=1"); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/provider-probe.mjs"); defer engine.freeValue(filename);
    const parsed = try compiler.probe(engine, source, filename); defer parsed.deinit(engine);
    if (parsed != .parsed) return error.ExpectedActualModuleSyntaxCompletion;
    try std.testing.expectEqual(compiler.static_import_export | compiler.top_level_await, parsed.parsed);
    try check(engine, "typeof probeRan==='undefined'");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}

test "native CJS raw provider preserves actual pending identity and does not consult stale captured reason" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const old = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(old);
    engine.captured_exception = c.JS_DupValue(engine.context, old);
    const ordinary = try compile(engine, "void /(/;"); defer ordinary.deinit(engine);
    if (ordinary != .syntax) return error.ExpectedActualSyntaxCompletion;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, old));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, ordinary.syntax.reason, old));
    const incoming = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(incoming);
    const content = try text(engine, "return 4"); defer engine.freeValue(content);
    const filename = try text(engine, "C:/compiler/pending.cjs"); defer engine.freeValue(filename);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, incoming));
    try std.testing.expectError(error.JavaScriptException, compiler.compile(engine, content, filename));
    const actual = engine.captured_exception orelse return error.MissingActualPendingReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, incoming));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
}

test "native CJS raw provider private callable is ordinary nonconstructor and primitive input failure does not coerce" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const callable = try compiler.createBodyCompiler(engine); defer engine.freeValue(callable);
    try publish(engine, "compileBody", callable);
    try check(engine, "compileBody.name==='compileBody'&&compileBody.length===2&&!Object.hasOwn(compileBody,'prototype')&&compileBody('return 9','C:/compiler/private.cjs')()===9");
    try std.testing.expect(!c.JS_IsAsyncFunction(callable));
    try std.testing.expect(!c.JS_IsConstructor(engine.context, callable));
    try check(engine, "globalThis.coerced=0;let reason;try{compileBody({toString(){coerced++;return 'return 8'}},'C:/compiler/input.cjs')}catch(e){reason=e}coerced===0&&reason instanceof TypeError");
}

test "native CJS raw provider factory preserves incoming reason before real one-byte VM quota and balances suppression" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const incoming = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(incoming);
    const suppressed = engine.native_exception_diagnostics_suppressed;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, incoming));
    c.JS_SetMemoryLimit(engine.runtime, 1);
    defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    const attempted = compiler.createBodyCompiler(engine);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    if (attempted) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedActualPendingFactoryFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
    try std.testing.expectEqual(suppressed, engine.native_exception_diagnostics_suppressed);
    const actual = engine.captured_exception orelse return error.MissingActualFactoryPendingReason;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, incoming));
    try std.testing.expect(!c.JS_IsUncatchableError(actual));
    try std.testing.expect(c.JS_IsUndefined(owner.first));
}
