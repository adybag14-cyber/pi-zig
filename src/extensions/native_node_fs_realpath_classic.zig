// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Genuine fs.realpathSync caller, live encoding and component walk.
//! The actual filesystem/path objects are supplied before fs export publication.
const std = @import("std");
const builtin = @import("builtin");
const a = @import("native_node_argument_values.zig");
const c = a.c;
const Scope = a.Scope;
const functions = @import("native_node_module_callable.zig");
const walk = @import("native_node_fs_realpath_cache.zig");
const urls = @import("native_node_file_url_paths.zig");
const collections = @import("native_node_fs_collections.zig");
const publication = @import("native_node_fs_private_publication.zig");
const marker = "\x00native.fs.classicRealpath";
const EncodingFrame = a.frames.Frame(enum { as_buffer });

fn optionBody(s: *Scope, function: c.JSValue, options: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(function, c.pi_js_undefined(), &.{options}));
}
fn addEmpty(s: *Scope, path: c.JSValue) !c.JSValue {
    // Source p += '' uses generic addition's default primitive hint.
    return a.duplicate(s.engine, try s.binary(0, path, try s.text("")));
}
fn validateBody(s: *Scope, function: c.JSValue, path: c.JSValue) !c.JSValue {
    _ = try s.call(function, c.pi_js_undefined(), &.{path});
    return c.pi_js_undefined();
}
fn resolveBody(s: *Scope, paths: c.JSValue, path: c.JSValue) !c.JSValue {
    const method = try s.get(paths, "resolve");
    return a.duplicate(s.engine, try s.call(method, paths, &.{path}));
}
fn cacheBody(s: *Scope, options: c.JSValue, key: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.getKey(options, key));
}
fn encodingEqual(s: *Scope, options: c.JSValue, text: []const u8) !c.JSValue {
    return a.boolean(s, s.equal(try s.get(options, "encoding"), try s.text(text)));
}
fn bufferFrom(s: *Scope, buffer: c.JSValue, result: c.JSValue) !c.JSValue {
    return a.duplicate(s.engine, try s.call(try s.get(buffer, "from"), buffer, &.{result}));
}
fn bufferString(s: *Scope, value: c.JSValue, options: c.JSValue) !c.JSValue {
    // Callee lookup precedes the final live encoding argument read.
    const method = try s.get(value, "toString");
    const encoding = try s.get(options, "encoding");
    return a.duplicate(s.engine, try s.call(method, value, &.{encoding}));
}
fn encodeBody(s: *Scope, frame: *EncodingFrame, buffer: c.JSValue, result: c.JSValue, options: c.JSValue) !c.JSValue {
    if (!s.truthy(options) or
        !try a.condition(s.engine, a.fieldTruthy, .{options, @as([*:0]const u8, "encoding")}) or
        try a.condition(s.engine, encodingEqual, .{options, @as([]const u8, "utf8")}))
        return a.duplicate(s.engine, result);
    try frame.take(.as_buffer, a.expression(s.engine, bufferFrom, .{buffer, result}));
    if (try a.condition(s.engine, encodingEqual, .{options, @as([]const u8, "buffer")}))
        return a.duplicate(s.engine, frame.get(.as_buffer));
    return a.expression(s.engine, bufferString, .{frame.get(.as_buffer), options});
}
fn encode(engine: *a.v.em.Engine, buffer: c.JSValue, result: c.JSValue, options: c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = EncodingFrame.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, encodeBody(&s, frame, buffer, result, options));
}
fn imports(s: *Scope, owner: c.JSValue) !walk.Imports {
    var result: walk.Imports = undefined;
    inline for (std.meta.fields(walk.Imports)) |field| @field(result, field.name) = try s.get(owner, field.name);
    return result;
}
fn body(s: *Scope, frame: *walk.Activation, args: []const c.JSValue, owner: c.JSValue) !c.JSValue {
    const selected = try imports(s, owner);
    try frame.copy(.p, a.arg(args, 0));
    try frame.copy(.options, a.arg(args, 1));
    try frame.take(.options, a.expression(s.engine, optionBody, .{try s.get(owner, "get_options"), frame.get(.options)}));
    try frame.take(.p, urls.toPathValue(s.engine, try s.get(owner, "url_owner"), frame.get(.p)));
    if (!c.JS_IsString(frame.get(.p))) try frame.take(.p, a.expression(s.engine, addEmpty, .{frame.get(.p)}));
    _ = try a.expression(s.engine, validateBody, .{try s.get(owner, "validate_path"), frame.get(.p)});
    try frame.take(.p, a.expression(s.engine, resolveBody, .{selected.paths, frame.get(.p)}));
    try frame.take(.cache, a.expression(s.engine, cacheBody, .{frame.get(.options), try s.get(owner, "cache_key")}));
    const walked = try walk.walk(s.engine, frame, selected);
    if (walked.cache_hit) return walked.value;
    // p remains a live Source local through encodeRealpathResult; the returned
    // walk duplicate is a native transfer token and retires before that call.
    var selected_path = walked.value;
    s.boundary.release(&selected_path);
    try s.pending();
    return encode(s.engine, try s.get(owner, "Buffer"), frame.get(.p), frame.get(.options));
}
fn called(engine: *a.v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    const frame = walk.Activation.create(&s.values) catch |err| return s.finish(err);
    return a.finishFrame(&s, frame, body(&s, frame, args, roots[0]));
}
fn verifyInputs(s: *Scope, function: c.JSValue, fs: c.JSValue, paths: c.JSValue) !void {
    const roots = try functions.capturedRoots(s.engine, function);
    if (roots.len != 1 or !s.equal(try s.get(roots[0], "filesystem"), fs) or
        !s.equal(try s.get(roots[0], "paths"), paths))
        return error.ActualClassicRealpathOwnerConflict;
}
fn existing(s: *Scope, function: c.JSValue, fs: c.JSValue, paths: c.JSValue) !c.JSValue {
    try verifyInputs(s, function, fs, paths);
    return a.duplicate(s.engine, function);
}
fn createBody(s: *Scope, fs: c.JSValue, paths: c.JSValue) !c.JSValue {
    const native = try s.get(try s.get(fs, "realpathSync"), "native");
    if (!c.JS_IsFunction(s.engine.context, native)) return error.ActualNativeRealpathRequired;
    const path_bootstrap = try s.own(try @import("native_node_fs_path_bootstrap.zig").prepare(s.engine));
    const helpers = try s.get(path_bootstrap, "helpers");
    const url_owner = try s.own(try urls.acquire(s.engine));
    const safe_map = try s.own(try collections.acquireSafeMap(s.engine));
    const safe_set = try s.own(try collections.acquireSafeSet(s.engine));
    const stat_owner = try s.own(try @import("native_node_fs_stat_values.zig").acquire(s.engine));
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    const strings = try s.get(try s.get(global, "String"), "prototype");
    const root_regex = if (builtin.os.tag == .windows)
        try s.construct(try s.get(global, "RegExp"), &.{try s.text("^(?:[a-zA-Z]:|[\\\\/]{2}[^\\\\/]+[\\\\/][^\\\\/]+)?[\\\\/]*")})
    else c.pi_js_undefined();
    const owner = try s.objectProto(c.pi_js_null());
    try s.put(owner, "filesystem", fs);
    try s.put(owner, "paths", paths);
    try s.put(owner, "native", native);
    try s.put(owner, "get_options", try s.get(helpers, "getOptions"));
    try s.put(owner, "validate_path", try s.get(helpers, "validatePath"));
    try s.put(owner, "url_owner", url_owner);
    try s.put(owner, "Buffer", try s.get(path_bootstrap, "Buffer"));
    try s.put(owner, "cache_key", try s.get(path_bootstrap, "realpathCacheKey"));
    try s.put(owner, "safe_map", safe_map);
    try s.put(owner, "safe_set", safe_set);
    try s.put(owner, "stat_owner", stat_owner);
    try s.put(owner, "string_slice", try s.get(strings, "slice"));
    try s.put(owner, "string_index_of", try s.get(strings, "indexOf"));
    try s.put(owner, "string_char_code_at", try s.get(strings, "charCodeAt"));
    try s.put(owner, "bigint_to_string", try s.get(try s.get(try s.get(global, "BigInt"), "prototype"), "toString"));
    try s.put(owner, "number", try s.get(global, "Number"));
    try s.put(owner, "root_regex", root_regex);
    const function = try s.own(try functions.create(s.engine, "realpathSync", 2, true, called, &.{owner}));
    try s.define(function, "native", native, c.JS_PROP_C_W_E);
    return a.duplicate(s.engine, function);
}
/// Called only by the real FS assembler, before any guest/public export access.
pub fn create(engine: *a.v.em.Engine, fs: c.JSValue, paths: c.JSValue) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(marker)) |known|
        return a.expression(engine, existing, .{known, fs, paths});
    const candidate = try a.expression(engine, createBody, .{fs, paths});
    if (engine.native_module_values.get(marker)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.expression(engine, existing, .{known, fs, paths}));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, marker, candidate);
}
fn installBody(s: *Scope, fs: c.JSValue, paths: c.JSValue) !c.JSValue {
    const function = try s.own(try create(s.engine, fs, paths));
    try s.put(fs, "realpathSync", function);
    return c.pi_js_undefined();
}
pub fn install(engine: *a.v.em.Engine, fs: c.JSValue, paths: c.JSValue) !void {
    _ = try a.expression(engine, installBody, .{fs, paths});
}
pub fn requireInstalled(engine: *a.v.em.Engine, actual: c.JSValue) !void {
    try engine.checkNativeEntry();
    const known = engine.native_module_values.get(marker) orelse return error.ActualClassicRealpathNotInstalled;
    if (!c.JS_IsStrictEqual(engine.context, known, actual)) return error.ActualClassicRealpathIdentityMismatch;
}
