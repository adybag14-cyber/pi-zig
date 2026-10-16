//! Actual class resource/filter/manifest callers. Required discovery and
//! pattern functions must be concrete native Source implementations; absent
//! helpers are rejected rather than replaced by empty resource arrays.
const data = @import("native_sdk_package_data.zig");
const v = @import("native_ai_provider_values.zig");
const package_catch = @import("native_sdk_package_catch.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Inputs = struct { paths: c.JSValue, filesystem: c.JSValue, helpers: c.JSValue };
pub const methods = .{ "collectPackageResources", "collectDefaultResources", "applyPackageFilter", "applyPackageDeltaFilter", "collectManifestFiles", "addManifestEntries", "collectFilesFromManifestEntries", "resolveLocalEntries", "collectFilesFromPaths", "resolveLocalExtensionSource" };
const Method = enum(i32) { collectPackageResources, collectDefaultResources, applyPackageFilter, applyPackageDeltaFilter, collectManifestFiles, addManifestEntries, collectFilesFromManifestEntries, resolveLocalEntries, collectFilesFromPaths, resolveLocalExtensionSource };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn required(s: *Scope, target: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void { inline for (names) |name| { const function = try s.get(namespace, name); if (!c.JS_IsFunction(s.engine.context, function)) return error.RequiredActualPackageResourceImport; try data.put(s.engine, target, name, function); } }
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try required(&s, imports, inputs.paths, .{ "join", "dirname", "resolve" }); try required(&s, imports, inputs.filesystem, .{ "existsSync", "statSync" });
    try required(&s, imports, inputs.helpers, .{ "readPiManifest", "collectResourceFiles", "applyPatterns", "applyAutoloadDisabledPatterns", "isOverridePattern", "hasGlobPattern", "expandPackageGlob", "splitPatterns" });
    const types = try s.array(); inline for (.{ "extensions", "skills", "prompts", "themes" }, 0..) |name, index| try s.index(types, index, try s.text(name)); try data.put(s.engine, imports, "types", types);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) { .collectManifestFiles, .collectFilesFromPaths => 2, .collectFilesFromManifestEntries => 3, .collectPackageResources, .collectDefaultResources => 4, else => 5 };
        const function = try s.own(try f.createMethod(engine, field.name, length, method, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, function), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn exists(s: *Scope, imports: c.JSValue, path: c.JSValue) !bool { return s.truthy(try imported(s, imports, "existsSync", &.{path})); }
fn manifestEntries(s: *Scope, imports: c.JSValue, root: c.JSValue, kind: c.JSValue) !c.JSValue { const manifest = try imported(s, imports, "readPiManifest", &.{try imported(s, imports, "join", &.{ root, try s.text("package.json") })}); return if (v.nullish(manifest)) c.pi_js_undefined() else s.own(try v.js.getKey(s.engine, manifest, kind)); }
fn pushSpread(s: *Scope, target: c.JSValue, push: c.JSValue, values: c.JSValue) !void {
    var arguments: @import("std").ArrayList(c.JSValue) = .empty;
    defer { for (arguments.items) |value| s.engine.freeValue(value); arguments.deinit(s.engine.gpa); }
    var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |value| arguments.append(s.engine.gpa, value) catch |err| { s.engine.freeValue(value); return err; };
    _ = try s.call(push, target, arguments.items);
}
fn add(s: *Scope, manager: c.JSValue, files: c.JSValue, target: c.JSValue, metadata: c.JSValue, enabled_set: ?c.JSValue, all: ?bool) !void {
    var iterator = try v.iterator(s, files); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |path| {
        defer s.engine.freeValue(path); const function = try s.get(manager, "addResource");
        const enabled = if (all) |value| c.pi_js_bool(s.engine.context, @intFromBool(value)) else try s.invoke(enabled_set.?, "has", &.{path});
        _ = try s.call(function, manager, &.{ target, path, metadata, enabled });
    }
}
fn defaults(s: *Scope, manager: c.JSValue, imports: c.JSValue, root: c.JSValue, kind: c.JSValue, target: c.JSValue, metadata: c.JSValue) !void {
    const entries = try manifestEntries(s, imports, root, kind);
    if (s.truthy(entries)) { _ = try s.invoke(manager, "addManifestEntries", &.{ entries, root, kind, target, metadata }); return; }
    const dir = try imported(s, imports, "join", &.{ root, kind }); if (try exists(s, imports, dir)) try add(s, manager, try imported(s, imports, "collectResourceFiles", &.{ dir, kind }), target, metadata, null, true);
}
fn packageResources(s: *Scope, manager: c.JSValue, imports: c.JSValue, root: c.JSValue, accumulator: c.JSValue, filter: c.JSValue, metadata: c.JSValue) !c.JSValue {
    if (s.truthy(filter)) {
        var types = try v.iterator(s, try s.get(imports, "types")); defer types.deinit(); errdefer types.closePreserving(); while (try types.next()) |kind| {
            defer s.engine.freeValue(kind); const patterns = try s.own(try v.js.getKey(s.engine, filter, kind)); const target = try s.invoke(manager, "getTargetMap", &.{ accumulator, kind });
            if (s.equal(try s.get(filter, "autoload"), c.pi_js_bool(s.engine.context, 0))) _ = try s.invoke(manager, "applyPackageDeltaFilter", &.{ root, if (v.nullish(patterns)) try s.array() else patterns, kind, target, metadata }) else if (!c.JS_IsUndefined(patterns)) _ = try s.invoke(manager, "applyPackageFilter", &.{ root, patterns, kind, target, metadata }) else _ = try s.invoke(manager, "collectDefaultResources", &.{ root, kind, target, metadata });
        }
        return c.pi_js_bool(s.engine.context, 1);
    }
    const manifest = try imported(s, imports, "readPiManifest", &.{try imported(s, imports, "join", &.{ root, try s.text("package.json") })});
    if (s.truthy(manifest)) {
        var types = try v.iterator(s, try s.get(imports, "types")); defer types.deinit(); errdefer types.closePreserving(); while (try types.next()) |kind| {
            defer s.engine.freeValue(kind); const entries = try s.own(try v.js.getKey(s.engine, manifest, kind)); const function = try s.get(manager, "addManifestEntries");
            _ = try s.call(function, manager, &.{ entries, root, kind, try s.invoke(manager, "getTargetMap", &.{ accumulator, kind }), metadata });
        }
        return c.pi_js_bool(s.engine.context, 1);
    }
    var found = false; var types = try v.iterator(s, try s.get(imports, "types")); defer types.deinit(); errdefer types.closePreserving(); while (try types.next()) |kind| {
        defer s.engine.freeValue(kind); const dir = try imported(s, imports, "join", &.{ root, kind }); if (!try exists(s, imports, dir)) continue;
        const files = try imported(s, imports, "collectResourceFiles", &.{ dir, kind }); var iterator = try v.iterator(s, files); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |path| { defer s.engine.freeValue(path); const function = try s.get(manager, "addResource"); const target = try s.invoke(manager, "getTargetMap", &.{ accumulator, kind }); _ = try s.call(function, manager, &.{ target, path, metadata, c.pi_js_bool(s.engine.context, 1) }); } found = true;
    }
    return c.pi_js_bool(s.engine.context, @intFromBool(found));
}
fn filtered(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue, delta: bool) !void {
    if (delta and s.equal(try s.get(arg(args, 1), "length"), c.JS_NewInt32(s.engine.context, 0))) return;
    const files = try s.get(try s.invoke(manager, "collectManifestFiles", &.{ arg(args, 0), arg(args, 2) }), "allFiles");
    if (!delta and s.equal(try s.get(arg(args, 1), "length"), c.JS_NewInt32(s.engine.context, 0))) { try add(s, manager, files, arg(args, 3), arg(args, 4), null, false); return; }
    const enabled = try imported(s, imports, if (delta) "applyAutoloadDisabledPatterns" else "applyPatterns", &.{ files, arg(args, 1), arg(args, 0) });
    if (!delta) {
        var files_iterator = try v.iterator(s, files); defer files_iterator.deinit(); errdefer files_iterator.closePreserving();
        while (try files_iterator.next()) |path| { defer s.engine.freeValue(path); const selected = try s.invoke(enabled, "has", &.{path}); _ = try s.invoke(manager, "addResource", &.{ arg(args, 3), path, arg(args, 4), selected }); }
        return;
    }
    var iterator = try v.iterator(s, enabled); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| { defer s.engine.freeValue(entry); const pair = try v.js.pair(s.engine, entry, try s.own(try s.engine.checked(c.JS_GetIteratorSymbol(s.engine.context)))); defer for (pair) |value| s.engine.freeValue(value); _ = try s.invoke(manager, "addResource", &.{ arg(args, 3), pair[0], arg(args, 4), pair[1] }); }
}
fn manifestFiles(s: *Scope, manager: c.JSValue, imports: c.JSValue, root: c.JSValue, kind: c.JSValue) !c.JSValue {
    const entries = try manifestEntries(s, imports, root, kind); const result = try s.object();
    if (s.truthy(entries) and try arithmetic.compare(s.engine, .greater, try s.get(entries, "length"), c.JS_NewInt32(s.engine.context, 0))) {
        const files = try s.invoke(manager, "collectFilesFromManifestEntries", &.{ entries, root, kind }); const patterns = try s.invoke(entries, "filter", &.{try s.get(imports, "isOverridePattern")});
        const enabled = if (try arithmetic.compare(s.engine, .greater, try s.get(patterns, "length"), c.JS_NewInt32(s.engine.context, 0))) try imported(s, imports, "applyPatterns", &.{ files, patterns, root }) else try s.own(try v.js.builtin(s.engine, "Set", &.{files}));
        try data.put(s.engine, result, "allFiles", try s.invoke(try s.global("Array"), "from", &.{enabled})); try data.put(s.engine, result, "enabledByManifest", enabled); return result;
    }
    const dir = try imported(s, imports, "join", &.{ root, kind });
    if (!try exists(s, imports, dir)) { try data.put(s.engine, result, "allFiles", try s.array()); try data.put(s.engine, result, "enabledByManifest", try s.own(try v.js.builtin(s.engine, "Set", &.{}))); return result; }
    const files = try imported(s, imports, "collectResourceFiles", &.{ dir, kind }); try data.put(s.engine, result, "allFiles", files); try data.put(s.engine, result, "enabledByManifest", try s.own(try v.js.builtin(s.engine, "Set", &.{files}))); return result;
}
fn addManifest(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue) !void {
    const entries = arg(args, 0); if (!s.truthy(entries)) return;
    const files = try s.invoke(manager, "collectFilesFromManifestEntries", &.{ entries, arg(args, 1), arg(args, 2) });
    const patterns = try s.invoke(entries, "filter", &.{try s.get(imports, "isOverridePattern")}); const enabled = try imported(s, imports, "applyPatterns", &.{ files, patterns, arg(args, 1) });
    var iterator = try v.iterator(s, files); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |path| { defer s.engine.freeValue(path); if (s.truthy(try s.invoke(enabled, "has", &.{path}))) _ = try s.invoke(manager, "addResource", &.{ arg(args, 3), path, arg(args, 4), c.pi_js_bool(s.engine.context, 1) }); }
}
fn plainEntry(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { const value = try v.js.call(engine, roots[0], c.pi_js_undefined(), &.{arg(args, 0)}); defer engine.freeValue(value); return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, value) == 0)); }
fn expandEntry(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = roots[0]; const entry = arg(args, 0);
    if (!s.truthy(try imported(&s, imports, "hasGlobPattern", &.{entry}))) { const values = try s.array(); try s.index(values, 0, try imported(&s, imports, "resolve", &.{ roots[1], entry })); return c.JS_DupValue(engine.context, values); }
    return v.js.call(engine, try s.get(imports, "expandPackageGlob"), c.pi_js_undefined(), &.{ entry, roots[1] });
}
fn fromManifest(s: *Scope, manager: c.JSValue, imports: c.JSValue, entries: c.JSValue, root: c.JSValue, kind: c.JSValue) !c.JSValue {
    const filter = try s.get(entries, "filter"); const plain = try s.own(try f.createArrow(s.engine, "", 1, plainEntry, &.{try s.get(imports, "isOverridePattern")})); const sources = try s.call(filter, entries, &.{plain});
    const flat_map = try s.get(sources, "flatMap"); const expand = try s.own(try f.createArrow(s.engine, "", 1, expandEntry, &.{ imports, root })); const paths = try s.call(flat_map, sources, &.{expand});
    return s.invoke(manager, "collectFilesFromPaths", &.{ paths, kind });
}
fn resolvePlain(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue { return v.js.invoke(engine, roots[0], "resolvePathFromBase", &.{ arg(args, 0), roots[1] }); }
fn localEntries(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue) !void {
    const entries = arg(args, 0); if (s.equal(try s.get(entries, "length"), c.JS_NewInt32(s.engine.context, 0))) return;
    const split = try imported(s, imports, "splitPatterns", &.{entries}); const plain = try s.get(split, "plain"); const patterns = try s.get(split, "patterns");
    const resolve = try s.own(try f.createArrow(s.engine, "", 1, resolvePlain, &.{ manager, arg(args, 4) })); const paths = try s.invoke(plain, "map", &.{resolve});
    const files = try s.invoke(manager, "collectFilesFromPaths", &.{ paths, arg(args, 1) }); const enabled = try imported(s, imports, "applyPatterns", &.{ files, patterns, arg(args, 4) });
    try add(s, manager, files, arg(args, 2), arg(args, 3), enabled, null);
}

fn fromPath(s: *Scope, imports: c.JSValue, files: c.JSValue, path: c.JSValue, kind: c.JSValue) !void {
    const stat = try imported(s, imports, "statSync", &.{path}); if (s.truthy(try s.invoke(stat, "isFile", &.{}))) try v.js.push(s.engine, files, path) else if (s.truthy(try s.invoke(stat, "isDirectory", &.{}))) {
        const push = try s.get(files, "push");
        try pushSpread(s, files, push, try imported(s, imports, "collectResourceFiles", &.{ path, kind }));
    }
}
fn fromPaths(s: *Scope, imports: c.JSValue, paths: c.JSValue, kind: c.JSValue) !c.JSValue {
    const files = try s.array(); var iterator = try v.iterator(s, paths); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |path| {
        defer s.engine.freeValue(path); if (!try exists(s, imports, path)) continue; const generation = s.engine.native_allocation_generation;
        fromPath(s, imports, files, path, kind) catch |err| { try package_catch.ignore(s.engine, err, generation); };
    }
    return files;
}
fn localSourceInner(s: *Scope, manager: c.JSValue, imports: c.JSValue, resolved: c.JSValue, args: []const c.JSValue) !void {
    const stat = try imported(s, imports, "statSync", &.{resolved}); const metadata = arg(args, 3);
    if (s.truthy(try s.invoke(stat, "isFile", &.{}))) { try s.set(metadata, "baseDir", try imported(s, imports, "dirname", &.{resolved})); const add_resource = try s.get(manager, "addResource"); _ = try s.call(add_resource, manager, &.{ try s.get(arg(args, 1), "extensions"), resolved, metadata, c.pi_js_bool(s.engine.context, 1) }); return; }
    if (s.truthy(try s.invoke(stat, "isDirectory", &.{}))) { try s.set(metadata, "baseDir", resolved); try s.set(metadata, "packageRoot", resolved); const resources = try s.invoke(manager, "collectPackageResources", &.{ resolved, arg(args, 1), arg(args, 2), metadata }); if (!s.truthy(resources)) { const add_resource = try s.get(manager, "addResource"); _ = try s.call(add_resource, manager, &.{ try s.get(arg(args, 1), "extensions"), resolved, metadata, c.pi_js_bool(s.engine.context, 1) }); } }
}
fn localSource(s: *Scope, manager: c.JSValue, imports: c.JSValue, args: []const c.JSValue) !void {
    const resolve = try s.get(manager, "resolvePathFromBase"); const resolved = try s.call(resolve, manager, &.{ try s.get(arg(args, 0), "path"), arg(args, 4) }); if (!try exists(s, imports, resolved)) return;
    const generation = s.engine.native_allocation_generation; localSourceInner(s, manager, imports, resolved, args) catch |err| { try package_catch.ignore(s.engine, err, generation); };
}
fn method(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const imports = roots[0];
    const result = switch (@as(Method, @enumFromInt(raw))) {
        .collectPackageResources => try packageResources(&s, manager, imports, arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3)),
        .collectDefaultResources => blk: { try defaults(&s, manager, imports, arg(args, 0), arg(args, 1), arg(args, 2), arg(args, 3)); break :blk c.pi_js_undefined(); },
        .applyPackageFilter, .applyPackageDeltaFilter => |kind| blk: { try filtered(&s, manager, imports, args, kind == .applyPackageDeltaFilter); break :blk c.pi_js_undefined(); },
        .collectManifestFiles => try manifestFiles(&s, manager, imports, arg(args, 0), arg(args, 1)), .addManifestEntries => blk: { try addManifest(&s, manager, imports, args); break :blk c.pi_js_undefined(); },
        .collectFilesFromManifestEntries => try fromManifest(&s, manager, imports, arg(args, 0), arg(args, 1), arg(args, 2)), .resolveLocalEntries => blk: { try localEntries(&s, manager, imports, args); break :blk c.pi_js_undefined(); },
        .collectFilesFromPaths => try fromPaths(&s, imports, arg(args, 0), arg(args, 1)), .resolveLocalExtensionSource => blk: { try localSource(&s, manager, imports, args); break :blk c.pi_js_undefined(); },
    }; return c.JS_DupValue(engine.context, result);
}
