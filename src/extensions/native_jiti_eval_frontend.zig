//! Actual jiti2.7 eval.ts frontend. Real transform/import/path/syntax bindings
//! are mandatory; no Babel/Acorn heuristic or fake factory fills a missing one.
//! Derived from jiti2.7, Copyright Pooya Parsa, MIT (retained authority license).
//! Local revision2: ordinary import catch separates rejected DATA/current event.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const body = @import("native_async_body.zig");
const evaluation = @import("native_jiti_eval_module.zig");
pub const Imports = struct {
    module_constructor: c.JSValue,
    nested_create_jiti: c.JSValue,
    jiti_require: c.JSValue,
    jiti_resolve: c.JSValue,
    pathe_dirname: c.JSValue,
    pathe_basename: c.JSValue,
    pathe_extname: c.JSValue,
    read_nearest_package_json: c.JSValue,
    has_esm_syntax: c.JSValue,
    performance: c.JSValue,
    debug: c.JSValue,
    transform: c.JSValue,
    native_import_or_require: c.JSValue,
    eval_module_self: c.JSValue,
};
pub fn validate(engine: *v.em.Engine, imports: Imports) !void {
    inline for (std.meta.fields(Imports)) |field| {
        const value = @field(imports, field.name);
        if (comptime std.mem.eql(u8, field.name, "performance")) {
            if (!c.JS_IsObject(value)) return error.RequiredActualJitiPerformance;
        } else if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualJitiFrontendImport;
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn put(engine: *v.em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn ignored(engine: *v.em.Engine, function: c.JSValue, args: []const c.JSValue) !void {
    const value = try v.js.call(engine, function, c.pi_js_undefined(), args); engine.freeValue(value);
}
fn binary(s: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_PiBinaryOperator(s.engine.context, operation, left, right)));
}
fn typescriptTest(engine: *v.em.Engine, extension: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const arguments = [_]c.JSValue{try s.text("\\.[cm]?tsx?$")};
    const expression = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 1, @constCast(&arguments))));
    return v.js.invoke(engine, expression, "test", &.{extension});
}
fn packageIsEsm(engine: *v.em.Engine, reader: c.JSValue, filename: c.JSValue) !bool {
    const package = try v.js.call(engine, reader, c.pi_js_undefined(), &.{filename}); defer engine.freeValue(package);
    if (v.nullish(package)) return false;
    const kind = try v.js.get(engine, package, "type"); defer engine.freeValue(kind);
    const expected = try engine.checked(c.JS_NewString(engine.context, "module")); defer engine.freeValue(expected);
    return c.JS_IsStrictEqual(engine.context, kind, expected);
}
fn elapsedTime(engine: *v.em.Engine, performance: c.JSValue, start: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const math = try s.global("Math"); const round = try s.get(math, "round");
    const end = try s.invoke(performance, "now", &.{});
    const thousand = c.JS_NewInt32(engine.context, 1000);
    const elapsed = try binary(&s, 2, try binary(&s, 1, end, start), thousand);
    const rounded = try s.call(round, math, &.{elapsed});
    return c.JS_DupValue(engine.context, try binary(&s, 3, rounded, thousand));
}
fn transform(engine: *v.em.Engine, imports: Imports, context: c.JSValue, source: c.JSValue, options: c.JSValue, filename: c.JSValue, typescript: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const request = try s.object();
    try put(engine, request, "filename", filename); try put(engine, request, "source", source); try put(engine, request, "ts", typescript);
    const asynchronous = try s.get(options, "async");
    try put(engine, request, "async", if (v.nullish(asynchronous)) c.pi_js_bool(engine.context, 0) else asynchronous);
    try put(engine, request, "jsx", try s.get(try s.get(context, "opts"), "jsx"));
    return v.js.call(engine, imports.transform, c.pi_js_undefined(), &.{ context, request });
}
fn take(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingJitiFrontendCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
fn nativeCall(engine: *v.em.Engine, imports: Imports, context: c.JSValue, filename: c.JSValue, options: c.JSValue) !c.JSValue {
    // The sync Source try covers argument getter evaluation as well as Call.
    const asynchronous = try v.js.get(engine, options, "async"); defer engine.freeValue(asynchronous);
    return v.js.call(engine, imports.native_import_or_require, c.pi_js_undefined(), &.{ context, filename, asynchronous });
}
/// Ordinary evalModule(ctx,source,evalOptions={}) body, returning the exact raw
/// Source value/Promise. Module/function compilation remains inside 4d's catch.
pub fn evaluate(engine: *v.em.Engine, imports: Imports, args: []const c.JSValue) !c.JSValue {
    try validate(engine, imports);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const context = arg(args, 0);
    var source = arg(args, 1);
    const options = if (c.JS_IsUndefined(arg(args, 2))) try s.object() else arg(args, 2);
    var id = try s.get(options, "id");
    if (!s.truthy(id)) {
        if (s.truthy(try s.get(options, "filename"))) {
            id = try s.call(imports.pathe_basename, c.pi_js_undefined(), &.{try s.get(options, "filename")});
        } else {
            var ext = try s.get(options, "ext");
            if (!s.truthy(ext)) ext = try s.text(if (s.truthy(try s.get(options, "async"))) "mjs" else "js");
            id = try s.concat(try s.text("_jitiEval."), try s.stringify(ext));
        }
    }
    var filename = try s.get(options, "filename");
    if (!s.truthy(filename)) {
        const resolve_options = try s.object(); try put(engine, resolve_options, "async", try s.get(options, "async"));
        filename = try s.call(imports.jiti_resolve, c.pi_js_undefined(), &.{ context, id, resolve_options });
    }
    var extension = try s.get(options, "ext");
    if (!s.truthy(extension)) extension = try s.call(imports.pathe_extname, c.pi_js_undefined(), &.{filename});
    var parent_cache = try s.get(options, "cache");
    if (!s.truthy(parent_cache)) { parent_cache = try s.get(context, "parentCache"); if (!s.truthy(parent_cache)) parent_cache = try s.object(); }
    const is_typescript = try s.own(try typescriptTest(engine, extension));
    var is_esm = s.equal(extension, try s.text(".mjs"));
    if (!is_esm and s.equal(extension, try s.text(".js"))) {
        is_esm = try packageIsEsm(engine, imports.read_nearest_package_json, filename);
    }
    const is_commonjs = s.equal(extension, try s.text(".cjs"));
    var needs_transpile = try s.get(options, "forceTranspile");
    if (v.nullish(needs_transpile)) {
        if (is_commonjs or (is_esm and s.truthy(try s.get(options, "async")))) {
            needs_transpile = c.pi_js_bool(engine.context, 0);
        } else if (s.truthy(is_typescript)) {
            needs_transpile = is_typescript;
        } else if (is_esm) {
            needs_transpile = c.pi_js_bool(engine.context, 1);
        } else {
            needs_transpile = try s.invoke(try s.get(context, "isTransformRe"), "test", &.{filename});
            if (!s.truthy(needs_transpile)) needs_transpile = try s.call(imports.has_esm_syntax, c.pi_js_undefined(), &.{source});
        }
    }
    const start = try s.invoke(imports.performance, "now", &.{});
    if (s.truthy(needs_transpile)) {
        source = try s.own(try transform(engine, imports, context, source, options, filename, is_typescript));
        const time = try s.own(try elapsedTime(engine, imports.performance, start));
        const kind = try s.text(if (s.truthy(try s.get(options, "async"))) "[esm]" else "[cjs]");
        const timing = try s.concat(try s.concat(try s.text("("), try s.stringify(time)), try s.text("ms)"));
        try ignored(engine, imports.debug, &.{ context, try s.text("[transpile]"), kind, filename, timing });
    } else {
        const kind = try s.text(if (s.truthy(try s.get(options, "async"))) "[import]" else "[require]");
        try ignored(engine, imports.debug, &.{ context, try s.text("[native]"), kind, filename });
        if (s.truthy(try s.get(options, "async"))) {
            const promise = try s.global("Promise"); const resolve = try s.get(promise, "resolve");
            const generation = engine.native_allocation_generation;
            const completion = try s.call(imports.native_import_or_require, c.pi_js_undefined(), &.{ context, filename, try s.get(options, "async") });
            const resolved = try s.call(resolve, promise, &.{completion});
            const catch_method = try s.get(resolved, "catch");
            const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
            inline for (.{ .{ "context", context }, .{ "source", source }, .{ "options", options }, .{ "filename", filename }, .{ "self", imports.eval_module_self }, .{ "debug", imports.debug } }) |entry| try put(engine, owner, entry[0], entry[1]);
            try put(engine, owner, "generation", try s.own(try engine.checked(c.JS_NewBigUint64(engine.context, generation))));
            const handler = try s.own(try functions.create(engine, "", 1, false, importFallback, &.{owner}));
            return v.js.call(engine, catch_method, resolved, &.{handler});
        }
        const generation = engine.native_allocation_generation;
        if (nativeCall(engine, imports, context, filename, options)) |value| {
            return value;
        } else |err| {
            const reason = try take(engine, err, generation); defer engine.freeValue(reason);
            try ignored(engine, imports.debug, &.{ context, try s.text("Native require error:"), reason });
            try ignored(engine, imports.debug, &.{ context, try s.text("[fallback]"), filename });
            source = try s.own(try transform(engine, imports, context, source, options, filename, is_typescript));
        }
    }
    return evaluation.evaluateLowered(engine, .{ .module_constructor = imports.module_constructor, .nested_create_jiti = imports.nested_create_jiti,
        .pathe_dirname = imports.pathe_dirname, .jiti_require = imports.jiti_require, .debug = imports.debug },
        .{ .context = context, .eval_options = options, .filename = filename, .parent_cache = parent_cache, .source = source });
}
fn importFallback(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // This ordinary callback is entered only through the reviewed native
    // ModuleCallable trampoline, which suppresses diagnostic coercion BEFORE
    // invoking this body. Its incoming rejected argument is DATA, not an event.
    const prior = engine.captured_exception;
    engine.captured_exception = null;
    defer {
        if (engine.captured_exception == null) engine.captured_exception = prior else if (prior) |reason| engine.freeValue(reason);
    }
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    return importFallbackInner(engine, args, roots) catch |err| {
        if (err == error.JavaScriptException) {
            if (engine.captured_exception == null and c.JS_HasException(engine.context)) {
                const capture_error = v.js.capture(engine);
                if (capture_error != error.JavaScriptException) return capture_error;
            }
            const caught = engine.captured_exception orelse return error.MissingJitiFrontendCurrentCapturedReason;
            if (c.JS_IsUncatchableError(caught)) return err;
            try body.rethrowRecognizedAllocation(engine, caught, generation);
        }
        // Unlike a native AF Action, this ordinary Source arrow propagates its
        // actual new capture to the trampoline and returns raw success values.
        return err;
    };
}
fn importFallbackInner(engine: *v.em.Engine, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const reason = arg(args, 0);
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(engine.context, &generation, try s.get(roots[0], "generation")) < 0) return v.js.capture(engine);
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    // No pending current event existed and no fresh private host cause was
    // recognized. Clear only this rejected DATA's historical hidden flag
    // before Source debug/spread/fallback callbacks can handle or rethrow it.
    c.JS_ClearUncatchableError(engine.context, reason);
    const context = try s.get(roots[0], "context");
    const filename = try s.get(roots[0], "filename");
    const debug = try s.get(roots[0], "debug");
    try ignored(engine, debug, &.{ context, try s.text("Native import error:"), reason });
    try ignored(engine, debug, &.{ context, try s.text("[fallback]"), filename });
    const options = try s.object(); try v.js.spreadInto(engine, options, try s.get(roots[0], "options"));
    try put(engine, options, "forceTranspile", c.pi_js_bool(engine.context, 1));
    return v.js.call(engine, try s.get(roots[0], "self"), c.pi_js_undefined(), &.{ context, try s.get(roots[0], "source"), options });
}
