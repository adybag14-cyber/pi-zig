//! Owner-native agent settings and document helpers.
const std = @import("std");
const engine_mod = @import("engine.zig");
const durable = @import("native_durable.zig");
const sdk = @import("native_sdk.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;
const defaults =
    \\{"stream":{},"retry":{"enabled":true,"maxRetries":3,"baseDelayMs":2000,"maxAgentDelayMs":60000},"compaction":{"enabled":true,"reserveTokens":16384,"keepRecentTokens":20000,"backgroundTokens":32768},"progress":{"partialIntervalMs":100,"outputIntervalMs":100},"toolExecution":"parallel","steeringMode":"one-at-a-time","followUpMode":"one-at-a-time","contextRetentionMs":600000}
;
pub fn settings(engine: *Engine, input: c.JSValue) !c.JSValue {
    var data = try @import("../durable/backend/json.zig").Owned.parse(engine.gpa, defaults);
    defer data.deinit();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const absent = c.JS_IsUndefined(input) or c.JS_IsNull(input);
    const extensions = if (absent) c.pi_js_undefined() else try sdk.get(engine, input, "extensions");
    defer engine.freeValue(extensions);
    if (!c.JS_IsUndefined(extensions)) try sdk.put(engine, result, "extensions", c.JS_DupValue(engine.context, extensions));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const object = try sdk.get(engine, global, "Object");
    defer engine.freeValue(object);
    const fallback = try durable.jsValue(engine, data.value);
    defer engine.freeValue(fallback);
    inline for (.{ "stream", "retry", "compaction", "progress" }, .{ "", "DEFAULT_RETRY_POLICY", "DEFAULT_COMPACTION_POLICY", "DEFAULT_PROGRESS_POLICY" }) |name, exported| {
        const base = if (exported.len != 0 and engine.native_module_values.get("@earendil-works/pi-durable") != null)
            try sdk.get(engine, engine.native_module_values.get("@earendil-works/pi-durable").?, exported)
        else
            try sdk.get(engine, fallback, name);
        defer engine.freeValue(base);
        const target = try sdk.object(engine);
        errdefer engine.freeValue(target);
        if (comptime std.mem.eql(u8, name, "progress")) {
            // The source resolves progress field by field; additional mutable
            // default properties are not part of the resulting settings.
            inline for (.{ "partialIntervalMs", "outputIntervalMs" }) |key| try sdk.put(engine, target, key, try sdk.get(engine, base, key));
        } else {
            const copied = try sdk.invoke(engine, object, "assign", &.{ target, base });
            engine.freeValue(copied);
        }
        try sdk.put(engine, result, name, target);
    }
    inline for (.{ "toolExecution", "steeringMode", "followUpMode", "contextRetentionMs" }) |name| try sdk.put(engine, result, name, try sdk.get(engine, fallback, name));
    if (absent) return result;
    inline for (.{ "stream", "retry", "compaction" }) |name| {
        const selected = try sdk.get(engine, input, name);
        defer engine.freeValue(selected);
        if (!c.JS_IsUndefined(selected) and !c.JS_IsNull(selected)) {
            const target = try sdk.get(engine, result, name);
            defer engine.freeValue(target);
            const copied = try sdk.invoke(engine, object, "assign", &.{ target, selected });
            engine.freeValue(copied);
        }
    }
    const progress = try sdk.get(engine, input, "progress");
    defer engine.freeValue(progress);
    if (!c.JS_IsUndefined(progress) and !c.JS_IsNull(progress)) {
        const target = try sdk.get(engine, result, "progress");
        defer engine.freeValue(target);
        inline for (.{ "partialIntervalMs", "outputIntervalMs" }) |name| {
            const value = try sdk.get(engine, progress, name);
            defer engine.freeValue(value);
            if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) try sdk.put(engine, target, name, c.JS_DupValue(engine.context, value));
        }
    }
    inline for (.{ "toolExecution", "steeringMode", "followUpMode", "contextRetentionMs" }) |name| {
        const value = try sdk.get(engine, input, name);
        defer engine.freeValue(value);
        if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) try sdk.put(engine, result, name, c.JS_DupValue(engine.context, value));
    }
    return result;
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    const resolved = try settings(engine, c.pi_js_undefined());
    defer engine.freeValue(resolved);
    inline for (.{ "retry", "compaction", "progress" }, .{ "DEFAULT_RETRY_POLICY", "DEFAULT_COMPACTION_POLICY", "DEFAULT_PROGRESS_POLICY" }) |name, exported_name| try sdk.put(engine, exports, exported_name, try sdk.get(engine, resolved, name));
    var metadata = try @import("../durable/backend/json.zig").Owned.parse(engine.gpa, "{\"kind\":\"pi.agent\",\"version\":1,\"scope\":\"conversation\",\"history\":\"rewindable\",\"fork\":\"asOf\"}");
    defer metadata.deinit();
    const definition = try durable.jsValue(engine, metadata.value);
    defer engine.freeValue(definition);
    try sdk.put(engine, definition, "initial", try engine.checked(c.JS_NewCFunction(engine.context, initialAgent, "initial", 0)));
    try sdk.put(engine, definition, "checkpointWhen", try engine.checked(c.JS_NewCFunction(engine.context, checkpointAgent, "checkpointWhen", 0)));
    const token = try sdk.object(engine);
    defer engine.freeValue(token);
    try sdk.put(engine, token, "definition", c.JS_DupValue(engine.context, definition));
    try sdk.put(engine, exports, "AgentDoc", c.JS_DupValue(engine.context, token));
    try sdk.put(engine, exports, "INSTRUCTIONS_KEY", try sdk.text(engine, "instructions"));
    var data_values = [_]c.JSValue{token};
    try sdk.put(engine, exports, "configure", try engine.checked(c.JS_NewCFunctionData(engine.context, configure, 3, 0, 1, &data_values)));
}
fn field(engine: *Engine, value: c.JSValue, name: [:0]const u8) !c.JSValue {
    return if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) c.pi_js_undefined() else sdk.get(engine, value, name);
}
fn construct(engine: *Engine, name: [:0]const u8) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, name);
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn mapSet(engine: *Engine, map: c.JSValue, key: c.JSValue, value: c.JSValue) !void {
    const ignored = try sdk.invoke(engine, map, "set", &.{ key, value });
    engine.freeValue(ignored);
}
fn includes(engine: *Engine, array: c.JSValue, value: c.JSValue) !bool {
    if (c.JS_IsUndefined(array) or c.JS_IsNull(array)) return false;
    const result = try sdk.invoke(engine, array, "includes", &.{value});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn callerTools(engine: *Engine, enabled: c.JSValue, caller: []const u8) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    const name = try sdk.text(engine, caller);
    defer engine.freeValue(name);
    for (0..try sdk.length(engine, enabled)) |index| {
        const tool = try at(engine, enabled, index);
        defer engine.freeValue(tool);
        const callers = try sdk.get(engine, tool, "callers");
        defer engine.freeValue(callers);
        const allowed = if (c.JS_IsUndefined(callers)) true else blk: {
            const selected = try sdk.invoke(engine, callers, "includes", &.{name});
            defer engine.freeValue(selected);
            break :blk c.JS_ToBool(engine.context, selected) != 0;
        };
        if (allowed) try sdk.append(engine, result, c.JS_DupValue(engine.context, tool));
    }
    return result;
}
fn filterTools(engine: *Engine, tools: c.JSValue, filter: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(filter)) return c.JS_DupValue(engine.context, tools);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsArray(filter)) {
        const used = try sdk.array(engine);
        defer engine.freeValue(used);
        for (0..try sdk.length(engine, filter)) |index| {
            const name = try at(engine, filter, index);
            defer engine.freeValue(name);
            if (try includes(engine, used, name)) continue;
            try sdk.append(engine, used, c.JS_DupValue(engine.context, name));
            for (0..try sdk.length(engine, tools)) |tool_index| {
                const tool = try at(engine, tools, tool_index);
                defer engine.freeValue(tool);
                const tool_name = try sdk.get(engine, tool, "name");
                defer engine.freeValue(tool_name);
                if (c.JS_IsStrictEqual(engine.context, name, tool_name)) {
                    try sdk.append(engine, result, c.JS_DupValue(engine.context, tool));
                    break;
                }
            }
        }
    } else {
        const removed = try sdk.get(engine, filter, "remove");
        defer engine.freeValue(removed);
        for (0..try sdk.length(engine, tools)) |index| {
            const tool = try at(engine, tools, index);
            defer engine.freeValue(tool);
            const name = try sdk.get(engine, tool, "name");
            defer engine.freeValue(name);
            if (!try includes(engine, removed, name)) try sdk.append(engine, result, c.JS_DupValue(engine.context, tool));
        }
    }
    return result;
}
fn at(engine: *Engine, array: c.JSValue, index: usize) !c.JSValue {
    return engine.checked(c.JS_GetPropertyUint32(engine.context, array, @intCast(index)));
}
fn values(engine: *Engine, map: c.JSValue) !c.JSValue {
    const iterator = try sdk.invoke(engine, map, "values", &.{});
    defer engine.freeValue(iterator);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const array = try sdk.get(engine, global, "Array");
    defer engine.freeValue(array);
    return sdk.invoke(engine, array, "from", &.{iterator});
}
fn report(engine: *Engine, callback: c.JSValue, failure: c.JSValue) !void {
    if (c.JS_IsUndefined(callback) or c.JS_IsNull(callback)) return;
    var args = [_]c.JSValue{failure};
    const result = try engine.checked(c.JS_Call(engine.context, callback, c.pi_js_undefined(), 1, &args));
    engine.freeValue(result);
}
/// Resolve refs on the owner. Maps preserve last-writer values and first insertion order.
pub fn resolve(engine: *Engine, state: c.JSValue, snapshot: c.JSValue, resolved_settings: c.JSValue, reporter: c.JSValue) !c.JSValue {
    const selected = try field(engine, state, "extensions");
    defer engine.freeValue(selected);
    const extensions = try sdk.array(engine);
    defer engine.freeValue(extensions);
    const names = try sdk.array(engine);
    defer engine.freeValue(names);
    const removed = if (c.JS_IsArray(selected)) c.pi_js_undefined() else try field(engine, selected, "remove");
    defer engine.freeValue(removed);
    if (c.JS_IsArray(selected)) {
        for (0..try sdk.length(engine, selected)) |index| try sdk.append(engine, names, try at(engine, selected, index));
    } else {
        const defaults_extensions = try field(engine, resolved_settings, "extensions");
        defer engine.freeValue(defaults_extensions);
        const base = if (c.JS_IsUndefined(defaults_extensions)) try sdk.invoke(engine, snapshot, "installed", &.{}) else c.JS_DupValue(engine.context, defaults_extensions);
        defer engine.freeValue(base);
        for (0..try sdk.length(engine, base)) |index| {
            const extension = try at(engine, base, index);
            defer engine.freeValue(extension);
            try sdk.append(engine, names, try sdk.get(engine, extension, "name"));
        }
        const added = try field(engine, selected, "add");
        defer engine.freeValue(added);
        if (!c.JS_IsUndefined(added)) for (0..try sdk.length(engine, added)) |index| try sdk.append(engine, names, try at(engine, added, index));
    }
    const seen = try construct(engine, "Map");
    defer engine.freeValue(seen);
    for (0..try sdk.length(engine, names)) |index| {
        const name = try at(engine, names, index);
        defer engine.freeValue(name);
        if (try includes(engine, removed, name)) continue;
        const present = try sdk.invoke(engine, seen, "has", &.{name});
        defer engine.freeValue(present);
        if (c.JS_ToBool(engine.context, present) != 0) continue;
        try mapSet(engine, seen, name, c.pi_js_bool(engine.context, 1));
        const extension = try sdk.invoke(engine, snapshot, "extension", &.{name});
        defer engine.freeValue(extension);
        if (!c.JS_IsUndefined(extension)) try sdk.append(engine, extensions, c.JS_DupValue(engine.context, extension));
    }
    const tools = try construct(engine, "Map");
    defer engine.freeValue(tools);
    const sections = try construct(engine, "Map");
    defer engine.freeValue(sections);
    for (0..try sdk.length(engine, extensions)) |index| {
        const extension = try at(engine, extensions, index);
        defer engine.freeValue(extension);
        inline for (.{ "tools", "sections" }, .{ "name", "key" }) |member, key_name| {
            const items = try field(engine, extension, member);
            defer engine.freeValue(items);
            if (!c.JS_IsUndefined(items)) {
                for (0..try sdk.length(engine, items)) |item_index| {
                    const item = try at(engine, items, item_index);
                    defer engine.freeValue(item);
                    const key = try sdk.get(engine, item, key_name);
                    defer engine.freeValue(key);
                    try mapSet(engine, if (comptime std.mem.eql(u8, member, "tools")) tools else sections, key, item);
                }
            }
        }
    }
    for (0..try sdk.length(engine, extensions)) |index| {
        const extension = try at(engine, extensions, index);
        defer engine.freeValue(extension);
        const wraps = try field(engine, extension, "wraps");
        defer engine.freeValue(wraps);
        if (c.JS_IsUndefined(wraps)) continue;
        for (0..try sdk.length(engine, wraps)) |wrap_index| {
            const wrap = try at(engine, wraps, wrap_index);
            defer engine.freeValue(wrap);
            const tool_atom = c.JS_NewAtom(engine.context, "tool");
            defer c.JS_FreeAtom(engine.context, tool_atom);
            const is_tool = c.JS_HasProperty(engine.context, wrap, tool_atom);
            if (is_tool < 0) return error.JavaScriptException;
            const map = if (is_tool != 0) tools else sections;
            const target = try sdk.get(engine, wrap, if (is_tool != 0) "tool" else "section");
            defer engine.freeValue(target);
            const item = try sdk.invoke(engine, map, "get", &.{target});
            defer engine.freeValue(item);
            if (c.JS_IsUndefined(item)) continue;
            const callback = try sdk.get(engine, wrap, "wrap");
            defer engine.freeValue(callback);
            var arguments = [_]c.JSValue{item};
            const wrapped = c.JS_Call(engine.context, callback, wrap, 1, &arguments);
            defer engine.freeValue(wrapped);
            var failure = c.pi_js_undefined();
            defer engine.freeValue(failure);
            if (c.JS_IsException(wrapped)) {
                failure = c.JS_GetException(engine.context);
            } else {
                const name = c.JS_GetPropertyStr(engine.context, wrapped, if (is_tool != 0) "name" else "key");
                defer engine.freeValue(name);
                if (c.JS_IsException(name)) {
                    failure = c.JS_GetException(engine.context);
                } else if (!c.JS_IsStrictEqual(engine.context, name, target)) {
                    const old_name = try engine.toString(target);
                    defer engine.gpa.free(old_name);
                    const new_name = try engine.toString(name);
                    defer engine.gpa.free(new_name);
                    const message = try std.fmt.allocPrint(engine.gpa, "Wrapper renamed {s} to {s}", .{ old_name, new_name });
                    defer engine.gpa.free(message);
                    const text = try sdk.text(engine, message);
                    defer engine.freeValue(text);
                    const global = c.JS_GetGlobalObject(engine.context);
                    defer engine.freeValue(global);
                    const constructor = try sdk.get(engine, global, "Error");
                    defer engine.freeValue(constructor);
                    var args = [_]c.JSValue{text};
                    failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
                } else {
                    try mapSet(engine, map, target, wrapped);
                    continue;
                }
            }
            const deleted = try sdk.invoke(engine, map, "delete", &.{target});
            engine.freeValue(deleted);
            try report(engine, reporter, failure);
        }
    }
    const filter = try field(engine, state, "tools");
    defer engine.freeValue(filter);
    const filtered = try sdk.array(engine);
    defer engine.freeValue(filtered);
    if (c.JS_IsArray(filter)) {
        const used = try sdk.array(engine);
        defer engine.freeValue(used);
        for (0..try sdk.length(engine, filter)) |index| {
            const name = try at(engine, filter, index);
            defer engine.freeValue(name);
            if (try includes(engine, used, name)) continue;
            try sdk.append(engine, used, c.JS_DupValue(engine.context, name));
            const tool = try sdk.invoke(engine, tools, "get", &.{name});
            defer engine.freeValue(tool);
            if (!c.JS_IsUndefined(tool)) try sdk.append(engine, filtered, c.JS_DupValue(engine.context, tool));
        }
    } else {
        const all = try values(engine, tools);
        defer engine.freeValue(all);
        const remove = try field(engine, filter, "remove");
        defer engine.freeValue(remove);
        for (0..try sdk.length(engine, all)) |index| {
            const tool = try at(engine, all, index);
            defer engine.freeValue(tool);
            const name = try sdk.get(engine, tool, "name");
            defer engine.freeValue(name);
            if (!try includes(engine, remove, name)) try sdk.append(engine, filtered, c.JS_DupValue(engine.context, tool));
        }
    }
    const model_candidates = try callerTools(engine, filtered, "model");
    defer engine.freeValue(model_candidates);
    const model_filter = try field(engine, state, "modelTools");
    defer engine.freeValue(model_filter);
    const offered = try filterTools(engine, model_candidates, model_filter);
    defer engine.freeValue(offered);
    const callable = try callerTools(engine, filtered, "tools");
    defer engine.freeValue(callable);
    const agent_sections = try values(engine, sections);
    defer engine.freeValue(agent_sections);
    const instructions = try field(engine, state, "instructions");
    defer engine.freeValue(instructions);
    if (!c.JS_IsUndefined(instructions)) {
        const section = try sdk.object(engine);
        errdefer engine.freeValue(section);
        try sdk.put(engine, section, "key", try sdk.text(engine, "instructions"));
        var capture = [_]c.JSValue{instructions};
        try sdk.put(engine, section, "render", try engine.checked(c.JS_NewCFunctionData(engine.context, renderInstructions, 0, 0, 1, &capture)));
        try sdk.append(engine, agent_sections, section);
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    const model = try field(engine, state, "model");
    defer engine.freeValue(model);
    if (!c.JS_IsUndefined(model)) try sdk.put(engine, result, "model", c.JS_DupValue(engine.context, model));
    const thinking = try field(engine, state, "thinkingLevel");
    defer engine.freeValue(thinking);
    try sdk.put(engine, result, "thinkingLevel", if (c.JS_IsUndefined(thinking) or c.JS_IsNull(thinking)) try sdk.text(engine, "off") else c.JS_DupValue(engine.context, thinking));
    try sdk.put(engine, result, "extensions", c.JS_DupValue(engine.context, extensions));
    try sdk.put(engine, result, "tools", c.JS_DupValue(engine.context, offered));
    try sdk.put(engine, result, "callable", c.JS_DupValue(engine.context, callable));
    try sdk.put(engine, result, "sections", c.JS_DupValue(engine.context, agent_sections));
    if (!c.JS_IsUndefined(instructions)) try sdk.put(engine, result, "instructions", c.JS_DupValue(engine.context, instructions));
    const cwd = try field(engine, state, "cwd");
    defer engine.freeValue(cwd);
    if (!c.JS_IsUndefined(cwd)) try sdk.put(engine, result, "cwd", c.JS_DupValue(engine.context, cwd));
    return result;
}
fn renderInstructions(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.JS_DupValue(context, data[0]);
}
pub fn resolveConversation(engine: *Engine, session: c.JSValue, options: c.JSValue, id: c.JSValue, snapshot_arg: c.JSValue, context: c.JSValue) !c.JSValue {
    const snapshot = if (!c.JS_IsUndefined(snapshot_arg) and !c.JS_IsNull(snapshot_arg)) c.JS_DupValue(engine.context, snapshot_arg) else blk: {
        const registry = try sdk.get(engine, options, "registry");
        defer engine.freeValue(registry);
        break :blk try sdk.invoke(engine, registry, "snapshot", &.{});
    };
    defer engine.freeValue(snapshot);
    const exports = engine.native_module_values.get("@earendil-works/pi-durable") orelse return error.DurableExportsUnavailable;
    const token = try sdk.get(engine, exports, "AgentDoc");
    defer engine.freeValue(token);
    const pending = try @import("native_durable_documents.zig").snapshot(engine, session, &.{ token, id, context });
    defer engine.freeValue(pending);
    var captures = [_]c.JSValue{ snapshot, options };
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, resolvedConversation, 1, 0, captures.len, &captures));
    defer engine.freeValue(callback);
    return sdk.invoke(engine, pending, "then", &.{callback});
}
fn resolvedConversation(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return resolvedConversationOwned(engine, if (argc == 0) c.pi_js_undefined() else argv[0], data[0], data[1]) catch |err| durable.reject(engine, err);
}
fn resolvedConversationOwned(engine: *Engine, state: c.JSValue, snapshot: c.JSValue, options: c.JSValue) !c.JSValue {
    const resolved_settings = try runtimeSettings(engine, options);
    defer engine.freeValue(resolved_settings);
    const reporter = try sdk.get(engine, options, "onReport");
    defer engine.freeValue(reporter);
    return resolve(engine, state, snapshot, resolved_settings, reporter);
}
pub fn runtimeSettings(engine: *Engine, options: c.JSValue) !c.JSValue {
    const input = try sdk.get(engine, options, "settings");
    defer engine.freeValue(input);
    return settings(engine, input);
}
fn initialAgent(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return sdk.object(engine) catch |err| durable.reject(engine, err);
}
fn checkpointAgent(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return c.pi_js_bool(context, 1);
}
fn configure(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc < 3) return durable.rejectedPromise(engine, error.AgentChangeArgumentsRequired);
    return configureOwned(engine, argv[0], argv[1], argv[2], data[0]) catch |err| durable.rejectedPromise(engine, err);
}
pub fn configureOwned(engine: *Engine, tx: c.JSValue, conversation: c.JSValue, change: c.JSValue, token: c.JSValue) !c.JSValue {
    const promise = try @import("native_durable_documents.zig").acquire(engine, tx, &.{ token, conversation });
    defer engine.freeValue(promise);
    var data = [_]c.JSValue{change};
    const callback = try engine.checked(c.JS_NewCFunctionData(engine.context, configured, 1, 0, 1, &data));
    defer engine.freeValue(callback);
    return sdk.invoke(engine, promise, "then", &.{callback});
}
fn configured(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (argc == 0) return durable.reject(engine, error.AgentDraftRequired);
    applyChange(engine, argv[0], data[0]) catch |err| return durable.reject(engine, err);
    return c.pi_js_undefined();
}
fn applyChange(engine: *Engine, draft: c.JSValue, change: c.JSValue) !void {
    var normalized = try @import("native_durable_harness.zig").agentChange(engine, change);
    defer normalized.deinit();
    for (normalized.value.object.keys(), normalized.value.object.values()) |name, value| {
        const key = try engine.gpa.dupeZ(u8, name);
        defer engine.gpa.free(key);
        if (value == .null) {
            const atom = c.JS_NewAtom(engine.context, key.ptr);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DeleteProperty(engine.context, draft, atom, c.JS_PROP_THROW) < 0) {
                const failure = c.JS_GetException(engine.context);
                _ = try engine.checked(c.JS_Throw(engine.context, failure));
            }
        } else if (c.JS_SetPropertyStr(engine.context, draft, key.ptr, try durable.jsValue(engine, value)) < 0) {
            const failure = c.JS_GetException(engine.context);
            _ = try engine.checked(c.JS_Throw(engine.context, failure));
        }
    }
}

test "native durable VM eba model and tools callers match actual Source selection order and definition identity" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    const captured = try engine.checked(c.JS_ParseJSON(engine.context, @embedFile("../durable/fixtures/durable-tool-callers-eba.json"), @embedFile("../durable/fixtures/durable-tool-callers-eba.json").len, "actual-eba-callers"));
    defer engine.freeValue(captured);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try sdk.put(engine, global, "callerFixture", c.JS_DupValue(engine.context, captured));
    const Callback = struct {
        fn run(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
            const owner = Engine.fromContext(context.?);
            if (argc < 2) return durable.reject(owner, error.ExpectedCallerFixture);
            const resolved = settings(owner, c.pi_js_undefined()) catch |err| return durable.reject(owner, err);
            defer owner.freeValue(resolved);
            return resolve(owner, argv[0], argv[1], resolved, c.pi_js_undefined()) catch |err| durable.reject(owner, err);
        }
    };
    try sdk.put(engine, global, "nativeResolveCallerFixture", try engine.checked(c.JS_NewCFunction(engine.context, Callback.run, "resolve", 2)));
    const result = engine.evalModule(
        \\const base=callerFixture.base;
        \\const extension={name:'base',tools:base};
        \\const snapshot={installed:()=>[extension],extension:name=>name==='base'?extension:undefined};
        \\for(const row of callerFixture.cases.filter(c=>c.name.startsWith('selection-'))){
        \\ const agent=nativeResolveCallerFixture(row.state??undefined,snapshot);
        \\ for(const field of ['tools','callable'])if(JSON.stringify(agent[field].map(t=>t.name))!==JSON.stringify(row[field]))throw Error(row.name+':'+field);
        \\ if(![...agent.tools,...agent.callable].every(t=>base.includes(t)))throw Error('definition identity');
        \\}
        \\const replacement={name:'default',callers:['tools']},wrapped={name:'both',callers:['model']};
        \\const extensions=[extension,{name:'override',tools:[replacement],wraps:[{tool:'both',wrap:()=>wrapped}]}];
        \\const overridden=nativeResolveCallerFixture(undefined,{installed:()=>extensions,extension:name=>extensions.find(e=>e.name===name)});
        \\const expected=callerFixture.cases.find(c=>c.name==='override-wrap');
        \\for(const field of ['tools','callable'])if(JSON.stringify(overridden[field].map(t=>t.name))!==JSON.stringify(expected[field]))throw Error('override '+field);
        \\if(overridden.callable[0]!==replacement||overridden.tools[0]!==wrapped)throw Error('wrapped identity');
        \\for(const callers of [null,3,'model']){
        \\ const odd={name:'base',tools:[{name:'odd',callers}]};const source=callerFixture.cases.find(c=>c.name==='odd-'+String(callers));
        \\ let actual;try{actual=nativeResolveCallerFixture(undefined,{installed:()=>[odd],extension:()=>odd});}catch(error){if(error.name!==source.error)throw error;continue;}
        \\ if(source.error||JSON.stringify(actual.tools.map(t=>t.name))!==JSON.stringify(source.tools)||JSON.stringify(actual.callable.map(t=>t.name))!==JSON.stringify(source.callable))throw Error('odd callers');
        \\}
    , "eba-actual-caller-fixture") catch |err| {
        std.debug.print("Actual Source callers: {s}\n", .{engine.last_error orelse "no diagnostic"});
        return err;
    };
    engine.freeValue(result);
}
