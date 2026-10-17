//! Actual jiti2.7 transformed eval.ts Module/evaluation orchestration.
//! The real Source front end supplies resolved inputs. API12a prepare happens
//! before Module creation; this does not invent options/resolve/transform APIs.
//! Derived from jiti2.7, Copyright Pooya Parsa, MIT (retained authority LICENSE).
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const lowering = @import("native_jiti_cjs_eval.zig");
const cache = @import("native_jiti_module_cache.zig");
const body = @import("native_async_body.zig");
const functions = @import("native_node_module_callable.zig");

/// Every binding is the actual completed implementation, not a substitute
/// namespace, identity callback, or empty factory. No global registration.
pub const Inputs = struct {
    module_constructor: c.JSValue,
    nested_create_jiti: c.JSValue,
    pathe_dirname: c.JSValue,
    jiti_require: c.JSValue,
    debug: c.JSValue,
};
/// Borrowed JS values and source bytes. The caller implements actual Source
/// id/filename/ext/cache/needsTranspile/options/fsCache/debug ordering first.
/// Only API12a's explicit native lowering profile is supported by this entry.
/// transform_async is the earlier transformation option, independently of the
/// later live evalOptions.async reads for wrapper construction and return.
pub const TransformedRequest = struct {
    context: c.JSValue,
    eval_options: c.JSValue,
    filename: c.JSValue,
    parent_cache: c.JSValue,
    source: []const u8,
    typescript: bool,
    transform_async: bool,
};
/// The actual transform/cache function has already returned this Source value.
/// Its template ToString occurs only at wrapModule after Module publication.
pub const LoweredRequest = struct {
    context: c.JSValue,
    eval_options: c.JSValue,
    filename: c.JSValue,
    parent_cache: c.JSValue,
    source: c.JSValue,
};
const BaseRequest = struct { context: c.JSValue, eval_options: c.JSValue, filename: c.JSValue, parent_cache: c.JSValue };
const Code = union(enum) {
    native: struct { source: []const u8, typescript: bool, asynchronous: bool },
    lowered: c.JSValue,
};
fn put(engine: *v.em.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
/// Source expression statements discard their call result before later guest
/// callbacks. Never put an ignored return in the enclosing broad Scope roots.
fn callIgnored(engine: *v.em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !void {
    const result = try v.js.call(engine, function, receiver, args);
    engine.freeValue(result);
}
fn invokeIgnored(engine: *v.em.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const function = try v.js.get(engine, receiver, name); defer engine.freeValue(function);
    try callIgnored(engine, function, receiver, args);
}
fn requireBindings(engine: *v.em.Engine, inputs: Inputs) !void {
    inline for (.{ "module_constructor", "nested_create_jiti", "pathe_dirname", "jiti_require", "debug" }) |field|
        if (!c.JS_IsFunction(engine.context, @field(inputs, field))) return error.RequiredActualJitiEvaluationBinding;
}
/// Owned raw value/Promise. This is a host entry into the actual ordinary
/// evalModule body, NOT an AF wrapper or a complete public evalModule facade.
pub fn evaluateTransformed(engine: *v.em.Engine, inputs: Inputs, request: TransformedRequest) !c.JSValue {
    return protectedEvaluate(engine, inputs, .{ .context = request.context, .eval_options = request.eval_options, .filename = request.filename, .parent_cache = request.parent_cache },
        .{ .native = .{ .source = request.source, .typescript = request.typescript, .asynchronous = request.transform_async } });
}
pub fn evaluateLowered(engine: *v.em.Engine, inputs: Inputs, request: LoweredRequest) !c.JSValue {
    return protectedEvaluate(engine, inputs, .{ .context = request.context, .eval_options = request.eval_options, .filename = request.filename, .parent_cache = request.parent_cache }, .{ .lowered = request.source });
}
fn protectedEvaluate(engine: *v.em.Engine, inputs: Inputs, request: BaseRequest, code: Code) !c.JSValue {
    try requireBindings(engine, inputs);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const generation = engine.native_allocation_generation;
    return evaluate(engine, inputs, request, code) catch |err| {
        if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
            if (c.JS_IsUncatchableError(reason)) return err;
            try body.rethrowRecognizedAllocation(engine, reason, generation);
        };
        return err;
    };
}
fn evaluate(engine: *v.em.Engine, inputs: Inputs, request: BaseRequest, code: Code) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    // Actual next() is lexically hoisted. Its private owner roots ctx/module;
    // no Source-visible object or collaborator is created as a placeholder.
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    try put(engine, owner, "context", request.context);
    try put(engine, owner, "module", c.pi_js_undefined());
    try put(engine, owner, "jitiRequire", inputs.jiti_require);
    const next = try s.own(try functions.create(engine, "next", 0, true, finish, &.{owner}));
    const generated: ?lowering.Prepared = switch (code) {
        .native => |input| try lowering.prepare(engine.gpa, input.source, .{ .typescript = input.typescript, .async_mode = input.asynchronous }),
        .lowered => null,
    };
    defer if (generated) |prepared| prepared.deinit(engine.gpa);

    var filename_args = [_]c.JSValue{request.filename};
    const module = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, inputs.module_constructor, 1, &filename_args)));
    try put(engine, owner, "module", module);
    try s.set(module, "filename", request.filename);
    if (s.truthy(try s.get(request.context, "parentModule"))) {
        try s.set(module, "parent", try s.get(request.context, "parentModule"));
        const array = try s.global("Array");
        const is_array = try s.get(array, "isArray");
        const children = try s.get(try s.get(request.context, "parentModule"), "children");
        if (s.truthy(try s.call(is_array, array, &.{children}))) {
            const included_children = try s.get(try s.get(request.context, "parentModule"), "children");
            if (!s.truthy(try s.invoke(included_children, "includes", &.{module}))) {
                const pushed_children = try s.get(try s.get(request.context, "parentModule"), "children");
                try invokeIgnored(engine, pushed_children, "push", &.{module});
            }
        }
    }
    // Callee args: filename, ctx.opts, then the parent context's fields in order.
    const options = try s.get(request.context, "opts");
    const parent = try s.object();
    try put(engine, parent, "parentModule", module);
    try put(engine, parent, "parentCache", request.parent_cache);
    try put(engine, parent, "nativeImport", try s.get(request.context, "nativeImport"));
    try put(engine, parent, "onError", try s.get(request.context, "onError"));
    try put(engine, parent, "createRequire", try s.get(request.context, "createRequire"));
    const nested = try s.call(inputs.nested_create_jiti, c.pi_js_undefined(), &.{ request.filename, options, parent, c.pi_js_bool(engine.context, 1) });
    try s.set(module, "require", nested);
    try s.set(module, "path", try s.call(inputs.pathe_dirname, c.pi_js_undefined(), &.{request.filename}));
    // Get live Module._nodeModulePaths before reading mod.path (callee first).
    const lookup_paths = try s.get(inputs.module_constructor, "_nodeModulePaths");
    try s.set(module, "paths", try s.call(lookup_paths, inputs.module_constructor, &.{try s.get(module, "path")}));
    try cache.publishBeforeEval(engine, request.context, request.parent_cache, request.filename, module);

    // Source wraps with a fresh async read outside the compile try. A guest
    // getter may differ from the earlier transform option and the later tail.
    const asynchronous = s.truthy(try s.get(request.eval_options, "async"));
    var source_bytes: ?[]u8 = null; defer if (source_bytes) |bytes| engine.gpa.free(bytes);
    const bytes = if (generated) |prepared| prepared.body else wrapped: {
        source_bytes = try wrapSourceBytes(engine, code.lowered);
        break :wrapped source_bytes.?;
    };
    const compiled_prepared: lowering.Prepared = .{ .body = bytes, .async_mode = asynchronous };
    var compiled = c.pi_js_undefined(); defer engine.freeValue(compiled);
    const compile_generation = engine.native_allocation_generation;
    if (compile(engine, &compiled_prepared, request.filename)) |value| {
        compiled = value;
    } else |err| {
        const reason = try takeCaught(engine, err, compile_generation); defer engine.freeValue(reason);
        if (s.equal(try s.get(reason, "name"), try s.text("SyntaxError")) and
            s.truthy(try s.get(request.eval_options, "async")) and
            s.truthy(try s.get(request.context, "nativeImport"))) {
            try callIgnored(engine, inputs.debug, c.pi_js_undefined(), &.{ request.context, try s.text("[esm]"), try s.text("[import]"), try s.text("[fallback]"), request.filename });
            // The real esmEval data/temp-file fallback is still absent. Never
            // substitute a fake function or silently take the ordinary catch.
            return error.RequiredActualJitiEsmEval;
        }
        try cache.afterEvalFailure(engine, request.context, request.filename);
        try invokeIgnored(engine, request.context, "onError", &.{reason});
        // Source onError may return: compiled remains undefined and evaluation
        // then throws its actual TypeError inside the next Source catch.
    }
    var eval_result = c.pi_js_undefined(); defer engine.freeValue(eval_result);
    const invoke_generation = engine.native_allocation_generation;
    if (lowering.invoke(engine, compiled, module, nested, inputs.pathe_dirname)) |value| {
        eval_result = value;
    } else |err| {
        const reason = try takeCaught(engine, err, invoke_generation); defer engine.freeValue(reason);
        try cache.afterEvalFailure(engine, request.context, request.filename);
        try invokeIgnored(engine, request.context, "onError", &.{reason});
        // Returning onError leaves evalResult undefined, then reaches next().
    }
    if (!s.truthy(try s.get(request.eval_options, "async"))) return v.js.call(engine, next, c.pi_js_undefined(), &.{});
    // Source ordinary Promise.resolve(...).then(next), including live callee,
    // receiver/getter effects and exact raw .then return. No manual Await.
    const promise = try s.global("Promise");
    const resolved = try s.invoke(promise, "resolve", &.{eval_result});
    return v.js.invoke(engine, resolved, "then", &.{next});
}
fn wrapSourceBytes(engine: *v.em.Engine, source: c.JSValue) ![]u8 {
    const string = try engine.checked(c.JS_ToString(engine.context, source)); defer engine.freeValue(string);
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen(engine.context, &length, string) orelse return v.js.capture(engine);
    defer c.JS_FreeCString(engine.context, bytes);
    return engine.gpa.dupe(u8, bytes[0..length]);
}
fn compile(engine: *v.em.Engine, prepared: *const lowering.Prepared, filename: c.JSValue) !c.JSValue {
    if (!c.JS_IsString(filename)) return v.js.typeError(engine, "Native jiti profile requires a physical string filename");
    var length: usize = 0;
    const bytes = c.JS_ToCStringLen(engine.context, &length, filename) orelse return v.js.capture(engine);
    defer c.JS_FreeCString(engine.context, bytes);
    if (std.mem.indexOfScalar(u8, bytes[0..length], 0) != null) return v.js.typeError(engine, "Native jiti profile requires a NUL-free physical filename");
    const terminated = try engine.gpa.dupeZ(u8, bytes[0..length]); defer engine.gpa.free(terminated);
    return lowering.compile(engine, prepared, terminated);
}
/// Own the original ordinary reason before guest cleanup/onError. A fresh
/// cleanup throw remains in Engine while this local old reason is freed.
fn takeCaught(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingActualJitiCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
fn finish(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const context = try s.get(roots[0], "context");
    const module = try s.get(roots[0], "module");
    if (s.truthy(try s.get(module, "exports"))) {
        if (s.truthy(try s.get(try s.get(module, "exports"), "__JITI_ERROR__"))) {
            const marker = try s.get(try s.get(module, "exports"), "__JITI_ERROR__");
            const filename = try s.get(marker, "filename");
            const line = try s.get(marker, "line");
            const column = try s.get(marker, "column");
            const code = try s.get(marker, "code");
            const message = try s.get(marker, "message");
            const location = try s.concat(try s.concat(try s.concat(try s.concat(try s.stringify(filename), try s.text(":")), try s.stringify(line)), try s.text(":")), try s.stringify(column));
            const error_constructor = try s.global("Error");
            const formatted = try s.concat(try s.concat(try s.concat(try s.concat(try s.stringify(code), try s.text(": ")), try s.stringify(message)), try s.text(" \n ")), location);
            var arguments = [_]c.JSValue{formatted};
            const reason = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, error_constructor, 1, &arguments)));
            // Error is looked up again after construction in Source. The
            // constructor/template effects can replace the global binding.
            const capture_owner = try s.global("Error");
            const capture = try s.get(capture_owner, "captureStackTrace");
            try callIgnored(engine, capture, capture_owner, &.{ reason, try s.get(roots[0], "jitiRequire") });
            try invokeIgnored(engine, context, "onError", &.{reason});
        }
    }
    return cache.loadedExports(engine, context, module);
}
