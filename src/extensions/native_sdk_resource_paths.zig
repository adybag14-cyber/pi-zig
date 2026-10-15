//! DefaultResourceLoader discovered path extension over its real native state.
//! File contents are loaded by the existing native skill, prompt and Theme
//! implementations. Source metadata is attached after synchronous overrides.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Category = enum(c_int) { skills, prompts, themes };
const categories = .{
    .{ Category.skills, "skillPaths", "lastSkillPaths", "extensionSkillSourceInfos", "skills", "skillsOverride" },
    .{ Category.prompts, "promptPaths", "lastPromptPaths", "extensionPromptSourceInfos", "prompts", "promptsOverride" },
    .{ Category.themes, "themePaths", "lastThemePaths", "extensionThemeSourceInfos", "themes", "themesOverride" },
};
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
pub fn initialize(engine: *em.Engine, data: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (categories) |category| try scope.put(data, category[2], try scope.array());
    try reset(engine, data);
}
pub fn reset(engine: *em.Engine, data: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (categories) |category| try scope.put(data, category[3], try scope.own(try js.builtin(engine, "Map", &.{})));
}
pub fn record(engine: *em.Engine, data: c.JSValue, comptime field: [*:0]const u8, paths: []const []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array();
    for (paths, 0..) |path, index| try scope.index(result, @intCast(index), try scope.text(path));
    try scope.put(data, field, result);
}
fn synthetic(scope: *Scope, path: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")})) or scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("<")}));
}
fn working(scope: *Scope, data: c.JSValue) !c.JSValue {
    const supplied = try scope.get(try scope.get(data, "options"), "cwd");
    if (!temp.nullish(supplied)) return supplied;
    const raw = try sdk.cwd(scope.engine);
    defer scope.engine.gpa.free(raw);
    return scope.text(raw);
}
fn resolve(scope: *Scope, data: c.JSValue, path: c.JSValue) !c.JSValue {
    if (try synthetic(scope, path)) return path;
    const options = try scope.object();
    try scope.put(options, "trim", c.pi_js_bool(scope.engine.context, 1));
    return scope.own(try @import("native_sdk_source_paths.zig").resolve(scope.engine, path, try working(scope, data), options));
}
fn canonical(scope: *Scope, path: c.JSValue) !c.JSValue {
    const raw = try scope.engine.toString(path);
    defer scope.engine.gpa.free(raw);
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const size = std.Io.Dir.cwd().realPathFile(scope.engine.native_io orelse return error.NativeIoUnavailable, raw, &buffer) catch return path;
    return scope.text(buffer[0..size]);
}
fn normalizeEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return normalizedEntry(engine, roots[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn normalizedEntry(engine: *em.Engine, data: c.JSValue, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const has_base = scope.truthy(try scope.get(try scope.get(entry, "metadata"), "baseDir"));
    const metadata = if (has_base) copied: {
        const result = try scope.own(try js.spread(engine, try scope.get(entry, "metadata")));
        try scope.put(result, "baseDir", try resolve(&scope, data, try scope.get(try scope.get(entry, "metadata"), "baseDir")));
        break :copied result;
    } else try scope.get(entry, "metadata");
    const result = try scope.object();
    try scope.put(result, "path", try resolve(&scope, data, try scope.get(entry, "path")));
    try scope.put(result, "metadata", metadata);
    return c.JS_DupValue(engine.context, result);
}
fn normalize(scope: *Scope, data: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const entries = if (temp.nullish(supplied)) try scope.array() else supplied;
    const map = try scope.get(entries, "map");
    var roots = [_]c.JSValue{data};
    const callback = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, normalizeEntry, "", 1, 0, roots.len, &roots)));
    return scope.call(map, entries, &.{callback});
}
fn sourceInfo(scope: *Scope, path: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", path);
    inline for (.{ "source", "scope", "origin", "baseDir" }) |key| try scope.put(result, key, try scope.get(metadata, key));
    return result;
}
fn pathEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return sdk.get(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "path") catch |err| sdk.fail(engine, err);
}
fn merge(scope: *Scope, data: c.JSValue, primary: c.JSValue, additional: c.JSValue) !c.JSValue {
    const merged = try scope.array();
    const seen = try scope.own(try js.builtin(scope.engine, "Set", &.{}));
    // Source first spreads both operands; iteration therefore completes before
    // any path resolver or realpath operation observes a callback mutation.
    const all = try scope.array();
    var count: u32 = 0;
    for ([_]c.JSValue{ primary, additional }) |values| {
        var it = try iterator(scope, values);
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |value| {
            defer scope.engine.freeValue(value);
            try scope.index(all, count, value);
            count += 1;
        }
    }
    var published: u32 = 0;
    for (0..count) |index| {
        const value = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, all, @intCast(index))));
        const resolved = try resolve(scope, data, value);
        const key = try canonical(scope, resolved);
        if (scope.truthy(try scope.invoke(seen, "has", &.{key}))) continue;
        _ = try scope.invoke(seen, "add", &.{key});
        try scope.index(merged, published, resolved);
        published += 1;
    }
    return merged;
}
pub fn extend(engine: *em.Engine, loader: c.JSValue, data: c.JSValue, input: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var normalized: [3]c.JSValue = undefined;
    inline for (categories, 0..) |category, index| normalized[index] = try normalize(&scope, data, try scope.get(input, category[1]));
    inline for (categories, 0..) |category, index| {
        const infos = try scope.get(data, category[3]);
        var it = try iterator(&scope, normalized[index]);
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |entry| {
            defer engine.freeValue(entry);
            const set = try scope.get(infos, "set");
            const key = try scope.get(entry, "path");
            const info = try sourceInfo(&scope, try scope.get(entry, "path"), try scope.get(entry, "metadata"));
            _ = try scope.call(set, infos, &.{ key, info });
        }
    }
    inline for (categories, 0..) |category, index| {
        if (try scope.positive(try scope.get(normalized[index], "length"))) {
            const map = try scope.get(normalized[index], "map");
            const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, pathEntry, "", 1)));
            const additions = try scope.call(map, normalized[index], &.{callback});
            const paths = try merge(&scope, data, try scope.get(data, category[2]), additions);
            try scope.put(data, category[2], paths);
            try update(&scope, loader, data, category[0], category[4], category[5], category[3], paths);
        }
    }
}
fn under(path: []const u8, root: []const u8) bool {
    return std.mem.eql(u8, path, root) or (std.mem.startsWith(u8, path, root) and (std.mem.endsWith(u8, root, std.fs.path.sep_str) or (path.len > root.len and path[root.len] == std.fs.path.sep)));
}
fn metadataFor(scope: *Scope, infos: c.JSValue, path: c.JSValue) !c.JSValue {
    if (!scope.truthy(path)) return c.pi_js_undefined();
    if (try synthetic(scope, path)) {
        var source = c.pi_js_undefined();
        if (scope.truthy(try scope.invoke(path, "startsWith", &.{try scope.text("builtin:")}))) {
            source = try scope.text("builtin");
        } else if (scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(">")}))) {
            const parts = try scope.invoke(try scope.invoke(path, "slice", &.{ c.JS_NewInt32(scope.engine.context, 1), c.JS_NewInt32(scope.engine.context, -1) }), "split", &.{try scope.text(":")});
            source = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, parts, 0)));
            if (!scope.truthy(source)) source = try scope.text("temporary");
        }
        if (!c.JS_IsUndefined(source)) {
            const info = try scope.object();
            try scope.put(info, "path", path);
            try scope.put(info, "source", source);
            try scope.put(info, "scope", try scope.text("temporary"));
            try scope.put(info, "origin", try scope.text("top-level"));
            return info;
        }
    }
    const raw = try scope.engine.toString(try nodeResolved(scope, path));
    defer scope.engine.gpa.free(raw);
    var it = try iterator(scope, try scope.invoke(infos, "entries", &.{}));
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |pair| {
        defer scope.engine.freeValue(pair);
        const key = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, pair, 0)));
        const base = try scope.engine.toString(try nodeResolved(scope, key));
        defer scope.engine.gpa.free(base);
        if (under(raw, base)) {
            const info = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, pair, 1)));
            const result = try scope.own(try js.spread(scope.engine, info));
            try scope.put(result, "path", path);
            try it.close();
            return result;
        }
    }
    return c.pi_js_undefined();
}
fn nodeResolved(scope: *Scope, path: c.JSValue) !c.JSValue {
    if (!scope.engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(scope.engine, scope.engine.native_io orelse return error.NativeIoUnavailable);
    const exports = scope.engine.native_module_values.get("node:path").?;
    return scope.call(try scope.get(exports, "resolve"), c.pi_js_undefined(), &.{path});
}
fn localInfo(scope: *Scope, path: []const u8, cwd: []const u8, agent_dir: []const u8, base: []const u8) !c.JSValue {
    var selected_scope: []const u8 = "temporary";
    var selected_base: []const u8 = base;
    inline for (.{ "skills", "prompts", "themes", "extensions" }) |name| {
        const user = try std.fs.path.join(scope.engine.gpa, &.{ agent_dir, name });
        defer scope.engine.gpa.free(user);
        const project = try std.fs.path.join(scope.engine.gpa, &.{ cwd, ".pi", name });
        defer scope.engine.gpa.free(project);
        if (under(path, user) or under(path, project)) {
            selected_scope = if (under(path, user)) "user" else "project";
            selected_base = if (under(path, user)) user else project;
            const result = try scope.object();
            try scope.put(result, "path", try scope.text(path));
            try scope.put(result, "source", try scope.text("local"));
            try scope.put(result, "scope", try scope.text(selected_scope));
            try scope.put(result, "origin", try scope.text("top-level"));
            try scope.put(result, "baseDir", try scope.text(selected_base));
            return result;
        }
    }
    const result = try scope.object();
    try scope.put(result, "path", try scope.text(path));
    try scope.put(result, "source", try scope.text("local"));
    try scope.put(result, "scope", try scope.text(selected_scope));
    try scope.put(result, "origin", try scope.text("top-level"));
    try scope.put(result, "baseDir", try scope.text(selected_base));
    return result;
}
fn update(scope: *Scope, loader: c.JSValue, data: c.JSValue, kind: Category, key: [*:0]const u8, override_key: [*:0]const u8, info_key: [*:0]const u8, paths: c.JSValue) !void {
    const raw = try load(scope, data, kind, paths);
    try publish(scope, loader, data, kind, key, override_key, info_key, raw);
}
pub fn reloadThemes(engine: *em.Engine, data: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(data, "themes", try load(&scope, data, .themes, try scope.get(data, "lastThemePaths")));
}
pub fn finishThemeReload(engine: *em.Engine, loader: c.JSValue, data: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try publish(&scope, loader, data, .themes, "themes", "themesOverride", "extensionThemeSourceInfos", try scope.get(data, "themes"));
}
fn publish(scope: *Scope, loader: c.JSValue, data: c.JSValue, kind: Category, key: [*:0]const u8, override_key: [*:0]const u8, info_key: [*:0]const u8, raw: c.JSValue) !void {
    const options = try scope.get(data, "options");
    const callback = try scope.get(options, override_key);
    const resolved = if (scope.truthy(callback)) try scope.call(callback, loader, &.{raw}) else raw;
    const rows = try scope.get(resolved, key);
    const map = try scope.get(rows, "map");
    var roots = [_]c.JSValue{ try scope.get(data, info_key), data };
    const fn_value = try scope.own(try scope.engine.checked(c.JS_NewCFunctionData2(scope.engine.context, attachMetadata, "", 1, @intFromEnum(kind), roots.len, &roots)));
    const published = try scope.call(map, rows, &.{fn_value});
    const result = try scope.object();
    try scope.put(result, key, published);
    try scope.put(result, "diagnostics", try scope.get(try scope.get(data, key), "diagnostics"));
    // Source assigns the resource array before reading override diagnostics.
    // A diagnostics getter failure therefore keeps the newly assigned array.
    try scope.put(data, key, result);
    try scope.put(result, "diagnostics", try scope.get(resolved, "diagnostics"));
}
fn attachMetadata(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return attached(engine, roots[0], roots[1], if (argc > 0) argv[0] else c.pi_js_undefined(), @enumFromInt(magic)) catch |err| sdk.fail(engine, err);
}
fn attached(engine: *em.Engine, infos: c.JSValue, data: c.JSValue, row: c.JSValue, kind: Category) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = if (kind == .themes) row else try scope.own(try js.spread(engine, row));
    const path = try scope.get(row, if (kind == .themes) "sourcePath" else "filePath");
    const extra = if (kind != .themes or scope.truthy(path)) try metadataFor(&scope, infos, path) else c.pi_js_undefined();
    var selected = extra;
    if (temp.nullish(selected)) {
        selected = try scope.get(row, "sourceInfo");
        if (temp.nullish(selected) and scope.truthy(path)) {
            const raw = try engine.toString(path);
            defer engine.gpa.free(raw);
            const cwd = try engine.toString(try working(&scope, data));
            defer engine.gpa.free(cwd);
            const supplied_root = try scope.get(try scope.get(data, "options"), "agentDir");
            const agent_dir = if (temp.nullish(supplied_root)) try sdk.agentDir(engine) else try engine.toString(supplied_root);
            defer engine.gpa.free(agent_dir);
            const stat = try std.Io.Dir.cwd().statFile(engine.native_io orelse return error.NativeIoUnavailable, raw, .{});
            selected = try localInfo(&scope, raw, cwd, agent_dir, if (stat.kind == .directory) raw else std.fs.path.dirname(raw) orelse ".");
        }
    }
    try scope.set(result, "sourceInfo", selected);
    return c.JS_DupValue(engine.context, result);
}
fn warning(scope: *Scope, diagnostics: c.JSValue, message: []const u8, path: []const u8) !void {
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("warning"));
    try scope.put(result, "message", try scope.text(message));
    try scope.put(result, "path", try scope.text(path));
    try sdk.append(scope.engine, diagnostics, c.JS_DupValue(scope.engine.context, result));
}
fn load(scope: *Scope, data: c.JSValue, kind: Category, paths: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const cwd = try engine.toString(try working(scope, data));
    defer engine.gpa.free(cwd);
    const options = try scope.get(data, "options");
    const supplied_root = try scope.get(options, "agentDir");
    const agent_dir = if (temp.nullish(supplied_root)) try sdk.agentDir(engine) else try engine.toString(supplied_root);
    defer engine.gpa.free(agent_dir);
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const count = try sdk.length(engine, paths);
    const raw_paths = try allocator.alloc([]const u8, count);
    for (raw_paths, 0..) |*path, index| {
        const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, paths, @intCast(index))));
        const raw = try engine.toString(value);
        defer engine.gpa.free(raw);
        path.* = try allocator.dupe(u8, raw);
    }
    const rows = try scope.array();
    const diagnostics = try scope.array();
    switch (kind) {
        .skills => {
            for (raw_paths) |path| {
                _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch {
                    try warning(scope, diagnostics, "skill path does not exist", path);
                    continue;
                };
            }
            const skills = try @import("../coding_agent/skills.zig").loadTrusted(engine.gpa, io, cwd, agent_dir, true, raw_paths, false);
            defer {
                for (skills) |*item| item.deinit(engine.gpa);
                engine.gpa.free(skills);
            }
            const seen = try scope.own(try js.builtin(engine, "Set", &.{}));
            for (skills) |item| {
                const file_path = try scope.text(item.path);
                const real_path = try canonical(scope, file_path);
                if (scope.truthy(try scope.invoke(seen, "has", &.{real_path}))) continue;
                if (try @import("native_sdk_resources.zig").duplicate(engine, rows, item.name, item.path, "skill", diagnostics)) continue;
                _ = try scope.invoke(seen, "add", &.{real_path});
                const row = try scope.object();
                const base = std.fs.path.dirname(item.path) orelse ".";
                try scope.put(row, "name", try scope.text(item.name));
                try scope.put(row, "description", try scope.text(item.description));
                try scope.put(row, "filePath", file_path);
                try scope.put(row, "baseDir", try scope.text(base));
                const info = try localInfo(scope, item.path, cwd, agent_dir, base);
                try scope.set(info, "baseDir", try scope.text(base));
                try scope.put(row, "sourceInfo", info);
                try scope.put(row, "disableModelInvocation", c.pi_js_bool(engine.context, @intFromBool(item.disable_model_invocation)));
                try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
            }
        },
        .prompts => {
            const prompts = try @import("../coding_agent/prompts.zig").loadTrusted(engine.gpa, io, cwd, agent_dir, true, raw_paths, false);
            defer {
                for (prompts) |*item| item.deinit(engine.gpa);
                engine.gpa.free(prompts);
            }
            for (prompts) |item| {
                if (try @import("native_sdk_resources.zig").duplicate(engine, rows, item.name, item.path, "prompt", diagnostics)) continue;
                const row = try scope.object();
                try scope.put(row, "name", try scope.text(item.name));
                try scope.put(row, "description", try scope.text(item.description));
                if (item.argument_hint) |hint| if (hint.len > 0) try scope.put(row, "argumentHint", try scope.text(hint));
                try scope.put(row, "content", try scope.text(@import("../coding_agent/frontmatter.zig").trim(item.content)));
                try scope.put(row, "sourceInfo", try localInfo(scope, item.path, cwd, agent_dir, std.fs.path.dirname(item.path) orelse "."));
                try scope.put(row, "filePath", try scope.text(item.path));
                try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
            }
        },
        .themes => if (raw_paths.len > 0) try loadThemes(scope, data, rows, diagnostics, raw_paths, cwd, agent_dir),
    }
    const result = try scope.object();
    try scope.put(result, switch (kind) {
        .skills => "skills",
        .prompts => "prompts",
        .themes => "themes",
    }, rows);
    try scope.put(result, "diagnostics", diagnostics);
    return result;
}
fn loadThemes(scope: *Scope, data: c.JSValue, rows: c.JSValue, diagnostics: c.JSValue, paths: []const []const u8, cwd: []const u8, agent_dir: []const u8) !void {
    const engine = scope.engine;
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const theme = @import("native_theme.zig");
    var mode = try theme.defaultMode(engine);
    const settings = try scope.get(try scope.get(data, "options"), "settingsManager");
    if (!temp.nullish(settings)) {
        const overrides = try scope.invoke(settings, "getTerminalCapabilityOverrides", &.{});
        const true_color = try scope.get(overrides, "trueColor");
        if (c.JS_IsBool(true_color)) mode = if (scope.truthy(true_color)) .truecolor else .@"256color";
    }
    for (paths) |path| {
        const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch {
            try warning(scope, diagnostics, "theme path does not exist", path);
            continue;
        };
        if (stat.kind == .directory) {
            const directory = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
            defer directory.close(io);
            var it = directory.iterate();
            while (try it.next(io)) |entry| {
                if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
                const file_path = try std.fs.path.join(engine.gpa, &.{ path, entry.name });
                defer engine.gpa.free(file_path);
                const file_stat = std.Io.Dir.cwd().statFile(io, file_path, .{}) catch continue;
                if (file_stat.kind == .file) try loadThemeFile(scope, rows, diagnostics, file_path, mode, cwd, agent_dir);
            }
        } else if (stat.kind == .file and std.mem.endsWith(u8, path, ".json")) try loadThemeFile(scope, rows, diagnostics, path, mode, cwd, agent_dir) else try warning(scope, diagnostics, "theme path is not a json file", path);
    }
}
fn loadThemeFile(scope: *Scope, rows: c.JSValue, diagnostics: c.JSValue, path: []const u8, mode: @import("native_theme.zig").ColorMode, cwd: []const u8, agent_dir: []const u8) !void {
    const engine = scope.engine;
    const generation = engine.native_allocation_generation;
    const loaded = @import("native_theme.zig").loadFile(engine, engine.native_io.?, path, mode) catch |err| {
        const original = engine.nativeAllocationError(err, generation);
        if (original == error.OutOfMemory) return original;
        const message = if (original == error.JavaScriptException and engine.captured_exception != null) try scope.get(engine.captured_exception.?, "message") else try scope.text(@errorName(original));
        const raw = try engine.toString(message);
        defer engine.gpa.free(raw);
        try warning(scope, diagnostics, raw, path);
        if (engine.captured_exception) |exception| engine.freeValue(exception);
        engine.captured_exception = null;
        return;
    };
    const row = try scope.own(loaded);
    const name = try scope.get(row, "name");
    const selected = if (temp.nullish(name)) try scope.text("unnamed") else name;
    const raw_name = try engine.toString(selected);
    defer engine.gpa.free(raw_name);
    for (0..try sdk.length(engine, rows)) |index| {
        const prior = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index))));
        const prior_name = try scope.get(prior, "name");
        if (!scope.equal(if (temp.nullish(prior_name)) try scope.text("unnamed") else prior_name, selected)) continue;
        const result = try scope.object();
        try scope.put(result, "type", try scope.text("collision"));
        const message = try std.fmt.allocPrint(engine.gpa, "name \"{s}\" collision", .{raw_name});
        defer engine.gpa.free(message);
        try scope.put(result, "message", try scope.text(message));
        try scope.put(result, "path", try scope.text(path));
        const collision = try scope.object();
        try scope.put(collision, "resourceType", try scope.text("theme"));
        try scope.put(collision, "name", selected);
        try scope.put(collision, "winnerPath", try scope.get(prior, "sourcePath"));
        try scope.put(collision, "loserPath", try scope.text(path));
        try scope.put(result, "collision", collision);
        try sdk.append(engine, diagnostics, c.JS_DupValue(engine.context, result));
        return;
    }
    _ = cwd;
    _ = agent_dir;
    try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
}
