//! SDK resource projections using the existing native parsers and filesystem.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const engine_mod = @import("engine.zig");
const skills_mod = @import("../coding_agent/skills.zig");
const prompts_mod = @import("../coding_agent/prompts.zig");
const c = engine_mod.c;
const group_mod = @import("native_group.zig");
pub fn reload(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const io = engine.native_io orelse return;
    const options = try sdk.get(engine, data, "options");
    defer engine.freeValue(options);
    const cwd_value = try sdk.get(engine, options, "cwd");
    defer engine.freeValue(cwd_value);
    const root_value = try sdk.get(engine, options, "agentDir");
    defer engine.freeValue(root_value);
    const cwd = if (c.JS_IsString(cwd_value)) try engine.toString(cwd_value) else try sdk.cwd(engine);
    defer engine.gpa.free(cwd);
    const root = if (c.JS_IsString(root_value)) try engine.toString(root_value) else try sdk.agentDir(engine);
    defer engine.gpa.free(root);
    const project = try std.fs.path.join(engine.gpa, &.{ cwd, ".pi" });
    defer engine.gpa.free(project);
    const no_skills = try flag(engine, options, "noSkills");
    const no_prompts = try flag(engine, options, "noPromptTemplates");
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const skill_paths = try paths(engine, allocator, options, "additionalSkillPaths", cwd, project, root, "skills", !no_skills);
    const skills = try skills_mod.loadTrusted(engine.gpa, io, cwd, root, true, skill_paths, false);
    defer {
        for (skills) |*item| item.deinit(engine.gpa);
        engine.gpa.free(skills);
    }
    const skill_rows = try sdk.array(engine);
    defer engine.freeValue(skill_rows);
    const skill_diagnostics = try sdk.array(engine);
    defer engine.freeValue(skill_diagnostics);
    for (skills) |item| {
        if (try duplicate(engine, skill_rows, item.name, item.path, "skill", skill_diagnostics)) continue;
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        try sdk.put(engine, row, "name", try sdk.text(engine, item.name));
        try sdk.put(engine, row, "description", try sdk.text(engine, item.description));
        try sdk.put(engine, row, "filePath", try sdk.text(engine, item.path));
        try sdk.put(engine, row, "baseDir", try sdk.text(engine, std.fs.path.dirname(item.path) orelse "."));
        try sdk.put(engine, row, "sourceInfo", try sourceInfo(engine, item.path, project, root));
        try sdk.put(engine, row, "disableModelInvocation", c.pi_js_bool(engine.context, @intFromBool(item.disable_model_invocation)));
        try sdk.append(engine, skill_rows, c.JS_DupValue(engine.context, row));
    }
    try publish(engine, data, "skills", skill_rows, skill_diagnostics);
    const prompt_paths = try paths(engine, allocator, options, "additionalPromptTemplatePaths", cwd, project, root, "prompts", !no_prompts);
    const prompts = try prompts_mod.loadTrusted(engine.gpa, io, cwd, root, true, prompt_paths, false);
    defer {
        for (prompts) |*item| item.deinit(engine.gpa);
        engine.gpa.free(prompts);
    }
    const prompt_rows = try sdk.array(engine);
    defer engine.freeValue(prompt_rows);
    const prompt_diagnostics = try sdk.array(engine);
    defer engine.freeValue(prompt_diagnostics);
    for (prompts) |item| {
        if (try duplicate(engine, prompt_rows, item.name, item.path, "prompt", prompt_diagnostics)) continue;
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        try sdk.put(engine, row, "name", try sdk.text(engine, item.name));
        try sdk.put(engine, row, "description", try sdk.text(engine, item.description));
        try sdk.put(engine, row, "content", try sdk.text(engine, item.content));
        if (item.argument_hint) |hint| try sdk.put(engine, row, "argumentHint", try sdk.text(engine, hint));
        try sdk.put(engine, row, "filePath", try sdk.text(engine, item.path));
        try sdk.put(engine, row, "sourceInfo", try sourceInfo(engine, item.path, project, root));
        try sdk.append(engine, prompt_rows, c.JS_DupValue(engine.context, row));
    }
    try publish(engine, data, "prompts", prompt_rows, prompt_diagnostics);
    const contexts = try sdk.array(engine);
    defer engine.freeValue(contexts);
    if (!try flag(engine, options, "noContextFiles")) {
        var instruction_files = try @import("../coding_agent/project_context.zig").load(engine.gpa, io, cwd, root, true);
        defer instruction_files.deinit(engine.gpa);
        for (instruction_files.items) |item| {
            const row = try sdk.object(engine);
            defer engine.freeValue(row);
            try sdk.put(engine, row, "path", try sdk.text(engine, item.path));
            try sdk.put(engine, row, "content", try sdk.text(engine, item.content));
            try sdk.append(engine, contexts, c.JS_DupValue(engine.context, row));
        }
    }
    const agents = try sdk.object(engine);
    defer engine.freeValue(agents);
    try sdk.put(engine, agents, "agentsFiles", c.JS_DupValue(engine.context, contexts));
    try sdk.put(engine, data, "agentsFiles", c.JS_DupValue(engine.context, agents));
    try promptFiles(engine, data, options, project, root);
}
pub fn factories(engine: *engine_mod.Engine, data: c.JSValue) !void {
    const options = try sdk.get(engine, data, "options");
    defer engine.freeValue(options);
    const inputs = try sdk.get(engine, options, "extensionFactories");
    defer engine.freeValue(inputs);
    const input_count = if (c.JS_IsArray(inputs)) try sdk.length(engine, inputs) else 0;
    const previous = try sdk.get(engine, data, "extensionOwnerIds");
    defer engine.freeValue(previous);
    if (input_count == 0 and (!c.JS_IsArray(previous) or try sdk.length(engine, previous) == 0)) return;
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    // A reload creates a new runtime. Saved APIs and existing sessions keep
    // their previous runtime until its own marked JS graph is collected.
    const private_scope = try @import("native_sdk_resource_owners.zig").create(group);
    defer engine.freeValue(private_scope);
    const ids = try sdk.array(engine);
    defer engine.freeValue(ids);
    const rows = try sdk.array(engine);
    defer engine.freeValue(rows);
    const errors = try sdk.array(engine);
    defer engine.freeValue(errors);
    for (0..input_count) |index| {
        const input = try engine.checked(c.JS_GetPropertyUint32(engine.context, inputs, @intCast(index)));
        defer engine.freeValue(input);
        const factory = if (c.JS_IsFunction(engine.context, input)) c.JS_DupValue(engine.context, input) else try sdk.get(engine, input, "factory");
        defer engine.freeValue(factory);
        const name = if (c.JS_IsFunction(engine.context, input)) try std.fmt.allocPrint(engine.gpa, "{d}", .{index + 1}) else named: {
            const value = try sdk.get(engine, input, "name");
            defer engine.freeValue(value);
            break :named try engine.toString(value);
        };
        defer engine.gpa.free(name);
        const path = try std.fmt.allocPrint(engine.gpa, "<inline:{s}>", .{name});
        defer engine.gpa.free(path);
        const binding = try group.addSdk(path, private_scope);
        binding.loadFactoryValue(factory) catch |err| {
            const diagnostic = try sdk.object(engine);
            defer engine.freeValue(diagnostic);
            try sdk.put(engine, diagnostic, "path", try sdk.text(engine, path));
            const message = if (err == error.JavaScriptException and engine.captured_exception != null and c.JS_IsError(engine.captured_exception.?)) try sdk.get(engine, engine.captured_exception.?, "message") else try sdk.text(engine, "failed to load extension");
            defer engine.freeValue(message);
            try sdk.put(engine, diagnostic, "error", c.JS_DupValue(engine.context, message));
            try sdk.append(engine, errors, c.JS_DupValue(engine.context, diagnostic));
            try group.remove(binding.owner_id);
            continue;
        };
        try sdk.append(engine, ids, c.JS_NewInt64(engine.context, @intCast(binding.owner_id)));
        const row = try sdk.object(engine);
        defer engine.freeValue(row);
        try sdk.put(engine, row, "path", try sdk.text(engine, path));
        const tools = try map(engine);
        defer engine.freeValue(tools);
        for (binding.tool_order.items) |tool_name| {
            const tool = binding.tools.get(tool_name).?;
            const key = try sdk.text(engine, tool_name);
            defer engine.freeValue(key);
            const ignored = try sdk.invoke(engine, tools, "set", &.{ key, tool });
            engine.freeValue(ignored);
        }
        try sdk.put(engine, row, "tools", c.JS_DupValue(engine.context, tools));
        try sdk.put(engine, row, "commands", try tableMap(engine, binding.commands));
        try sdk.put(engine, row, "flags", try tableMap(engine, binding.flags));
        try sdk.append(engine, rows, c.JS_DupValue(engine.context, row));
    }
    try sdk.put(engine, private_scope, "_extensionOwnerIds", c.JS_DupValue(engine.context, ids));
    try sdk.put(engine, data, "_sdkExtensionOwnerScope", c.JS_DupValue(engine.context, private_scope));
    try sdk.put(engine, data, "extensionOwnerIds", c.JS_DupValue(engine.context, ids));
    const result = try sdk.object(engine);
    defer engine.freeValue(result);
    try sdk.put(engine, result, "extensions", c.JS_DupValue(engine.context, rows));
    try sdk.put(engine, result, "errors", c.JS_DupValue(engine.context, errors));
    try sdk.put(engine, result, "warnings", try sdk.array(engine));
    try sdk.put(engine, data, "extensions", c.JS_DupValue(engine.context, result));
}
fn map(engine: *engine_mod.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Map");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn tableMap(engine: *engine_mod.Engine, table: std.StringHashMapUnmanaged(c.JSValue)) !c.JSValue {
    const result = try map(engine);
    errdefer engine.freeValue(result);
    var iterator = table.iterator();
    while (iterator.next()) |entry| {
        const key = try sdk.text(engine, entry.key_ptr.*);
        defer engine.freeValue(key);
        const ignored = try sdk.invoke(engine, result, "set", &.{ key, entry.value_ptr.* });
        engine.freeValue(ignored);
    }
    return result;
}
pub fn emit(engine: *engine_mod.Engine, resources: c.JSValue, session_data: c.JSValue, event: []const u8, payload: []const u8) !void {
    const pending = try emitAsync(engine, resources, session_data, event, payload);
    defer engine.freeValue(pending);
    const result = try engine.awaitValueOnly(pending);
    engine.freeValue(result);
}
pub fn emitAsync(engine: *engine_mod.Engine, resources: c.JSValue, session_data: c.JSValue, event: []const u8, payload: []const u8) !c.JSValue {
    const terminated = try engine.gpa.dupeZ(u8, payload);
    defer engine.gpa.free(terminated);
    const parsed = try engine.checked(c.JS_ParseJSON(engine.context, terminated.ptr, payload.len, "sdk-resource-event"));
    defer engine.freeValue(parsed);
    return emitValue(engine, resources, session_data, event, parsed);
}
pub fn emitValue(engine: *engine_mod.Engine, resources: c.JSValue, session_data: c.JSValue, event: []const u8, payload: c.JSValue) !c.JSValue {
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return sdk.promise(engine, c.pi_js_undefined())));
    _ = resources;
    const ids = try @import("native_sdk_resource_owners.zig").sessionOwnerIds(engine, session_data);
    defer engine.freeValue(ids);
    if (!c.JS_IsArray(ids)) return sdk.promise(engine, c.pi_js_undefined());
    const session = try sdk.sessionDataSessionValue(engine, session_data);
    defer engine.freeValue(session);
    const lease = if ((try sdk.state(engine, session)).disposed) null else try sdk.sessionDataModelLease(engine, session_data);
    const registry = try sdk.get(engine, session_data, "modelRegistry");
    defer engine.freeValue(registry);
    const context = try sdk.object(engine);
    defer engine.freeValue(context);
    const manager = try sdk.get(engine, session_data, "sessionManager");
    defer engine.freeValue(manager);
    try sdk.put(engine, context, "cwd", try sdk.invoke(engine, manager, "getCwd", &.{}));
    try sdk.put(engine, context, "sessionId", try sdk.invoke(engine, manager, "getSessionId", &.{}));
    try sdk.put(engine, context, "sessionEntries", try sdk.invoke(engine, manager, "getEntries", &.{}));
    // SDK ctx.model is read from its captured genuine session by the native
    // accessor. Serializing the model here would invoke guest getters that
    // the Source context constructor does not observe, and lose VM identity.
    try sdk.put(engine, context, "thinkingLevel", try sdk.get(engine, session_data, "thinkingLevel"));
    try sdk.put(engine, context, "activeTools", try sdk.get(engine, session_data, "activeTools"));
    try sdk.put(engine, context, "systemPrompt", try sdk.get(engine, session_data, "systemPrompt"));
    try sdk.put(engine, context, "mode", try @import("native_sdk_ui_context.zig").mode(engine, session));
    try sdk.put(engine, context, "hasUI", c.pi_js_bool(engine.context, @intFromBool(try @import("native_sdk_ui_context.zig").hasUI(engine, session))));
    try sdk.put(engine, context, "idle", c.pi_js_bool(engine.context, @intFromBool(!(try sdk.state(engine, session)).running)));
    const raw = try engine.stringify(context);
    defer engine.gpa.free(raw);
    var pending: ?c.JSValue = null;
    errdefer if (pending) |value| engine.freeValue(value);
    for (0..try sdk.length(engine, ids)) |index| {
        const id = try engine.checked(c.JS_GetPropertyUint32(engine.context, ids, @intCast(index)));
        defer engine.freeValue(id);
        var integer: i64 = 0;
        if (c.JS_ToInt64(engine.context, &integer, id) < 0) return error.JavaScriptException;
        const binding = try group.selected(@intCast(integer));
        const next = try @import("native_sdk_events.zig").emitOneValue(engine, binding, session, if (lease) |live| .{ .session = session, .registry = registry, .manager = manager, .lease = live } else null, raw, event, payload, pending);
        if (pending) |value| engine.freeValue(value);
        pending = next;
    }
    return pending orelse try sdk.promise(engine, c.pi_js_undefined());
}
fn flag(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !bool {
    const value = try sdk.get(engine, object, name);
    defer engine.freeValue(value);
    return c.JS_ToBool(engine.context, value) == 1;
}
fn paths(engine: *engine_mod.Engine, allocator: std.mem.Allocator, options: c.JSValue, key: [*:0]const u8, cwd: []const u8, project: []const u8, root: []const u8, kind: []const u8, defaults: bool) ![]const []const u8 {
    var result: std.ArrayList([]const u8) = .empty;
    const additional = try sdk.get(engine, options, key);
    defer engine.freeValue(additional);
    if (c.JS_IsArray(additional)) for (0..try sdk.length(engine, additional)) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, additional, @intCast(index)));
        defer engine.freeValue(value);
        const path = try engine.toString(value);
        defer engine.gpa.free(path);
        try result.append(allocator, if (std.fs.path.isAbsolute(path)) try allocator.dupe(u8, path) else try std.fs.path.resolve(allocator, &.{ cwd, path }));
    };
    if (defaults) {
        try result.append(allocator, try std.fs.path.join(allocator, &.{ project, kind }));
        try result.append(allocator, try std.fs.path.join(allocator, &.{ root, kind }));
    }
    return result.items;
}
fn sourceInfo(engine: *engine_mod.Engine, path: []const u8, project: []const u8, root: []const u8) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const local = std.mem.startsWith(u8, path, project);
    const global = std.mem.startsWith(u8, path, root);
    try sdk.put(engine, result, "path", try sdk.text(engine, path));
    try sdk.put(engine, result, "source", try sdk.text(engine, if (local or global) "auto" else "cli"));
    try sdk.put(engine, result, "scope", try sdk.text(engine, if (local) "project" else if (global) "user" else "temporary"));
    try sdk.put(engine, result, "origin", try sdk.text(engine, "top-level"));
    if (local or global) try sdk.put(engine, result, "baseDir", try sdk.text(engine, if (local) project else root));
    return result;
}
fn publish(engine: *engine_mod.Engine, data: c.JSValue, name: [*:0]const u8, rows: c.JSValue, diagnostics: c.JSValue) !void {
    const result = try sdk.object(engine);
    defer engine.freeValue(result);
    try sdk.put(engine, result, name, c.JS_DupValue(engine.context, rows));
    try sdk.put(engine, result, "diagnostics", c.JS_DupValue(engine.context, diagnostics));
    try sdk.put(engine, data, name, c.JS_DupValue(engine.context, result));
}
fn duplicate(engine: *engine_mod.Engine, rows: c.JSValue, name: []const u8, path: []const u8, kind: []const u8, diagnostics: c.JSValue) !bool {
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const candidate = try sdk.get(engine, row, "name");
        defer engine.freeValue(candidate);
        const label = try engine.toString(candidate);
        defer engine.gpa.free(label);
        if (!std.mem.eql(u8, label, name)) continue;
        const diagnostic = try sdk.object(engine);
        defer engine.freeValue(diagnostic);
        try sdk.put(engine, diagnostic, "type", try sdk.text(engine, "collision"));
        const message = try std.fmt.allocPrint(engine.gpa, "name \"{s}{s}\" collision", .{ if (std.mem.eql(u8, kind, "prompt")) "/" else "", name });
        defer engine.gpa.free(message);
        try sdk.put(engine, diagnostic, "message", try sdk.text(engine, message));
        try sdk.put(engine, diagnostic, "path", try sdk.text(engine, path));
        const collision = try sdk.object(engine);
        defer engine.freeValue(collision);
        try sdk.put(engine, collision, "resourceType", try sdk.text(engine, kind));
        try sdk.put(engine, collision, "name", try sdk.text(engine, name));
        try sdk.put(engine, collision, "winnerPath", try sdk.get(engine, row, "filePath"));
        try sdk.put(engine, collision, "loserPath", try sdk.text(engine, path));
        try sdk.put(engine, diagnostic, "collision", c.JS_DupValue(engine.context, collision));
        try sdk.append(engine, diagnostics, c.JS_DupValue(engine.context, diagnostic));
        return true;
    }
    return false;
}
fn file(engine: *engine_mod.Engine, path: []const u8) !?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(engine.native_io.?, path, engine.gpa, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound, error.IsDir => null,
        else => return err,
    };
}
fn stripBom(value: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, value, "\xEF\xBB\xBF")) value[3..] else value;
}
fn promptFiles(engine: *engine_mod.Engine, data: c.JSValue, options: c.JSValue, project: []const u8, root: []const u8) !void {
    const explicit = try sdk.get(engine, options, "systemPrompt");
    defer engine.freeValue(explicit);
    try sdk.put(engine, data, "systemPrompt", c.pi_js_undefined());
    try sdk.put(engine, data, "systemPromptSource", c.pi_js_undefined());
    if (c.JS_IsString(explicit)) {
        try resolvePrompt(engine, data, "systemPrompt", explicit, true);
    } else for ([_][]const u8{ project, root }) |directory| {
        const path = try std.fs.path.join(engine.gpa, &.{ directory, "SYSTEM.md" });
        defer engine.gpa.free(path);
        if (try file(engine, path)) |contents| {
            defer engine.gpa.free(contents);
            try sdk.put(engine, data, "systemPrompt", try sdk.text(engine, stripBom(contents)));
            const source = try sdk.object(engine);
            defer engine.freeValue(source);
            try sdk.put(engine, source, "path", try sdk.text(engine, path));
            try sdk.put(engine, data, "systemPromptSource", c.JS_DupValue(engine.context, source));
            break;
        }
    }
    const appended = try sdk.array(engine);
    defer engine.freeValue(appended);
    const sources = try sdk.array(engine);
    defer engine.freeValue(sources);
    const supplied = try sdk.get(engine, options, "appendSystemPrompt");
    defer engine.freeValue(supplied);
    if (c.JS_IsArray(supplied)) {
        for (0..try sdk.length(engine, supplied)) |index| {
            const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, supplied, @intCast(index)));
            defer engine.freeValue(value);
            const text = try engine.toString(value);
            defer engine.gpa.free(text);
            if (try file(engine, text)) |contents| {
                defer engine.gpa.free(contents);
                try sdk.append(engine, appended, try sdk.text(engine, stripBom(contents)));
                const source = try sdk.object(engine);
                defer engine.freeValue(source);
                try sdk.put(engine, source, "path", c.JS_DupValue(engine.context, value));
                try sdk.append(engine, sources, c.JS_DupValue(engine.context, source));
            } else try sdk.append(engine, appended, c.JS_DupValue(engine.context, value));
        }
    } else for ([_][]const u8{ project, root }) |directory| {
        const path = try std.fs.path.join(engine.gpa, &.{ directory, "APPEND_SYSTEM.md" });
        defer engine.gpa.free(path);
        if (try file(engine, path)) |contents| {
            defer engine.gpa.free(contents);
            try sdk.append(engine, appended, try sdk.text(engine, stripBom(contents)));
            const source = try sdk.object(engine);
            defer engine.freeValue(source);
            try sdk.put(engine, source, "path", try sdk.text(engine, path));
            try sdk.append(engine, sources, c.JS_DupValue(engine.context, source));
            break;
        }
    }
    try sdk.put(engine, data, "appendSystemPrompt", c.JS_DupValue(engine.context, appended));
    try sdk.put(engine, data, "appendSystemPromptSources", c.JS_DupValue(engine.context, sources));
}
fn resolvePrompt(engine: *engine_mod.Engine, data: c.JSValue, name: [*:0]const u8, input: c.JSValue, system: bool) !void {
    const path = try engine.toString(input);
    defer engine.gpa.free(path);
    if (try file(engine, path)) |contents| {
        defer engine.gpa.free(contents);
        try sdk.put(engine, data, name, try sdk.text(engine, stripBom(contents)));
        if (system) {
            const source = try sdk.object(engine);
            defer engine.freeValue(source);
            try sdk.put(engine, source, "path", c.JS_DupValue(engine.context, input));
            try sdk.put(engine, data, "systemPromptSource", c.JS_DupValue(engine.context, source));
        }
    } else try sdk.put(engine, data, name, c.JS_DupValue(engine.context, input));
}
