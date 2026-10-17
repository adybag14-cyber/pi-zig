//! Prepared direct real-VM controls, not a Node Module/bootstrap replacement.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
extern fn pi_test_cjs_compiler_allocations(mode: c_int) c_int;
extern fn pi_test_cjs_regexp_controls(mode: c_int) c_int;
extern fn pi_test_cjs_lexer_poll(mode: c_int) c_int;
extern fn pi_test_cjs_semantic_work() c_int;
const Owner = struct {
    error_value: c.JSValue,
    replacement: c.JSValue,
    pending_once: bool = false,
    calls: usize = 0,
    fn init(self: *Owner, engine: *em.Engine) void {
        self.* = .{ .error_value = c.pi_js_undefined(), .replacement = c.pi_js_undefined() };
        c.JS_SetNativeErrorStackHook(engine.runtime, capture, self);
    }
    fn deinit(self: *Owner, engine: *em.Engine) void {
        c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
        engine.freeValue(self.error_value); engine.freeValue(self.replacement);
    }
    fn capture(context: ?*c.JSContext, reason: c.JSValue, phase: c_int, _: c.JSValue, _: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
        const self: *Owner = @ptrCast(@alignCast(data.?)); self.calls += 1;
        if (self.pending_once) {
            self.pending_once = false;
            _ = c.JS_Throw(context, c.JS_DupValue(context, self.replacement));
            return 0; // Real native success plus actual pending reason.
        }
        if (phase == c.JS_ERROR_STACK_CAPTURE and c.JS_IsUndefined(self.error_value)) self.error_value = c.JS_DupValue(context, reason);
        return 0; // Pure native capture, no guest callbacks or formatting.
    }
};
fn text(engine: *em.Engine, value: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len));
}
fn compile(engine: *em.Engine, body: []const u8) !c.JSValue {
    const source = try text(engine, body); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/body.cjs"); defer engine.freeValue(filename);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ESM_PARSE_REQUIRED;
    const result = c.JS_PiCompileCJSFunction(engine.context, source, filename, &category);
    errdefer engine.freeValue(result);
    try std.testing.expect(!c.JS_IsException(result));
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    return result;
}
fn rejected(engine: *em.Engine, body: []const u8, expected: c.JSPiCJSParseCategory) !c.JSValue {
    const source = try text(engine, body); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/bad.cjs"); defer engine.freeValue(filename);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_NO_SYNTAX_CATEGORY;
    const result = c.JS_PiCompileCJSFunction(engine.context, source, filename, &category); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); errdefer engine.freeValue(reason);
    try std.testing.expectEqual(expected, category);
    return reason;
}
fn probe(engine: *em.Engine, body: []const u8, expected_status: c_int, expected_flags: c_uint) !?c.JSValue {
    const source = try text(engine, body); defer engine.freeValue(source);
    const filename = try text(engine, "fixture:syntax-probe"); defer engine.freeValue(filename);
    var flags: c_uint = 99;
    var diagnostic: c.JSPiModuleParseDiagnostic = c.JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC;
    const status = c.JS_PiParseModuleSyntax(engine.context, source, filename, &flags, &diagnostic);
    try std.testing.expectEqual(expected_status, status);
    try std.testing.expectEqual(expected_flags, flags);
    if (status == 0) {
        try std.testing.expect(!c.JS_HasException(engine.context));
        try std.testing.expectEqual(@as(c.JSPiModuleParseDiagnostic, c.JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC), diagnostic);
        return null;
    }
    try std.testing.expect(c.JS_HasException(engine.context));
    const reason = c.JS_GetException(engine.context); errdefer engine.freeValue(reason);
    try std.testing.expectEqual(@as(c.JSPiModuleParseDiagnostic, if (status == 1) c.JS_PI_MODULE_ORDINARY_SYNTAX else c.JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC), diagnostic);
    return reason;
}
fn call(engine: *em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !c.JSValue {
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "C:/compiler/observer.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}
fn publish(engine: *em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name.ptr, c.JS_DupValue(engine.context, value)) < 0) return error.ControlPublicationFailed;
}
test "native CJS compiler compiles actual fixed-five ordinary function before any body or jobs" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try compile(engine, "globalThis.bodyRuns=(globalThis.bodyRuns||0)+1;return [exports,require,module,__filename,__dirname,arguments.length]"); defer engine.freeValue(function);
    try std.testing.expect(c.JS_IsFunction(engine.context, function));
    try std.testing.expect(c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    try publish(engine, "bodyFunction", function);
    try check(engine, "globalThis.bodyRuns===undefined&&bodyFunction.length===5&&bodyFunction.name===''&&bodyFunction.constructor===Function");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    const args = [_]c.JSValue{ c.JS_NewInt32(engine.context, 1), c.JS_NewInt32(engine.context, 2), c.JS_NewInt32(engine.context, 3), c.JS_NewInt32(engine.context, 4), c.JS_NewInt32(engine.context, 5) };
    const result = try call(engine, function, c.pi_js_undefined(), &args); defer engine.freeValue(result);
    try publish(engine, "bodyArguments", result);
    try check(engine, "bodyRuns===1&&JSON.stringify(bodyArguments)==='[1,2,3,4,5,5]'");
}
test "native CJS compiler rejects closing-brace outer-program escape through actual EOF function grammar" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const reason = try rejected(engine, "});globalThis.escaped=1;(function(){", c.JS_PI_CJS_ESM_PARSE_REQUIRED); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.error_value));
    try check(engine, "globalThis.escaped===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "native CJS compiler supports nested classes templates regexp direct eval and mapped arguments in actual VM" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try compile(engine, "class Local{#x=7;value(){return this.#x}};function nested(){return `${new Local().value()}`};exports=9;return [nested(),/a+/u.test('aaa'),arguments[0],eval('exports'),new.target]"); defer engine.freeValue(function);
    const result = try call(engine, function, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 1)}); defer engine.freeValue(result);
    try publish(engine, "grammarResult", result);
    try check(engine, "grammarResult[0]==='7'&&grammarResult[1]===true&&grammarResult[2]===9&&grammarResult[3]===9&&grammarResult[4]===undefined");
}
test "native CJS compiler actual strict directive controls this and arguments rather than host caller mode" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const sloppy = try compile(engine, "exports=8;return [this,arguments[0]]"); defer engine.freeValue(sloppy);
    const strict = try compile(engine, "'use strict';exports=8;return [this,arguments[0]]"); defer engine.freeValue(strict);
    const a = try call(engine, sloppy, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 1)}); defer engine.freeValue(a);
    const b = try call(engine, strict, c.pi_js_undefined(), &.{c.JS_NewInt32(engine.context, 1)}); defer engine.freeValue(b);
    try publish(engine, "sloppyResult", a); try publish(engine, "strictResult", b);
    try check(engine, "sloppyResult[0]===globalThis&&sloppyResult[1]===8&&strictResult[0]===undefined&&strictResult[1]===1");
}
test "native CJS compiler returns raw Promise and thrown input without async adoption wrapper" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try compile(engine, "return exports"); defer engine.freeValue(function);
    const throwing = try compile(engine, "throw exports"); defer engine.freeValue(throwing);
    const promise = try engine.eval("Promise.resolve(3)", "C:/compiler/promise.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(promise);
    const returned = try call(engine, function, c.pi_js_undefined(), &.{promise}); defer engine.freeValue(returned);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, promise, returned));
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    var args = [_]c.JSValue{reason};
    const failed = c.JS_Call(engine.context, throwing, c.pi_js_undefined(), args.len, &args); defer engine.freeValue(failed);
    try std.testing.expect(c.JS_IsException(failed));
    const caught = c.JS_GetException(engine.context); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, caught));
}
test "native CJS compiler actual grammar event distinguishes direct module retry from full-probe-required collision" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const direct = try rejected(engine, "export {};return )", c.JS_PI_CJS_DIRECT_MODULE_SYNTAX); defer engine.freeValue(direct);
    const import_only = try rejected(engine, "import x from 'absent';return )", c.JS_PI_CJS_DIRECT_MODULE_SYNTAX); defer engine.freeValue(import_only);
    const meta = try rejected(engine, "import.meta;return )", c.JS_PI_CJS_DIRECT_MODULE_SYNTAX); defer engine.freeValue(meta);
    const collision = try rejected(engine, "const module=1;return )", c.JS_PI_CJS_ESM_PARSE_REQUIRED); defer engine.freeValue(collision);
    const invalid_probe = (try probe(engine, "const module=1;return )", 1, 99)).?; defer engine.freeValue(invalid_probe);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, invalid_probe, collision));
    // Caller retains the actual original reason while probing; no string policy.
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, collision));
    const original = c.JS_GetException(engine.context); defer engine.freeValue(original);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, collision, original));
}
const LoaderProbe = struct {
    loads: usize = 0,
    checks: usize = 0,
    fn load(_: ?*c.JSContext, _: [*c]const u8, data: ?*anyopaque) callconv(.c) ?*c.JSModuleDef {
        const self: *LoaderProbe = @ptrCast(@alignCast(data.?)); self.loads += 1; return null;
    }
    fn attributes(context: ?*c.JSContext, data: ?*anyopaque, _: c.JSValue) callconv(.c) c_int {
        const self: *LoaderProbe = @ptrCast(@alignCast(data.?)); self.checks += 1;
        _ = c.JS_ThrowTypeError(context, "actual host attribute policy must not run during syntax probe");
        return -1;
    }
};
test "native CJS compiler module probe parses nonexistent imports and unreachable TLA without load evaluation or jobs" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    var loader: LoaderProbe = .{};
    c.JS_SetModuleLoaderFunc(engine.runtime, null, LoaderProbe.load, &loader);
    defer c.JS_SetModuleLoaderFunc(engine.runtime, null, null, null);
    _ = try probe(engine, "import 'fixture:does-not-exist';export{};if(false)await 0;globalThis.probeBody=1", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT | c.JS_PI_MODULE_TOP_LEVEL_AWAIT);
    _ = try probe(engine, "export async function f(){await 0};function g(){return import.meta}", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT | c.JS_PI_MODULE_IMPORT_META);
    try std.testing.expectEqual(@as(usize, 0), loader.loads);
    try check(engine, "globalThis.probeBody===undefined");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
fn nativeInitialize(context: ?*c.JSContext, module: ?*c.JSModuleDef) callconv(.c) c_int {
    return c.JS_SetModuleExport(context, module, "marker", c.JS_NewInt32(context, 2));
}
test "native CJS compiler detached probe never poisons the ordinary same-physical-name module cache" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    _ = try probe(engine, "export const marker=1;globalThis.staleProbeBody=1", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
    _ = try probe(engine, "export const marker=3;globalThis.staleProbeBody=3", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
    c.JS_RunGC(engine.runtime);
    const module = c.JS_NewCModule(engine.context, "fixture:syntax-probe", nativeInitialize) orelse return error.NativeFixtureSetupFailed;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_AddModuleExport(engine.context, module, "marker"));
    const result = try engine.evalModule("import{marker}from'fixture:syntax-probe';globalThis.importedMarker=marker", "C:/compiler/probe-cache-check.mjs"); defer engine.freeValue(result);
    try check(engine, "importedMarker===2&&globalThis.staleProbeBody===undefined");
}
test "native CJS compiler syntax probe checks attribute grammar without invoking runtime host attribute policy" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    var loader: LoaderProbe = .{};
    c.JS_SetModuleLoaderFunc2(engine.runtime, null, null, LoaderProbe.attributes, &loader);
    defer c.JS_SetModuleLoaderFunc(engine.runtime, null, null, null);
    _ = try probe(engine, "import x from'fixture:absent' with{unsupported:'owned'};export{x}", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
    try std.testing.expectEqual(@as(usize, 0), loader.checks);
    try std.testing.expectEqual(@as(usize, 0), loader.loads);
    const bad = (try probe(engine, "import x from'fixture:absent' with{unsupported:1}", 1, 99)).?; defer engine.freeValue(bad);
    try std.testing.expectEqual(@as(usize, 0), loader.checks);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}
test "native CJS compiler module probe runs real semantic undefined-export validation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const reason = (try probe(engine, "export{notDeclared}", 1, 99)).?; defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.error_value));
    _ = try probe(engine, "const actual=1;export{actual}", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
}
test "native CJS compiler actual pending entry reason precedes category flags input validation and native capture" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ESM_PARSE_REQUIRED;
    const result = c.JS_PiCompileCJSFunction(engine.context, c.pi_js_undefined(), c.pi_js_undefined(), &category); defer engine.freeValue(result);
    const caught = c.JS_GetException(engine.context); defer engine.freeValue(caught);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, caught));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    try std.testing.expectEqual(@as(usize, 0), owner.calls);
    var flags: c_uint = 99; var diagnostic: c.JSPiModuleParseDiagnostic = c.JS_PI_MODULE_ORDINARY_SYNTAX;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
    try std.testing.expectEqual(@as(c_int, -1), c.JS_PiParseModuleSyntax(engine.context, c.pi_js_undefined(), c.pi_js_undefined(), &flags, &diagnostic));
    const again = c.JS_GetException(engine.context); defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, again));
    try std.testing.expectEqual(@as(c_uint, 99), flags);
    try std.testing.expectEqual(@as(c.JSPiModuleParseDiagnostic, c.JS_PI_MODULE_NO_SYNTAX_DIAGNOSTIC), diagnostic);
}
test "native CJS compiler success-with-pending capture failure is not labeled an ordinary parser syntax rejection" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    owner.replacement = try engine.checked(c.JS_NewObject(engine.context)); owner.pending_once = true;
    const reason = try rejected(engine, "return )", c.JS_PI_CJS_NO_SYNTAX_CATEGORY); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.replacement));
    try std.testing.expectEqual(@as(usize, 1), owner.calls);
    const healthy = try compile(engine, "return 7"); defer engine.freeValue(healthy);
}
test "native CJS compiler real memory limit failure stays operational and releases state before healthy reuse" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const source = try text(engine, "return 3"); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/oom.cjs"); defer engine.freeValue(filename);
    c.JS_SetMemoryLimit(engine.runtime, 1); defer c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ESM_PARSE_REQUIRED;
    const result = c.JS_PiCompileCJSFunction(engine.context, source, filename, &category); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    c.JS_RunGC(engine.runtime);
    const healthy = try compile(engine, "return 5"); defer engine.freeValue(healthy);
    _ = try probe(engine, "export{}", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
}
fn bridge(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_NO_SYNTAX_CATEGORY;
    return c.JS_PiCompileCJSFunction(context, if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined(), &category);
}
test "native CJS compiler does not inherit strict caller or caller lexical bindings and retains actual global realm through GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try engine.checked(c.JS_NewCFunction(engine.context, bridge, "compilerBridge", 2)); defer engine.freeValue(function);
    try publish(engine, "compilerBridge", function);
    try check(engine, "const lexicalGlobal=7;globalThis.fromStrict=(function(){'use strict';const secret=91;return compilerBridge('return [this,typeof secret,lexicalGlobal]', 'C:/compiler/from-strict.cjs')})();true");
    c.JS_RunGC(engine.runtime);
    try check(engine, "fromStrict()[0]===globalThis&&fromStrict()[1]==='undefined'&&fromStrict()[2]===7");
}
test "native CJS compiler ordinary VM constructor has actual new target rather than outer parser function state" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try compile(engine, "return new.target"); defer engine.freeValue(function);
    const ordinary = try call(engine, function, c.pi_js_undefined(), &.{}); defer engine.freeValue(ordinary);
    try std.testing.expect(c.JS_IsUndefined(ordinary));
    const constructed = try engine.checked(c.JS_CallConstructor(engine.context, function, 0, null)); defer engine.freeValue(constructed);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, function, constructed));
}
fn frames(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 8, c.pi_js_undefined(), null, 0, 0, c.JS_ERROR_STACK_SKIP_FIRST);
}
test "native CJS compiler physical body origin and UTF16 columns precede retained wrapped-source presentation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const capture = try engine.checked(c.JS_NewCFunction(engine.context, frames, "compilerCapture", 0)); defer engine.freeValue(capture);
    try publish(engine, "compilerCapture", capture);
    const body = "'use strict';\nconst astral='😀'; return compilerCapture()";
    const function = try compile(engine, body); defer engine.freeValue(function);
    try publish(engine, "physicalFunction", function);
    const value = try call(engine, function, c.pi_js_undefined(), &.{}); defer engine.freeValue(value);
    try publish(engine, "physicalFrames", value);
    c.JS_RunGC(engine.runtime);
    try check(engine, "physicalFrames[0].getFileName()==='C:/compiler/body.cjs'&&physicalFrames[0].getLineNumber()===2&&physicalFrames[0].getColumnNumber()===27&&physicalFrames[0].getFunction()===undefined&&physicalFrames[0].getThis()===undefined");
    const original = try text(engine, body); defer engine.freeValue(original); try publish(engine, "originalBody", original);
    try check(engine, "physicalFunction.toString()==='function (exports, require, module, __filename, __dirname) {\\n'+originalBody+'\\n}'");
}
test "native CJS compiler primitive input admission avoids coercion and refuses filename NUL without truncation" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const bad = try engine.eval("globalThis.coerced=0;({toString(){coerced++;return 'return 3'}})", "C:/compiler/input.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(bad);
    const filename = try text(engine, "C:/compiler/input.cjs"); defer engine.freeValue(filename);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ESM_PARSE_REQUIRED;
    const result = c.JS_PiCompileCJSFunction(engine.context, bad, filename, &category); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(result)); try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    try check(engine, "coerced===0");
    const source = try text(engine, "return 3"); defer engine.freeValue(source);
    const nul_filename = try text(engine, "C:/compiler/bad\x00suffix.cjs"); defer engine.freeValue(nul_filename);
    const nul = c.JS_PiCompileCJSFunction(engine.context, source, nul_filename, &category); defer engine.freeValue(nul);
    const nul_reason = c.JS_GetException(engine.context); defer engine.freeValue(nul_reason);
    try std.testing.expect(c.JS_IsException(nul)); try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    const embedded = try rejected(engine, "return \x00;globalThis.truncatedBody=1", c.JS_PI_CJS_ESM_PARSE_REQUIRED); defer engine.freeValue(embedded);
    try check(engine, "globalThis.truncatedBody===undefined");
}
test "native CJS compiler actual trusted cancellation is operational rather than ordinary syntax and permits reuse" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    var body: std.ArrayList(u8) = .empty; defer body.deinit(std.testing.allocator);
    for (0..12000) |_| try body.appendSlice(std.testing.allocator, "void 0;");
    const source = try text(engine, body.items); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/cancelled.cjs"); defer engine.freeValue(filename);
    engine.cancelled.store(true, .release); defer engine.cancelled.store(false, .release);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ORDINARY_SYNTAX;
    const result = c.JS_PiCompileCJSFunction(engine.context, source, filename, &category); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    engine.cancelled.store(false, .release);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    try std.testing.expect(c.JS_IsUncatchableError(reason));
    c.JS_ClearUncatchableError(engine.context, reason);
    const healthy = try compile(engine, "return 2"); defer engine.freeValue(healthy);
}
test "native CJS compiler actual measured allocator failures in valid parsing semantic compilation regexp and closure retain operational reasons" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(0));
}
test "native CJS compiler actual SyntaxError allocation events preserve first reason and trusted completion through native recovery" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(1));
}
test "native CJS compiler actual literal-regexp allocator events never convert OOM into ordinary regexp syntax rejection" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(2));
}
test "native CJS compiler actual detached probe allocation positions retain flags and clean state before reuse" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(3));
}
test "native CJS compiler actual semantic-export SyntaxError allocation positions preserve native reason identity and cleanup" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(4));
}
test "native CJS compiler actual stack failure is operational before ordinary syntax and permits later compile and probe" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const source = try text(engine, "return 3"); defer engine.freeValue(source);
    const filename = try text(engine, "C:/compiler/stack.cjs"); defer engine.freeValue(filename);
    c.JS_SetMaxStackSize(engine.runtime, 1); defer c.JS_SetMaxStackSize(engine.runtime, engine.options.stack_limit);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_ORDINARY_SYNTAX;
    const result = c.JS_PiCompileCJSFunction(engine.context, source, filename, &category); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    c.JS_SetMaxStackSize(engine.runtime, engine.options.stack_limit);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.error_value));
    const healthy = try compile(engine, "return 9"); defer engine.freeValue(healthy);
    _ = try probe(engine, "export{}", 0, c.JS_PI_MODULE_STATIC_IMPORT_EXPORT);
}
test "native CJS compiler true EOF accepts trailing line comments and preserves source NUL within a literal" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const function = try compile(engine, "return 7 // genuine EOF body comment"); defer engine.freeValue(function);
    const result = try call(engine, function, c.pi_js_undefined(), &.{}); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 7)));
    const nul_function = try compile(engine, "return '\x00'"); defer engine.freeValue(nul_function);
    const nul = try call(engine, nul_function, c.pi_js_undefined(), &.{}); defer engine.freeValue(nul);
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen(engine.context, &length, nul);
    if (bytes == null) return error.LiteralReadFailed;
    defer c.JS_FreeCString(engine.context, bytes);
    try std.testing.expectEqual(@as(usize, 1), length);
    try std.testing.expectEqual(@as(u8, 0), bytes[0]);
}
test "native CJS compiler real VM local-variable capacity SyntaxError remains operational rather than ordinary grammar" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    var body: std.ArrayList(u8) = .empty; defer body.deinit(std.testing.allocator);
    // Actual public parsing exceeds the pinned VM's 16-bit local slots. No FD
    // field, limit, completion timestamp or parser outcome is fabricated.
    for (0..70000) |index| {
        const declaration = try std.fmt.allocPrint(std.testing.allocator, "var v{d};", .{index});
        defer std.testing.allocator.free(declaration);
        try body.appendSlice(std.testing.allocator, declaration);
    }
    const reason = try rejected(engine, body.items, c.JS_PI_CJS_NO_SYNTAX_CATEGORY); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.error_value));
    try publish(engine, "capacityReason", reason);
    try check(engine, "Object.getPrototypeOf(capacityReason)===SyntaxError.prototype");
    const healthy = try compile(engine, "return 2"); defer engine.freeValue(healthy);
}

test "native CJS compiler actual regexp capture ceiling has no ordinary syntax category in compile and probe" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    var body: std.ArrayList(u8) = .empty; defer body.deinit(std.testing.allocator);
    try body.appendSlice(std.testing.allocator, "void /");
    for (0..255) |_| try body.appendSlice(std.testing.allocator, "()");
    try body.appendSlice(std.testing.allocator, "/;");
    const reason = try rejected(engine, body.items, c.JS_PI_CJS_NO_SYNTAX_CATEGORY); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.error_value));
    try publish(engine, "regexpCapacityReason", reason);
    try check(engine, "Object.getPrototypeOf(regexpCapacityReason)===SyntaxError.prototype");
    const probe_reason = (try probe(engine, body.items, -1, 99)).?; defer engine.freeValue(probe_reason);
    const ordinary = try rejected(engine, "void /(/;", c.JS_PI_CJS_ORDINARY_SYNTAX); defer engine.freeValue(ordinary);
    const ordinary_probe = (try probe(engine, "void /(/;", 1, 99)).?; defer engine.freeValue(ordinary_probe);
    c.JS_RunGC(engine.runtime);
    const healthy = try compile(engine, "return /[\\q{ab|abc|de}]/v.test('abc')"); defer engine.freeValue(healthy);
    const result = try call(engine, healthy, c.pi_js_undefined(), &.{}); defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}

test "native CJS compiler actual optin regexp bytecode equals legacy and explicit NULL with no option callbacks" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(0));
}

test "native CJS compiler actual regexp capture producer reports only the actual native limit" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(1));
}

test "native CJS compiler measured Unicode stringset compile poll sweep preserves first pending reason through hash sort cleanup GC and reuse" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(2));
}

test "native CJS compiler optin regexp first poll preserves already pending reason without further callbacks" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(3));
}

test "native CJS compiler actual nested quantifier register capacity uses producer channel" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(4));
}

test "native CJS compiler actual named alternative scope capacity uses producer channel" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(5));
}

test "native CJS compiler actual native group name buffer capacity uses producer channel" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_regexp_controls(6));
}

test "native CJS compiler actual Unicode stringset allocator sweep covers native hash table and optin sort scratch retirement" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(5));
}

test "native CJS compiler actual string and template Unicode escape work interrupts preserve native success pending reason" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(0));
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(2));
}

test "native CJS compiler actual identifier and private-name Unicode escape work interrupts preserve first reason" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(1));
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(3));
}

test "native CJS compiler actual shebang scan uses trusted interrupt cadence before body or diagnostic production" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(4));
}

test "native CJS compiler detached probe escape and shebang work interrupts preserve flags and exact pending reason" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(5));
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(6));
}

test "native CJS compiler actual controlflow atom release counts survive measured allocator failures before healthy execution" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(6));
}

test "native CJS compiler measured real interrupt sweep through lexical semantic label and line work retires exact atom owners" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_semantic_work());
}

test "native CJS compiler actual async lookahead block comment and whitespace work preserve first pending reason" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(7));
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(8));
}

test "native CJS compiler actual arrow and label line comment lookahead work preserve first pending reason" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(9));
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_lexer_poll(10));
}
