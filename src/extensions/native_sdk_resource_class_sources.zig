//! Ordinary DefaultResourceLoader source attribution and prompt discovery.
//! Imported filesystem/path functions are captured once at installation.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum(c_int) { addExtensionConflictDiagnostics, mapSkillPath, applyExtensionSourceInfo, findSourceInfoForPath, getDefaultSourceInfoForPath, dedupePrompts, dedupeThemes, discoverSystemPromptFile, discoverAppendSystemPromptFile, isUnderPath, detectExtensionConflicts };
const Import = enum(usize) { resolve, join, sep, exists, stat, config_dir };
pub fn install(engine: *em.Engine, prototype: c.JSValue, config_dir: c.JSValue) !void {
    const io = engine.native_io orelse return error.NativeResourceClassRequiresIo;
    if (!engine.native_module_values.contains("node:path")) try @import("node_path.zig").install(engine, io);
    if (!engine.native_module_values.contains("node:fs")) try @import("node_fs.zig").install(engine, io);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const path = engine.native_module_values.get("node:path").?;
    const fs = engine.native_module_values.get("node:fs").?;
    var roots = [_]c.JSValue{ try scope.get(path, "resolve"), try scope.get(path, "join"), try scope.get(path, "sep"), try scope.get(fs, "existsSync"), try scope.get(fs, "statSync"), config_dir };
    inline for (std.meta.fields(Method)) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .mapSkillPath, .applyExtensionSourceInfo, .isUnderPath => 2,
            .findSourceInfoForPath => 3,
            .getDefaultSourceInfoForPath, .dedupePrompts, .dedupeThemes, .addExtensionConflictDiagnostics, .detectExtensionConflicts => 1,
            else => 0,
        };
        const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, length, field.value, roots.len, &roots));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, loader: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return method(engine, loader, @enumFromInt(magic), if (argc > 0) argv[0..@intCast(argc)] else &.{}, roots) catch |err| sdk.fail(engine, err);
}
fn imported(scope: *Scope, roots: [*c]c.JSValue, name: Import, args: []const c.JSValue) !c.JSValue {
    return scope.call(roots[@intFromEnum(name)], c.pi_js_undefined(), args);
}
fn iterator(scope: *Scope, value: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, value, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn pair(scope: *Scope, value: c.JSValue) ![2]c.JSValue {
    var it = try iterator(scope, value);
    defer it.deinit();
    errdefer it.closePreserving();
    const first = if (try it.next()) |item| try scope.own(item) else c.pi_js_undefined();
    const second = if (try it.next()) |item| try scope.own(item) else c.pi_js_undefined();
    try it.close();
    return .{ first, second };
}
fn starts(scope: *Scope, path: c.JSValue, prefix: c.JSValue) !bool {
    return scope.truthy(try scope.invoke(path, "startsWith", &.{prefix}));
}
fn synthetic(scope: *Scope, path: c.JSValue) !bool {
    return try starts(scope, path, try scope.text("builtin:")) or try starts(scope, path, try scope.text("<"));
}
fn source(scope: *Scope, path: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", path);
    inline for (.{ "source", "scope", "origin", "baseDir" }) |key| try scope.put(result, key, try scope.get(metadata, key));
    return result;
}
fn under(scope: *Scope, roots: [*c]c.JSValue, target: c.JSValue, root: c.JSValue) !bool {
    const normalized = try imported(scope, roots, .resolve, &.{root});
    if (scope.equal(target, normalized)) return true;
    const sep = roots[@intFromEnum(Import.sep)];
    const prefix = if (scope.truthy(try scope.invoke(normalized, "endsWith", &.{sep}))) normalized else try scope.concat(normalized, sep);
    return starts(scope, target, prefix);
}
fn defaultSource(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, path: c.JSValue) !c.JSValue {
    const synthetic_source = if (try starts(scope, path, try scope.text("builtin:"))) try scope.text("builtin") else if (try starts(scope, path, try scope.text("<")) and scope.truthy(try scope.invoke(path, "endsWith", &.{try scope.text(">")}))) value: {
        const inside = try scope.invoke(path, "slice", &.{ c.JS_NewInt32(scope.engine.context, 1), c.JS_NewInt32(scope.engine.context, -1) });
        const split = try scope.invoke(inside, "split", &.{try scope.text(":")});
        const first = try at(scope, split, 0);
        break :value if (scope.truthy(first)) first else try scope.text("temporary");
    } else c.pi_js_undefined();
    if (scope.truthy(synthetic_source)) {
        const result = try scope.object();
        try scope.put(result, "path", path);
        try scope.put(result, "source", synthetic_source);
        try scope.put(result, "scope", try scope.text("temporary"));
        try scope.put(result, "origin", try scope.text("top-level"));
        return result;
    }
    const normalized = try imported(scope, roots, .resolve, &.{path});
    const agent_roots = try scope.array();
    const project_roots = try scope.array();
    inline for (.{ "skills", "prompts", "themes", "extensions" }, 0..) |category, index| {
        try scope.index(agent_roots, index, try imported(scope, roots, .join, &.{ try scope.get(loader, "agentDir"), try scope.text(category) }));
    }
    inline for (.{ "skills", "prompts", "themes", "extensions" }, 0..) |category, index| {
        try scope.index(project_roots, index, try imported(scope, roots, .join, &.{ try scope.get(loader, "cwd"), roots[@intFromEnum(Import.config_dir)], try scope.text(category) }));
    }
    for ([_]c.JSValue{ agent_roots, project_roots }, 0..) |values, scope_index| {
        var it = try iterator(scope, values);
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |root| {
            defer scope.engine.freeValue(root);
            const is_under = try scope.get(loader, "isUnderPath");
            if (scope.truthy(try scope.call(is_under, loader, &.{ normalized, root }))) {
                try it.close();
                return localSource(scope, path, if (scope_index == 0) "user" else "project", root);
            }
        }
    }
    const result = try scope.object();
    try scope.put(result, "path", path);
    try scope.put(result, "source", try scope.text("local"));
    try scope.put(result, "scope", try scope.text("temporary"));
    try scope.put(result, "origin", try scope.text("top-level"));
    const stats = try imported(scope, roots, .stat, &.{normalized});
    const base = if (scope.truthy(try scope.invoke(stats, "isDirectory", &.{}))) normalized else try imported(scope, roots, .resolve, &.{ normalized, try scope.text("..") });
    try scope.put(result, "baseDir", base);
    return result;
}
fn localSource(scope: *Scope, path: c.JSValue, selected_scope: []const u8, base: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "path", path);
    try scope.put(result, "source", try scope.text("local"));
    try scope.put(result, "scope", try scope.text(selected_scope));
    try scope.put(result, "origin", try scope.text("top-level"));
    try scope.put(result, "baseDir", base);
    return result;
}
fn find(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, path: c.JSValue, extra: c.JSValue, metadata: c.JSValue) !c.JSValue {
    if (!scope.truthy(path)) return c.pi_js_undefined();
    if (try synthetic(scope, path)) return scope.invoke(loader, "getDefaultSourceInfoForPath", &.{path});
    const normalized = try imported(scope, roots, .resolve, &.{path});
    if (scope.truthy(extra)) {
        var it = try iterator(scope, try scope.invoke(extra, "entries", &.{}));
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const selected = try pair(scope, entry);
            const normalized_source = try imported(scope, roots, .resolve, &.{selected[0]});
            const prefix = try scope.concat(normalized_source, roots[@intFromEnum(Import.sep)]);
            if (scope.equal(normalized, normalized_source) or try starts(scope, normalized, prefix)) {
                const result = try scope.own(try js.spread(scope.engine, selected[1]));
                try scope.put(result, "path", path);
                try it.close();
                return result;
            }
        }
    }
    if (scope.truthy(metadata)) {
        const found = try scope.invoke(metadata, "get", &.{normalized});
        const exact = if (temp.nullish(found)) try scope.invoke(metadata, "get", &.{path}) else found;
        if (scope.truthy(exact)) return source(scope, path, exact);
        var it = try iterator(scope, try scope.invoke(metadata, "entries", &.{}));
        defer it.deinit();
        errdefer it.closePreserving();
        while (try it.next()) |entry| {
            defer scope.engine.freeValue(entry);
            const selected = try pair(scope, entry);
            const normalized_source = try imported(scope, roots, .resolve, &.{selected[0]});
            const prefix = try scope.concat(normalized_source, roots[@intFromEnum(Import.sep)]);
            if (scope.equal(normalized, normalized_source) or try starts(scope, normalized, prefix)) {
                const result = try source(scope, path, selected[1]);
                try it.close();
                return result;
            }
        }
    }
    return c.pi_js_undefined();
}
fn discover(scope: *Scope, roots: [*c]c.JSValue, loader: c.JSValue, filename: []const u8) !c.JSValue {
    const project = try imported(scope, roots, .join, &.{ try scope.get(loader, "cwd"), roots[@intFromEnum(Import.config_dir)], try scope.text(filename) });
    const settings = try scope.get(loader, "settingsManager");
    if (scope.truthy(try scope.invoke(settings, "isProjectTrusted", &.{})) and scope.truthy(try imported(scope, roots, .exists, &.{project}))) return project;
    const global = try imported(scope, roots, .join, &.{ try scope.get(loader, "agentDir"), try scope.text(filename) });
    if (scope.truthy(try imported(scope, roots, .exists, &.{global}))) return global;
    return c.pi_js_undefined();
}
fn skill(scope: *Scope, roots: [*c]c.JSValue, resource: c.JSValue, metadata: c.JSValue) !c.JSValue {
    const info = try scope.get(resource, "metadata");
    if (!scope.equal(try scope.get(info, "source"), try scope.text("auto")) and !scope.equal(try scope.get(try scope.get(resource, "metadata"), "origin"), try scope.text("package"))) return scope.get(resource, "path");
    const generation = scope.engine.native_allocation_generation;
    const is_directory = skillDirectory(scope, roots, resource) catch |err| {
        const original = scope.engine.nativeAllocationError(err, generation);
        if (original == error.OutOfMemory) return original;
        if (scope.engine.captured_exception) |exception| scope.engine.freeValue(exception);
        scope.engine.captured_exception = null;
        return scope.get(resource, "path");
    };
    if (!is_directory) return scope.get(resource, "path");
    const file = try imported(scope, roots, .join, &.{ try scope.get(resource, "path"), try scope.text("SKILL.md") });
    if (scope.truthy(try imported(scope, roots, .exists, &.{file}))) {
        if (!scope.truthy(try scope.invoke(metadata, "has", &.{file}))) _ = try scope.invoke(metadata, "set", &.{ file, try scope.get(resource, "metadata") });
        return file;
    }
    return scope.get(resource, "path");
}
fn skillDirectory(scope: *Scope, roots: [*c]c.JSValue, resource: c.JSValue) !bool {
    const stats = try imported(scope, roots, .stat, &.{try scope.get(resource, "path")});
    return scope.truthy(try scope.invoke(stats, "isDirectory", &.{}));
}
fn apply(scope: *Scope, loader: c.JSValue, extensions: c.JSValue, metadata: c.JSValue) !void {
    var it = try iterator(scope, extensions);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |extension| {
        defer scope.engine.freeValue(extension);
        const find_function = try scope.get(loader, "findSourceInfoForPath");
        const found = try scope.call(find_function, loader, &.{ try scope.get(extension, "path"), c.pi_js_undefined(), metadata });
        const info = if (temp.nullish(found)) try scope.invoke(loader, "getDefaultSourceInfoForPath", &.{try scope.get(extension, "path")}) else found;
        try scope.set(extension, "sourceInfo", info);
        inline for (.{ "commands", "tools" }) |field| {
            var values = try iterator(scope, try scope.invoke(try scope.get(extension, field), "values", &.{}));
            defer values.deinit();
            errdefer values.closePreserving();
            while (try values.next()) |item| {
                defer scope.engine.freeValue(item);
                try scope.set(item, "sourceInfo", try scope.get(extension, "sourceInfo"));
            }
        }
    }
}
fn dedupe(scope: *Scope, values: c.JSValue, themes: bool) !c.JSValue {
    const seen = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
    const diagnostics = try scope.array();
    var it = try iterator(scope, values);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |item| {
        defer scope.engine.freeValue(item);
        const original_name = try scope.get(item, "name");
        const name = if (themes and temp.nullish(original_name)) try scope.text("unnamed") else original_name;
        const existing = try scope.invoke(seen, "get", &.{name});
        if (scope.truthy(existing)) {
            const diagnostic = try scope.object();
            try scope.put(diagnostic, "type", try scope.text("collision"));
            const message_name = if (themes) name else try scope.get(item, "name");
            const prefix = try scope.text(if (themes) "name \"" else "name \"/");
            const message = try scope.concat(try scope.concat(prefix, try scope.stringify(message_name)), try scope.text("\" collision"));
            try scope.put(diagnostic, "message", message);
            try scope.put(diagnostic, "path", try scope.get(item, if (themes) "sourcePath" else "filePath"));
            const collision = try scope.object();
            try scope.put(collision, "resourceType", try scope.text(if (themes) "theme" else "prompt"));
            try scope.put(collision, "name", if (themes) name else try scope.get(item, "name"));
            const winner = try scope.get(existing, if (themes) "sourcePath" else "filePath");
            try scope.put(collision, "winnerPath", if (themes and temp.nullish(winner)) try scope.text("<builtin>") else winner);
            const loser = try scope.get(item, if (themes) "sourcePath" else "filePath");
            try scope.put(collision, "loserPath", if (themes and temp.nullish(loser)) try scope.text("<builtin>") else loser);
            try scope.put(diagnostic, "collision", collision);
            _ = try scope.invoke(diagnostics, "push", &.{diagnostic});
        } else {
            const selected_name = if (themes) name else try scope.get(item, "name");
            _ = try scope.invoke(seen, "set", &.{ selected_name, item });
        }
    }
    const result = try scope.object();
    const array_constructor = try scope.global("Array");
    const from = try scope.get(array_constructor, "from");
    try scope.put(result, if (themes) "themes" else "prompts", try scope.call(from, array_constructor, &.{try scope.invoke(seen, "values", &.{})}));
    try scope.put(result, "diagnostics", diagnostics);
    return result;
}
fn conflicts(scope: *Scope, extensions: c.JSValue) !c.JSValue {
    const result = try scope.array();
    const tool_owners = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
    const flag_owners = try scope.own(try js.builtin(scope.engine, "Map", &.{}));
    var it = try iterator(scope, extensions);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |extension| {
        defer scope.engine.freeValue(extension);
        inline for (.{ .{ "tools", tool_owners, "Tool \"" }, .{ "flags", flag_owners, "Flag \"--" } }) |category| {
            const collection = try scope.get(extension, category[0]);
            var names = try iterator(scope, try scope.invoke(collection, "keys", &.{}));
            defer names.deinit();
            errdefer names.closePreserving();
            while (try names.next()) |name| {
                defer scope.engine.freeValue(name);
                const existing = try scope.invoke(category[1], "get", &.{name});
                if (scope.truthy(existing) and !scope.equal(existing, try scope.get(extension, "path"))) {
                    const diagnostic = try scope.object();
                    try scope.put(diagnostic, "path", try scope.get(extension, "path"));
                    const text = try scope.concat(try scope.concat(try scope.concat(try scope.text(category[2]), try scope.stringify(name)), try scope.text("\" conflicts with ")), try scope.stringify(existing));
                    try scope.put(diagnostic, "message", text);
                    _ = try scope.invoke(result, "push", &.{diagnostic});
                } else {
                    _ = try scope.invoke(category[1], "set", &.{ name, try scope.get(extension, "path") });
                }
            }
        }
    }
    return result;
}
fn addConflicts(scope: *Scope, loader: c.JSValue, result: c.JSValue) !void {
    const detect = try scope.get(loader, "detectExtensionConflicts");
    const diagnostics = try scope.call(detect, loader, &.{try scope.get(result, "extensions")});
    var it = try iterator(scope, diagnostics);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |conflict| {
        defer scope.engine.freeValue(conflict);
        const errors = try scope.get(result, "errors");
        const push = try scope.get(errors, "push");
        const diagnostic = try scope.object();
        try scope.put(diagnostic, "path", try scope.get(conflict, "path"));
        try scope.put(diagnostic, "error", try scope.get(conflict, "message"));
        _ = try scope.call(push, errors, &.{diagnostic});
    }
}
fn method(engine: *em.Engine, loader: c.JSValue, kind: Method, args: []const c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const first = if (args.len > 0) args[0] else c.pi_js_undefined();
    const second = if (args.len > 1) args[1] else c.pi_js_undefined();
    const result = switch (kind) {
        .findSourceInfoForPath => try find(&scope, roots, loader, first, second, if (args.len > 2) args[2] else c.pi_js_undefined()),
        .getDefaultSourceInfoForPath => try defaultSource(&scope, roots, loader, first),
        .discoverSystemPromptFile => try discover(&scope, roots, loader, "SYSTEM.md"),
        .discoverAppendSystemPromptFile => try discover(&scope, roots, loader, "APPEND_SYSTEM.md"),
        .isUnderPath => c.pi_js_bool(engine.context, @intFromBool(try under(&scope, roots, first, second))),
        .mapSkillPath => try skill(&scope, roots, first, second),
        .dedupePrompts => try dedupe(&scope, first, false),
        .dedupeThemes => try dedupe(&scope, first, true),
        .detectExtensionConflicts => try conflicts(&scope, first),
        .addExtensionConflictDiagnostics => done: {
            try addConflicts(&scope, loader, first);
            break :done c.pi_js_undefined();
        },
        .applyExtensionSourceInfo => done: {
            try apply(&scope, loader, first, second);
            break :done c.pi_js_undefined();
        },
    };
    return c.JS_DupValue(engine.context, result);
}
