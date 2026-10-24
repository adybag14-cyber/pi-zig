//! Actual restored compiler-info owner with current native-entry ownership.
//! All controls are authored and unexecuted; no complete wrapSafe or loader is fabricated.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
const info = @import("extensions/native_node_commonjs_compile_info.zig");
const raw = @import("extensions/native_node_commonjs_body_compiler.zig");

// The real C compiler requires a capture-only native Error hook. This observer
// copies the actual reason and counts capture events; it never formats, calls
// guest code, changes loader policy or substitutes a compiler result.
const Capture = struct {
    first: c.JSValue,
    calls: usize = 0,
    fn init(self: *Capture, engine: *em.Engine) void {
        self.* = .{ .first = c.pi_js_undefined() };
        c.JS_SetNativeErrorStackHook(engine.runtime, capture, self);
    }
    fn deinit(self: *Capture, engine: *em.Engine) void {
        c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
        engine.freeValue(self.first);
    }
    fn capture(context: ?*c.JSContext, reason: c.JSValue, phase: c_int, _: c.JSValue,
        _: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int
    {
        const self: *Capture = @ptrCast(@alignCast(data.?));
        if (phase == c.JS_ERROR_STACK_CAPTURE) {
            self.calls += 1;
            if (c.JS_IsUndefined(self.first)) self.first = c.JS_DupValue(context, reason);
        }
        return 0;
    }
};
fn text(engine: *em.Engine, bytes: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, bytes.ptr, bytes.len));
}
fn expectText(engine: *em.Engine, actual: c.JSValue, expected: []const u8) !void {
    const value = try text(engine, expected); defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, value));
}
fn publish(engine: *em.Engine, name: [*:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_DefinePropertyValueStr(engine.context, global, name,
        c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.InfoControlPublicationFailed;
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const value = try engine.eval(source, "C:/info/observer.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(value);
    try std.testing.expect(c.JS_ToBool(engine.context, value) == 1);
}
fn compile(engine: *em.Engine, source: []const u8) !info.Completion {
    const body = try text(engine, source); defer engine.freeValue(body);
    const name = try text(engine, "C:/info/physical.cjs"); defer engine.freeValue(name);
    return info.compile(engine, body, name);
}
fn prepareScript(engine: *em.Engine, source: []const u8) !info.Info {
    const body = try text(engine, source); defer engine.freeValue(body);
    const name = try text(engine, "C:/info/physical.cjs"); defer engine.freeValue(name);
    return info.script(engine, body, name);
}
fn rejectedCompile(engine: *em.Engine, result: anyerror!info.Completion) !void {
    if (result) |unexpected| {
        unexpected.deinit(engine);
        return error.ExpectedInfoCompileFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
}
fn rejectedScript(engine: *em.Engine, result: anyerror!info.Info) !void {
    if (result) |unexpected| {
        unexpected.deinit(engine);
        return error.ExpectedInfoScriptFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
}
fn rejectedRun(engine: *em.Engine, result: anyerror!c.JSValue) !void {
    if (result) |unexpected| {
        engine.freeValue(unexpected);
        return error.ExpectedInfoRunFailure;
    } else |err| try std.testing.expectEqual(error.JavaScriptException, err);
}
fn balanced(engine: *em.Engine) !void {
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
    try std.testing.expect(engine.native_fatal_invocation == null);
}

test "native module compile info returns genuine function and lexer metadata before any body execution" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const completion = try compile(engine, "globalThis.infoBodyRuns=1;return exports;\n//# sourceURL=logical.js\n//# sourceMappingURL=actual.map");
    defer completion.deinit(engine);
    if (completion != .compiled) return error.ExpectedActualInfoCompilation;
    try expectText(engine, completion.compiled.source_url, "logical.js");
    try expectText(engine, completion.compiled.source_map_url, "actual.map");
    const function = completion.compiled.value;
    try std.testing.expect(c.JS_IsFunction(engine.context, function));
    try std.testing.expect(c.JS_IsConstructor(engine.context, function));
    try std.testing.expect(!c.JS_IsAsyncFunction(function));
    try publish(engine, "actualInfoFunction", function);
    try check(engine, "actualInfoFunction.length===5&&typeof infoBodyRuns==='undefined'");
    const promise = try engine.eval("Promise.resolve(17)", "C:/info/promise.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    c.JS_RunGC(engine.runtime);
    var args = [_]c.JSValue{promise};
    const result = try engine.checked(c.JS_Call(engine.context, function, c.pi_js_undefined(), 1, &args));
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, promise));
    try check(engine, "infoBodyRuns===1");
    try balanced(engine);
}
test "native module compile info patched script preserves actual metadata and raw Promise through compile run and GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const promise = try engine.eval("globalThis.infoPromise=Promise.resolve(23)", "C:/info/promise.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(promise);
    const script = try prepareScript(engine, "globalThis.infoScriptRuns=1;infoPromise;\n//# sourceURL=patched.js\n//# sourceMappingURL=patched.map");
    defer script.deinit(engine);
    try expectText(engine, script.source_url, "patched.js");
    try expectText(engine, script.source_map_url, "patched.map");
    try check(engine, "typeof infoScriptRuns==='undefined'");
    c.JS_RunGC(engine.runtime);
    const result = try info.run(engine, script.value); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, promise));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try check(engine, "infoScriptRuns===1");
    try balanced(engine);
}
test "native module compile info preserves physical fallback and full logical NUL from the actual lexer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const plain = try compile(engine, "void '//# sourceURL=not-a-comment.js';return 1");
    defer plain.deinit(engine);
    if (plain != .compiled) return error.ExpectedActualInfoCompilation;
    try expectText(engine, plain.compiled.source_url, "C:/info/physical.cjs");
    try std.testing.expect(c.JS_IsUndefined(plain.compiled.source_map_url));
    const logical = try compile(engine, "return 1;\n//# sourceURL=prefix\x00suffix.js");
    defer logical.deinit(engine);
    if (logical != .compiled) return error.ExpectedActualInfoCompilation;
    try expectText(engine, logical.compiled.source_url, "prefix\x00suffix.js");
    try std.testing.expect(c.JS_IsUndefined(logical.compiled.source_map_url));
    try balanced(engine);
}
test "native module compile info retains actual syntax reason categories separately from stale captured diagnostics" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const stale = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(stale);
    engine.captured_exception = c.JS_DupValue(engine.context, stale);
    const ordinary = try compile(engine, "void /(/;"); defer ordinary.deinit(engine);
    if (ordinary != .syntax) return error.ExpectedActualInfoSyntax;
    try std.testing.expectEqual(raw.SyntaxCategory.ordinary, ordinary.syntax.category);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, ordinary.syntax.reason, capture.first));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, stale));
    const direct = try compile(engine, "export {; definitely invalid module tail"); defer direct.deinit(engine);
    if (direct != .syntax) return error.ExpectedActualInfoSyntax;
    try std.testing.expectEqual(raw.SyntaxCategory.direct_module, direct.syntax.category);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try balanced(engine);
}
test "native module compile info rejects internal nonstrings without coercion and does not truncate physical NUL" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const hostile = try engine.eval("globalThis.infoCoercions=0;({toString(){infoCoercions++;return 'return 1'}})", "C:/info/input.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(hostile);
    const name = try text(engine, "C:/info/input.cjs"); defer engine.freeValue(name);
    try rejectedCompile(engine, info.compile(engine, hostile, name));
    try check(engine, "infoCoercions===0");
    const source = try text(engine, "return 1"); defer engine.freeValue(source);
    const nul = try text(engine, "C:/info/prefix\x00suffix.cjs"); defer engine.freeValue(nul);
    try rejectedCompile(engine, info.compile(engine, source, nul));
    try balanced(engine);
}
test "native module compile info pending entry precedes both compiler forms and preserves the exact reason under quota" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const source = try text(engine, "const = ;"); defer engine.freeValue(source);
    const filename = try text(engine, "C:/info/pending.cjs"); defer engine.freeValue(filename);
    const reason = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(reason);
    inline for (.{ false, true }) |script| {
        _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason));
        const generation = engine.native_allocation_generation;
        const captures = capture.calls;
        c.JS_SetMemoryLimit(engine.runtime, 1);
        if (script) {
            const result = info.script(engine, source, filename);
            c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
            try rejectedScript(engine, result);
        } else {
            const result = info.compile(engine, source, filename);
            c.JS_SetMemoryLimit(engine.runtime, engine.options.memory_limit);
            try rejectedCompile(engine, result);
        }
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, reason));
        try std.testing.expectEqual(generation, engine.native_allocation_generation);
        try std.testing.expectEqual(captures, capture.calls);
        try balanced(engine);
    }
}
fn leaveOuter(engine: *em.Engine, outer: *em.Engine.NativeInvocation) void {
    const result = engine.leaveNativeInvocation(outer, c.pi_js_undefined()); engine.freeValue(result);
    if (c.JS_HasException(engine.context)) engine.freeValue(c.JS_GetException(engine.context));
}
test "native module compile info retained native producer is checked before invoking the syntax compiler" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const source = try text(engine, "void /(/;"); defer engine.freeValue(source);
    const filename = try text(engine, "C:/info/retained.cjs"); defer engine.freeValue(filename);
    var outer: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&outer);
    defer leaveOuter(engine, &outer);
    _ = engine.throwNativeOutOfMemoryFatal();
    const first = c.JS_GetException(engine.context); defer engine.freeValue(first);
    try std.testing.expect(!c.JS_HasException(engine.context));
    const captures = capture.calls;
    const generation = engine.native_allocation_generation;
    try rejectedCompile(engine, info.compile(engine, source, filename));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, engine.captured_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(engine.captured_exception.?));
    try std.testing.expectEqual(captures, capture.calls);
    try std.testing.expectEqual(generation, engine.native_allocation_generation);
    try std.testing.expect(engine.native_fatal_invocation == &outer);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
test "native module compile info retained native producer prevents actual script side effects before run" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const marker = try engine.eval("globalThis.infoMarker={ran:false};infoMarker", "C:/info/marker.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(marker);
    const script = try prepareScript(engine, "infoMarker.ran=true;37"); defer script.deinit(engine);
    var outer: em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&outer);
    defer leaveOuter(engine, &outer);
    _ = engine.throwNativeOutOfMemoryFatal();
    const first = c.JS_GetException(engine.context); defer engine.freeValue(first);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try rejectedRun(engine, info.run(engine, script.value));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, first, engine.captured_exception.?));
    const ran = c.JS_GetPropertyStr(engine.context, marker, "ran"); defer engine.freeValue(ran);
    try std.testing.expect(c.JS_IsBool(ran) and c.JS_ToBool(engine.context, ran) == 0);
    try std.testing.expect(engine.native_fatal_invocation == &outer);
    try std.testing.expectEqual(@as(usize, 0), engine.native_exception_diagnostics_suppressed);
}
fn nativeFatalTaken(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    _ = engine.throwNativeOutOfMemoryFatal();
    engine.freeValue(c.JS_GetException(context));
    return c.JS_NewInt32(context, 41);
}
test "native module compile info run owns a stable invocation before a native producer clears its raw slot" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    try engine.bindFunction("infoFatalTaken", nativeFatalTaken, 0);
    const script = try prepareScript(engine, "infoFatalTaken()"); defer script.deinit(engine);
    const generation = engine.native_allocation_generation;
    try rejectedRun(engine, info.run(engine, script.value));
    const actual = engine.captured_exception orelse return error.MissingInfoNativeProducer;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(actual));
    try std.testing.expectEqual(generation +% 1, engine.native_allocation_generation);
    try balanced(engine);
}
const Retirement = struct {
    engine: *em.Engine,
    ordinary: c.JSValue,
    first: c.JSValue,
    class_id: c.JSClassID = 0,
    releases: usize = 0,
    armed: bool = true,
    previous: bool,
};
var retirement: ?*Retirement = null;
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const probe: *Retirement = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    probe.releases += 1;
    if (!probe.armed) return;
    probe.armed = false;
    _ = probe.engine.throwNativeOutOfMemoryFatal();
    const reason = c.JS_GetException(probe.engine.context);
    probe.first = c.JS_DupValue(probe.engine.context, reason);
    _ = c.JS_Throw(probe.engine.context, reason);
}
fn carrier(probe: *Retirement) c.JSValue {
    const value = c.JS_NewObjectProtoClass(probe.engine.context, c.pi_js_null(), probe.class_id);
    if (!c.JS_IsException(value)) _ = c.JS_SetOpaque(value, probe);
    return value;
}
fn returnPendingCarrier(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const probe = retirement.?;
    if (probe.previous) return c.JS_Throw(context, c.JS_DupValue(context, probe.ordinary));
    const value = carrier(probe);
    if (c.JS_IsException(value)) return value;
    _ = c.JS_Throw(context, c.JS_DupValue(context, probe.ordinary));
    return value;
}
fn retirementControl(previous: bool) !void {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    const ordinary = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(ordinary);
    var probe: Retirement = .{ .engine = engine, .ordinary = ordinary, .first = c.pi_js_undefined(), .previous = previous };
    retirement = &probe;
    defer { probe.armed = false; retirement = null; engine.freeValue(probe.first); }
    _ = c.JS_NewClassID(engine.runtime, &probe.class_id);
    const definition: c.JSClassDef = .{ .class_name = "Actual Info owned retirement carrier", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, probe.class_id, &definition) < 0) return error.OutOfMemory;
    try engine.bindFunction("infoPendingCarrier", returnPendingCarrier, 0);
    const script = try prepareScript(engine, "infoPendingCarrier()"); defer script.deinit(engine);
    if (previous) {
        const value = try engine.checked(carrier(&probe));
        engine.captured_exception = value; // Deliberate owned diagnostic DATA, not a producer.
    }
    const generation = engine.native_allocation_generation;
    try rejectedRun(engine, info.run(engine, script.value));
    try std.testing.expectEqual(@as(usize, 1), probe.releases);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, engine.captured_exception.?, probe.first));
    try std.testing.expect(c.JS_IsUncatchableError(probe.first));
    try std.testing.expectEqual(generation +% 1, engine.native_allocation_generation);
    try balanced(engine);
}
test "native module compile info retires actual returned and prior diagnostic carriers under the same first fatal owner" {
    try retirementControl(false);
    try retirementControl(true);
}
fn capturedFlaggedData(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var resolving: [2]c.JSValue = undefined;
    const promise = c.JS_NewPromiseCapability(context, &resolving);
    if (c.JS_IsException(promise)) return promise;
    defer engine.freeValue(promise);
    defer engine.freeValue(resolving[0]);
    defer engine.freeValue(resolving[1]);
    _ = engine.throwNativeOutOfMemory();
    const reason = c.JS_GetException(context); defer engine.freeValue(reason);
    c.JS_SetUncatchableError(context, reason);
    var args = [_]c.JSValue{reason};
    const result = c.JS_Call(context, resolving[1], c.pi_js_undefined(), 1, &args);
    defer engine.freeValue(result);
    if (c.JS_IsException(result)) return result;
    if (engine.awaitValueOnly(promise)) |unexpected| engine.freeValue(unexpected) else |_| {}
    return c.JS_NewInt32(context, 43);
}
test "native module compile info successful script keeps newly captured rejected flagged Promise data nonfatal" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var capture: Capture = undefined; capture.init(engine); defer capture.deinit(engine);
    try engine.bindFunction("infoCapturedFlaggedData", capturedFlaggedData, 0);
    const script = try prepareScript(engine, "infoCapturedFlaggedData()"); defer script.deinit(engine);
    const generation = engine.native_allocation_generation;
    const result = try info.run(engine, script.value); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 43)));
    const diagnostic = engine.captured_exception orelse return error.MissingInfoCapturedData;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, diagnostic, engine.native_allocation_exception.?));
    try std.testing.expect(c.JS_IsUncatchableError(diagnostic));
    try std.testing.expectEqual(generation +% 1, engine.native_allocation_generation);
    try std.testing.expect(!c.JS_HasException(engine.context));
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
    try balanced(engine);
    try engine.checkNativeEntry();
}
