//! Actual jiti2.7 cache.ts bodies. No replacement cache, host JS or fake IO.
//! Derived from jiti, Copyright Pooya Parsa, MIT; retained source/LICENSE.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = v.Scope;
const functions = @import("native_node_module_callable.zig");
const allocation = @import("native_async_body.zig");
pub const CACHE_VERSION = "9";
pub const Inputs = struct {
    exists_sync: c.JSValue,
    mkdir_sync: c.JSValue,
    read_file_sync: c.JSValue,
    write_file_sync: c.JSValue,
    tmpdir: c.JSValue,
    pathe_dirname: c.JSValue,
    pathe_join: c.JSValue,
    pathe_basename: c.JSValue,
    pathe_resolve: c.JSValue,
    pathe_filename: c.JSValue,
    debug: c.JSValue,
    is_writable: c.JSValue,
    hash: c.JSValue,
};
pub const Exports = struct {
    get_cache: c.JSValue,
    prepare_cache_dir: c.JSValue,
    get_cache_dir: c.JSValue,
    pub fn deinit(self: Exports, engine: *v.em.Engine) void {
        engine.freeValue(self.get_cache); engine.freeValue(self.prepare_cache_dir); engine.freeValue(self.get_cache_dir);
    }
};
/// Every slot is an actual native import. Missing dependency implementations
/// are supplied by their owners, never normalized to identity/no-op callbacks.
pub fn create(engine: *v.em.Engine, inputs: Inputs) !Exports {
    inline for (std.meta.fields(Inputs)) |field| if (!c.JS_IsFunction(engine.context, @field(inputs, field.name))) return error.RequiredActualJitiCacheImport;
    const roots = rootsOf(inputs);
    const directory = try functions.create(engine, "getCacheDir", 1, true, directoryCall, &roots);
    errdefer engine.freeValue(directory);
    const cached = try functions.create(engine, "getCache", 3, true, cacheCall, &roots);
    errdefer engine.freeValue(cached);
    var prepare_roots: [14]c.JSValue = undefined;
    for (roots, 0..) |value, index| prepare_roots[index] = value;
    prepare_roots[13] = directory;
    const prepare = try functions.create(engine, "prepareCacheDir", 1, true, prepareCall, &prepare_roots);
    return .{ .get_cache = cached, .prepare_cache_dir = prepare, .get_cache_dir = directory };
}
fn rootsOf(inputs: Inputs) [13]c.JSValue {
    return .{ inputs.exists_sync, inputs.mkdir_sync, inputs.read_file_sync, inputs.write_file_sync, inputs.tmpdir, inputs.pathe_dirname, inputs.pathe_join, inputs.pathe_basename, inputs.pathe_resolve, inputs.pathe_filename, inputs.debug, inputs.is_writable, inputs.hash };
}
fn fromRoots(roots: []const c.JSValue) Inputs {
    return .{ .exists_sync = roots[0], .mkdir_sync = roots[1], .read_file_sync = roots[2], .write_file_sync = roots[3], .tmpdir = roots[4], .pathe_dirname = roots[5], .pathe_join = roots[6], .pathe_basename = roots[7], .pathe_resolve = roots[8], .pathe_filename = roots[9], .debug = roots[10], .is_writable = roots[11], .hash = roots[12] };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn cacheCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return getCache(engine, fromRoots(roots), arg(args, 0), arg(args, 1), arg(args, 2));
}
fn directoryCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return getCacheDir(engine, fromRoots(roots), arg(args, 0));
}
fn prepareCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return prepareCacheDir(engine, fromRoots(roots), roots[13], arg(args, 0));
}
fn ignored(engine: *v.em.Engine, function: c.JSValue, args: []const c.JSValue) !void {
    const value = try v.js.call(engine, function, c.pi_js_undefined(), args); engine.freeValue(value);
}
/// Borrowed ctx/options/get callback; owned raw return. Cache writes do not
/// change the returned fresh code; a hit returns the stored hash-suffixed code.
pub fn getCache(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, options: c.JSValue, get: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return cacheValues(engine, inputs, context, options, get) catch |err| return exactFailure(engine, err, generation);
}
fn cacheValues(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue, options: c.JSValue, get: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (!s.truthy(try s.get(try s.get(context, "opts"), "fsCache")) or !s.truthy(try s.get(options, "filename"))) return v.js.call(engine, get, c.pi_js_undefined(), &.{});
    const source_hash = try s.concat(try s.concat(try s.text(" /* v" ++ CACHE_VERSION ++ "-"), try s.stringify(try s.call(inputs.hash, c.pi_js_undefined(), &.{ try s.get(options, "source"), c.JS_NewInt32(engine.context, 16) }))), try s.text(" */\n"));
    const parent = try s.call(inputs.pathe_dirname, c.pi_js_undefined(), &.{try s.get(options, "filename")});
    const basename = try s.stringify(try s.call(inputs.pathe_basename, c.pi_js_undefined(), &.{parent}));
    const prefix = try s.concat(basename, try s.text("-"));
    const filename = try s.stringify(try s.call(inputs.pathe_filename, c.pi_js_undefined(), &.{try s.get(options, "filename")}));
    var name = try s.concat(prefix, filename);
    name = try s.concat(name, try s.text(if (s.truthy(try s.get(try s.get(context, "opts"), "sourceMaps"))) "+map" else ""));
    name = try s.concat(name, try s.text(if (s.truthy(try s.get(options, "interopDefault"))) ".i" else ""));
    name = try s.concat(name, try s.concat(try s.text("."), try s.stringify(try s.call(inputs.hash, c.pi_js_undefined(), &.{try s.get(options, "filename")}))));
    name = try s.concat(name, try s.text(if (s.truthy(try s.get(options, "async"))) ".mjs" else ".cjs"));
    if (s.truthy(try s.get(options, "jsx")) and s.truthy(try s.invoke(try s.get(options, "filename"), "endsWith", &.{try s.text("x")}))) name = try s.concat(name, try s.text("x"));
    const directory = try s.get(try s.get(context, "opts"), "fsCache");
    const path = try s.call(inputs.pathe_join, c.pi_js_undefined(), &.{ directory, name });
    if (!s.truthy(try s.get(try s.get(context, "opts"), "rebuildFsCache")) and s.truthy(try s.call(inputs.exists_sync, c.pi_js_undefined(), &.{path}))) {
        const cached = try s.call(inputs.read_file_sync, c.pi_js_undefined(), &.{ path, try s.text("utf8") });
        if (s.truthy(try s.invoke(cached, "endsWith", &.{source_hash}))) {
            try ignored(engine, inputs.debug, &.{ context, try s.text("[cache]"), try s.text("[hit]"), try s.get(options, "filename"), try s.text("~>"), path });
            return c.JS_DupValue(engine.context, cached);
        }
    }
    try ignored(engine, inputs.debug, &.{ context, try s.text("[cache]"), try s.text("[miss]"), try s.get(options, "filename") });
    const result = try s.call(get, c.pi_js_undefined(), &.{});
    if (!s.truthy(try s.invoke(result, "includes", &.{try s.text("__JITI_ERROR__")}))) {
        try ignored(engine, inputs.write_file_sync, &.{ path, try s.concat(result, source_hash), try s.text("utf8") });
        try ignored(engine, inputs.debug, &.{ context, try s.text("[cache]"), try s.text("[store]"), try s.get(options, "filename"), try s.text("~>"), path });
    }
    return c.JS_DupValue(engine.context, result);
}
/// Borrowed real getCacheDir declaration ensures its same exported identity is
/// used internally. Source assignment evaluates its ctx.opts receiver first.
pub fn prepareCacheDir(engine: *v.em.Engine, inputs: Inputs, get_directory: c.JSValue, context: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return prepareValues(engine, inputs, get_directory, context) catch |err| return exactFailure(engine, err, generation);
}
fn prepareValues(engine: *v.em.Engine, inputs: Inputs, get_directory: c.JSValue, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.equal(try s.get(try s.get(context, "opts"), "fsCache"), c.pi_js_bool(engine.context, 1))) {
        const target = try s.get(context, "opts");
        try s.set(target, "fsCache", try s.call(get_directory, c.pi_js_undefined(), &.{context}));
    }
    if (s.truthy(try s.get(try s.get(context, "opts"), "fsCache"))) {
        const generation = engine.native_allocation_generation;
        prepareDirectory(engine, inputs, context) catch |err| {
            const reason = try s.own(try takeCaught(engine, err, generation));
            try ignored(engine, inputs.debug, &.{ context, try s.text("Error creating cache directory at "), try s.get(try s.get(context, "opts"), "fsCache"), reason });
            try s.set(try s.get(context, "opts"), "fsCache", c.pi_js_bool(engine.context, 0));
        };
    }
    return c.pi_js_undefined();
}
fn prepareDirectory(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const directory = try s.get(try s.get(context, "opts"), "fsCache");
    const options = try s.object(); try s.put(options, "recursive", c.pi_js_bool(engine.context, 1));
    try ignored(engine, inputs.mkdir_sync, &.{ directory, options });
    if (!s.truthy(try s.call(inputs.is_writable, c.pi_js_undefined(), &.{try s.get(try s.get(context, "opts"), "fsCache")}))) {
        const reason = try s.own(try v.js.builtin(engine, "Error", &.{try s.text("directory is not writable!")}));
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, reason)));
        unreachable;
    }
}
pub fn getCacheDir(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue) anyerror!c.JSValue {
    const generation = engine.native_allocation_generation;
    return directoryValues(engine, inputs, context) catch |err| return exactFailure(engine, err, generation);
}
fn directoryValues(engine: *v.em.Engine, inputs: Inputs, context: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const first_filename = try s.get(context, "filename");
    const modules = if (s.truthy(first_filename)) try s.call(inputs.pathe_resolve, c.pi_js_undefined(), &.{ try s.get(context, "filename"), try s.text("../node_modules") }) else first_filename;
    if (s.truthy(modules) and s.truthy(try s.call(inputs.exists_sync, c.pi_js_undefined(), &.{modules}))) return v.js.call(engine, inputs.pathe_join, c.pi_js_undefined(), &.{ modules, try s.text(".cache/jiti") });
    var directory = try s.call(inputs.tmpdir, c.pi_js_undefined(), &.{});
    if (s.truthy(try s.get(try s.get(try s.global("process"), "env"), "TMPDIR")) and
        s.equal(directory, try s.invoke(try s.global("process"), "cwd", &.{})) and
        !s.truthy(try s.get(try s.get(try s.global("process"), "env"), "JITI_RESPECT_TMPDIR_ENV"))) {
        const original = try s.get(try s.get(try s.global("process"), "env"), "TMPDIR");
        try v.remove(&s, try s.get(try s.global("process"), "env"), "TMPDIR");
        // Source has no try/finally: a thrown second tmpdir leaves TMPDIR
        // deleted, and restoration re-reads the live process/env receiver.
        directory = try s.call(inputs.tmpdir, c.pi_js_undefined(), &.{});
        try s.set(try s.get(try s.global("process"), "env"), "TMPDIR", original);
    }
    return v.js.call(engine, inputs.pathe_join, c.pi_js_undefined(), &.{ directory, try s.text("jiti") });
}
pub fn exactFailure(engine: *v.em.Engine, err: anyerror, generation: u64) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |reason| {
        if (c.JS_IsUncatchableError(reason)) return err;
        allocation.rethrowRecognizedAllocation(engine, reason, generation) catch |fatal| return fatal;
    };
    return err;
}
fn takeCaught(engine: *v.em.Engine, err: anyerror, generation: u64) !c.JSValue {
    if (err != error.JavaScriptException) return err;
    const reason = engine.captured_exception orelse return error.MissingActualJitiCacheReason;
    if (c.JS_IsUncatchableError(reason)) return err;
    try allocation.rethrowRecognizedAllocation(engine, reason, generation);
    engine.captured_exception = null;
    return reason;
}
