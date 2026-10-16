//! Actual Source prompt loading from default and explicit files/directories.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const flow = @import("native_agent_async.zig");
const spread = @import("native_sdk_resource_spread.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Import = enum(usize) { exists, stat, readdir, join, resolve, dirname, sep, file, config_dir };
pub fn create(engine: *em.Engine, config_dir: c.JSValue) !c.JSValue {
    const io = engine.native_io orelse return error.NativePromptsRequireIo;
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const fs = engine.native_module_values.get("node:fs").?;
    const path = engine.native_module_values.get("node:path").?;
    return @import("native_node_function.zig").create(engine, "loadPromptTemplates", 1, invoke, &.{ try scope.get(fs, "existsSync"), try scope.get(fs, "statSync"), try scope.get(fs, "readdirSync"), try scope.get(path, "join"), try scope.get(path, "resolve"), try scope.get(path, "dirname"), try scope.get(path, "sep"), try scope.own(try @import("native_sdk_prompt_file.zig").create(engine)), config_dir });
}
fn imported(scope: *Scope, roots: []const c.JSValue, kind: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(kind)], c.pi_js_undefined(), args);
}
fn iterator(scope: *Scope, values: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, values, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn appendField(scope: *Scope, target: c.JSValue, input: c.JSValue, field: [*:0]const u8) !void {
    const push = try scope.get(target, "push");
    _ = try spread.call(scope, push, target, try scope.get(input, field));
}
fn discard(scope: *Scope, err: anyerror, generation: u64) !void {
    if (scope.engine.nativeAllocationError(err, generation) == error.OutOfMemory) return error.OutOfMemory;
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
}
fn warning(scope: *Scope, diagnostics: c.JSValue, path: c.JSValue, err: anyerror, generation: u64) !void {
    const original = scope.engine.nativeAllocationError(err, generation);
    if (original == error.OutOfMemory) return original;
    const reason = try scope.own(flow.reason(scope.engine, original));
    if (scope.engine.captured_exception) |value| scope.engine.freeValue(value);
    scope.engine.captured_exception = null;
    const instance = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("Error"));
    if (instance < 0) return js.capture(scope.engine);
    const message = if (instance != 0) try scope.get(reason, "message") else try scope.text("failed to read prompt template path");
    const push = try scope.get(diagnostics, "push");
    const diagnostic = try scope.object();
    try scope.put(diagnostic, "type", try scope.text("warning"));
    try scope.put(diagnostic, "message", message);
    try scope.put(diagnostic, "path", path);
    _ = try scope.call(push, diagnostics, &.{diagnostic});
}
fn under(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, root: c.JSValue) !bool {
    const normalized = try imported(scope, roots, .resolve, &.{root});
    if (scope.equal(path, normalized)) return true;
    const sep = roots[@intFromEnum(Import.sep)];
    const prefix = if (scope.truthy(try scope.invoke(normalized, "endsWith", &.{sep}))) normalized else try scope.concat(normalized, sep);
    return scope.truthy(try scope.invoke(path, "startsWith", &.{prefix}));
}
fn sourceInfo(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, user: c.JSValue, project: c.JSValue) !c.JSValue {
    const selected = if (try under(scope, roots, path, user)) "user" else if (try under(scope, roots, path, project)) "project" else "temporary";
    const base = if (scope.equal(try scope.text(selected), try scope.text("user"))) user else if (scope.equal(try scope.text(selected), try scope.text("project"))) project else value: {
        const stats = try imported(scope, roots, .stat, &.{path});
        break :value if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) path else try imported(scope, roots, .dirname, &.{path});
    };
    const result = try scope.object();
    try scope.put(result, "path", path);
    try scope.put(result, "source", try scope.text("local"));
    try scope.put(result, "scope", try scope.text(selected));
    try scope.put(result, "origin", try scope.text("top-level"));
    try scope.put(result, "baseDir", base);
    return result;
}
fn addFile(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, user: c.JSValue, project: c.JSValue, templates: c.JSValue, diagnostics: c.JSValue) !void {
    const loaded = try imported(scope, roots, .file, &.{ path, try sourceInfo(scope, roots, path, user, project) });
    if (scope.truthy(try scope.get(loaded, "template"))) _ = try scope.invoke(templates, "push", &.{try scope.get(loaded, "template")});
    try appendField(scope, diagnostics, loaded, "diagnostics");
}
fn symlinkFile(scope: *Scope, roots: []const c.JSValue, path: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(try imported(scope, roots, .stat, &.{path}), "isFile", &.{}));
}
fn directoryBody(scope: *Scope, roots: []const c.JSValue, dir: c.JSValue, user: c.JSValue, project: c.JSValue, templates: c.JSValue, diagnostics: c.JSValue) !void {
    const options = try scope.object();
    try scope.put(options, "withFileTypes", c.pi_js_bool(scope.engine.context, 1));
    var it = try iterator(scope, try imported(scope, roots, .readdir, &.{ dir, options }));
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |entry| {
        defer scope.engine.freeValue(entry);
        const path = try imported(scope, roots, .join, &.{ dir, try scope.get(entry, "name") });
        var is_file = scope.truthy(try scope.invoke(entry, "isFile", &.{}));
        if (scope.truthy(try scope.invoke(entry, "isSymbolicLink", &.{}))) {
            const generation = scope.engine.native_allocation_generation;
            is_file = symlinkFile(scope, roots, path) catch |err| {
                try discard(scope, err, generation);
                continue;
            };
        }
        if (is_file and scope.truthy(try scope.invoke(try scope.get(entry, "name"), "endsWith", &.{try scope.text(".md")}))) try addFile(scope, roots, path, user, project, templates, diagnostics);
    }
}
fn directory(scope: *Scope, roots: []const c.JSValue, dir: c.JSValue, user: c.JSValue, project: c.JSValue) !c.JSValue {
    const templates = try scope.array();
    const diagnostics = try scope.array();
    const result = try scope.object();
    try scope.put(result, "templates", templates);
    try scope.put(result, "diagnostics", diagnostics);
    if (!scope.truthy(try imported(scope, roots, .exists, &.{dir}))) return result;
    const generation = scope.engine.native_allocation_generation;
    directoryBody(scope, roots, dir, user, project, templates, diagnostics) catch |err| try discard(scope, err, generation);
    return result;
}
fn addDirectory(scope: *Scope, roots: []const c.JSValue, dir: c.JSValue, user: c.JSValue, project: c.JSValue, templates: c.JSValue, diagnostics: c.JSValue) !void {
    const result = try directory(scope, roots, dir, user, project);
    try appendField(scope, templates, result, "templates");
    try appendField(scope, diagnostics, result, "diagnostics");
}
fn pathAttempt(scope: *Scope, roots: []const c.JSValue, path: c.JSValue, user: c.JSValue, project: c.JSValue, templates: c.JSValue, diagnostics: c.JSValue) !void {
    const stats = try imported(scope, roots, .stat, &.{path});
    if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) try addDirectory(scope, roots, path, user, project, templates, diagnostics) else if (scope.truthy(try scope.invoke(stats, "isFile", &.{})) and scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(".md")}))) try addFile(scope, roots, path, user, project, templates, diagnostics);
}
fn invoke(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const options = if (args.len > 0) args[0] else c.pi_js_undefined();
    const cwd = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "cwd"), c.pi_js_undefined(), c.pi_js_undefined()));
    const agent = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, try scope.get(options, "agentDir"), c.pi_js_undefined(), c.pi_js_undefined()));
    const paths = try scope.get(options, "promptPaths");
    const defaults = try scope.get(options, "includeDefaults");
    const templates = try scope.array();
    const diagnostics = try scope.array();
    const user = try imported(&scope, roots, .join, &.{ agent, try scope.text("prompts") });
    const project = try imported(&scope, roots, .resolve, &.{ cwd, roots[@intFromEnum(Import.config_dir)], try scope.text("prompts") });
    if (scope.truthy(defaults)) {
        try addDirectory(&scope, roots, user, user, project, templates, diagnostics);
        try addDirectory(&scope, roots, project, user, project, templates, diagnostics);
    }
    var it = try iterator(&scope, paths);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |raw| {
        defer engine.freeValue(raw);
        const resolve_options = try scope.object();
        try scope.put(resolve_options, "trim", c.pi_js_bool(engine.context, 1));
        const path = try scope.own(try @import("native_sdk_source_paths.zig").resolve(engine, raw, cwd, resolve_options));
        if (!scope.truthy(try imported(&scope, roots, .exists, &.{path}))) continue;
        const generation = engine.native_allocation_generation;
        pathAttempt(&scope, roots, path, user, project, templates, diagnostics) catch |err| try warning(&scope, diagnostics, path, err, generation);
    }
    const result = try scope.object();
    try scope.put(result, "templates", templates);
    try scope.put(result, "diagnostics", diagnostics);
    return c.JS_DupValue(engine.context, result);
}
