//! Actual jiti2.7 jiti.ts core factory body. Real imports only; no namespace
//! registration/default facade. Canonical declaration/linking is separate.
//! Derived from jiti2.7, Copyright Pooya Parsa, MIT (retained authority license).
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const body = @import("native_async_body.zig");
const functions = @import("native_node_module_callable.zig");
pub const Imports = struct {
    resolve_options: c.JSValue,
    file_url_to_path: c.JSValue,
    path_to_file_url: c.JSValue,
    normalize_aliases: c.JSValue,
    escape_string_regexp: c.JSValue,
    library_require: c.JSValue,
    is_dir: c.JSValue,
    pathe_dirname: c.JSValue,
    pathe_join: c.JSValue,
    debug: c.JSValue,
    prepare_cache_dir: c.JSValue,
    jiti_require: c.JSValue,
    jiti_resolve: c.JSValue,
    transform: c.JSValue,
    eval_module: c.JSValue,
    package_json: c.JSValue,
    iterator_symbol: c.JSValue,
};
pub fn validate(engine: *v.em.Engine, imports: Imports) !void {
    inline for (std.meta.fields(Imports)) |field| {
        const value = @field(imports, field.name);
        if (comptime std.mem.eql(u8, field.name, "package_json")) {
            if (!c.JS_IsObject(value)) return error.RequiredActualJitiPackageJson;
        } else if (comptime std.mem.eql(u8, field.name, "iterator_symbol")) {
            if (!c.JS_IsSymbol(value)) return error.RequiredActualJitiIteratorSymbol;
        } else if (!c.JS_IsFunction(engine.context, value)) return error.RequiredActualJitiFactoryImport;
    }
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn put(engine: *v.em.Engine, target: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, target, name, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn literal(engine: *v.em.Engine, values: []const c.JSValue) !c.JSValue {
    const result = try v.js.array(engine); errdefer engine.freeValue(result);
    for (values, 0..) |value, index| if (c.JS_DefinePropertyValueUint32(engine.context, result, @intCast(index), c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
    return result;
}
fn take(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingJitiFactoryCapturedReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try body.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
fn closeAbrupt(engine: *v.em.Engine, iterator: *v.js.Iterator, err: anyerror, generation: u64) anyerror {
    const original = take(engine, err, generation) catch |fatal| return fatal;
    defer engine.freeValue(original);
    if (!iterator.closed) {
        iterator.closed = true;
        const closing_generation = engine.native_allocation_generation;
        closeReturn(engine, iterator.iterator) catch |close_err| {
            const suppressed = take(engine, close_err, closing_generation) catch |fatal| return fatal;
            engine.freeValue(suppressed);
        };
    }
    engine.captured_exception = c.JS_DupValue(engine.context, original);
    return err;
}
fn closeReturn(engine: *v.em.Engine, iterator: c.JSValue) !void {
    const method = try v.js.get(engine, iterator, "return"); defer engine.freeValue(method);
    if (v.nullish(method)) return;
    // A throwing completion precedes IteratorClose's result-object check.
    const ignored_result = try v.js.call(engine, method, iterator, &.{}); engine.freeValue(ignored_result);
}
fn spread(engine: *v.em.Engine, target: c.JSValue, iterable: c.JSValue, symbol: c.JSValue, start: u32) !void {
    var iterator = try v.js.Iterator.init(engine, iterable, symbol); defer iterator.deinit();
    var index = start;
    while (try iterator.next()) |value| {
        defer engine.freeValue(value);
        const generation = engine.native_allocation_generation;
        append(engine, target, index, value) catch |err| return closeAbrupt(engine, &iterator, err, generation);
        index += 1;
    }
}
fn append(engine: *v.em.Engine, target: c.JSValue, index: u32, value: c.JSValue) !void {
    if (index == std.math.maxInt(u32)) {
        _ = try engine.checked(c.JS_ThrowRangeError(engine.context, "Invalid array length")); unreachable;
    }
    if (c.JS_DefinePropertyValueUint32(engine.context, target, index, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E | c.JS_PROP_THROW) < 0) return v.js.capture(engine);
}
fn regexp(engine: *v.em.Engine, modules: c.JSValue, escape: c.JSValue) !c.JSValue {
    const constructor = try v.js.global(engine, "RegExp"); defer engine.freeValue(constructor);
    const mapped = try mapModules(engine, modules, escape);
    var mapped_live = true; defer if (mapped_live) engine.freeValue(mapped);
    const pipe = try engine.checked(c.JS_NewString(engine.context, "|")); defer engine.freeValue(pipe);
    const joined = try v.js.invoke(engine, mapped, "join", &.{pipe});
    engine.freeValue(mapped);
    mapped_live = false;
    const text = engine.checked(c.JS_ToString(engine.context, joined)) catch |err| { engine.freeValue(joined); return err; };
    engine.freeValue(joined); defer engine.freeValue(text);
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const pattern = try s.concat(try s.concat(try s.text("node_modules/("), text), try s.text(")/"));
    var args = [_]c.JSValue{pattern};
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
}
fn mapModules(engine: *v.em.Engine, modules: c.JSValue, escape: c.JSValue) !c.JSValue {
    const map = try v.js.get(engine, modules, "map"); defer engine.freeValue(map);
    // Source passes a fresh one-argument arrow, not the imported declaration.
    // A replaced map can observe the callback's identity/shape and invoke it.
    const mapper = try functions.create(engine, "", 1, false, escapeModule, &.{escape});
    defer engine.freeValue(mapper);
    return v.js.call(engine, map, modules, &.{mapper});
}
fn escapeModule(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.js.call(engine, roots[0], c.pi_js_undefined(), &.{arg(args, 0)});
}
fn ignored(engine: *v.em.Engine, function: c.JSValue, receiver: c.JSValue, args: []const c.JSValue) !void {
    const result = try v.js.call(engine, function, receiver, args); engine.freeValue(result);
}
fn debugArguments(engine: *v.em.Engine, imports: Imports, context: c.JSValue, opts: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const pairs = try s.array();
    const version = try s.own(try literal(engine, &.{ try s.text("version:"), try s.get(imports.package_json, "version") }));
    try append(engine, pairs, 0, version);
    inline for (.{ .{ "module-cache:", "moduleCache" }, .{ "fs-cache:", "fsCache" }, .{ "rebuild-fs-cache:", "rebuildFsCache" }, .{ "interop-defaults:", "interopDefault" } }, 1..) |entry, index| {
        const pair = try s.own(try literal(engine, &.{ try s.text(entry[0]), try s.get(opts, entry[1]) }));
        try append(engine, pairs, index, pair);
    }
    const flattened = try s.invoke(pairs, "flat", &.{});
    const args_array = try s.own(try literal(engine, &.{ context, try s.text("[init]") }));
    try spread(engine, args_array, flattened, imports.iterator_symbol, 2);
    return c.JS_DupValue(engine.context, args_array);
}
fn debugInit(engine: *v.em.Engine, imports: Imports, context: c.JSValue, opts: c.JSValue) !void {
    const args_array = try debugArguments(engine, imports, context, opts);
    var array_live = true; defer if (array_live) engine.freeValue(args_array);
    var length: u32 = 0;
    const count = try v.js.get(engine, args_array, "length"); defer engine.freeValue(count);
    if (c.JS_ToUint32(engine.context, &length, count) < 0) return v.js.capture(engine);
    if (length > std.math.maxInt(c_int)) return error.OutOfMemory;
    const bytes = std.math.mul(usize, length, @sizeOf(c.JSValue)) catch return error.OutOfMemory;
    if (c.pi_js_native_memory_reserve(engine.native_memory_owner, bytes) == 0) return error.OutOfMemory;
    defer c.pi_js_native_memory_release(engine.native_memory_owner, bytes);
    const arguments = try engine.gpa.alloc(c.JSValue, length); defer engine.gpa.free(arguments);
    var initialized: usize = 0;
    defer for (arguments[0..initialized]) |value| engine.freeValue(value);
    for (arguments, 0..) |*slot, index| { slot.* = try engine.checked(c.JS_GetPropertyUint32(engine.context, args_array, @intCast(index))); initialized += 1; }
    engine.freeValue(args_array); array_live = false;
    try ignored(engine, imports.debug, c.pi_js_undefined(), arguments);
}
fn additionalExtensions(engine: *v.em.Engine, extensions: c.JSValue) !c.JSValue {
    const filter = try v.js.get(engine, extensions, "filter"); defer engine.freeValue(filter);
    const js = try engine.checked(c.JS_NewString(engine.context, ".js")); defer engine.freeValue(js);
    const select = try functions.create(engine, "", 1, false, additionalExtension, &.{js}); defer engine.freeValue(select);
    return v.js.call(engine, filter, extensions, &.{select});
}
fn spreadOption(engine: *v.em.Engine, target: c.JSValue, opts: c.JSValue, name: [*:0]const u8, symbol: c.JSValue, start: u32, fallback: bool) !void {
    const value = try v.js.get(engine, opts, name); defer engine.freeValue(value);
    if (fallback and c.JS_ToBool(engine.context, value) == 0) {
        const empty_array = try v.js.array(engine); defer engine.freeValue(empty_array);
        return spread(engine, target, empty_array, symbol, start);
    }
    return spread(engine, target, value, symbol, start);
}
fn additionalFromOptions(engine: *v.em.Engine, opts: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const extensions = try v.js.array(engine); defer engine.freeValue(extensions);
    try spreadOption(engine, extensions, opts, "extensions", symbol, 0, false);
    return additionalExtensions(engine, extensions);
}
fn aliases(engine: *v.em.Engine, imports: Imports, opts: c.JSValue) !c.JSValue {
    const first = try v.js.get(engine, opts, "alias");
    const enabled = c.JS_ToBool(engine.context, first) != 0; engine.freeValue(first);
    if (!enabled) return c.pi_js_undefined();
    var populated = false;
    {
        const object = try v.js.global(engine, "Object"); defer engine.freeValue(object);
        const keys = try v.js.get(engine, object, "keys"); defer engine.freeValue(keys);
        const value = try v.js.get(engine, opts, "alias"); defer engine.freeValue(value);
        const names = try v.js.call(engine, keys, object, &.{value}); defer engine.freeValue(names);
        const length = try v.js.get(engine, names, "length"); defer engine.freeValue(length);
        const positive = try engine.checked(c.JS_PiBinaryOperator(engine.context, 6, length, c.JS_NewInt32(engine.context, 0))); defer engine.freeValue(positive);
        populated = c.JS_ToBool(engine.context, positive) != 0;
    }
    if (!populated) return c.pi_js_undefined();
    const value = try v.js.get(engine, opts, "alias"); defer engine.freeValue(value);
    const fallback = if (c.JS_ToBool(engine.context, value) != 0) c.JS_DupValue(engine.context, value) else try v.js.object(engine); defer engine.freeValue(fallback);
    return v.js.call(engine, imports.normalize_aliases, c.pi_js_undefined(), &.{fallback});
}
fn tsconfigMatcher(engine: *v.em.Engine, imports: Imports, filename: c.JSValue, opts: c.JSValue) !c.JSValue {
    const enabled = try v.js.get(engine, opts, "tsconfigPaths");
    const active = c.JS_ToBool(engine.context, enabled) != 0; engine.freeValue(enabled);
    if (!active) return c.pi_js_undefined();
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const helpers = try s.call(imports.library_require, c.pi_js_undefined(), &.{try s.text("get-tsconfig")});
    const get = try s.get(helpers, "getTsconfig"); const matcher = try s.get(helpers, "createPathsMatcher");
    const search = if (c.JS_IsString(try s.get(opts, "tsconfigPaths"))) try s.get(opts, "tsconfigPaths") else try s.call(imports.pathe_dirname, c.pi_js_undefined(), &.{filename});
    const config = try s.call(get, c.pi_js_undefined(), &.{search});
    return if (s.truthy(config)) v.js.call(engine, matcher, c.pi_js_undefined(), &.{config}) else c.pi_js_undefined();
}
/// Owned actual jiti instance. is_windows is the real Source module's platform
/// capture, initialized only after complete real import linking.
pub fn instantiate(engine: *v.em.Engine, imports: Imports, is_windows: bool, args: []const c.JSValue) !c.JSValue {
    try validate(engine, imports);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var filename = arg(args, 0);
    const user_options = if (c.JS_IsUndefined(arg(args, 1))) try s.object() else arg(args, 1);
    const parent_context = arg(args, 2);
    const nested = s.truthy(arg(args, 3));
    const opts = if (nested) user_options else try s.call(imports.resolve_options, c.pi_js_undefined(), &.{user_options});
    if (c.JS_IsString(filename) and s.truthy(try s.invoke(filename, "startsWith", &.{try s.text("file://")}))) filename = try s.call(imports.file_url_to_path, c.pi_js_undefined(), &.{filename});
    const alias = try s.own(try aliases(engine, imports, opts));
    const paths_matcher = try s.own(try tsconfigMatcher(engine, imports, filename, opts));
    const native_modules = try s.own(try literal(engine, &.{ try s.text("typescript"), try s.text("jiti") }));
    try spreadOption(engine, native_modules, opts, "nativeModules", imports.iterator_symbol, 2, true);
    const native_re = try s.own(try regexp(engine, native_modules, imports.escape_string_regexp));
    const transform_modules = try s.array();
    try spreadOption(engine, transform_modules, opts, "transformModules", imports.iterator_symbol, 0, true);
    const transform_re = try s.own(try regexp(engine, transform_modules, imports.escape_string_regexp));
    if (!s.truthy(filename)) filename = try s.invoke(try s.global("process"), "cwd", &.{});
    if (!nested and s.truthy(try s.call(imports.is_dir, c.pi_js_undefined(), &.{filename}))) filename = try s.call(imports.pathe_join, c.pi_js_undefined(), &.{ filename, try s.text("_index.js") });
    const url = try s.call(imports.path_to_file_url, c.pi_js_undefined(), &.{filename});
    const additional = try s.own(try additionalFromOptions(engine, opts, imports.iterator_symbol));
    const create_require = try s.get(parent_context, "createRequire");
    var require_filename = filename;
    if (is_windows) {
        const replace = try s.get(filename, "replace");
        const slash = try s.own(try slashRegexp(engine));
        require_filename = try s.call(replace, filename, &.{ slash, try s.text("\\") });
    }
    const native_require = try s.call(create_require, parent_context, &.{require_filename});
    const context = try s.object();
    inline for (.{ .{ "filename", filename }, .{ "url", url }, .{ "opts", opts }, .{ "alias", alias }, .{ "resolveTsConfigPaths", paths_matcher }, .{ "nativeModules", native_modules }, .{ "transformModules", transform_modules }, .{ "isNativeRe", native_re }, .{ "isTransformRe", transform_re }, .{ "additionalExts", additional }, .{ "nativeRequire", native_require } }) |entry| try put(engine, context, entry[0], entry[1]);
    inline for (.{ "onError", "parentModule", "parentCache", "nativeImport", "createRequire" }) |name| try put(engine, context, name, try s.get(parent_context, name));
    if (!nested) { try debugInit(engine, imports, context, opts); try ignored(engine, imports.prepare_cache_dir, c.pi_js_undefined(), &.{context}); }
    const owner = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.JS_NULL)));
    inline for (.{ .{ "context", context }, .{ "url", url }, .{ "require", imports.jiti_require }, .{ "resolve", imports.jiti_resolve }, .{ "transform", imports.transform }, .{ "evalModule", imports.eval_module }, .{ "pathToFileURL", imports.path_to_file_url } }) |entry| try put(engine, owner, entry[0], entry[1]);
    // Source retrieves outer Object.assign before building either argument.
    const object = try s.global("Object"); const assign = try s.get(object, "assign");
    const jiti = try s.own(try functions.create(engine, "jiti", 1, true, requireCall, &.{owner}));
    const properties = try s.object();
    const cache = if (s.truthy(try s.get(opts, "moduleCache"))) try s.get(native_require, "cache") else try s.invoke(try s.global("Object"), "create", &.{c.JS_NULL});
    try put(engine, properties, "cache", cache);
    try put(engine, properties, "extensions", try s.get(native_require, "extensions"));
    try put(engine, properties, "main", try s.get(native_require, "main"));
    try put(engine, properties, "options", opts);
    const resolve_object = try s.global("Object"); const resolve_assign = try s.get(resolve_object, "assign");
    const resolve = try s.own(try functions.create(engine, "resolve", 2, true, resolveCall, &.{owner}));
    const resolve_properties = try s.object(); try put(engine, resolve_properties, "paths", try s.get(try s.get(native_require, "resolve"), "paths"));
    try put(engine, properties, "resolve", try s.call(resolve_assign, resolve_object, &.{ resolve, resolve_properties }));
    try put(engine, properties, "transform", try s.own(try functions.create(engine, "transform", 1, false, transformCall, &.{owner})));
    try put(engine, properties, "evalModule", try s.own(try functions.create(engine, "evalModule", 2, false, evalCall, &.{owner})));
    try put(engine, properties, "import", try s.own(try @import("native_jiti_import.zig").create(engine, context, imports.jiti_require)));
    try put(engine, properties, "esmResolve", try s.own(try functions.create(engine, "esmResolve", 2, false, esmResolveCall, &.{owner})));
    return v.js.call(engine, assign, object, &.{ jiti, properties });
}
fn slashRegexp(engine: *v.em.Engine) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const args = [_]c.JSValue{ try s.text("/"), try s.text("g") };
    return engine.checked(c.JS_CallConstructor(engine.context, engine.intrinsic_regexp_constructor, 2, @constCast(&args)));
}
fn additionalExtension(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return c.pi_js_bool(engine.context, @intFromBool(!c.JS_IsStrictEqual(engine.context, arg(args, 0), roots[0])));
}
fn dispatch(engine: *v.em.Engine, owner: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return v.js.call(engine, try s.get(owner, name), c.pi_js_undefined(), args);
}
fn requireCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const options = try s.object(); try put(engine, options, "async", c.pi_js_bool(engine.context, 0));
    return dispatch(engine, roots[0], "require", &.{ try s.get(roots[0], "context"), arg(args, 0), options });
}
fn resolveCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const options = try s.object(); try v.js.spreadInto(engine, options, arg(args, 1)); try put(engine, options, "async", c.pi_js_bool(engine.context, 0));
    return dispatch(engine, roots[0], "resolve", &.{ try s.get(roots[0], "context"), arg(args, 0), options });
}
fn transformCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return dispatch(engine, roots[0], "transform", &.{ try s.get(roots[0], "context"), arg(args, 0) });
}
fn evalCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    return dispatch(engine, roots[0], "evalModule", &.{ try s.get(roots[0], "context"), arg(args, 0), arg(args, 1) });
}
fn esmResolveCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    var requested = arg(args, 1);
    if (c.JS_IsString(requested)) { const options = try s.object(); try put(engine, options, "parentURL", requested); requested = options; }
    const options = try s.object(); try put(engine, options, "parentURL", try s.get(roots[0], "url"));
    try v.js.spreadInto(engine, options, requested); try put(engine, options, "async", c.pi_js_bool(engine.context, 1));
    const resolved = try s.own(try dispatch(engine, roots[0], "resolve", &.{ try s.get(roots[0], "context"), arg(args, 0), options }));
    if (!s.truthy(resolved) or !c.JS_IsString(resolved) or s.truthy(try s.invoke(resolved, "startsWith", &.{try s.text("file://")}))) return c.JS_DupValue(engine.context, resolved);
    return dispatch(engine, roots[0], "pathToFileURL", &.{resolved});
}
