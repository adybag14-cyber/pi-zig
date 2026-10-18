//! Genuine linked compiler/script metadata controls, all prepared and UNRUN.
const std = @import("std");
const em = @import("extensions/engine.zig");
const c = em.c;
extern fn pi_test_cjs_compiler_allocations(mode: c_int) c_int;
extern fn pi_test_cjs_metadata_work() c_int;
extern fn pi_test_cjs_metadata_legacy_allocations() c_int;
extern fn pi_test_cjs_metadata_finalizer_allocations() c_int;
const Owner = struct {
    first: c.JSValue,
    replacement: c.JSValue,
    pending_once: bool = false,
    filename: [256]u8 = undefined,
    filename_length: usize = 0,
    fn init(self: *Owner, engine: *em.Engine) void {
        self.* = .{ .first = c.pi_js_undefined(), .replacement = c.pi_js_undefined() };
        c.JS_SetNativeErrorStackHook(engine.runtime, capture, self);
    }
    fn deinit(self: *Owner, engine: *em.Engine) void {
        c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
        engine.freeValue(self.first); engine.freeValue(self.replacement);
    }
    fn capture(context: ?*c.JSContext, reason: c.JSValue, phase: c_int, _: c.JSValue, filename: [*c]const u8, _: c_int, _: c_int, _: c_int, data: ?*anyopaque) callconv(.c) c_int {
        const self: *Owner = @ptrCast(@alignCast(data.?));
        if (phase != c.JS_ERROR_STACK_CAPTURE) return 0;
        if (c.JS_IsUndefined(self.first)) self.first = c.JS_DupValue(context, reason);
        if (filename != null) {
            var length: usize = 0;
            while (length < self.filename.len and filename[length] != 0) : (length += 1) self.filename[length] = filename[length];
            self.filename_length = length;
        }
        if (self.pending_once) {
            self.pending_once = false;
            _ = c.JS_Throw(context, c.JS_DupValue(context, self.replacement));
        }
        return 0; // Only native capture/copy; no guest or formatting/reentry.
    }
};
const Info = struct {
    engine: *em.Engine,
    value: c.JSValue,
    url: c.JSValue,
    map: c.JSValue,
    fn deinit(self: Info) void { self.engine.freeValue(self.value); self.engine.freeValue(self.url); self.engine.freeValue(self.map); }
};
fn text(engine: *em.Engine, value: []const u8) !c.JSValue { return engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len)); }
fn compile(engine: *em.Engine, body: []const u8, script: bool) !Info {
    const source = try text(engine, body); defer engine.freeValue(source);
    const filename = try text(engine, "C:/metadata/physical.cjs"); defer engine.freeValue(filename);
    var url = c.pi_js_undefined(); errdefer engine.freeValue(url);
    var map = c.pi_js_undefined(); errdefer engine.freeValue(map);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_NO_SYNTAX_CATEGORY;
    const value = if (script) c.JS_PiCompileCommonJSScriptInfo(engine.context, source, filename, &url, &map) else c.JS_PiCompileCJSFunctionInfo(engine.context, source, filename, &category, &url, &map);
    errdefer engine.freeValue(value);
    if (c.JS_IsException(value) or c.JS_HasException(engine.context)) {
        const reason = c.JS_GetException(engine.context);
        defer engine.freeValue(reason);
        return error.UnexpectedActualMetadataCompileFailure;
    }
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    return .{ .engine = engine, .value = value, .url = url, .map = map };
}
fn equalText(engine: *em.Engine, actual: c.JSValue, expected: []const u8) !void {
    const value = try text(engine, expected); defer engine.freeValue(value);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, value));
}
fn publish(engine: *em.Engine, name: [:0]const u8, value: c.JSValue) !void {
    const global = try engine.checked(c.JS_GetGlobalObject(engine.context)); defer engine.freeValue(global);
    if (c.JS_SetPropertyStr(engine.context, global, name, c.JS_DupValue(engine.context, value)) < 0) return error.ControlPublicationFailed;
}
fn check(engine: *em.Engine, source: []const u8) !void {
    const result = try engine.eval(source, "C:/metadata/observer.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) == 1);
}
fn frames(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_CaptureCurrentStackFrames(context, 8, c.pi_js_undefined(), null, 0, 0, c.JS_ERROR_STACK_SKIP_FIRST);
}

test "native CJS metadata actual lexer comments produce URL map and nested real function origin before execution" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const capture = try engine.checked(c.JS_NewCFunction(engine.context, frames, "metadataFrames", 0)); defer engine.freeValue(capture);
    try publish(engine, "metadataFrames", capture);
    const info = try compile(engine, "globalThis.metadataBodyRuns=1;return function nested(){return metadataFrames()};\n//# sourceURL=logical-origin.js\n//# sourceMappingURL=actual.map", false); defer info.deinit();
    try equalText(engine, info.url, "logical-origin.js"); try equalText(engine, info.map, "actual.map");
    try check(engine, "typeof metadataBodyRuns==='undefined'");
    const nested = try engine.checked(c.JS_Call(engine.context, info.value, c.pi_js_undefined(), 0, null)); defer engine.freeValue(nested);
    c.JS_RunGC(engine.runtime);
    const captured = try engine.checked(c.JS_Call(engine.context, nested, c.pi_js_undefined(), 0, null)); defer engine.freeValue(captured);
    try publish(engine, "actualMetadataFrames", captured);
    try check(engine, "metadataBodyRuns===1&&actualMetadataFrames[0].getFileName()==='C:/metadata/physical.cjs'&&actualMetadataFrames[0].getScriptNameOrSourceURL()==='logical-origin.js'");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}

test "native CJS metadata string template regexp block HTML and malformed comments never become magic events" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const info = try compile(engine, "void '//# sourceURL=string.js';void `\n//# sourceURL=template.js\n`;void /sourceURL=fake/;/* //# sourceURL=block.js */\n<!-- //# sourceURL=html.js\n//#sourceURL=no-space.js\n//#  sourceURL=two-spaces.js", false); defer info.deinit();
    try equalText(engine, info.url, "C:/metadata/physical.cjs");
    try std.testing.expect(c.JS_IsUndefined(info.map));
}

test "native CJS metadata exact mandatory whitespace and recognized invalid later assignment follow actual scanner rules" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const kept = try compile(engine, "return 1;\n//# sourceURL=first.js\n//# sourceURL =ignored.js\n//#  sourceURL=ignored-two.js\n//@\tsourceMappingURL=map.json  \t", false); defer kept.deinit();
    try equalText(engine, kept.url, "first.js"); try equalText(engine, kept.map, "map.json");
    const cleared = try compile(engine, "return 1;\n//# sourceURL=first.js\n//# sourceMappingURL=first.map\n//# sourceURL=bad.js extra\n//# sourceMappingURL=", false); defer cleared.deinit();
    try equalText(engine, cleared.url, "C:/metadata/physical.cjs"); try std.testing.expect(c.JS_IsUndefined(cleared.map));
}

test "native CJS metadata raw unicode and quoted values are not URI normalized or unquoted" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const info = try compile(engine, "return 1;\n//# sourceURL=ümlaut🧪.js \n//# sourceMappingURL=\"quoted.map\"", false); defer info.deinit();
    try equalText(engine, info.url, "ümlaut🧪.js"); try equalText(engine, info.map, "\"quoted.map\"");
}

test "native CJS metadata first pending reason dominates syntax producer and leaves output slots untouched" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    owner.replacement = try engine.checked(c.JS_NewObject(engine.context)); owner.pending_once = true;
    const body = try text(engine, "//# sourceURL=before-error.js\nvoid /(/;"); defer engine.freeValue(body);
    const filename = try text(engine, "C:/metadata/bad.cjs"); defer engine.freeValue(filename);
    var url = c.JS_NewInt32(engine.context, 99); defer engine.freeValue(url);
    var map = c.JS_NewInt32(engine.context, 77); defer engine.freeValue(map);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_DIRECT_MODULE_SYNTAX;
    const result = c.JS_PiCompileCJSFunctionInfo(engine.context, body, filename, &category, &url, &map); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, owner.replacement));
    try std.testing.expectEqual(@as(c.JSPiCJSParseCategory, c.JS_PI_CJS_NO_SYNTAX_CATEGORY), category);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, url, c.JS_NewInt32(engine.context, 99)));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, map, c.JS_NewInt32(engine.context, 77)));
    try std.testing.expectEqualStrings("C:/metadata/bad.cjs", owner.filename[0..owner.filename_length]);
    c.JS_RunGC(engine.runtime);
    const healthy = try compile(engine, "return 1", false); defer healthy.deinit();
}

test "native CJS metadata incoming pending and invalid alias admission do not alter owned output slots" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const body = try text(engine, "return 1"); defer engine.freeValue(body);
    const filename = try text(engine, "C:/metadata/pending.cjs"); defer engine.freeValue(filename);
    const incoming = try engine.checked(c.JS_NewObject(engine.context)); defer engine.freeValue(incoming);
    var url = c.JS_NewInt32(engine.context, 99); defer engine.freeValue(url);
    var map = c.JS_NewInt32(engine.context, 77); defer engine.freeValue(map);
    var category: c.JSPiCJSParseCategory = c.JS_PI_CJS_DIRECT_MODULE_SYNTAX;
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, incoming));
    const result = c.JS_PiCompileCJSFunctionInfo(engine.context, body, filename, &category, &url, &map); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(result));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, reason, incoming));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, url, c.JS_NewInt32(engine.context, 99)));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, map, c.JS_NewInt32(engine.context, 77)));
    const aliased = c.JS_PiCompileCJSFunctionInfo(engine.context, body, filename, &category, &url, &url); defer engine.freeValue(aliased);
    const alias_reason = c.JS_GetException(engine.context); defer engine.freeValue(alias_reason);
    try std.testing.expect(c.JS_IsException(aliased));
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, url, c.JS_NewInt32(engine.context, 99)));
}

test "native CJS metadata patched script compiles before body and retains actual raw Promise completion" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const promise = try engine.eval("globalThis.metadataPromise=Promise.resolve(7)", "C:/metadata/promise.js", c.JS_EVAL_TYPE_GLOBAL); defer engine.freeValue(promise);
    const info = try compile(engine, "globalThis.metadataScriptRuns=1;metadataPromise;\n//# sourceURL=patched-origin.js\n//# sourceMappingURL=patched.map", true); defer info.deinit();
    try equalText(engine, info.url, "patched-origin.js"); try equalText(engine, info.map, "patched.map");
    try check(engine, "typeof metadataScriptRuns==='undefined'");
    c.JS_RunGC(engine.runtime);
    const result = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, info.value))); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, promise));
    try check(engine, "metadataScriptRuns===1");
}

test "native CJS metadata real embedded source URL NUL is length preserved in returned metadata" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const info = try compile(engine, "return 1;\n//# sourceURL=prefix\x00suffix.js", false); defer info.deinit();
    try equalText(engine, info.url, "prefix\x00suffix.js");
    // The physical native-hook location remains separate from this full logical value.
}

fn pump(engine: *em.Engine) !void {
    for (0..32) |_| {
        if (!c.JS_IsJobPending(engine.runtime)) return;
        var context: ?*c.JSContext = null;
        const status = c.JS_ExecutePendingJob(engine.runtime, &context);
        if (status < 0) {
            if (context) |actual| engine.freeValue(c.JS_GetException(actual));
            return error.ActualMetadataImportJobFailed;
        }
        try std.testing.expectEqual(engine.context, context.?);
    }
    return error.ActualMetadataImportJobBoundExceeded;
}
fn physicalInit(context: ?*c.JSContext, module: ?*c.JSModuleDef) callconv(.c) c_int {
    return c.JS_SetModuleExport(context, module, "marker", c.JS_NewInt32(context, 17));
}
fn logicalInit(context: ?*c.JSContext, module: ?*c.JSModuleDef) callconv(.c) c_int {
    return c.JS_SetModuleExport(context, module, "marker", c.JS_NewInt32(context, 91));
}

test "native CJS metadata logical source URL never redirects actual nested dynamic import physical referrer" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const physical = c.JS_NewCModule(engine.context, "C:/metadata/dep.mjs", physicalInit) orelse return error.PhysicalFixtureModuleFailed;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_AddModuleExport(engine.context, physical, "marker"));
    const logical = c.JS_NewCModule(engine.context, "C:/logical/dep.mjs", logicalInit) orelse return error.LogicalFixtureModuleFailed;
    try std.testing.expectEqual(@as(c_int, 0), c.JS_AddModuleExport(engine.context, logical, "marker"));
    const info = try compile(engine, "return function nested(){return import('./dep.mjs')};\n//# sourceURL=C:/logical/other.cjs", false); defer info.deinit();
    try equalText(engine, info.url, "C:/logical/other.cjs");
    const nested = try engine.checked(c.JS_Call(engine.context, info.value, c.pi_js_undefined(), 0, null)); defer engine.freeValue(nested);
    c.JS_RunGC(engine.runtime);
    const promise = try engine.checked(c.JS_Call(engine.context, nested, c.pi_js_undefined(), 0, null)); defer engine.freeValue(promise);
    try std.testing.expect(c.JS_IsJobPending(engine.runtime));
    try pump(engine);
    try std.testing.expectEqual(c.JS_PROMISE_FULFILLED, c.JS_PromiseState(engine.context, promise));
    const namespace = c.JS_PromiseResult(engine.context, promise); defer engine.freeValue(namespace);
    const marker = try engine.checked(c.JS_GetPropertyStr(engine.context, namespace, "marker")); defer engine.freeValue(marker);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, marker, c.JS_NewInt32(engine.context, 17)));
}

test "native CJS metadata private logical URL serialization refuses while ordinary legacy bytecode roundtrip remains real" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const private = try compile(engine, "1;\n//# sourceURL=logical.js", true); defer private.deinit();
    var length: usize = 0;
    const encoded = c.JS_WriteObject(engine.context, &length, private.value, c.JS_WRITE_OBJ_BYTECODE);
    defer if (encoded != null) c.js_free(engine.context, encoded);
    try std.testing.expect(encoded == null);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    const ordinary = try compile(engine, "7;", true); defer ordinary.deinit();
    const bytes = c.JS_WriteObject(engine.context, &length, ordinary.value, c.JS_WRITE_OBJ_BYTECODE);
    if (bytes == null) return error.OrdinarySerializationFailed;
    defer c.js_free(engine.context, bytes);
    const read = try engine.checked(c.JS_ReadObject(engine.context, bytes, length, c.JS_READ_OBJ_BYTECODE)); defer engine.freeValue(read);
    c.JS_RunGC(engine.runtime);
    const result = try engine.checked(c.JS_EvalFunction(engine.context, c.JS_DupValue(engine.context, read))); defer engine.freeValue(result);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, result, c.JS_NewInt32(engine.context, 7)));
}

test "native CJS metadata cloned frames own physical and full logical names after function GC" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const capture = try engine.checked(c.JS_NewCFunction(engine.context, frames, "metadataFrames", 0)); defer engine.freeValue(capture);
    try publish(engine, "metadataFrames", capture);
    const info = try compile(engine, "return metadataFrames();\n//# sourceURL=full\x00logical.js", false);
    const captured = try engine.checked(c.JS_Call(engine.context, info.value, c.pi_js_undefined(), 0, null)); defer engine.freeValue(captured);
    info.deinit();
    const first = try engine.checked(c.JS_GetPropertyUint32(engine.context, captured, 0)); defer engine.freeValue(first);
    const clone = try engine.checked(c.JS_CloneCapturedStackFrame(engine.context, first)); defer engine.freeValue(clone);
    c.JS_RunGC(engine.runtime);
    var logical_name = c.pi_js_undefined();
    try std.testing.expectEqual(@as(c_int, 0), c.JS_ReadCapturedStackFrameSourceName(engine.context, clone, &logical_name)); defer engine.freeValue(logical_name);
    try equalText(engine, logical_name, "full\x00logical.js");
    try publish(engine, "ownedMetadataFrame", clone);
    try check(engine, "ownedMetadataFrame.getFileName()==='C:/metadata/physical.cjs'&&ownedMetadataFrame.getScriptNameOrSourceURL().length===15");
}

test "native CJS metadata actual allocator sweep retires FD bytecode logical atoms and uncommitted outputs" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_compiler_allocations(7));
}

test "native CJS metadata actual cadence pending interrupts preserve outputs and retire logical atoms" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_metadata_work());
}

test "native CJS metadata real legacy numeric source name failure stops preparation and preserves cause before unwind" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_metadata_legacy_allocations());
}

test "native CJS metadata default legacy formatted location preserves embedded logical NUL by length" {
    const engine = try em.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    var owner: Owner = undefined; owner.init(engine); defer owner.deinit(engine);
    const info = try compile(engine, "throw new Error('owned');\n//# sourceURL=full\x00logical.js", false); defer info.deinit();
    c.JS_SetNativeErrorStackHook(engine.runtime, null, null);
    const result = c.JS_Call(engine.context, info.value, c.pi_js_undefined(), 0, null); defer engine.freeValue(result);
    const reason = c.JS_GetException(engine.context); defer engine.freeValue(reason);
    try std.testing.expect(c.JS_IsException(result));
    const stack = try engine.checked(c.JS_GetPropertyStr(engine.context, reason, "stack")); defer engine.freeValue(stack);
    try publish(engine, "metadataDefaultStack", stack);
    try check(engine, "typeof metadataDefaultStack==='string'&&metadataDefaultStack.includes('full\\u0000logical.js')");
    try std.testing.expect(!c.JS_IsJobPending(engine.runtime));
}

test "native CJS metadata actual sole owned Error prototype finalizer fatal supersedes ordinary capture failure" {
    try std.testing.expectEqual(@as(c_int, 0), pi_test_cjs_metadata_finalizer_allocations());
}
