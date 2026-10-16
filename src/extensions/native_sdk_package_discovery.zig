//! Actual filesystem discovery callers with genuine ignore/glob/Dirent/path
//! dependencies. Recursive calls cross the native VM function boundary; there
//! is no silent depth truncation or substitute ignore/glob implementation.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const package_catch = @import("native_sdk_package_catch.zig");
const Scope = v.Scope;
const c = v.c;
const f = @import("native_node_function.zig");
const arithmetic = @import("native_image_arithmetic.zig");
pub const Inputs = struct { paths: c.JSValue, filesystem: c.JSValue, ignore: c.JSValue, read_pi_manifest: c.JSValue, homedir: c.JSValue, process: c.JSValue };
const Method = enum(i32) { prefixIgnorePattern, addIgnoreRules, collectFiles, collectSkillEntries, collectAutoSkillEntries, findGitRepoRoot, collectAncestorAgentsSkillDirs, collectAutoPromptEntries, collectAutoThemeEntries, resolveExtensionEntries, collectAutoExtensionEntries, collectResourceFiles, expandPackageGlob, getHomeDir, getExtensionTempFolder };
const Callback = enum(i32) { prefix, boolean, glob_resolve, glob_visible, visible_segment, lexical_sort };
fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn private(s: *Scope) !c.JSValue { return s.own(try s.engine.checked(c.JS_NewObjectProto(s.engine.context, c.pi_js_null()))); }
fn required(s: *Scope, target: c.JSValue, namespace: c.JSValue, comptime names: anytype) !void { inline for (names) |name| { const function = try s.get(namespace, name); if (!c.JS_IsFunction(s.engine.context, function)) return error.RequiredActualPackageDiscoveryImport; try s.put(target, name, function); } }
pub fn create(engine: *v.em.Engine, inputs: Inputs) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); const imports = try private(&s);
    try required(&s, imports, inputs.paths, .{ "join", "resolve", "relative", "dirname" }); try required(&s, imports, inputs.filesystem, .{ "existsSync", "readFileSync", "readdirSync", "statSync", "globSync", "mkdirSync", "chmodSync" });
    inline for (.{ .{ "ignore", inputs.ignore }, .{ "readPiManifest", inputs.read_pi_manifest }, .{ "homedir", inputs.homedir } }) |entry| { if (!c.JS_IsFunction(engine.context, entry[1])) return error.RequiredActualPackageDiscoveryImport; try s.put(imports, entry[0], entry[1]); }
    try s.put(imports, "process", inputs.process); try s.put(imports, "sep", try s.get(inputs.paths, "sep"));
    const patterns = try private(&s); inline for (.{ .{ "extensions", "\\.(ts|js)$" }, .{ "skills", "\\.md$" }, .{ "prompts", "\\.md$" }, .{ "themes", "\\.json$" } }) |entry| try s.put(patterns, entry[0], try regexp(&s, entry[1])); try s.put(imports, "patterns", patterns);
    const exports = try s.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) { .getHomeDir => 0, .prefixIgnorePattern, .collectFiles, .collectAutoSkillEntries, .collectResourceFiles, .expandPackageGlob => 2, .addIgnoreRules => 3, .collectSkillEntries => 4, else => 1 };
        const function = try s.own(try f.create(engine, field.name, length, method, &.{ imports, c.JS_NewInt32(engine.context, field.value) })); try s.put(exports, field.name, function);
        // Source lexical function bindings stay private and stable even when
        // the assembler inspects or exposes the returned namespace object.
        try s.put(imports, field.name, function);
    }
    return c.JS_DupValue(engine.context, exports);
}
fn regexp(s: *Scope, pattern: []const u8) !c.JSValue { var args = [_]c.JSValue{ try s.text(pattern), try s.text("") }; return s.own(try s.engine.checked(c.JS_CallConstructor(s.engine.context, s.engine.intrinsic_regexp_constructor, 2, &args))); }
fn imported(s: *Scope, imports: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue { return s.call(try s.get(imports, name), c.pi_js_undefined(), args); }
fn exists(s: *Scope, imports: c.JSValue, path: c.JSValue) !bool { return s.truthy(try imported(s, imports, "existsSync", &.{path})); }
fn starts(s: *Scope, value: c.JSValue, prefix: []const u8) !bool { return s.truthy(try s.invoke(value, "startsWith", &.{try s.text(prefix)})); }
fn posix(s: *Scope, imports: c.JSValue, path: c.JSValue) !c.JSValue { return s.invoke(try s.invoke(path, "split", &.{try s.get(imports, "sep")}), "join", &.{try s.text("/")}); }
fn dirents(s: *Scope, imports: c.JSValue, dir: c.JSValue) !c.JSValue { const options = try s.object(); try s.put(options, "withFileTypes", c.pi_js_bool(s.engine.context, 1)); return imported(s, imports, "readdirSync", &.{ dir, options }); }

const LinkFlags = struct { directory: c.JSValue, file: c.JSValue };
fn linkFlags(s: *Scope, imports: c.JSValue, path: c.JSValue, with_directory: bool) !LinkFlags {
    const stat = try imported(s, imports, "statSync", &.{path});
    const directory = if (with_directory) try s.invoke(stat, "isDirectory", &.{}) else c.pi_js_undefined();
    return .{ .directory = directory, .file = try s.invoke(stat, "isFile", &.{}) };
}
fn pushSpread(s: *Scope, array: c.JSValue, push: c.JSValue, values: c.JSValue) !void {
    var arguments: std.ArrayList(c.JSValue) = .empty; defer { for (arguments.items) |value| s.engine.freeValue(value); arguments.deinit(s.engine.gpa); }
    var iterator = try v.iterator(s, values); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |value| arguments.append(s.engine.gpa, value) catch |err| { s.engine.freeValue(value); return err; };
    _ = try s.call(push, array, arguments.items);
}
fn prefixPattern(s: *Scope, line: c.JSValue, prefix: c.JSValue) !c.JSValue {
    const trimmed = try s.invoke(line, "trim", &.{}); if (!s.truthy(trimmed)) return c.pi_js_null();
    if (try starts(s, trimmed, "#") and !try starts(s, trimmed, "\\#")) return c.pi_js_null();
    var pattern = line; var negated = false;
    if (try starts(s, pattern, "!")) { negated = true; pattern = try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)}); } else if (try starts(s, pattern, "\\!")) pattern = try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)});
    if (try starts(s, pattern, "/")) pattern = try s.invoke(pattern, "slice", &.{c.JS_NewInt32(s.engine.context, 1)});
    const prefixed = if (s.truthy(prefix)) try s.concat(try s.stringify(prefix), try s.stringify(pattern)) else pattern;
    return if (negated) s.concat(try s.text("!"), try s.stringify(prefixed)) else prefixed;
}
fn callback(s: *Scope, kind: Callback, roots: []const c.JSValue) !c.JSValue { const values = try s.engine.gpa.alloc(c.JSValue, roots.len + 1); defer s.engine.gpa.free(values); values[0] = c.JS_NewInt32(s.engine.context, @intFromEnum(kind)); @memcpy(values[1..], roots); return s.own(try f.createArrow(s.engine, "", if (kind == .lexical_sort) 2 else 1, mapped, values)); }
fn mapped(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[0]) < 0) return v.js.capture(engine); const input = arg(args, 0);
    const result = switch (@as(Callback, @enumFromInt(raw))) {
        .prefix => try prefixPattern(&s, input, roots[1]), .boolean => try s.call(try s.global("Boolean"), c.pi_js_undefined(), &.{input}),
        .glob_resolve => try imported(&s, roots[1], "resolve", &.{ roots[2], input }),
        .visible_segment => c.pi_js_bool(engine.context, @intFromBool(try v.eq(&s, input, "..") or !try starts(&s, input, "."))),
        .glob_visible => blk: { const relative = try imported(&s, roots[1], "relative", &.{ roots[2], input }); const segments = try s.invoke(relative, "split", &.{try s.get(roots[1], "sep")}); break :blk try s.invoke(segments, "every", &.{try callback(&s, .visible_segment, &.{})}); },
        .lexical_sort => c.JS_NewInt32(engine.context, if (try arithmetic.compare(engine, .less, input, arg(args, 1))) -1 else if (try arithmetic.compare(engine, .greater, input, arg(args, 1))) 1 else 0),
    }; return c.JS_DupValue(engine.context, result);
}
fn ruleFile(s: *Scope, imports: c.JSValue, matcher: c.JSValue, path: c.JSValue, prefix: c.JSValue) !void {
    const content = try imported(s, imports, "readFileSync", &.{ path, try s.text("utf-8") }); const split = try s.get(content, "split"); const lines = try s.call(split, content, &.{try regexp(s, "\\r?\\n")});
    const mapped_lines = try s.invoke(lines, "map", &.{try callback(s, .prefix, &.{prefix})}); const patterns = try s.invoke(mapped_lines, "filter", &.{try callback(s, .boolean, &.{})});
    if (try arithmetic.compare(s.engine, .greater, try s.get(patterns, "length"), c.JS_NewInt32(s.engine.context, 0))) _ = try s.invoke(matcher, "add", &.{patterns});
}
fn rules(s: *Scope, imports: c.JSValue, matcher: c.JSValue, dir: c.JSValue, root: c.JSValue) !void {
    const relative = try imported(s, imports, "relative", &.{ root, dir }); const prefix = if (s.truthy(relative)) try s.concat(try posix(s, imports, relative), try s.text("/")) else try s.text("");
    inline for (.{ ".gitignore", ".ignore", ".fdignore" }) |filename| { const path = try imported(s, imports, "join", &.{ dir, try s.text(filename) }); if (!try exists(s, imports, path)) continue; const generation = s.engine.native_allocation_generation; ruleFile(s, imports, matcher, path, prefix) catch |err| { try package_catch.ignore(s.engine, err, generation); }; }
}
fn filesInner(s: *Scope, imports: c.JSValue, dir: c.JSValue, pattern: c.JSValue, skip_modules: c.JSValue, matcher: c.JSValue, root: c.JSValue, files: c.JSValue) !void {
    var iterator = try v.iterator(s, try dirents(s, imports, dir)); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry); if (try starts(s, try s.get(entry, "name"), ".")) continue; if (s.truthy(skip_modules) and try v.eq(s, try s.get(entry, "name"), "node_modules")) continue;
        const path = try imported(s, imports, "join", &.{ dir, try s.get(entry, "name") }); var is_dir = try s.invoke(entry, "isDirectory", &.{}); var is_file = try s.invoke(entry, "isFile", &.{});
        if (s.truthy(try s.invoke(entry, "isSymbolicLink", &.{}))) {
            const generation = s.engine.native_allocation_generation; const flags = linkFlags(s, imports, path, true) catch |err| { try package_catch.ignore(s.engine, err, generation); continue; }; is_dir = flags.directory; is_file = flags.file;
        }
        const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ root, path })); const ignore_path = if (s.truthy(is_dir)) try s.concat(try s.stringify(rel), try s.text("/")) else rel;
        if (s.truthy(try s.invoke(matcher, "ignores", &.{ignore_path}))) continue;
        if (s.truthy(is_dir)) { const push = try s.get(files, "push"); try pushSpread(s, files, push, try imported(s, imports, "collectFiles", &.{ path, pattern, skip_modules, matcher, root })); } else if (s.truthy(is_file) and s.truthy(try s.invoke(pattern, "test", &.{try s.get(entry, "name")}))) try v.js.push(s.engine, files, path);
    }
}
fn files(s: *Scope, imports: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const result = try s.array(); const dir = arg(args, 0); if (!try exists(s, imports, dir)) return result;
    const root = if (v.nullish(arg(args, 4))) dir else arg(args, 4); const matcher = if (v.nullish(arg(args, 3))) try imported(s, imports, "ignore", &.{}) else arg(args, 3); const skip = if (c.JS_IsUndefined(arg(args, 2))) c.pi_js_bool(s.engine.context, 1) else arg(args, 2);
    try rules(s, imports, matcher, dir, root); const generation = s.engine.native_allocation_generation; filesInner(s, imports, dir, arg(args, 1), skip, matcher, root, result) catch |err| { try package_catch.ignore(s.engine, err, generation); }; return result;
}
fn skillsInner(s: *Scope, imports: c.JSValue, dir: c.JSValue, mode: c.JSValue, matcher: c.JSValue, root: c.JSValue, result: c.JSValue) !void {
    const entries = try dirents(s, imports, dir); var first = try v.iterator(s, entries); defer first.deinit(); errdefer first.closePreserving(); while (try first.next()) |entry| {
        defer s.engine.freeValue(entry); if (!try v.eq(s, try s.get(entry, "name"), "SKILL.md")) continue; const path = try imported(s, imports, "join", &.{ dir, try s.get(entry, "name") }); var is_file = try s.invoke(entry, "isFile", &.{});
        if (s.truthy(try s.invoke(entry, "isSymbolicLink", &.{}))) { const generation = s.engine.native_allocation_generation; const flags = linkFlags(s, imports, path, false) catch |err| { try package_catch.ignore(s.engine, err, generation); continue; }; is_file = flags.file; }
        const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ root, path })); if (s.truthy(is_file) and !s.truthy(try s.invoke(matcher, "ignores", &.{rel}))) { try v.js.push(s.engine, result, path); return; }
    }
    var iterator = try v.iterator(s, entries); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry); if (try starts(s, try s.get(entry, "name"), ".") or try v.eq(s, try s.get(entry, "name"), "node_modules")) continue; const path = try imported(s, imports, "join", &.{ dir, try s.get(entry, "name") }); var is_dir = try s.invoke(entry, "isDirectory", &.{}); var is_file = try s.invoke(entry, "isFile", &.{});
        if (s.truthy(try s.invoke(entry, "isSymbolicLink", &.{}))) { const generation = s.engine.native_allocation_generation; const flags = linkFlags(s, imports, path, true) catch |err| { try package_catch.ignore(s.engine, err, generation); continue; }; is_dir = flags.directory; is_file = flags.file; }
        const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ root, path })); const include = s.truthy(is_file) and s.truthy(try s.invoke(try s.get(entry, "name"), "endsWith", &.{try s.text(".md")})) and !s.truthy(try s.invoke(matcher, "ignores", &.{rel})) and ((try v.eq(s, mode, "pi") and s.equal(dir, root)) or (try v.eq(s, mode, "agents") and !s.equal(dir, root)));
        if (include) { try v.js.push(s.engine, result, path); continue; } if (!s.truthy(is_dir)) continue;
        if (s.truthy(try s.invoke(matcher, "ignores", &.{try s.concat(try s.stringify(rel), try s.text("/"))}))) continue;
        const push = try s.get(result, "push"); try pushSpread(s, result, push, try imported(s, imports, "collectSkillEntries", &.{ path, mode, matcher, root }));
    }
}
fn skills(s: *Scope, imports: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const result = try s.array(); const dir = arg(args, 0); if (!try exists(s, imports, dir)) return result; const root = if (v.nullish(arg(args, 3))) dir else arg(args, 3); const matcher = if (v.nullish(arg(args, 2))) try imported(s, imports, "ignore", &.{}) else arg(args, 2);
    try rules(s, imports, matcher, dir, root); const generation = s.engine.native_allocation_generation; skillsInner(s, imports, dir, arg(args, 1), matcher, root, result) catch |err| { try package_catch.ignore(s.engine, err, generation); }; return result;
}
fn simpleInner(s: *Scope, imports: c.JSValue, dir: c.JSValue, matcher: c.JSValue, result: c.JSValue, extension: []const u8) !void {
    var iterator = try v.iterator(s, try dirents(s, imports, dir)); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry); if (try starts(s, try s.get(entry, "name"), ".") or try v.eq(s, try s.get(entry, "name"), "node_modules")) continue; const path = try imported(s, imports, "join", &.{ dir, try s.get(entry, "name") }); var is_file = try s.invoke(entry, "isFile", &.{});
        if (s.truthy(try s.invoke(entry, "isSymbolicLink", &.{}))) { const generation = s.engine.native_allocation_generation; const flags = linkFlags(s, imports, path, false) catch |err| { try package_catch.ignore(s.engine, err, generation); continue; }; is_file = flags.file; }
        const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ dir, path })); if (s.truthy(try s.invoke(matcher, "ignores", &.{rel}))) continue;
        if (s.truthy(is_file) and s.truthy(try s.invoke(try s.get(entry, "name"), "endsWith", &.{try s.text(extension)}))) try v.js.push(s.engine, result, path);
    }
}
fn simple(s: *Scope, imports: c.JSValue, dir: c.JSValue, extension: []const u8) !c.JSValue {
    const result = try s.array(); if (!try exists(s, imports, dir)) return result; const matcher = try imported(s, imports, "ignore", &.{}); try rules(s, imports, matcher, dir, dir);
    const generation = s.engine.native_allocation_generation; simpleInner(s, imports, dir, matcher, result, extension) catch |err| { try package_catch.ignore(s.engine, err, generation); }; return result;
}
fn extensionEntries(s: *Scope, imports: c.JSValue, dir: c.JSValue) !c.JSValue {
    const package_path = try imported(s, imports, "join", &.{ dir, try s.text("package.json") });
    if (try exists(s, imports, package_path)) {
        const manifest = try imported(s, imports, "readPiManifest", &.{package_path}); const extensions = try v.optional(s, manifest, "extensions"); const length = try v.optional(s, extensions, "length");
        if (s.truthy(length)) { const entries = try s.array(); var iterator = try v.iterator(s, try s.get(manifest, "extensions")); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |path| { defer s.engine.freeValue(path); const resolved = try imported(s, imports, "resolve", &.{ dir, path }); if (try exists(s, imports, resolved)) try v.js.push(s.engine, entries, resolved); } if (try arithmetic.compare(s.engine, .greater, try s.get(entries, "length"), c.JS_NewInt32(s.engine.context, 0))) return entries; }
    }
    const ts = try imported(s, imports, "join", &.{ dir, try s.text("index.ts") }); const js = try imported(s, imports, "join", &.{ dir, try s.text("index.js") });
    if (try exists(s, imports, ts)) { const value = try s.array(); try s.index(value, 0, ts); return value; } if (try exists(s, imports, js)) { const value = try s.array(); try s.index(value, 0, js); return value; } return c.pi_js_null();
}
fn extensionsInner(s: *Scope, imports: c.JSValue, dir: c.JSValue, matcher: c.JSValue, result: c.JSValue) !void {
    var iterator = try v.iterator(s, try dirents(s, imports, dir)); defer iterator.deinit(); errdefer iterator.closePreserving(); while (try iterator.next()) |entry| {
        defer s.engine.freeValue(entry); if (try starts(s, try s.get(entry, "name"), ".") or try v.eq(s, try s.get(entry, "name"), "node_modules")) continue; const path = try imported(s, imports, "join", &.{ dir, try s.get(entry, "name") }); var is_dir = try s.invoke(entry, "isDirectory", &.{}); var is_file = try s.invoke(entry, "isFile", &.{});
        if (s.truthy(try s.invoke(entry, "isSymbolicLink", &.{}))) { const generation = s.engine.native_allocation_generation; const flags = linkFlags(s, imports, path, true) catch |err| { try package_catch.ignore(s.engine, err, generation); continue; }; is_dir = flags.directory; is_file = flags.file; }
        const rel = try posix(s, imports, try imported(s, imports, "relative", &.{ dir, path })); const ignored = if (s.truthy(is_dir)) try s.concat(try s.stringify(rel), try s.text("/")) else rel; if (s.truthy(try s.invoke(matcher, "ignores", &.{ignored}))) continue;
        if (s.truthy(is_file) and (s.truthy(try s.invoke(try s.get(entry, "name"), "endsWith", &.{try s.text(".ts")})) or s.truthy(try s.invoke(try s.get(entry, "name"), "endsWith", &.{try s.text(".js")})))) try v.js.push(s.engine, result, path) else if (s.truthy(is_dir)) { const resolved = try imported(s, imports, "resolveExtensionEntries", &.{path}); if (s.truthy(resolved)) { const push = try s.get(result, "push"); try pushSpread(s, result, push, resolved); } }
    }
}
fn extensions(s: *Scope, imports: c.JSValue, dir: c.JSValue) !c.JSValue {
    const result = try s.array(); if (!try exists(s, imports, dir)) return result; const root_entries = try imported(s, imports, "resolveExtensionEntries", &.{dir}); if (s.truthy(root_entries)) return root_entries;
    const matcher = try imported(s, imports, "ignore", &.{}); try rules(s, imports, matcher, dir, dir); const generation = s.engine.native_allocation_generation; extensionsInner(s, imports, dir, matcher, result) catch |err| { try package_catch.ignore(s.engine, err, generation); }; return result;
}
fn gitRoot(s: *Scope, imports: c.JSValue, start: c.JSValue) !c.JSValue { var dir = try imported(s, imports, "resolve", &.{start}); while (true) { if (try exists(s, imports, try imported(s, imports, "join", &.{ dir, try s.text(".git") }))) return dir; const parent = try imported(s, imports, "dirname", &.{dir}); if (s.equal(parent, dir)) return c.pi_js_null(); dir = parent; } }
fn ancestors(s: *Scope, imports: c.JSValue, start: c.JSValue) !c.JSValue {
    const result = try s.array(); const resolved = try imported(s, imports, "resolve", &.{start}); const git = try imported(s, imports, "findGitRepoRoot", &.{resolved}); var dir = resolved;
    while (true) { const push = try s.get(result, "push"); _ = try s.call(push, result, &.{try imported(s, imports, "join", &.{ dir, try s.text(".agents"), try s.text("skills") })}); if (s.truthy(git) and s.equal(dir, git)) break; const parent = try imported(s, imports, "dirname", &.{dir}); if (s.equal(parent, dir)) break; dir = parent; } return result;
}
fn glob(s: *Scope, imports: c.JSValue, pattern: c.JSValue, root: c.JSValue) !c.JSValue {
    const options = try s.object(); try s.put(options, "cwd", root); const values = try imported(s, imports, "globSync", &.{ pattern, options }); const resolved = try s.invoke(values, "map", &.{try callback(s, .glob_resolve, &.{ imports, root })}); const visible = try s.invoke(resolved, "filter", &.{try callback(s, .glob_visible, &.{ imports, root })}); return s.invoke(visible, "sort", &.{try callback(s, .lexical_sort, &.{})});
}
fn method(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine }; defer s.deinit(); var raw: i32 = 0; if (c.JS_ToInt32(engine.context, &raw, roots[1]) < 0) return v.js.capture(engine); const imports = roots[0]; const first = arg(args, 0);
    const result = switch (@as(Method, @enumFromInt(raw))) {
        .prefixIgnorePattern => try prefixPattern(&s, first, arg(args, 1)), .addIgnoreRules => blk: { try rules(&s, imports, first, arg(args, 1), arg(args, 2)); break :blk c.pi_js_undefined(); }, .collectFiles => try files(&s, imports, args), .collectSkillEntries => try skills(&s, imports, args), .collectAutoSkillEntries => try imported(&s, imports, "collectSkillEntries", &.{ first, arg(args, 1) }),
        .findGitRepoRoot => try gitRoot(&s, imports, first), .collectAncestorAgentsSkillDirs => try ancestors(&s, imports, first), .collectAutoPromptEntries => try simple(&s, imports, first, ".md"), .collectAutoThemeEntries => try simple(&s, imports, first, ".json"), .resolveExtensionEntries => try extensionEntries(&s, imports, first), .collectAutoExtensionEntries => try extensions(&s, imports, first),
        .collectResourceFiles => blk: { const kind = arg(args, 1); if (try v.eq(&s, kind, "skills")) break :blk try imported(&s, imports, "collectSkillEntries", &.{ first, try s.text("pi") }); if (try v.eq(&s, kind, "extensions")) break :blk try imported(&s, imports, "collectAutoExtensionEntries", &.{first}); const pattern = try s.own(try v.js.getKey(engine, try s.get(imports, "patterns"), kind)); break :blk try imported(&s, imports, "collectFiles", &.{ first, pattern }); }, .expandPackageGlob => try glob(&s, imports, first, arg(args, 1)),
        .getHomeDir => blk: { const home = try s.get(try s.get(try s.get(imports, "process"), "env"), "HOME"); break :blk if (s.truthy(home)) home else try imported(&s, imports, "homedir", &.{}); },
        .getExtensionTempFolder => blk: { const path = try imported(&s, imports, "join", &.{ first, try s.text("tmp"), try s.text("extensions") }); const options = try s.object(); try s.put(options, "recursive", c.pi_js_bool(engine.context, 1)); try s.put(options, "mode", c.JS_NewInt32(engine.context, 0o700)); _ = try imported(&s, imports, "mkdirSync", &.{ path, options }); _ = try imported(&s, imports, "chmodSync", &.{ path, c.JS_NewInt32(engine.context, 0o700) }); break :blk path; },
    }; return c.JS_DupValue(engine.context, result);
}
