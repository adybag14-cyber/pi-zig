//! Source billed session totals, separate from current-context estimation.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const c = em.c;
fn number(engine: *em.Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return @import("native_js_values.zig").capture(engine);
    return result;
}
fn fieldNumber(engine: *em.Engine, value: c.JSValue, key: [*:0]const u8) !f64 {
    const field = try sdk.get(engine, value, key);
    defer engine.freeValue(field);
    return number(engine, field);
}
fn is(engine: *em.Engine, object: c.JSValue, key: [*:0]const u8, expected: []const u8) !bool {
    const value = try sdk.get(engine, object, key);
    defer engine.freeValue(value);
    const text = try sdk.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
const Totals = struct {
    input: f64 = 0,
    output: f64 = 0,
    cache_read: f64 = 0,
    cache_write: f64 = 0,
    cost: f64 = 0,
    fn add(self: *Totals, engine: *em.Engine, usage: c.JSValue) !void {
        self.input += try fieldNumber(engine, usage, "input");
        self.output += try fieldNumber(engine, usage, "output");
        self.cache_read += try fieldNumber(engine, usage, "cacheRead");
        self.cache_write += try fieldNumber(engine, usage, "cacheWrite");
        const cost = try sdk.get(engine, usage, "cost");
        defer engine.freeValue(cost);
        self.cost += try fieldNumber(engine, cost, "total");
    }
};
pub fn billed(engine: *em.Engine, manager: c.JSValue) !c.JSValue {
    const entries = try sdk.invoke(engine, manager, "getEntries", &.{});
    defer engine.freeValue(entries);
    var totals: Totals = .{};
    var users: u32 = 0;
    var assistants: u32 = 0;
    var results: u32 = 0;
    var messages: u32 = 0;
    var calls: u32 = 0;
    for (0..try sdk.length(engine, entries)) |index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.freeValue(entry);
        if (try is(engine, entry, "type", "usage")) {
            const usage = try sdk.get(engine, entry, "usage");
            defer engine.freeValue(usage);
            try totals.add(engine, usage);
        } else if (try is(engine, entry, "type", "branch_summary") or try is(engine, entry, "type", "compaction")) {
            const usage = try sdk.get(engine, entry, "usage");
            defer engine.freeValue(usage);
            if (c.JS_ToBool(engine.context, usage) == 1) try totals.add(engine, usage);
        }
        if (!try is(engine, entry, "type", "message")) continue;
        messages += 1;
        const message = try sdk.get(engine, entry, "message");
        defer engine.freeValue(message);
        if (try is(engine, message, "role", "user")) {
            users += 1;
        } else if (try is(engine, message, "role", "toolResult")) {
            results += 1;
            const usage = try sdk.get(engine, message, "usage");
            defer engine.freeValue(usage);
            if (c.JS_ToBool(engine.context, usage) == 1) try totals.add(engine, usage);
        } else if (try is(engine, message, "role", "assistant")) {
            assistants += 1;
            const content = try sdk.get(engine, message, "content");
            defer engine.freeValue(content);
            if (c.JS_IsArray(content)) for (0..try sdk.length(engine, content)) |part_index| {
                const part = try engine.checked(c.JS_GetPropertyUint32(engine.context, content, @intCast(part_index)));
                defer engine.freeValue(part);
                if (try is(engine, part, "type", "toolCall")) calls += 1;
            };
            const usage = try sdk.get(engine, message, "usage");
            defer engine.freeValue(usage);
            try totals.add(engine, usage);
        }
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "userMessages", users }, .{ "assistantMessages", assistants }, .{ "toolCalls", calls }, .{ "toolResults", results }, .{ "totalMessages", messages } }) |pair| try sdk.put(engine, result, pair[0], c.JS_NewUint32(engine.context, pair[1]));
    const tokens = try sdk.object(engine);
    defer engine.freeValue(tokens);
    inline for (.{ .{ "input", totals.input }, .{ "output", totals.output }, .{ "cacheRead", totals.cache_read }, .{ "cacheWrite", totals.cache_write }, .{ "total", totals.input + totals.output + totals.cache_read + totals.cache_write } }) |pair| try sdk.put(engine, tokens, pair[0], c.JS_NewFloat64(engine.context, pair[1]));
    try sdk.put(engine, result, "tokens", c.JS_DupValue(engine.context, tokens));
    try sdk.put(engine, result, "cost", c.JS_NewFloat64(engine.context, totals.cost));
    return result;
}

fn at(engine: *em.Engine, values: c.JSValue, index: usize) !c.JSValue {
    return engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
}
fn chars(engine: *em.Engine, value: c.JSValue) !f64 {
    return fieldNumber(engine, value, "length");
}
fn encodedChars(engine: *em.Engine, value: c.JSValue) !f64 {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const json = try sdk.get(engine, global, "JSON");
    defer engine.freeValue(json);
    const encoded = try sdk.invoke(engine, json, "stringify", &.{value});
    defer engine.freeValue(encoded);
    return chars(engine, encoded);
}
fn textImageChars(engine: *em.Engine, content: c.JSValue) !f64 {
    if (c.JS_IsString(content)) return chars(engine, content);
    var total: f64 = 0;
    for (0..try sdk.length(engine, content)) |index| {
        const block = try at(engine, content, index);
        defer engine.freeValue(block);
        if (try is(engine, block, "type", "text")) {
            const text = try sdk.get(engine, block, "text");
            defer engine.freeValue(text);
            if (c.JS_ToBool(engine.context, text) == 1) total += try chars(engine, text);
        } else if (try is(engine, block, "type", "image")) total += 4800;
    }
    return total;
}
fn objectValues(engine: *em.Engine, object: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Object");
    defer engine.freeValue(constructor);
    return sdk.invoke(engine, constructor, "values", &.{object});
}
pub fn estimateTokens(engine: *em.Engine, message: c.JSValue) !f64 {
    var count: f64 = 0;
    if (try is(engine, message, "role", "system")) {
        const content = try sdk.get(engine, message, "content");
        defer engine.freeValue(content);
        count = try textImageChars(engine, content);
        const sections = try sdk.get(engine, message, "sections");
        defer engine.freeValue(sections);
        if (c.JS_ToBool(engine.context, sections) == 1) {
            const values = try objectValues(engine, sections);
            defer engine.freeValue(values);
            for (0..try sdk.length(engine, values)) |index| {
                const section = try at(engine, values, index);
                defer engine.freeValue(section);
                if (c.JS_ToBool(engine.context, section) == 1) count += try chars(engine, section);
            }
        }
        const tools = try sdk.get(engine, message, "toolsAdded");
        defer engine.freeValue(tools);
        if (c.JS_ToBool(engine.context, tools) == 1) count += try encodedChars(engine, tools);
    } else if (try is(engine, message, "role", "user") or try is(engine, message, "role", "custom") or try is(engine, message, "role", "toolResult")) {
        const content = try sdk.get(engine, message, "content");
        defer engine.freeValue(content);
        count = try textImageChars(engine, content);
    } else if (try is(engine, message, "role", "assistant")) {
        const content = try sdk.get(engine, message, "content");
        defer engine.freeValue(content);
        for (0..try sdk.length(engine, content)) |index| {
            const block = try at(engine, content, index);
            defer engine.freeValue(block);
            if (try is(engine, block, "type", "text") or try is(engine, block, "type", "thinking")) {
                const text = try sdk.get(engine, block, if (try is(engine, block, "type", "text")) "text" else "thinking");
                defer engine.freeValue(text);
                count += try chars(engine, text);
            } else if (try is(engine, block, "type", "toolCall")) {
                const name = try sdk.get(engine, block, "name");
                defer engine.freeValue(name);
                const arguments = try sdk.get(engine, block, "arguments");
                defer engine.freeValue(arguments);
                count += try chars(engine, name) + try encodedChars(engine, arguments);
            }
        }
    } else if (try is(engine, message, "role", "bashExecution")) {
        const command = try sdk.get(engine, message, "command");
        defer engine.freeValue(command);
        const output = try sdk.get(engine, message, "output");
        defer engine.freeValue(output);
        count = try chars(engine, command) + try chars(engine, output);
    } else if (try is(engine, message, "role", "branchSummary") or try is(engine, message, "role", "compactionSummary")) {
        const summary = try sdk.get(engine, message, "summary");
        defer engine.freeValue(summary);
        count = try chars(engine, summary);
    }
    return @ceil(count / 4);
}
fn usageTokens(engine: *em.Engine, usage: c.JSValue) !f64 {
    const total = try sdk.get(engine, usage, "totalTokens");
    defer engine.freeValue(total);
    if (c.JS_ToBool(engine.context, total) == 1) return number(engine, total);
    return try fieldNumber(engine, usage, "input") + try fieldNumber(engine, usage, "output") + try fieldNumber(engine, usage, "cacheRead") + try fieldNumber(engine, usage, "cacheWrite");
}
fn assistantUsage(engine: *em.Engine, message: c.JSValue) !?f64 {
    if (!try is(engine, message, "role", "assistant")) return null;
    const atom = c.JS_NewAtom(engine.context, "usage");
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    defer c.JS_FreeAtom(engine.context, atom);
    const present = c.JS_HasProperty(engine.context, message, atom);
    if (present < 0) return @import("native_js_values.zig").capture(engine);
    if (present == 0) return null;
    if (try is(engine, message, "stopReason", "aborted") or try is(engine, message, "stopReason", "error")) return null;
    const usage = try sdk.get(engine, message, "usage");
    defer engine.freeValue(usage);
    if (c.JS_ToBool(engine.context, usage) != 1) return null;
    const total = try usageTokens(engine, usage);
    return if (total > 0) total else null;
}

fn newMap(engine: *em.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Map");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn newWeakMap(engine: *em.Engine) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "WeakMap");
    defer engine.freeValue(constructor);
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 0, null));
}
fn callDiscard(engine: *em.Engine, object: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !void {
    const value = try sdk.invoke(engine, object, name, args);
    engine.freeValue(value);
}
fn arrayFrom(engine: *em.Engine, iterable: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Array");
    defer engine.freeValue(constructor);
    return sdk.invoke(engine, constructor, "from", &.{iterable});
}
fn objectEntries(engine: *em.Engine, object: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const constructor = try sdk.get(engine, global, "Object");
    defer engine.freeValue(constructor);
    return sdk.invoke(engine, constructor, "entries", &.{object});
}
/// Source transcript replay folds system content, named sections and tool deltas.
fn currentSystem(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    const content = try sdk.array(engine);
    defer engine.freeValue(content);
    const sections = try newMap(engine);
    defer engine.freeValue(sections);
    var timestamp = c.pi_js_undefined();
    defer engine.freeValue(timestamp);
    for (0..try sdk.length(engine, messages)) |index| {
        const message = try at(engine, messages, index);
        defer engine.freeValue(message);
        if (!try is(engine, message, "role", "system")) continue;
        if (c.JS_IsUndefined(timestamp) or c.JS_IsNull(timestamp)) {
            engine.freeValue(timestamp);
            timestamp = try sdk.get(engine, message, "timestamp");
        }
        const body = try sdk.get(engine, message, "content");
        defer engine.freeValue(body);
        const text = if (c.JS_IsString(body)) c.JS_DupValue(engine.context, body) else text: {
            const parts = try sdk.array(engine);
            defer engine.freeValue(parts);
            for (0..try sdk.length(engine, body)) |part_index| {
                const block = try at(engine, body, part_index);
                defer engine.freeValue(block);
                if (try is(engine, block, "type", "text")) try sdk.append(engine, parts, try sdk.get(engine, block, "text"));
            }
            const separator = try sdk.text(engine, "\n");
            defer engine.freeValue(separator);
            break :text try sdk.invoke(engine, parts, "join", &.{separator});
        };
        defer engine.freeValue(text);
        if (try chars(engine, text) > 0) try sdk.append(engine, content, c.JS_DupValue(engine.context, text));
        const patch = try sdk.get(engine, message, "sections");
        defer engine.freeValue(patch);
        const empty = try sdk.object(engine);
        defer engine.freeValue(empty);
        const entries = try objectEntries(engine, if (c.JS_IsNull(patch) or c.JS_IsUndefined(patch)) empty else patch);
        defer engine.freeValue(entries);
        for (0..try sdk.length(engine, entries)) |entry_index| {
            const pair = try at(engine, entries, entry_index);
            defer engine.freeValue(pair);
            const key = try at(engine, pair, 0);
            defer engine.freeValue(key);
            const value = try at(engine, pair, 1);
            defer engine.freeValue(value);
            if (c.JS_IsNull(value)) try callDiscard(engine, sections, "delete", &.{key}) else try callDiscard(engine, sections, "set", &.{ key, value });
        }
    }
    const tools = try newMap(engine);
    defer engine.freeValue(tools);
    for (0..try sdk.length(engine, messages)) |index| {
        const message = try at(engine, messages, index);
        defer engine.freeValue(message);
        if (!try is(engine, message, "role", "system")) continue;
        inline for (.{ "toolsRemoved", "toolsAdded" }) |key| {
            const rows = try sdk.get(engine, message, key);
            defer engine.freeValue(rows);
            if (!c.JS_IsUndefined(rows) and !c.JS_IsNull(rows)) for (0..try sdk.length(engine, rows)) |tool_index| {
                const tool = try at(engine, rows, tool_index);
                defer engine.freeValue(tool);
                const name = try sdk.get(engine, tool, "name");
                defer engine.freeValue(name);
                if (comptime std.mem.eql(u8, key, "toolsRemoved")) try callDiscard(engine, tools, "delete", &.{name}) else try callDiscard(engine, tools, "set", &.{ name, tool });
            };
        }
    }
    const iterator = try sdk.invoke(engine, tools, "values", &.{});
    defer engine.freeValue(iterator);
    const active_tools = try arrayFrom(engine, iterator);
    defer engine.freeValue(active_tools);
    if (c.JS_IsUndefined(timestamp) and try sdk.length(engine, active_tools) == 0) return c.pi_js_undefined();
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "role", try sdk.text(engine, "system"));
    const separator = try sdk.text(engine, "\n\n");
    defer engine.freeValue(separator);
    try sdk.put(engine, result, "content", try sdk.invoke(engine, content, "join", &.{separator}));
    const section_size = try fieldNumber(engine, sections, "size");
    if (section_size > 0) {
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        const constructor = try sdk.get(engine, global, "Object");
        defer engine.freeValue(constructor);
        try sdk.put(engine, result, "sections", try sdk.invoke(engine, constructor, "fromEntries", &.{sections}));
    }
    if (try sdk.length(engine, active_tools) > 0) try sdk.put(engine, result, "toolsAdded", c.JS_DupValue(engine.context, active_tools));
    try sdk.put(engine, result, "timestamp", if (c.JS_IsNull(timestamp) or c.JS_IsUndefined(timestamp)) c.JS_NewInt32(engine.context, 0) else c.JS_DupValue(engine.context, timestamp));
    return result;
}

pub fn contextUsage(engine: *em.Engine, model: c.JSValue, manager: c.JSValue) !c.JSValue {
    if (c.JS_ToBool(engine.context, model) != 1) return c.pi_js_undefined();
    const limit = try sdk.get(engine, model, "contextWindow");
    defer engine.freeValue(limit);
    const window = if (c.JS_IsUndefined(limit) or c.JS_IsNull(limit)) 0 else try number(engine, limit);
    if (window <= 0) return c.pi_js_undefined();
    const projection = try sdk.invoke(engine, manager, "buildSessionProjection", &.{});
    defer engine.freeValue(projection);
    const messages = try sdk.get(engine, projection, "messages");
    defer engine.freeValue(messages);
    const projected = try sdk.get(engine, projection, "entries");
    defer engine.freeValue(projected);
    const branch = try sdk.invoke(engine, manager, "getBranch", &.{});
    defer engine.freeValue(branch);
    const branch_count = try sdk.length(engine, branch);
    var latest_compaction: ?usize = null;
    var latest_invalidating: ?usize = null;
    for (0..branch_count) |index| {
        const entry = try at(engine, branch, index);
        defer engine.freeValue(entry);
        if (try is(engine, entry, "type", "compaction")) latest_compaction = index;
        if (try is(engine, entry, "type", "compaction") or try is(engine, entry, "type", "context_edit")) latest_invalidating = index;
    }
    var known = true;
    if (latest_compaction) |compaction| {
        known = false;
        for (compaction + 1..branch_count) |index| {
            const entry = try at(engine, branch, index);
            defer engine.freeValue(entry);
            const id = try sdk.get(engine, entry, "id");
            defer engine.freeValue(id);
            for (0..try sdk.length(engine, projected)) |projected_index| {
                const row = try at(engine, projected, projected_index);
                defer engine.freeValue(row);
                const source = try sdk.get(engine, row, "sourceEntry");
                defer engine.freeValue(source);
                const source_id = try sdk.get(engine, source, "id");
                defer engine.freeValue(source_id);
                if (!c.JS_IsStrictEqual(engine.context, id, source_id)) continue;
                const values = try sdk.get(engine, row, "messages");
                defer engine.freeValue(values);
                for (0..try sdk.length(engine, values)) |message_index| {
                    const message = try at(engine, values, message_index);
                    defer engine.freeValue(message);
                    if (try assistantUsage(engine, message) != null) known = true;
                }
            }
        }
    }
    var tokens: f64 = 0;
    if (known) {
        var last_usage: ?usize = null;
        var usage_tokens: f64 = 0;
        const count = try sdk.length(engine, messages);
        var usage_cursor = count;
        while (usage_cursor > 0) {
            usage_cursor -= 1;
            const index = usage_cursor;
            const message = try at(engine, messages, index);
            defer engine.freeValue(message);
            if (try assistantUsage(engine, message)) |usage| {
                last_usage = index;
                usage_tokens = usage;
                break;
            }
        }
        var trust_usage = false;
        if (last_usage) |usage_index| {
            var offset: usize = 0;
            for (0..try sdk.length(engine, projected)) |index| {
                const row = try at(engine, projected, index);
                defer engine.freeValue(row);
                const values = try sdk.get(engine, row, "messages");
                defer engine.freeValue(values);
                const next = offset + try sdk.length(engine, values);
                if (usage_index < next) {
                    const source = try sdk.get(engine, row, "sourceEntry");
                    defer engine.freeValue(source);
                    const id = try sdk.get(engine, source, "id");
                    defer engine.freeValue(id);
                    for (0..branch_count) |entry_index| {
                        const entry = try at(engine, branch, entry_index);
                        defer engine.freeValue(entry);
                        const candidate = try sdk.get(engine, entry, "id");
                        defer engine.freeValue(candidate);
                        if (c.JS_IsStrictEqual(engine.context, id, candidate)) {
                            trust_usage = latest_invalidating == null or entry_index > latest_invalidating.?;
                            break;
                        }
                    }
                    break;
                }
                offset = next;
            }
            if (trust_usage) {
                tokens = usage_tokens;
                for (usage_index + 1..count) |index| {
                    const message = try at(engine, messages, index);
                    defer engine.freeValue(message);
                    tokens += try estimateTokens(engine, message);
                }
            }
        }
        if (!trust_usage) {
            const system = try currentSystem(engine, messages);
            defer engine.freeValue(system);
            if (c.JS_ToBool(engine.context, system) == 1) tokens += try estimateTokens(engine, system);
            for (0..count) |index| {
                const message = try at(engine, messages, index);
                defer engine.freeValue(message);
                if (!try is(engine, message, "role", "system")) tokens += try estimateTokens(engine, message);
            }
        }
    }
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "tokens", if (known) c.JS_NewFloat64(engine.context, tokens) else c.pi_js_null());
    try sdk.put(engine, result, "contextWindow", c.JS_NewFloat64(engine.context, window));
    try sdk.put(engine, result, "percent", if (known) c.JS_NewFloat64(engine.context, tokens / window * 100) else c.pi_js_null());
    return result;
}

pub fn routedModel(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const selected = try sdk.agentField(owner, "model");
    defer engine.freeValue(selected);
    if (!try @import("native_sdk_virtual.zig").isVirtual(engine, selected)) return c.pi_js_undefined();
    const messages = try sdk.agentField(owner, "messages");
    defer engine.freeValue(messages);
    var index = try sdk.length(engine, messages);
    while (index > 0) {
        index -= 1;
        const message = try at(engine, messages, index);
        defer engine.freeValue(message);
        if (!try is(engine, message, "role", "assistant") or try is(engine, message, "stopReason", "error") or try is(engine, message, "stopReason", "aborted")) continue;
        const provider = try sdk.get(engine, message, "provider");
        defer engine.freeValue(provider);
        const id = try sdk.get(engine, message, "model");
        defer engine.freeValue(id);
        const runtime = try sdk.get(engine, owner.data, "modelRuntime");
        defer engine.freeValue(runtime);
        const model = try sdk.invoke(engine, runtime, "getPhysicalModel", &.{ provider, id });
        defer engine.freeValue(model);
        if (c.JS_ToBool(engine.context, model) != 1) return c.JS_DupValue(engine.context, model);
        const result = try sdk.object(engine);
        errdefer engine.freeValue(result);
        try sdk.put(engine, result, "model", c.JS_DupValue(engine.context, model));
        try sdk.put(engine, result, "thinkingLevel", try sdk.get(engine, message, "thinkingLevel"));
        return result;
    }
    return c.pi_js_undefined();
}
pub fn sessionContextUsage(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const routed = try routedModel(owner);
    defer engine.freeValue(routed);
    const model = if (c.JS_ToBool(engine.context, routed) == 1) try sdk.get(engine, routed, "model") else try sdk.agentField(owner, "model");
    defer engine.freeValue(model);
    const manager = try sdk.get(engine, owner.data, "sessionManager");
    defer engine.freeValue(manager);
    return contextUsage(engine, model, manager);
}
pub fn sessionStats(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const manager = try sdk.get(engine, owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const totals = try billed(engine, manager);
    defer engine.freeValue(totals);
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try sdk.put(engine, result, "sessionFile", try sdk.invoke(engine, manager, "getSessionFile", &.{}));
    try sdk.put(engine, result, "sessionId", try sdk.invoke(engine, manager, "getSessionId", &.{}));
    inline for (.{ "userMessages", "assistantMessages", "toolCalls", "toolResults", "totalMessages", "tokens", "cost" }) |field| try sdk.put(engine, result, field, try sdk.get(engine, totals, field));
    try sdk.put(engine, result, "contextUsage", try sessionContextUsage(owner));
    return result;
}
pub fn refreshContext(owner: *sdk.State) !void {
    const engine = owner.engine;
    const manager = try sdk.get(engine, owner.data, "sessionManager");
    defer engine.freeValue(manager);
    const projection = try sdk.invoke(engine, manager, "buildSessionProjection", &.{});
    defer engine.freeValue(projection);
    const messages = try sdk.get(engine, projection, "messages");
    defer engine.freeValue(messages);
    // setAgentField uses the actual agent.state setter and preserves Source's
    // shallow copy. The message/source-entry map will also feed later APIs.
    const rows = try sdk.get(engine, projection, "entries");
    defer engine.freeValue(rows);
    var map = try sdk.get(engine, owner.data, "_entryIdsByMessage");
    if (c.JS_IsUndefined(map)) {
        engine.freeValue(map);
        map = try newWeakMap(engine);
        try sdk.put(engine, owner.data, "_entryIdsByMessage", c.JS_DupValue(engine.context, map));
    }
    defer engine.freeValue(map);
    for (0..try sdk.length(engine, rows)) |index| {
        const row = try at(engine, rows, index);
        defer engine.freeValue(row);
        const source = try sdk.get(engine, row, "sourceEntry");
        defer engine.freeValue(source);
        const id = try sdk.get(engine, source, "id");
        defer engine.freeValue(id);
        const values = try sdk.get(engine, row, "messages");
        defer engine.freeValue(values);
        for (0..try sdk.length(engine, values)) |message_index| {
            const message = try at(engine, values, message_index);
            defer engine.freeValue(message);
            try callDiscard(engine, map, "set", &.{ message, id });
        }
    }
    try sdk.setAgentField(owner, "messages", messages);
}
