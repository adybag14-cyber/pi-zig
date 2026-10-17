//! Actual ordinary jiti 2.7 require.ts body and its ordinary Promise callbacks.
//! Derived from jiti, Copyright Pooya Parsa, MIT; retained primary/LICENSE.
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const resolution = @import("native_jiti_resolve.zig");
const interop = @import("native_jiti_interop.zig");
const cache = @import("native_jiti_module_cache.zig");
const body = @import("native_async_body.zig");
pub const Inputs = struct {
    resolve_inputs: resolution.Inputs,
    node_file_url_to_path: c.JSValue,
    pathe_extname: c.JSValue,
    pathe_is_absolute: c.JSValue,
    mlly_path_to_file_url: c.JSValue,
    node_builtin_modules: c.JSValue,
    read_file_sync: c.JSValue,
    debug: c.JSValue,
    /// Actual eval.ts frontend(ctx,source,options), not just transformed hostbody.
    eval_module: c.JSValue,
    /// Actual std-env module initialization result, not user process spoofing.
    is_windows: bool,
};
/// Genuine ordinary exported jitiRequire(ctx,id,opts), length 3. Captures are
/// VM traced; the factory owns its real root/nested contexts independently.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const roots = inputRoots(engine, inputs);
    return @import("native_node_module_callable.zig").create(engine, "jitiRequire", 3, true, exported, &roots);
}
/// Actual second require.ts declaration, ordinary/constructible length3.
/// Same real module input captures/interop callbacks; no importer alias, AF,
/// Promise adoption or replacement jitiRequire implementation is supplied.
pub fn createNativeImportOrRequire(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    const roots = inputRoots(engine, inputs);
    return @import("native_node_module_callable.zig").create(engine, "nativeImportOrRequire", 3, true, exportedNativeImport, &roots);
}
fn exported(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return require(engine, fromRoots(engine, roots), arg(args, 0), arg(args, 1), arg(args, 2));
}
fn exportedNativeImport(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    // ModuleCallable suppresses diagnostics before this private callback. A
    // previous diagnostic capture is not a new exception event in this call.
    const prior = engine.captured_exception;
    engine.captured_exception = null;
    defer {
        if (engine.captured_exception == null) engine.captured_exception = prior else if (prior) |reason| engine.freeValue(reason);
    }
    if (c.JS_HasException(engine.context)) return v.js.capture(engine);
    const generation = engine.native_allocation_generation;
    const result = nativeImportOrRequire(engine, fromRoots(engine, roots), arg(args, 0), arg(args, 1), arg(args, 2)) catch |err| {
        if (err == error.JavaScriptException) {
            if (engine.captured_exception == null and c.JS_HasException(engine.context)) _ = v.js.capture(engine);
            const reason = engine.captured_exception orelse return error.MissingNativeImportCurrentCapturedReason;
            if (c.JS_IsUncatchableError(reason)) return err;
            try body.rethrowRecognizedAllocation(engine, reason, generation);
        }
        return err;
    };
    // A public host hook can leave an actual event despite a success value.
    // Do not return/publish a success over that still-pending VM event.
    if (c.JS_HasException(engine.context)) {
        const pending = c.JS_GetException(engine.context);
        engine.freeValue(result);
        return engine.checked(c.JS_Throw(engine.context, pending));
    }
    return result;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
/// Borrowed inputs/ctx/id/opts; owned exact raw result or Promise. Ordinary
/// jitiRequire is not an AsyncFunction and does not adopt branch returns.
pub fn require(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return requireInner(engine, inputs, context, id, options) catch |err| return resolution.exactFailure(engine, err, generation);
}
fn requireInner(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, original_id: c.JSValue, options: c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var id = original_id;
    const parent = try s.own(try cache.forRequire(engine, context));
    if (s.truthy(try s.invoke(id, "startsWith", &.{try s.text("node:")}))) {
        return nativeImportOrRequire(engine, inputs, context, id, try s.get(options, "async"));
    } else if (s.truthy(try s.invoke(id, "startsWith", &.{try s.text("file:")}))) {
        id = try s.call(inputs.node_file_url_to_path, c.pi_js_undefined(), &.{id});
    } else if (s.truthy(try s.invoke(id, "startsWith", &.{try s.text("data:")}))) {
        if (!s.truthy(try s.get(options, "async"))) return v.errorText(&s, try s.text("`data:` URLs are only supported in ESM context. Use `import` or `jiti.import` instead."));
        try debug(engine, inputs, &.{ context, try s.text("[native]"), try s.text("[data]"), try s.text("[import]"), id });
        return nativeImportOrRequire(engine, inputs, context, id, c.pi_js_bool(engine.context, 1));
    }
    if (s.truthy(try s.invoke(inputs.node_builtin_modules, "includes", &.{id})) or s.equal(id, try s.text(".pnp.js"))) return nativeImportOrRequire(engine, inputs, context, id, try s.get(options, "async"));
    if (s.truthy(try s.get(try s.get(context, "opts"), "virtualModules")) and try v.js.hasKey(engine, try s.get(try s.get(context, "opts"), "virtualModules"), id)) {
        try debug(engine, inputs, &.{ context, try s.text("[virtual]"), id });
        const module = try s.own(try v.js.getKey(engine, try s.get(try s.get(context, "opts"), "virtualModules"), id));
        if (s.truthy(try s.get(options, "async"))) {
            const promise = try s.global("Promise");
            const method = try s.get(promise, "resolve");
            const value = try s.own(try interop.jitiInteropDefault(engine, context, module));
            return v.js.call(engine, method, promise, &.{value});
        }
        return interop.jitiInteropDefault(engine, context, module);
    }
    if (s.truthy(try s.get(try s.get(context, "opts"), "tryNative")) and !s.truthy(try s.get(try s.get(context, "opts"), "transformOptions"))) {
        // id assignment precedes every later fallible operation in this try.
        // A sync failure falls through with that current id, not original_id.
        const generation = engine.native_allocation_generation;
        const attempted = resolution.resolve(engine, inputs.resolve_inputs, context, id, options);
        if (attempted) |value| {
            id = try s.own(value);
            const after_generation = engine.native_allocation_generation;
            if (tryNativeResolved(engine, inputs, context, id, options)) |result| return result else |err| {
                const reason = try s.own(try resolution.takeCaught(engine, err, after_generation));
                try fallbackDebug(engine, inputs, context, id, reason);
            }
        } else |err| {
            const reason = try s.own(try resolution.takeCaught(engine, err, generation));
            try fallbackDebug(engine, inputs, context, id, reason);
        }
    }
    const filename = try s.own(try resolution.resolve(engine, inputs.resolve_inputs, context, id, options));
    if (!s.truthy(filename) and s.truthy(try s.get(options, "try"))) return c.pi_js_undefined();
    const ext = try s.call(inputs.pathe_extname, c.pi_js_undefined(), &.{filename});
    if (s.equal(ext, try s.text(".json"))) {
        try debug(engine, inputs, &.{ context, try s.text("[json]"), filename });
        const module = try s.invoke(context, "nativeRequire", &.{filename});
        return interop.jsonSelfDefault(engine, module);
    }
    if (s.truthy(ext) and !s.truthy(try s.invoke(try s.get(try s.get(context, "opts"), "extensions"), "includes", &.{ext}))) {
        const mode = if (s.truthy(try s.get(options, "async"))) "[import]" else "[require]";
        try debug(engine, inputs, &.{ context, try s.text("[native]"), try s.text("[unknown]"), try s.text(mode), filename });
        return nativeImportOrRequire(engine, inputs, context, filename, try s.get(options, "async"));
    }
    if (s.truthy(try s.invoke(try s.get(context, "isNativeRe"), "test", &.{filename}))) {
        const mode = if (s.truthy(try s.get(options, "async"))) "[import]" else "[require]";
        try debug(engine, inputs, &.{ context, try s.text("[native]"), try s.text(mode), filename });
        return nativeImportOrRequire(engine, inputs, context, filename, try s.get(options, "async"));
    }
    const found = try cache.lookup(engine, context, parent, filename);
    if (found.hit) return found.value;
    engine.freeValue(found.value);
    const source = try s.call(inputs.read_file_sync, c.pi_js_undefined(), &.{ filename, try s.text("utf8") });
    const eval_options = try s.object();
    try s.put(eval_options, "id", id);
    try s.put(eval_options, "filename", filename);
    try s.put(eval_options, "ext", ext);
    try s.put(eval_options, "cache", parent);
    try s.put(eval_options, "async", try s.get(options, "async"));
    return v.js.call(engine, inputs.eval_module, c.pi_js_undefined(), &.{ context, source, eval_options });
}
fn tryNativeResolved(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, options: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(id) and s.truthy(try s.get(options, "try"))) return c.pi_js_undefined();
    const mode = if (s.truthy(try s.get(options, "async")) and s.truthy(try s.get(context, "nativeImport"))) "[import]" else "[require]";
    try debug(engine, inputs, &.{ context, try s.text("[try-native]"), try s.text(mode), id });
    if (s.truthy(try s.get(options, "async")) and s.truthy(try s.get(context, "nativeImport"))) {
        const generation = engine.native_allocation_generation;
        const imported = try s.invoke(context, "nativeImport", &.{id});
        const then = try s.get(imported, "then");
        const success = try s.own(try callback(engine, inputs, .native_success, context, id, options, generation));
        const result = try s.call(then, imported, &.{success});
        const catcher = try s.get(result, "catch");
        const fallback = try s.own(try callback(engine, inputs, .native_fallback, context, id, options, generation));
        return v.js.call(engine, catcher, result, &.{fallback});
    }
    const module = try s.invoke(context, "nativeRequire", &.{id});
    try cache.afterNativeSuccess(engine, context, id);
    return interop.jitiInteropDefault(engine, context, module);
}
/// Source nativeImportOrRequire: preserve synchronous throws and exact raw
/// `.then` return. No new Promise/Await appears in this ordinary function.
pub fn nativeImportOrRequire(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, asynchronous: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return nativeInner(engine, inputs, context, id, asynchronous) catch |err| return resolution.exactFailure(engine, err, generation);
}
fn nativeInner(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, asynchronous: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.truthy(asynchronous) and s.truthy(try s.get(context, "nativeImport"))) {
        const function = try s.get(context, "nativeImport");
        var normalized = id;
        if (inputs.is_windows and s.truthy(try s.call(inputs.pathe_is_absolute, c.pi_js_undefined(), &.{id}))) normalized = try s.call(inputs.mlly_path_to_file_url, c.pi_js_undefined(), &.{id});
        const imported = try s.call(function, context, &.{normalized});
        const then = try s.get(imported, "then");
        const next = try s.own(try callback(engine, inputs, .interop_only, context, c.pi_js_undefined(), c.pi_js_undefined(), 0));
        return v.js.call(engine, then, imported, &.{next});
    }
    return interop.jitiInteropDefault(engine, context, try s.invoke(context, "nativeRequire", &.{id}));
}
fn debug(engine: *v.em.Engine, inputs: Inputs, args: []const c.JSValue) !void {
    const ignored = try v.js.call(engine, inputs.debug, c.pi_js_undefined(), args); engine.freeValue(ignored);
}
fn fallbackDebug(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, id: c.JSValue, reason: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    // Template interpolation is ToString, not '+' default-hint coercion.
    const message = try s.concat(try s.concat(try s.text("[try-native] Using fallback for "), try s.stringify(id)), try s.text(" because of an error:"));
    try debug(engine, inputs, &.{ context, message, reason });
}
const Callback = enum(c_int) { interop_only, native_success, native_fallback };
fn inputRoots(engine: *v.em.Engine, inputs: Inputs) [17]c.JSValue {
    return .{
        inputs.resolve_inputs.pathe_resolve_alias, inputs.resolve_inputs.mlly_file_url_to_path,
        inputs.resolve_inputs.mlly_resolve_path_sync, inputs.resolve_inputs.pathe_join,
        inputs.resolve_inputs.pathe_dirname, inputs.resolve_inputs.is_dir,
        inputs.node_file_url_to_path, inputs.pathe_extname, inputs.pathe_is_absolute,
        inputs.mlly_path_to_file_url, inputs.node_builtin_modules, inputs.read_file_sync,
        inputs.debug, inputs.eval_module, c.pi_js_bool(engine.context, @intFromBool(inputs.is_windows)),
        inputs.resolve_inputs.js_ext_re, inputs.resolve_inputs.ts_ext_re,
    };
}
fn callback(engine: *v.em.Engine, inputs: Inputs, kind: Callback, context: c.JSValue, id: c.JSValue, options: c.JSValue, generation: u64) !c.JSValue {
    const tagged_boundary = try engine.checked(c.JS_NewBigUint64(engine.context, generation));
    defer engine.freeValue(tagged_boundary);
    var roots: [21]c.JSValue = undefined;
    for (inputRoots(engine, inputs), 0..) |value, index| roots[index] = value;
    roots[17] = context; roots[18] = id; roots[19] = options; roots[20] = tagged_boundary;
    // VM function-data roots have actual GC tracing and aggregate charging.
    // This is an ordinary nonconstructible Source arrow; no public namespace.
    return engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, "", 1, @intFromEnum(kind), roots.len, &roots));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    const generation = engine.native_allocation_generation;
    return callbackInner(engine, @enumFromInt(kind), roots[0..21], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| {
        const current = interop.callbackFailure(engine, err, generation);
        if (current == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowTypeError(context, "Native jiti callback: %s", @as([*:0]const u8, @errorName(current)));
    };
}
fn fromRoots(engine: *v.em.Engine, roots: []const c.JSValue) Inputs {
    return .{
        .resolve_inputs = .{ .pathe_resolve_alias = roots[0], .mlly_file_url_to_path = roots[1], .mlly_resolve_path_sync = roots[2], .pathe_join = roots[3], .pathe_dirname = roots[4], .is_dir = roots[5], .js_ext_re = roots[15], .ts_ext_re = roots[16] },
        .node_file_url_to_path = roots[6], .pathe_extname = roots[7], .pathe_is_absolute = roots[8], .mlly_path_to_file_url = roots[9],
        .node_builtin_modules = roots[10], .read_file_sync = roots[11], .debug = roots[12], .eval_module = roots[13], .is_windows = c.JS_ToBool(engine.context, roots[14]) == 1,
    };
}
fn callbackInner(engine: *v.em.Engine, kind: Callback, roots: []const c.JSValue, value: c.JSValue) !c.JSValue {
    const inputs = fromRoots(engine, roots);
    const ctx = roots[17]; const id = roots[18]; const options = roots[19];
    switch (kind) {
        .interop_only => return interop.jitiInteropDefault(engine, ctx, value),
        .native_success => { try cache.afterNativeSuccess(engine, ctx, id); return interop.jitiInteropDefault(engine, ctx, value); },
        .native_fallback => {
            var s: Scope = .{ .engine = engine }; defer s.deinit();
            // Rejected data alone never proves a pending native fatal, even
            // if its old flag remains set. Only a fresh private allocation tag
            // in this explicit operation boundary qualifies this reason.
            var generation: u64 = 0;
            if (c.JS_ToBigUint64(engine.context, &generation, roots[20]) < 0) return v.js.capture(engine);
            try body.rethrowRecognizedAllocation(engine, value, generation);
            try fallbackDebug(engine, inputs, ctx, id, value);
            const nested = try s.own(try v.js.spread(engine, ctx));
            const opts = try s.own(try v.js.spread(engine, try s.get(ctx, "opts")));
            try s.put(opts, "tryNative", c.pi_js_bool(engine.context, 0));
            try s.put(nested, "opts", opts);
            return require(engine, inputs, nested, id, options);
        },
    }
}
