//! Owner-thread, provenance-preserving SDK session projections. Entries and
//! unchanged messages retain Source identity; edits copy only edited messages.
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    return @import("native_sdk_public_session_helpers.zig").install(engine, exports);
}
pub fn parseEntries(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    return @import("native_sdk_public_session_helpers.zig").parseLines(engine, value, true);
}
pub fn parseLines(engine: *engine_mod.Engine, value: c.JSValue, trim_outer: bool) !c.JSValue {
    return @import("native_sdk_public_session_helpers.zig").parseLines(engine, value, trim_outer);
}
pub fn migrate(engine: *engine_mod.Engine, entries: c.JSValue) !bool {
    return @import("native_sdk_public_session_helpers.zig").migrate(engine, entries);
}
fn same(engine: *engine_mod.Engine, value: c.JSValue, label: []const u8) !bool {
    const text = try sdk.text(engine, label);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn typeIs(engine: *engine_mod.Engine, row: c.JSValue, label: []const u8) !bool {
    const typ = try sdk.get(engine, row, "type");
    defer engine.freeValue(typ);
    return same(engine, typ, label);
}
fn spread(engine: *engine_mod.Engine, original: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try models.copy(engine, result, original);
    return result;
}
pub fn dateTime(engine: *engine_mod.Engine, stamp: c.JSValue) !c.JSValue {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const date = try sdk.get(engine, global, "Date");
    defer engine.freeValue(date);
    var args = [_]c.JSValue{stamp};
    const instance = try engine.checked(c.JS_CallConstructor(engine.context, date, 1, &args));
    defer engine.freeValue(instance);
    return sdk.invoke(engine, instance, "getTime", &.{});
}
pub fn contextEntries(engine: *engine_mod.Engine, path: c.JSValue) !c.JSValue {
    const count = try sdk.length(engine, path);
    var latest: ?u32 = null;
    for (0..count) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, @intCast(index)));
        defer engine.freeValue(row);
        if (try typeIs(engine, row, "compaction")) latest = @intCast(index);
    }
    const index = latest orelse return sdk.invoke(engine, path, "slice", &.{});
    const compact = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, index));
    defer engine.freeValue(compact);
    const kept_id = try sdk.get(engine, compact, "firstKeptEntryId");
    defer engine.freeValue(kept_id);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    try sdk.append(engine, result, c.JS_DupValue(engine.context, compact));
    var found = false;
    for (0..count) |i| {
        if (i == index) continue;
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, @intCast(i)));
        defer engine.freeValue(row);
        const id = try sdk.get(engine, row, "id");
        defer engine.freeValue(id);
        if (c.JS_IsStrictEqual(engine.context, id, kept_id)) found = true;
        if (i < index) {
            if (!found) continue;
            if (try typeIs(engine, row, "message")) {
                const message = try sdk.get(engine, row, "message");
                defer engine.freeValue(message);
                const role = try sdk.get(engine, message, "role");
                defer engine.freeValue(role);
                if (try same(engine, role, "system")) continue;
            }
        }
        try sdk.append(engine, result, c.JS_DupValue(engine.context, row));
    }
    return result;
}
pub fn entryMessages(engine: *engine_mod.Engine, row: c.JSValue) !c.JSValue {
    return @import("native_sdk_session_projection_live.zig").entryMessages(engine, row);
}
fn edited(engine: *engine_mod.Engine, messages: c.JSValue, edit: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(edit)) return c.JS_DupValue(engine.context, messages);
    const replacement = try sdk.get(engine, edit, "replacement");
    defer engine.freeValue(replacement);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsNull(replacement)) return result;
    const content = try sdk.get(engine, replacement, "content");
    defer engine.freeValue(content);
    for (0..try sdk.length(engine, messages)) |index| {
        const original = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(index)));
        defer engine.freeValue(original);
        const role = try sdk.get(engine, original, "role");
        defer engine.freeValue(role);
        const assistant = try same(engine, role, "assistant");
        const tool = try same(engine, role, "toolResult");
        if (!assistant and !tool and !try same(engine, role, "user") and !try same(engine, role, "custom")) {
            try sdk.append(engine, result, c.JS_DupValue(engine.context, original));
            continue;
        }
        const message = try spread(engine, original);
        defer engine.freeValue(message);
        if ((assistant or tool) and c.JS_IsString(content)) {
            const parts = try sdk.array(engine);
            defer engine.freeValue(parts);
            const text = try sdk.object(engine);
            defer engine.freeValue(text);
            try sdk.put(engine, text, "type", try sdk.text(engine, "text"));
            try sdk.put(engine, text, "text", c.JS_DupValue(engine.context, content));
            try sdk.append(engine, parts, c.JS_DupValue(engine.context, text));
            try sdk.put(engine, message, "content", c.JS_DupValue(engine.context, parts));
        } else try sdk.put(engine, message, "content", c.JS_DupValue(engine.context, content));
        try sdk.append(engine, result, c.JS_DupValue(engine.context, message));
    }
    return result;
}
pub fn project(engine: *engine_mod.Engine, path: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    var thinking = try sdk.text(engine, "off");
    defer engine.freeValue(thinking);
    var model = c.pi_js_null();
    defer engine.freeValue(model);
    for (0..try sdk.length(engine, path)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, path, @intCast(index)));
        defer engine.freeValue(row);
        if (try typeIs(engine, row, "thinking_level_change")) {
            const next = try sdk.get(engine, row, "thinkingLevel");
            engine.freeValue(thinking);
            thinking = next;
        } else {
            var source = c.JS_DupValue(engine.context, row);
            defer engine.freeValue(source);
            var selected = try typeIs(engine, row, "model_change");
            var assistant = false;
            if (try typeIs(engine, row, "message")) {
                const next_source = try sdk.get(engine, row, "message");
                engine.freeValue(source);
                source = next_source;
                const role = try sdk.get(engine, source, "role");
                defer engine.freeValue(role);
                assistant = try same(engine, role, "assistant");
                selected = selected or assistant;
            }
            if (selected) {
                const next = try sdk.object(engine);
                errdefer engine.freeValue(next);
                try sdk.put(engine, next, "provider", try sdk.get(engine, source, "provider"));
                try sdk.put(engine, next, "modelId", try sdk.get(engine, source, if (assistant) "model" else "modelId"));
                engine.freeValue(model);
                model = next;
            }
        }
    }
    const context = try contextEntries(engine, path);
    defer engine.freeValue(context);
    const edits = try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(edits);
    for (0..try sdk.length(engine, context)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, context, @intCast(index)));
        defer engine.freeValue(row);
        if (try typeIs(engine, row, "context_edit")) {
            const id = try sdk.get(engine, row, "targetId");
            defer engine.freeValue(id);
            const ignored = try sdk.invoke(engine, edits, "set", &.{ id, row });
            engine.freeValue(ignored);
        }
    }
    const projected = try sdk.array(engine);
    defer engine.freeValue(projected);
    const flattened = try sdk.array(engine);
    defer engine.freeValue(flattened);
    for (0..try sdk.length(engine, context)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, context, @intCast(index)));
        defer engine.freeValue(row);
        const id = try sdk.get(engine, row, "id");
        defer engine.freeValue(id);
        const edit = try sdk.invoke(engine, edits, "get", &.{id});
        defer engine.freeValue(edit);
        const raw = if (index > 0 and try typeIs(engine, row, "compaction")) try sdk.array(engine) else try entryMessages(engine, row);
        defer engine.freeValue(raw);
        const messages = try edited(engine, raw, edit);
        defer engine.freeValue(messages);
        const entry = try sdk.object(engine);
        defer engine.freeValue(entry);
        try sdk.put(engine, entry, "sourceEntry", c.JS_DupValue(engine.context, row));
        try sdk.put(engine, entry, "messages", c.JS_DupValue(engine.context, messages));
        try sdk.append(engine, projected, c.JS_DupValue(engine.context, entry));
        for (0..try sdk.length(engine, messages)) |i| try sdk.append(engine, flattened, try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, @intCast(i))));
    }
    try sdk.put(engine, result, "entries", c.JS_DupValue(engine.context, projected));
    try sdk.put(engine, result, "messages", c.JS_DupValue(engine.context, flattened));
    try sdk.put(engine, result, "thinkingLevel", c.JS_DupValue(engine.context, thinking));
    try sdk.put(engine, result, "model", c.JS_DupValue(engine.context, model));
    return result;
}
