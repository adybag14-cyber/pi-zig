// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! Node24 package_json_reader read/nearest bodies over genuine native files.
//! Native read failures are cached; invalid JSON is not. All JS data and lazy
//! exports/imports remain VM-owned, and nearest results retain object identity.
const std = @import("std");
const builtin = @import("builtin");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const Scope = @import("native_node_operation_scope.zig").Scope;
const functions = @import("native_node_module_callable.zig");
const fields = @import("native_node_package_json_fields.zig");
const native_path = @import("native_node_package_path.zig");
pub const Permission = struct {
    context: ?*anyopaque = null,
    /// Null means the actual process has no Permission Model enabled.
    can_read: ?*const fn (?*anyopaque, []const u8) anyerror!bool = null,
};
const Policy = struct {
    engine: *v.em.Engine,
    permission: Permission,
    // node_modules.cc owns this cache natively; only the two deserialized
    // wrapper caches are SafeMap objects visible to primordial construction.
    files: std.StringHashMapUnmanaged(?fields.Fields) = .empty,
};
fn policy(value: c.JSValue) *Policy { return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?)); }
fn retirePolicy(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Policy = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    const engine = state.engine;
    var entries = state.files.iterator();
    while (entries.next()) |entry| {
        engine.gpa.free(entry.key_ptr.*);
        if (entry.value_ptr.*) |*config| config.deinit(engine.gpa);
    }
    state.files.deinit(engine.gpa);
    engine.gpa.destroy(state);
    c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Policy));
}
fn policyValue(s: *Scope, permission: Permission) !c.JSValue {
    if (c.pi_js_native_memory_reserve(s.engine.native_memory_owner, @sizeOf(Policy)) == 0) return error.OutOfMemory;
    var attached = false;
    errdefer if (!attached) c.pi_js_native_memory_release(s.engine.native_memory_owner, @sizeOf(Policy));
    const state = try s.engine.gpa.create(Policy);
    errdefer if (!attached) s.engine.gpa.destroy(state);
    var id: c.JSClassID = 0;
    if (c.JS_NewClassID(s.engine.runtime, &id) == 0) return error.OutOfMemory;
    const definition: c.JSClassDef = .{ .class_name = "Private filesystem permission", .finalizer = retirePolicy };
    if (c.JS_NewClass(s.engine.runtime, id, &definition) < 0) return error.OutOfMemory;
    const generation = try s.beforeAllocation();
    const result = try s.checkedAllocation(c.JS_NewObjectClass(s.engine.context, id), generation);
    state.* = .{ .engine = s.engine, .permission = permission };
    _ = c.JS_SetOpaque(result, state);
    attached = true;
    return result;
}
fn get(s: *Scope, owner: c.JSValue, map_name: [*:0]const u8, key: c.JSValue) !c.JSValue {
    const map = try s.get(owner, map_name);
    return s.call(try s.get(owner, "mapGet"), map, &.{key});
}
fn set(s: *Scope, owner: c.JSValue, map_name: [*:0]const u8, key: c.JSValue, value: c.JSValue) !void {
    const map = try s.get(owner, map_name);
    _ = try s.call(try s.get(owner, "mapSet"), map, &.{key, value});
}
fn pathCall(s: *Scope, owner: c.JSValue, method: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const paths = try s.get(owner, "paths");
    return s.call(try s.get(paths, method), paths, args);
}
fn pathBytes(s: *Scope, value: c.JSValue) ![]u8 {
    if (!c.JS_IsString(value)) return error.RequiredPrivatePackagePathString;
    const bytes = try s.engine.toString(value);
    errdefer s.engine.gpa.free(bytes);
    try s.pending();
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return error.InvalidNativePackagePath;
    return bytes;
}
fn coded(s: *Scope, name: []const u8, text: []const u8, resource: ?[]const u8) !c.JSValue {
    const generation = try s.beforeAllocation();
    const reason = try s.checkedAllocation(c.JS_NewError(s.engine.context), generation);
    try s.define(reason, "message", try s.text(text), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE);
    try s.define(reason, "code", try s.text(name), c.JS_PROP_C_W_E);
    if (resource) |path| {
        try s.define(reason, "permission", try s.text("FileSystemRead"), c.JS_PROP_C_W_E);
        try s.define(reason, "resource", try s.text(path), c.JS_PROP_C_W_E);
    }
    _ = c.JS_Throw(s.engine.context, c.JS_DupValue(s.engine.context, reason));
    try s.pending();
    return error.ActualPackageErrorDidNotEscape;
}
fn permits(s: *Scope, owner: c.JSValue, path: []const u8) !bool {
    const actual = policy(try s.get(owner, "policy")).permission;
    try s.pending();
    const allowed = if (actual.can_read) |check| try check(actual.context, path) else true;
    try s.pending();
    return allowed;
}
fn serialize(s: *Scope, normalized: c.JSValue, parsed: *const fields.Fields) !c.JSValue {
    const serial = try s.objectProto(c.pi_js_null());
    inline for (.{ "name", "main", "type", "imports", "exports" }) |field| {
        const value = if (comptime std.mem.eql(u8, field, "type"))
            try s.text(@tagName(parsed.kind))
        else if (@field(parsed.*, field)) |text| try s.text(text) else c.pi_js_undefined();
        try s.define(serial, field, value, c.JS_PROP_C_W_E);
    }
    try s.define(serial, "path", normalized, c.JS_PROP_C_W_E);
    return serial;
}
fn cacheFile(state: *Policy, path: []const u8, parsed: ?fields.Fields) !void {
    const key = try state.engine.gpa.dupe(u8, path);
    errdefer state.engine.gpa.free(key);
    try state.files.put(state.engine.gpa, key, parsed);
}
fn nativeRead(s: *Scope, owner: c.JSValue, normalized: c.JSValue) !c.JSValue {
    const path = try pathBytes(s, normalized);
    defer s.engine.gpa.free(path);
    const state = policy(try s.get(owner, "policy"));
    if (state.files.getEntry(path)) |entry| {
        if (entry.value_ptr.*) |*parsed| return serialize(s, normalized, parsed);
        return c.pi_js_null();
    }
    const io = s.engine.native_io orelse return error.ActualPackageReaderRequiresIo;
    try s.pending();
    // Node util.cc's ReadFileSync reads through EOF without a 64 MiB ceiling.
    // This is the native binding operation, with no public fs property access.
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, s.engine.gpa, .unlimited) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            try cacheFile(state, path, null);
            return c.pi_js_null();
        },
    };
    defer s.engine.gpa.free(bytes);
    var parsed = fields.parse(s.engine.gpa, bytes) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => {
            const message = try std.fmt.allocPrint(s.engine.gpa, "Invalid package config {s}.", .{path});
            defer s.engine.gpa.free(message);
            return coded(s, "ERR_INVALID_PACKAGE_CONFIG", message, null);
        },
    };
    var transferred = false;
    defer if (!transferred) parsed.deinit(s.engine.gpa);
    try cacheFile(state, path, parsed);
    transferred = true;
    // The native parsed fields are cached before the fresh VM serialization.
    return serialize(s, normalized, &parsed);
}
fn lazyCall(engine: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(lazyBody(&s, roots));
}
fn firstCharacter(engine: *v.em.Engine, value: c.JSValue, expected: []const u8) !bool {
    var s = Scope.init(engine);
    const result = firstCharacterBody(&s, value, expected);
    const yes = try s.finish(if (result) |matched| c.pi_js_bool(engine.context, @intFromBool(matched)) else |err| err);
    return c.JS_ToBool(engine.context, yes) == 1;
}
fn firstCharacterBody(s: *Scope, value: c.JSValue, expected: []const u8) !bool {
    const actual = try s.getKey(value, c.JS_NewInt32(s.engine.context, 0));
    return s.equal(actual, try s.text(expected));
}
fn lazyBody(s: *Scope, roots: []const c.JSValue) !c.JSValue {
    var value = roots[1];
    if (!c.JS_IsUndefined(value) and
        (try firstCharacter(s.engine, value, "[") or try firstCharacter(s.engine, value, "{")))
        value = try s.call(roots[2], c.pi_js_undefined(), &.{value});
    const atom = try v.js.atom(s.engine, roots[3]);
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    const result = c.JS_DefineProperty(s.engine.context, roots[0], atom, value, c.pi_js_undefined(), c.pi_js_undefined(),
        c.JS_PROP_HAS_VALUE | c.JS_PROP_HAS_ENUMERABLE | c.JS_PROP_ENUMERABLE | c.JS_PROP_HAS_WRITABLE | c.JS_PROP_HAS_CONFIGURABLE);
    try s.pending();
    if (result < 0) return error.MissingActualPackageLazyPropertyReason;
    return c.JS_DupValue(s.engine.context, value);
}
fn lazy(s: *Scope, owner: c.JSValue, data: c.JSValue, name: [*:0]const u8, plain: c.JSValue) !void {
    const getter = try s.own(try functions.create(s.engine, "get", 0, false, lazyCall, &.{data, plain, try s.get(owner, "jsonParse"), try s.text(std.mem.span(name))}));
    const atom = c.JS_NewAtom(s.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(s.engine.context, atom);
    try s.pending();
    const status = c.JS_DefinePropertyGetSet(s.engine.context, data, atom, c.JS_DupValue(s.engine.context, getter), c.pi_js_undefined(), c.JS_PROP_ENUMERABLE | c.JS_PROP_CONFIGURABLE);
    try s.pending();
    if (status < 0) return error.MissingActualPackageAccessorReason;
}
fn deserialize(s: *Scope, owner: c.JSValue, requested: c.JSValue, serial: c.JSValue) !c.JSValue {
    const data = try s.objectProto(c.pi_js_null());
    const exists = !v.nullish(serial);
    if (exists) {
        inline for (.{ "name", "main", "type" }) |name| {
            const value = try s.get(serial, name);
            if (!v.nullish(value)) try s.define(data, name, value, c.JS_PROP_C_W_E);
        }
        // Native absent fields serialize as undefined, not null. The actual
        // reader still defines both lazy enumerable fields in this case.
        try lazy(s, owner, data, "exports", try s.get(serial, "exports"));
        try lazy(s, owner, data, "imports", try s.get(serial, "imports"));
    } else try s.define(data, "type", try s.text("none"), c.JS_PROP_C_W_E);
    const result = try s.object();
    try s.define(result, "data", data, c.JS_PROP_C_W_E);
    try s.define(result, "exists", c.pi_js_bool(s.engine.context, @intFromBool(exists)), c.JS_PROP_C_W_E);
    try s.define(result, "path", if (exists) try s.get(serial, "path") else requested, c.JS_PROP_C_W_E);
    return result;
}
fn readCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(readBody(&s, roots[0], if (args.len == 0) c.pi_js_undefined() else args[0]));
}
fn readBody(s: *Scope, owner: c.JSValue, request: c.JSValue) !c.JSValue {
    const json_path = try pathCall(s, owner, "resolve", &.{request, try s.text("package.json")});
    const raw = try pathBytes(s, json_path);
    defer s.engine.gpa.free(raw);
    if (!try permits(s, owner, raw)) return coded(s, "ERR_ACCESS_DENIED", "Access to this API has been restricted. Use --allow-fs-read to manage permissions.", raw);
    // The Source readPackage wrapper above calls the real JS path.resolve.
    // Its internal binding then uses native ToNamespacedPath without another
    // public path getter, process.cwd call, or user-controlled namespace method.
    try s.pending();
    const normalized_bytes = try native_path.namespaced(s.engine.gpa, raw);
    defer s.engine.gpa.free(normalized_bytes);
    try s.pending();
    const normalized = try s.text(normalized_bytes);
    const result = try deserialize(s, owner, json_path, try nativeRead(s, owner, normalized));
    const data = try s.get(result, "data");
    const output = try s.objectProto(c.pi_js_null());
    inline for (.{ "name", "main", "type", "exports", "imports" }) |name| {
        if (try s.hasOwn(data, try s.text(name))) try s.define(output, name, try s.get(data, name), c.JS_PROP_C_W_E);
    }
    try s.define(output, "exists", try s.get(result, "exists"), c.JS_PROP_C_W_E);
    try s.define(output, "pjsonPath", try s.get(result, "path"), c.JS_PROP_C_W_E);
    return c.JS_DupValue(s.engine.context, output);
}
fn nearestCall(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(nearestBody(&s, roots[0], if (args.len == 0) c.pi_js_undefined() else args[0]));
}
fn nativeNearest(s: *Scope, owner: c.JSValue, check_path: c.JSValue) !c.JSValue {
    const original = try pathBytes(s, check_path);
    defer s.engine.gpa.free(original);
    try s.pending();
    const normalized = try native_path.namespaced(s.engine.gpa, original);
    defer s.engine.gpa.free(normalized);
    try s.pending();
    var current: []const u8 = normalized;
    const separator: u8 = if (builtin.os.tag == .windows) '\\' else '/';
    // NormalizePath restores ONLY the platform's own trailing separator after
    // ToNamespacedPath. A restored empty final component is the first parent;
    // e.g. Windows '/' alone does not activate this Source slashCheck.
    const restored_empty = original.len != 0 and original[original.len - 1] == separator and
        (normalized.len == 0 or normalized[normalized.len - 1] != separator);
    var first = true;
    var steps: usize = 0;
    while (true) {
        try @import("native_node_commonjs_interrupt.zig").step(s.engine, &steps);
        if (!(first and restored_empty)) current = native_path.parent(current, native_path.native);
        first = false;
        const parent = native_path.parent(current, native_path.native);
        if (std.mem.eql(u8, parent, current)) break;
        const generic_path = try native_path.generic(s.engine.gpa, current, native_path.native);
        defer s.engine.gpa.free(generic_path);
        if (!try permits(s, owner, generic_path)) return c.pi_js_null();
        if (std.mem.eql(u8, native_path.filename(current, native_path.native), "node_modules")) return c.pi_js_null();
        const json_bytes = try native_path.appendPackage(s.engine.gpa, current, native_path.native);
        defer s.engine.gpa.free(json_bytes);
        const serial = try nativeRead(s, owner, try s.text(json_bytes));
        if (!v.nullish(serial)) return serial;
    }
    return c.pi_js_null();
}
fn nearestBody(s: *Scope, owner: c.JSValue, check_path: c.JSValue) !c.JSValue {
    const known_path = try get(s, owner, "parents", check_path);
    if (!c.JS_IsUndefined(known_path))
        return c.JS_DupValue(s.engine.context, try get(s, owner, "deserialized", known_path));
    const config = try deserialize(s, owner, check_path, try nativeNearest(s, owner, check_path));
    const json_path = try s.get(config, "path");
    try set(s, owner, "parents", check_path, json_path);
    const known = try get(s, owner, "deserialized", json_path);
    if (!c.JS_IsUndefined(known)) return c.JS_DupValue(s.engine.context, known);
    try set(s, owner, "deserialized", json_path, config);
    return c.JS_DupValue(s.engine.context, config);
}
/// Returns one owned private namespace. The policy context, if any, must remain
/// valid until the owning Engine is destroyed, just like its real IO backend.
pub fn create(engine: *v.em.Engine, paths: c.JSValue, permission: Permission) !c.JSValue {
    var s = Scope.init(engine);
    return s.finish(createBody(&s, paths, permission));
}
fn createBody(s: *Scope, paths: c.JSValue, permission: Permission) !c.JSValue {
    try s.pending();
    const owner = try s.objectProto(c.pi_js_null());
    try s.define(owner, "paths", paths, c.JS_PROP_C_W_E);
    try s.define(owner, "policy", try policyValue(s, permission), c.JS_PROP_C_W_E);
    const safe = try s.own(try @import("native_node_fs_collections.zig").acquireSafeMap(s.engine));
    const prototype = try s.get(safe, "prototype");
    try s.define(owner, "mapGet", try s.get(prototype, "get"), c.JS_PROP_C_W_E);
    try s.define(owner, "mapSet", try s.get(prototype, "set"), c.JS_PROP_C_W_E);
    inline for (.{ "parents", "deserialized" }) |name| try s.define(owner, name, try s.construct(safe, &.{}), c.JS_PROP_C_W_E);
    const global = try s.checked(c.JS_GetGlobalObject(s.engine.context));
    try s.define(owner, "jsonParse", try s.get(try s.get(global, "JSON"), "parse"), c.JS_PROP_C_W_E);
    const result = try s.objectProto(c.pi_js_null());
    try s.define(result, "readPackage", try s.own(try functions.create(s.engine, "readPackage", 1, true, readCall, &.{owner})), c.JS_PROP_C_W_E);
    try s.define(result, "getNearestParentPackageJSON", try s.own(try functions.create(s.engine, "getNearestParentPackageJSON", 1, true, nearestCall, &.{owner})), c.JS_PROP_C_W_E);
    return c.JS_DupValue(s.engine.context, result);
}
