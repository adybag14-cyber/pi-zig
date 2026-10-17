//! get-tsconfig 4.14.0 resolve-extends-path, including actual optional PnP hooks.
const h = @import("native_tsconfig_values.zig");
const c = h.c;
const Scope = h.Scope;
fn fromPackage(engine: *h.v.em.Engine, state: c.JSValue, file: c.JSValue, subpath: c.JSValue, ignore: bool, cache: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const key = try s.concat(try s.text("resolveFromPackageJsonPath:"), try s.invoke(try h.array(&s, &.{ file, subpath, c.pi_js_bool(engine.context, @intFromBool(ignore)) }), "join", &.{try s.text(":")}));
    if (s.truthy(try s.invoke(cache, "has", &.{key}))) return h.v.js.invoke(engine, cache, "get", &.{key});
    const package = try h.read(&s, state, cache, file); if (!s.truthy(package)) return c.pi_js_undefined();
    var resolved = if (s.truthy(subpath)) subpath else try s.text("tsconfig.json");
    const exports = if (!ignore) try s.get(package, "exports") else c.pi_js_undefined();
    if (!ignore and s.truthy(exports)) {
        const generation = engine.native_allocation_generation;
        const values = @import("native_tsconfig_package_exports.zig").resolve(engine, state, exports, subpath) catch |err| {
            try h.ordinary(engine, err, generation); return c.pi_js_bool(engine.context, 0);
        };
        const held = try s.own(values); resolved = try h.at(&s, held, 0);
    } else if (!s.truthy(subpath)) {
        const config = try s.get(package, "tsconfig"); if (s.truthy(config)) resolved = config;
    }
    resolved = try h.path(&s, state, "join", &.{ file, try s.text(".."), resolved });
    _ = try s.invoke(cache, "set", &.{ key, resolved }); return c.JS_DupValue(engine.context, resolved);
}
fn withPnp(engine: *h.v.em.Engine, state: c.JSValue, resolve_request: c.JSValue, package_name: c.JSValue, requested: c.JSValue, directory: c.JSValue, subpath: c.JSValue, cache: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    if (s.equal(package_name, requested)) {
        const file = try s.call(resolve_request, c.pi_js_undefined(), &.{ try h.path(&s, state, "join", &.{ package_name, try s.text("package.json") }), directory });
        if (s.truthy(file)) {
            const resolved = try s.own(try fromPackage(engine, state, file, subpath, false, cache));
            if (s.truthy(resolved) and try h.exists(&s, state, cache, resolved)) return c.JS_DupValue(engine.context, resolved);
        }
    } else {
        const options = try s.object(); try s.put(options, "extensions", try h.array(&s, &.{try s.text(".json")}));
        const generation = engine.native_allocation_generation;
        const resolved = s.call(resolve_request, c.pi_js_undefined(), &.{ requested, directory, options }) catch |err| blk: {
            try h.ordinary(engine, err, generation);
            break :blk try s.call(resolve_request, c.pi_js_undefined(), &.{ try h.path(&s, state, "join", &.{ requested, try s.text("tsconfig.json") }), directory });
        };
        if (s.truthy(resolved)) return c.JS_DupValue(engine.context, resolved);
    }
    return c.pi_js_undefined();
}
pub fn resolve(engine: *h.v.em.Engine, state: c.JSValue, requested: c.JSValue, directory: c.JSValue, cache: c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var file = requested;
    if (try h.eq(&s, requested, "..")) file = try h.path(&s, state, "join", &.{ file, try s.text("tsconfig.json") });
    if (try h.eq(&s, try h.at(&s, requested, 0), ".")) file = try h.path(&s, state, "resolve", &.{ directory, file });
    if (s.truthy(try h.path(&s, state, "isAbsolute", &.{file}))) {
        if (try h.exists(&s, state, cache, file)) {
            if (try h.isKind(&s, state, cache, file, "isFile")) return c.JS_DupValue(engine.context, file);
        } else if (!s.truthy(try s.invoke(file, "endsWith", &.{try s.text(".json")}))) {
            const json = try s.concat(file, try s.text(".json")); if (try h.exists(&s, state, cache, json)) return c.JS_DupValue(engine.context, json);
        }
        return c.pi_js_undefined();
    }
    const parts = try s.invoke(requested, "split", &.{try s.text("/")});
    const org = try s.invoke(parts, "shift", &.{});
    const package = if (try h.eq(&s, try h.at(&s, org, 0), "@")) try s.concat(try s.concat(try s.stringify(org), try s.text("/")), try s.stringify(try s.invoke(parts, "shift", &.{}))) else org;
    const subpath = try s.invoke(parts, "join", &.{try s.text("/")});
    const pnp_function = try s.get(try s.get(state, "module"), "findPnpApi");
    const pnp = if (s.truthy(pnp_function)) try s.call(pnp_function, c.pi_js_undefined(), &.{try s.invoke(try s.get(state, "process"), "cwd", &.{})}) else pnp_function;
    if (s.truthy(pnp)) {
        const generation = engine.native_allocation_generation;
        const found = withPnp(engine, state, try s.get(pnp, "resolveRequest"), package, requested, directory, subpath, cache) catch |err| blk: {
            try h.ordinary(engine, err, generation); break :blk c.pi_js_undefined();
        };
        if (!c.JS_IsUndefined(found)) return found;
    }
    const package_path = try s.own(try h.findUp(engine, state, try h.path(&s, state, "resolve", &.{directory}), try h.path(&s, state, "join", &.{ try s.text("node_modules"), package }), cache));
    if (!s.truthy(package_path) or !try h.isKind(&s, state, cache, package_path, "isDirectory")) return c.pi_js_undefined();
    const package_json = try h.path(&s, state, "join", &.{ package_path, try s.text("package.json") });
    if (try h.exists(&s, state, cache, package_json)) {
        const resolved = try s.own(try fromPackage(engine, state, package_json, subpath, false, cache));
        if (s.equal(resolved, c.pi_js_bool(engine.context, 0))) return c.pi_js_undefined();
        if (s.truthy(resolved) and try h.exists(&s, state, cache, resolved) and try h.isKind(&s, state, cache, resolved, "isFile")) return c.JS_DupValue(engine.context, resolved);
    }
    const full = try h.path(&s, state, "join", &.{ package_path, subpath });
    const json_extension = s.truthy(try s.invoke(full, "endsWith", &.{try s.text(".json")}));
    if (!json_extension) {
        const json = try s.concat(full, try s.text(".json")); if (try h.exists(&s, state, cache, json)) return c.JS_DupValue(engine.context, json);
    }
    if (!try h.exists(&s, state, cache, full)) return c.pi_js_undefined();
    if (try h.isKind(&s, state, cache, full, "isDirectory")) {
        const package_file = try h.path(&s, state, "join", &.{ full, try s.text("package.json") });
        if (try h.exists(&s, state, cache, package_file)) {
            const resolved = try s.own(try fromPackage(engine, state, package_file, try s.text(""), true, cache));
            if (s.truthy(resolved) and try h.exists(&s, state, cache, resolved)) return c.JS_DupValue(engine.context, resolved);
        }
        const config_file = try h.path(&s, state, "join", &.{ full, try s.text("tsconfig.json") });
        if (try h.exists(&s, state, cache, config_file)) return c.JS_DupValue(engine.context, config_file);
    } else if (json_extension) return c.JS_DupValue(engine.context, full);
    return c.pi_js_undefined();
}
