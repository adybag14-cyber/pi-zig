//! Source loadSkills aggregation over real native discovery and full-YAML files.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const spread = @import("native_sdk_resource_spread.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Import = enum(usize) { exists, stat, canonical, join, resolve, sep, file, agent_dir, config_dir };
pub fn create(engine: *em.Engine, config_dir: c.JSValue, get_agent_dir: c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.NativeSkillsRequireIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fs = engine.native_module_values.get("node:fs").?;
    const path = engine.native_module_values.get("node:path").?;
    const file = try scope.own(try @import("native_sdk_skill_file.zig").create(engine));
    if (!c.JS_IsFunction(engine.context, get_agent_dir)) return error.RequiredActualSkillConfiguration;
    return @import("native_node_function.zig").create(engine, "loadSkills", 1, invoke, &.{ try scope.get(fs, "existsSync"), try scope.get(fs, "statSync"), try scope.get(fs, "realpathSync"), try scope.get(path, "join"), try scope.get(path, "resolve"), try scope.get(path, "sep"), file, get_agent_dir, config_dir });
}
fn imported(scope: *Scope, roots: []const c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(kind)], c.pi_js_undefined(), args);
}
fn iterator(scope: *Scope, values: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, values, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn appendField(scope: *Scope, target: c.JSValue, from: c.JSValue, field: [*:0]const u8) !void {
    const push = try scope.get(target, "push");
    _ = try spread.call(scope, push, target, try scope.get(from, field));
}
fn warning(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, message: c.JSValue) !void {
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("warning"));
    try scope.put(row, "message", message);
    try scope.put(row, "path", path);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn discard(scope: *Scope, err: anyerror, generation: u64) !void {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
}
fn caught(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, err: anyerror, generation: u64) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    const reason = try scope.own(flow.reason(scope.engine, original));
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return js.capture(scope.engine);
    try warning(scope, diagnostics, path, if (instance != 0) try scope.get(reason, "message") else try scope.text("failed to read skill path"));
}
fn directory(scope: *Scope, roots: []const c.JSValue, dir: c.JSValue, source: c.JSValue) !c.JSValue {
    const result = try scope.object();
    const skills = try scope.array();
    const diagnostics = try scope.array();
    try scope.put(result, "skills", skills);
    try scope.put(result, "diagnostics", diagnostics);
    if (!scope.truthy(try imported(scope, roots, .exists, &.{dir}))) return result;
    const generation = scope.engine.native_allocation_generation;
    directoryBody(scope, roots, dir, source, skills, diagnostics) catch |err| try discard(scope, err, generation);
    return result;
}
fn directoryBody(scope: *Scope, roots: []const c.JSValue, dir: c.JSValue, source: c.JSValue, skills: c.JSValue, diagnostics: c.JSValue) !void {
    const stats = try imported(scope, roots, .stat, &.{dir});
    if (!scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) return;
    const raw = try scope.engine.toString(dir);
    defer scope.engine.gpa.free(raw);
    // Reuse the real ignore/symlink/skill-root discovery primitive. It does
    // not parse or silently discard invalid skill documents.
    var paths = try @import("../coding_agent/package_resources.zig").resolveSourcePath(scope.engine.gpa, scope.engine.native_io.?, raw, .skills);
    defer paths.deinit();
    for (paths.items.items) |path| {
        if (!std.mem.endsWith(u8, path, ".md")) continue;
        const loaded = try imported(scope, roots, .file, &.{ try scope.text(path), source });
        const skill = try scope.get(loaded, "skill");
        if (scope.truthy(skill)) _ = try scope.invoke(skills, "push", &.{skill});
        try appendField(scope, diagnostics, loaded, "diagnostics");
    }
}
fn canonical(scope: *Scope, roots: []const c.JSValue, path: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    return imported(scope, roots, .canonical, &.{path}) catch |err| {
        try discard(scope, err, generation);
        return path;
    };
}
fn collision(scope: *Scope, diagnostics: c.JSValue, skill: c.JSValue, existing: c.JSValue) !void {
    const push = try scope.get(diagnostics, "push");
    const row = try scope.object();
    try scope.put(row, "type", try scope.text("collision"));
    const message = try scope.concat(try scope.concat(try scope.text("name \""), try scope.stringify(try scope.get(skill, "name"))), try scope.text("\" collision"));
    try scope.put(row, "message", message);
    try scope.put(row, "path", try scope.get(skill, "filePath"));
    const details = try scope.object();
    try scope.put(details, "resourceType", try scope.text("skill"));
    try scope.put(details, "name", try scope.get(skill, "name"));
    try scope.put(details, "winnerPath", try scope.get(existing, "filePath"));
    try scope.put(details, "loserPath", try scope.get(skill, "filePath"));
    try scope.put(row, "collision", details);
    _ = try scope.call(push, diagnostics, &.{row});
}
fn add(scope: *Scope, roots: []const c.JSValue, loaded: c.JSValue, map: c.JSValue, real_paths: c.JSValue, diagnostics: c.JSValue, collisions: c.JSValue) !void {
    try appendField(scope, diagnostics, loaded, "diagnostics");
    var it = try iterator(scope, try scope.get(loaded, "skills"));
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |skill| {
        defer scope.engine.freeValue(skill);
        const real = try canonical(scope, roots, try scope.get(skill, "filePath"));
        if (scope.truthy(try scope.invoke(real_paths, "has", &.{real}))) continue;
        const existing = try scope.invoke(map, "get", &.{try scope.get(skill, "name")});
        if (scope.truthy(existing)) try collision(scope, collisions, skill, existing) else {
            _ = try scope.invoke(map, "set", &.{ try scope.get(skill, "name"), skill });
            _ = try scope.invoke(real_paths, "add", &.{real});
        }
    }
}
fn under(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, root: c.JSValue) !bool {
    const normalized = try imported(scope, roots, .resolve, &.{root});
    if (scope.equal(path, normalized)) return true;
    const sep = roots[@intFromEnum(Import.sep)];
    const prefix = if (scope.truthy(try scope.invoke(normalized, "endsWith", &.{sep}))) normalized else try scope.concat(normalized, sep);
    return scope.truthy(try scope.invoke(path, "startsWith", &.{prefix}));
}
fn loadPath(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, stats: c.JSValue, source: c.JSValue, map: c.JSValue, real_paths: c.JSValue, diagnostics: c.JSValue, collisions: c.JSValue) !void {
    if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) {
        try add(scope, roots, try directory(scope, roots, path, source), map, real_paths, diagnostics, collisions);
    } else if (scope.truthy(try scope.invoke(stats, "isFile", &.{})) and scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(".md")}))) {
        const loaded = try imported(scope, roots, .file, &.{ path, source });
        const skill = try scope.get(loaded, "skill");
        if (scope.truthy(skill)) {
            const single = try scope.object();
            const skills = try scope.array();
            try scope.index(skills, 0, skill);
            try scope.put(single, "skills", skills);
            try scope.put(single, "diagnostics", try scope.get(loaded, "diagnostics"));
            try add(scope, roots, single, map, real_paths, diagnostics, collisions);
        } else try appendField(scope, diagnostics, loaded, "diagnostics");
    } else try warning(scope, diagnostics, path, try scope.text("skill path is not a markdown file"));
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    const agent = try scope.get(options, "agentDir");
    const paths = try scope.get(options, "skillPaths");
    const defaults = try scope.get(options, "includeDefaults");
    const cwd = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined()));
    const agent_dir = if (temp.nullish(agent)) try imported(&scope, roots, .agent_dir, &.{}) else agent;
    const resolved_agent = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, agent_dir, c.pi_js_undefined(), c.pi_js_undefined()));
    const map = try scope.own(try js.builtin(engine, "Map", &.{}));
    const real_paths = try scope.own(try js.builtin(engine, "Set", &.{}));
    const diagnostics = try scope.array();
    const collisions = try scope.array();
    if (scope.truthy(defaults)) {
        const global = try imported(&scope, roots, .join, &.{ resolved_agent, try scope.text("skills") });
        try add(&scope, roots, try directory(&scope, roots, global, try scope.text("user")), map, real_paths, diagnostics, collisions);
        const project = try imported(&scope, roots, .resolve, &.{ cwd, roots[@intFromEnum(Import.config_dir)], try scope.text("skills") });
        try add(&scope, roots, try directory(&scope, roots, project, try scope.text("project")), map, real_paths, diagnostics, collisions);
    }
    const user_root = try imported(&scope, roots, .join, &.{ resolved_agent, try scope.text("skills") });
    const project_root = try imported(&scope, roots, .resolve, &.{ cwd, roots[@intFromEnum(Import.config_dir)], try scope.text("skills") });
    var it = try iterator(&scope, paths);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |raw_path| {
        defer engine.freeValue(raw_path);
        const resolve_options = try scope.object();
        try scope.put(resolve_options, "trim", c.pi_js_bool(engine.context, 1));
        const path = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, raw_path, cwd, resolve_options));
        if (!scope.truthy(try imported(&scope, roots, .exists, &.{path}))) {
            try warning(&scope, diagnostics, path, try scope.text("skill path does not exist"));
            continue;
        }
        const generation = engine.native_allocation_generation;
        pathAttempt(&scope, roots, path, defaults, user_root, project_root, map, real_paths, diagnostics, collisions) catch |err| try caught(&scope, diagnostics, path, err, generation);
    }
    const result = try scope.object();
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    try scope.put(result, "skills", try scope.call(from, array, &.{try scope.invoke(map, "values", &.{})}));
    const all_diagnostics = try scope.array();
    var diagnostic_index: u32 = 0;
    try literalSpread(&scope, all_diagnostics, diagnostics, &diagnostic_index);
    try literalSpread(&scope, all_diagnostics, collisions, &diagnostic_index);
    try scope.put(result, "diagnostics", all_diagnostics);
    return c.JS_DupValue(engine.context, result);
}
fn pathAttempt(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, defaults: c.JSValue, user_root: c.JSValue, project_root: c.JSValue, map: c.JSValue, real_paths: c.JSValue, diagnostics: c.JSValue, collisions: c.JSValue) !void {
    const stats = try imported(scope, roots, .stat, &.{path});
    var source: []const u8 = "path";
    if (!scope.truthy(defaults)) {
        if (try under(scope, roots, path, user_root)) source = "user" else if (try under(scope, roots, path, project_root)) source = "project";
    }
    try loadPath(scope, roots, path, stats, try scope.text(source), map, real_paths, diagnostics, collisions);
}
fn literalSpread(scope: *Scope, target: c.JSValue, values: c.JSValue, index: *u32) !void {
    var it = try iterator(scope, values);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |value| {
        defer scope.engine.freeValue(value);
        try scope.index(target, index.*, value);
        index.* += 1;
    }
}
