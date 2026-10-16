//! Actual managed/npm/git storage layout and manifest setup. Every filesystem
//! effect and command uses the captured real platform or live class method.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
pub const Inputs = struct { paths: c.JSValue, filesystem: c.JSValue, create_hash: c.JSValue, mark_cloud_ignored: c.JSValue, strip_bom: c.JSValue, config_dir: c.JSValue };
pub const methods = .{ "getInstalledNpmVersion", "hasMissingGitDependencies", "getGitUpdateMarkerPath", "pruneEmptyGitParents", "ensureNpmProject", "ensureGitIgnore", "getNpmInstallRoot", "getGlobalNpmRoot", "getPnpmGlobalPackagePath", "getManagedNpmInstallPath", "getLegacyGlobalNpmInstallPath", "getNpmInstallPath", "getGitInstallPath", "getGitInstallRoot", "getTemporaryDir", "resolveManagedPath" };
const Method = enum(i32) { getInstalledNpmVersion, hasMissingGitDependencies, getGitUpdateMarkerPath, pruneEmptyGitParents, ensureNpmProject, ensureGitIgnore, getNpmInstallRoot, getGlobalNpmRoot, getPnpmGlobalPackagePath, getManagedNpmInstallPath, getLegacyGlobalNpmInstallPath, getNpmInstallPath, getGitInstallPath, getGitInstallRoot, getTemporaryDir, resolveManagedPath };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn required(s: *Scope, target: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void {
    inline for (names) |name| { const value = try s.get(namespace, name); if (!c.JS_IsFunction(s.engine.context, value)) return error.RequiredActualPackageStorageImport; try s.put(target, name, value); }
}
pub fn install(engine: *v.em.Engine, prototype: c.JSValue, inputs: Inputs) !void {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const imports = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try required(&s, imports, inputs.paths, .{ "join", "dirname", "basename", "resolve" });
    try required(&s, imports, inputs.filesystem, .{ "existsSync", "mkdirSync", "chmodSync", "readdirSync", "readFileSync", "rmSync", "writeFileSync" });
    inline for (.{ .{ "createHash", inputs.create_hash }, .{ "markPathIgnoredByCloudSync", inputs.mark_cloud_ignored }, .{ "stripBom", inputs.strip_bom } }) |entry| { if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackageStorageImport; try s.put(imports, entry[0], entry[1]); }
    const separator = try s.get(inputs.paths, "sep"); if (!c.JS_IsString(separator) or !c.JS_IsString(inputs.config_dir)) return error.RequiredActualPackageStorageConstants;
    try s.put(imports, "sep", separator); try s.put(imports, "configDir", inputs.config_dir);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) { .getGlobalNpmRoot => 0, .getTemporaryDir => 3, .pruneEmptyGitParents, .getNpmInstallRoot, .getManagedNpmInstallPath, .getNpmInstallPath, .getGitInstallPath => 2, else => 1 };
        const value = try s.own(try f.createMethod(engine, field.name, length, invoke, &.{ imports, c.JS_NewInt32(engine.context, field.value) }));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, c.JS_DupValue(engine.context, value), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return v.js.capture(engine);
    }
}
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn array(s: *Scope, values: []const c.JSValue) !c.JSValue { const result = try s.array(); for (values, 0..) |value, index| try s.index(result, @intCast(index), value); return result; }
fn options(s: *Scope, recursive: bool, force: bool) !c.JSValue { const result = try s.object(); if (recursive) try s.put(result, "recursive", c.pi_js_bool(s.engine.context, 1)); if (force) try s.put(result, "force", c.pi_js_bool(s.engine.context, 1)); return result; }
fn exists(s: *Scope, imports: c.JSValue, path: c.JSValue) !bool { return s.truthy(try imported(s, imports, "existsSync", &.{path})); }
fn ignored(s: *Scope, manager: c.JSValue, imports: c.JSValue, directory: c.JSValue) !void {
    if (!try exists(s, imports, directory)) _ = try imported(s, imports, "mkdirSync", &.{ directory, try options(s, true, false) });
    const path = try imported(s, imports, "join", &.{ directory, try s.text(".gitignore") });
    if (!try exists(s, imports, path)) _ = try imported(s, imports, "writeFileSync", &.{ path, try s.text("*\n!.gitignore\n"), try s.text("utf-8") });
    _ = manager;
}
fn ensureNpm(s: *Scope, manager: c.JSValue, imports: c.JSValue, root: c.JSValue) !void {
    if (!try exists(s, imports, root)) _ = try imported(s, imports, "mkdirSync", &.{ root, try options(s, true, false) });
    _ = try imported(s, imports, "markPathIgnoredByCloudSync", &.{root}); _ = try s.invoke(manager, "ensureGitIgnore", &.{root});
    const path = try imported(s, imports, "join", &.{ root, try s.text("package.json") });
    if (!try exists(s, imports, path)) {
        const value = try s.object(); try s.put(value, "name", try s.text("pi-extensions")); try s.put(value, "private", c.pi_js_bool(s.engine.context, 1));
        const write = try s.get(imports, "writeFileSync"); const text = try s.invoke(try s.global("JSON"), "stringify", &.{ value, c.pi_js_null(), c.JS_NewInt32(s.engine.context, 2) });
        _ = try s.call(write, c.pi_js_undefined(), &.{ path, text, try s.text("utf-8") });
    }
}
fn parsedManifest(s: *Scope, imports: c.JSValue, path: c.JSValue) !c.JSValue {
    const json = try s.global("JSON"); const parse = try s.get(json, "parse");
    const content = try imported(s, imports, "readFileSync", &.{ path, try s.text("utf-8") });
    const stripped = try imported(s, imports, "stripBom", &.{content}); return s.call(parse, json, &.{stripped});
}
fn installedVersion(s: *Scope, imports: c.JSValue, root: c.JSValue) !c.JSValue {
    const path = try imported(s, imports, "join", &.{ root, try s.text("package.json") }); if (!try exists(s, imports, path)) return c.pi_js_undefined();
    const generation = s.engine.native_allocation_generation;
    return versionInner(s, imports, path) catch |err| { const failure = s.engine.nativeAllocationError(err, generation); if (failure == error.OutOfMemory) return failure; return c.pi_js_undefined(); };
}
fn versionInner(s: *Scope, imports: c.JSValue, path: c.JSValue) !c.JSValue { return s.get(try parsedManifest(s, imports, path), "version"); }
fn missingDependency(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit();
    const path = try imported(&s, roots[0], "resolve", &.{ roots[1], arg(args, 0) });
    const prefix = try s.concat(try s.stringify(roots[1]), try s.stringify(try s.get(roots[0], "sep")));
    if (!s.truthy(try s.invoke(path, "startsWith", &.{prefix}))) return c.pi_js_bool(engine.context, 0);
    return c.pi_js_bool(engine.context, @intFromBool(!try exists(&s, roots[0], path)));
}
fn missingInner(s: *Scope, imports: c.JSValue, root: c.JSValue, path: c.JSValue) !c.JSValue {
    const manifest = try parsedManifest(s, imports, path);
    if (!s.truthy(try s.get(manifest, "dependencies"))) return c.pi_js_bool(s.engine.context, 0);
    const dependencies = try s.get(manifest, "dependencies");
    if (!c.JS_IsNull(dependencies) and (!c.JS_IsObject(dependencies) or c.JS_IsFunction(s.engine.context, dependencies))) return c.pi_js_bool(s.engine.context, 0);
    if (try v.array(s, try s.get(manifest, "dependencies"))) return c.pi_js_bool(s.engine.context, 0);
    const modules = try imported(s, imports, "resolve", &.{ root, try s.text("node_modules") });
    const object = try s.global("Object"); const keys = try s.invoke(object, "keys", &.{try s.get(manifest, "dependencies")});
    const callback = try s.own(try f.createArrow(s.engine, "", 1, missingDependency, &.{ imports, modules })); return s.invoke(keys, "some", &.{callback});
}
fn missing(s: *Scope, imports: c.JSValue, root: c.JSValue) !c.JSValue {
    const path = try imported(s, imports, "join", &.{ root, try s.text("package.json") }); if (!try exists(s, imports, path)) return c.pi_js_bool(s.engine.context, 0);
    const generation = s.engine.native_allocation_generation;
    return missingInner(s, imports, root, path) catch |err| { const failure = s.engine.nativeAllocationError(err, generation); if (failure == error.OutOfMemory) return failure; return c.pi_js_bool(s.engine.context, 0); };
}
fn managed(s: *Scope, imports: c.JSValue, root: c.JSValue, parts: []const c.JSValue) !c.JSValue {
    const resolved_root = try imported(s, imports, "resolve", &.{root}); const args = try s.engine.gpa.alloc(c.JSValue, parts.len + 1); defer s.engine.gpa.free(args); args[0] = resolved_root; @memcpy(args[1..], parts);
    const path = try imported(s, imports, "resolve", args);
    if (!s.equal(path, resolved_root) and !s.truthy(try s.invoke(path, "startsWith", &.{try s.concat(try s.stringify(resolved_root), try s.stringify(try s.get(imports, "sep")))}))) return v.errorText(s, try s.concat(try s.text("Refusing to use path outside package install root: "), try s.stringify(path)));
    return path;
}
fn temp(s: *Scope, manager: c.JSValue, imports: c.JSValue, prefix: c.JSValue, suffix: c.JSValue, ref: c.JSValue) !c.JSValue {
    const resolve_managed = try s.get(manager, "resolveManagedPath");
    const folder = try imported(s, imports, "join", &.{ try s.get(manager, "agentDir"), try s.text("tmp"), try s.text("extensions") });
    const mkdir_options = try options(s, true, false); try s.put(mkdir_options, "mode", c.JS_NewInt32(s.engine.context, 0o700));
    _ = try imported(s, imports, "mkdirSync", &.{ folder, mkdir_options }); _ = try imported(s, imports, "chmodSync", &.{ folder, c.JS_NewInt32(s.engine.context, 0o700) });
    const root = try s.call(resolve_managed, manager, &.{ folder, prefix });
    const hash = try imported(s, imports, "createHash", &.{try s.text("sha256")});
    const update = try s.get(hash, "update");
    const prefix_text = try s.stringify(prefix); const suffix_text = try s.stringify(if (v.nullish(suffix)) try s.text("") else suffix);
    const ref_text = if (s.truthy(ref)) try s.concat(try s.text("@"), try s.stringify(ref)) else try s.text("");
    const bytes = try s.concat(try s.concat(try s.concat(prefix_text, try s.text("-")), suffix_text), ref_text);
    const digest = try s.invoke(try s.call(update, hash, &.{bytes}), "digest", &.{try s.text("hex")}); const short = try s.invoke(digest, "slice", &.{ c.JS_NewInt32(s.engine.context, 0), c.JS_NewInt32(s.engine.context, 8) });
    return s.invoke(manager, "resolveManagedPath", &.{ root, short, if (v.nullish(suffix)) try s.text("") else suffix });
}
fn globalRoot(s: *Scope, manager: c.JSValue, imports: c.JSValue) !c.JSValue {
    const command = try s.invoke(manager, "getNpmCommand", &.{}); const values = try array(s, &.{try s.get(command, "command")});
    var iterator = try v.iterator(s, try s.get(command, "args")); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |value| { defer s.engine.freeValue(value); try s.index(values, try v.length(s, values), value); }
    const key = try s.invoke(values, "join", &.{try s.text("\x00")});
    if (s.truthy(try s.get(manager, "globalNpmRoot")) and s.equal(try s.get(manager, "globalNpmRootCommandKey"), key)) return s.get(manager, "globalNpmRoot");
    if (try v.eq(s, try s.invoke(manager, "getPackageManagerName", &.{}), "bun")) {
        const bin = try s.invoke(try s.invoke(manager, "runNpmCommandSync", &.{try array(s, &.{ try s.text("pm"), try s.text("bin"), try s.text("-g") })}), "trim", &.{});
        try s.set(manager, "globalNpmRoot", try imported(s, imports, "join", &.{ try imported(s, imports, "dirname", &.{bin}), try s.text("install"), try s.text("global"), try s.text("node_modules") }));
    } else try s.set(manager, "globalNpmRoot", try s.invoke(try s.invoke(manager, "runNpmCommandSync", &.{try array(s, &.{ try s.text("root"), try s.text("-g") })}), "trim", &.{}));
    try s.set(manager, "globalNpmRootCommandKey", key); return s.get(manager, "globalNpmRoot");
}
fn pnpmPath(s: *Scope, manager: c.JSValue, name: c.JSValue) !c.JSValue {
    if (!try v.eq(s, try s.invoke(manager, "getPackageManagerName", &.{}), "pnpm")) return c.pi_js_undefined();
    const output = try s.invoke(manager, "runNpmCommandSync", &.{try array(s, &.{ try s.text("list"), try s.text("-g"), try s.text("--depth"), try s.text("0"), try s.text("--json") })});
    const entries = try s.invoke(try s.global("JSON"), "parse", &.{output}); var iterator = try v.iterator(s, entries); defer iterator.deinit(); errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| { defer s.engine.freeValue(entry); const dependencies = try s.get(entry, "dependencies"); const value = if (v.nullish(dependencies)) c.pi_js_undefined() else try s.own(try v.js.getKey(s.engine, dependencies, name)); const path = try v.optional(s, value, "path"); if (s.truthy(path)) return path; }
    return c.pi_js_undefined();
}
fn legacy(s: *Scope, manager: c.JSValue, imports: c.JSValue, source: c.JSValue) !c.JSValue { const pnpm = try s.invoke(manager, "getPnpmGlobalPackagePath", &.{try s.get(source, "name")}); return if (!v.nullish(pnpm)) pnpm else imported(s, imports, "join", &.{ try s.invoke(manager, "getGlobalNpmRoot", &.{}), try s.get(source, "name") }); }
fn prune(s: *Scope, imports: c.JSValue, target: c.JSValue, root: c.JSValue) !void {
    if (!s.truthy(root)) return; const resolved = try imported(s, imports, "resolve", &.{root}); var current = try imported(s, imports, "dirname", &.{target});
    while (s.truthy(try s.invoke(current, "startsWith", &.{resolved})) and !s.equal(current, resolved)) {
        if (!try exists(s, imports, current)) { current = try imported(s, imports, "dirname", &.{current}); continue; }
        if (try @import("native_image_arithmetic.zig").compare(s.engine, .greater, try s.get(try imported(s, imports, "readdirSync", &.{current}), "length"), c.JS_NewInt32(s.engine.context, 0))) break;
        const generation = s.engine.native_allocation_generation;
        _ = imported(s, imports, "rmSync", &.{ current, try options(s, true, true) }) catch |err| { const failure = s.engine.nativeAllocationError(err, generation); if (failure == error.OutOfMemory) return failure; break; };
        current = try imported(s, imports, "dirname", &.{current});
    }
}
fn invoke(engine: *v.em.Engine, manager: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine);
    const imports = roots[0]; const first = arg(args, 0); const second = arg(args, 1);
    const result = switch (@as(Method, @enumFromInt(raw))) {
        .getInstalledNpmVersion => try installedVersion(&s, imports, first), .hasMissingGitDependencies => try missing(&s, imports, first),
        .getGitUpdateMarkerPath => blk: { const dir = try imported(&s, imports, "dirname", &.{first}); const name = try s.concat(try s.concat(try s.text("."), try s.stringify(try imported(&s, imports, "basename", &.{first}))), try s.text(".pi-update-incomplete")); break :blk try imported(&s, imports, "join", &.{ dir, name }); },
        .pruneEmptyGitParents => blk: { try prune(&s, imports, first, second); break :blk c.pi_js_undefined(); }, .ensureNpmProject => blk: { try ensureNpm(&s, manager, imports, first); break :blk c.pi_js_undefined(); }, .ensureGitIgnore => blk: { try ignored(&s, manager, imports, first); break :blk c.pi_js_undefined(); },
        .getNpmInstallRoot => blk: { if (s.truthy(second)) break :blk try s.invoke(manager, "getTemporaryDir", &.{try s.text("npm")}); if (try v.eq(&s, first, "project")) { _ = try s.invoke(manager, "assertProjectTrustedForScope", &.{first}); break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "cwd"), try s.get(imports, "configDir"), try s.text("npm") }); } break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "agentDir"), try s.text("npm") }); },
        .getGlobalNpmRoot => try globalRoot(&s, manager, imports), .getPnpmGlobalPackagePath => try pnpmPath(&s, manager, first),
        .getManagedNpmInstallPath => blk: { if (try v.eq(&s, second, "temporary")) break :blk try imported(&s, imports, "join", &.{ try s.invoke(manager, "getTemporaryDir", &.{try s.text("npm")}), try s.text("node_modules"), try s.get(first, "name") }); if (try v.eq(&s, second, "project")) { _ = try s.invoke(manager, "assertProjectTrustedForScope", &.{second}); break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "cwd"), try s.get(imports, "configDir"), try s.text("npm"), try s.text("node_modules"), try s.get(first, "name") }); } break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "agentDir"), try s.text("npm"), try s.text("node_modules"), try s.get(first, "name") }); },
        .getLegacyGlobalNpmInstallPath => blk: { const generation = engine.native_allocation_generation; break :blk legacy(&s, manager, imports, first) catch |err| { const failure = engine.nativeAllocationError(err, generation); if (failure == error.OutOfMemory) return failure; break :blk c.pi_js_undefined(); }; },
        .getNpmInstallPath => blk: { const path = try s.invoke(manager, "getManagedNpmInstallPath", &.{ first, second }); if (!try v.eq(&s, second, "user") or try exists(&s, imports, path)) break :blk path; const previous = try s.invoke(manager, "getLegacyGlobalNpmInstallPath", &.{first}); break :blk if (s.truthy(previous) and try exists(&s, imports, previous)) previous else path; },
        .getGitInstallPath => blk: { if (try v.eq(&s, second, "temporary")) { const get = try s.get(manager, "getTemporaryDir"); const prefix = try s.concat(try s.text("git-"), try s.stringify(try s.get(first, "host"))); break :blk try s.call(get, manager, &.{ prefix, try s.get(first, "path"), try s.get(first, "ref") }); } const root = try s.invoke(manager, "getGitInstallRoot", &.{second}); if (!s.truthy(root)) return v.errorText(&s, try s.text("Missing git install root")); break :blk try s.invoke(manager, "resolveManagedPath", &.{ root, try s.get(first, "host"), try s.get(first, "path") }); },
        .getGitInstallRoot => blk: { if (try v.eq(&s, first, "temporary")) break :blk c.pi_js_undefined(); if (try v.eq(&s, first, "project")) { _ = try s.invoke(manager, "assertProjectTrustedForScope", &.{first}); break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "cwd"), try s.get(imports, "configDir"), try s.text("git") }); } break :blk try imported(&s, imports, "join", &.{ try s.get(manager, "agentDir"), try s.text("git") }); },
        .getTemporaryDir => try temp(&s, manager, imports, first, second, arg(args, 2)), .resolveManagedPath => try managed(&s, imports, first, if (args.len > 1) args[1..] else &.{}),
    }; return c.JS_DupValue(engine.context, result);
}
