//! Owner-thread, provenance-preserving SDK session projections. Entries and
//! unchanged messages retain Source identity; edits copy only edited messages.
const sdk = @import("native_sdk.zig");
const models = @import("native_sdk_models.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Public = enum(c_int) { buildContextEntries, buildSessionProjection, buildSessionContext, sessionEntryToContextMessages, getLatestCompactionEntry, parseSessionEntries, migrateSessionEntries };
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    try sdk.put(engine, exports, "CURRENT_SESSION_VERSION", c.JS_NewInt32(engine.context, 3));
    inline for (@import("std").meta.fields(Public)) |field| try sdk.put(engine, exports, field.name, try engine.checked(c.pi_js_function_magic(engine.context, publicCallback, field.name, if (field.value < 3) 3 else 1, @intCast(field.value))));
}
fn publicCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 3;
    for (0..@min(args.len, @as(usize, @intCast(@max(argc, 0))))) |index| args[index] = argv[index];
    return publicDispatch(engine, @enumFromInt(magic), &args) catch |err| sdk.fail(engine, err);
}
fn publicDispatch(engine: *engine_mod.Engine, method: Public, args: []const c.JSValue) !c.JSValue {
    if (method == .sessionEntryToContextMessages) return entryMessages(engine, args[0]);
    if (method == .getLatestCompactionEntry) {
        var index = try sdk.length(engine, args[0]);
        while (index > 0) {
            index -= 1;
            const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, args[0], index));
            errdefer engine.freeValue(row);
            if (try typeIs(engine, row, "compaction")) return row;
            engine.freeValue(row);
        }
        return c.pi_js_null();
    }
    if (method == .parseSessionEntries) return parseEntries(engine, args[0]);
    if (method == .migrateSessionEntries) {
        _ = try migrate(engine, args[0]);
        return c.pi_js_undefined();
    }
    const path = try buildPath(engine, args[0], args[1], args[2]);
    defer engine.freeValue(path);
    if (method == .buildContextEntries) return contextEntries(engine, path);
    const result = try project(engine, path);
    if (method == .buildSessionProjection) return result;
    defer engine.freeValue(result);
    const context = try sdk.object(engine);
    errdefer engine.freeValue(context);
    inline for (.{ "messages", "thinkingLevel", "model" }) |field| try sdk.put(engine, context, field, try sdk.get(engine, result, field));
    return context;
}
pub fn parseEntries(engine: *engine_mod.Engine, value: c.JSValue) !c.JSValue {
    const std = @import("std");
    const trimmed = try sdk.invoke(engine, value, "trim", &.{});
    defer engine.freeValue(trimmed);
    const raw = try engine.toString(trimmed);
    defer engine.gpa.free(raw);
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    var lines = std.mem.splitScalar(u8, raw, '\n');
    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        const terminated = try engine.gpa.dupeZ(u8, line);
        defer engine.gpa.free(terminated);
        const row = c.JS_ParseJSON(engine.context, terminated, line.len, "session-entry");
        if (c.JS_IsException(row)) {
            engine.freeValue(c.JS_GetException(engine.context));
            continue;
        }
        try sdk.append(engine, result, row);
    }
    return result;
}
pub fn migrate(engine: *engine_mod.Engine, entries: c.JSValue) !bool {
    const count = try sdk.length(engine, entries);
    var version: f64 = 1;
    for (0..count) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.freeValue(row);
        if (!try typeIs(engine, row, "session")) continue;
        const value = try sdk.get(engine, row, "version");
        defer engine.freeValue(value);
        if (!c.JS_IsUndefined(value) and !c.JS_IsNull(value)) if (c.JS_ToFloat64(engine.context, &version, value) < 0) return error.JavaScriptException;
        break;
    }
    if (version >= 3) return false;
    var previous = c.pi_js_null();
    defer engine.freeValue(previous);
    for (0..count) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(index)));
        defer engine.freeValue(row);
        if (try typeIs(engine, row, "session")) {
            try sdk.put(engine, row, "version", c.JS_NewInt32(engine.context, 3));
            continue;
        }
        if (version < 2) {
            const id = try sdk.identifier(engine, "entry");
            defer engine.freeValue(id);
            try sdk.put(engine, row, "id", c.JS_DupValue(engine.context, id));
            try sdk.put(engine, row, "parentId", c.JS_DupValue(engine.context, previous));
            engine.freeValue(previous);
            previous = c.JS_DupValue(engine.context, id);
            if (try typeIs(engine, row, "compaction")) {
                const kept = try sdk.get(engine, row, "firstKeptEntryIndex");
                defer engine.freeValue(kept);
                if (c.JS_IsNumber(kept)) {
                    const index_atom = c.JS_ValueToAtom(engine.context, kept);
                    if (index_atom == c.JS_ATOM_NULL) return error.JavaScriptException;
                    defer c.JS_FreeAtom(engine.context, index_atom);
                    const target = try engine.checked(c.JS_GetProperty(engine.context, entries, index_atom));
                    defer engine.freeValue(target);
                    if (c.JS_ToBool(engine.context, target) == 1 and !try typeIs(engine, target, "session")) try sdk.put(engine, row, "firstKeptEntryId", try sdk.get(engine, target, "id"));
                    const atom = c.JS_NewAtom(engine.context, "firstKeptEntryIndex");
                    defer c.JS_FreeAtom(engine.context, atom);
                    if (c.JS_DeleteProperty(engine.context, row, atom, 0) < 0) return error.JavaScriptException;
                }
            }
        }
        if (try typeIs(engine, row, "message")) {
            const message = try sdk.get(engine, row, "message");
            defer engine.freeValue(message);
            if (c.JS_ToBool(engine.context, message) == 1) {
                const role = try sdk.get(engine, message, "role");
                defer engine.freeValue(role);
                if (try same(engine, role, "hookMessage")) try sdk.put(engine, message, "role", try sdk.text(engine, "custom"));
            }
        }
    }
    return true;
}
fn buildPath(engine: *engine_mod.Engine, entries: c.JSValue, leaf: c.JSValue, supplied: c.JSValue) !c.JSValue {
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsNull(leaf)) return result;
    const index = if (c.JS_IsObject(supplied)) c.JS_DupValue(engine.context, supplied) else try @import("native_sdk_auth_snapshot.zig").collection(engine, "Map");
    defer engine.freeValue(index);
    const count = try sdk.length(engine, entries);
    if (!c.JS_IsObject(supplied)) for (0..count) |i| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, @intCast(i)));
        defer engine.freeValue(row);
        const id = try sdk.get(engine, row, "id");
        defer engine.freeValue(id);
        const added = try sdk.invoke(engine, index, "set", &.{ id, row });
        engine.freeValue(added);
    };
    var current = if (c.JS_ToBool(engine.context, leaf) == 1) try sdk.invoke(engine, index, "get", &.{leaf}) else c.pi_js_undefined();
    defer engine.freeValue(current);
    if ((c.JS_IsUndefined(current) or c.JS_IsNull(current)) and count > 0) {
        engine.freeValue(current);
        current = try engine.checked(c.JS_GetPropertyUint32(engine.context, entries, count - 1));
    }
    for (0..65536) |_| {
        if (c.JS_ToBool(engine.context, current) != 1) break;
        try sdk.append(engine, result, c.JS_DupValue(engine.context, current));
        const parent = try sdk.get(engine, current, "parentId");
        defer engine.freeValue(parent);
        const next = if (c.JS_ToBool(engine.context, parent) == 1) try sdk.invoke(engine, index, "get", &.{parent}) else c.pi_js_undefined();
        engine.freeValue(current);
        current = next;
    }
    const reversed = try sdk.invoke(engine, result, "reverse", &.{});
    engine.freeValue(reversed);
    return result;
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
    const result = try sdk.array(engine);
    errdefer engine.freeValue(result);
    if (try typeIs(engine, row, "message")) {
        const original = try sdk.get(engine, row, "message");
        defer engine.freeValue(original);
        const role = try sdk.get(engine, original, "role");
        defer engine.freeValue(role);
        const content = try sdk.get(engine, original, "content");
        defer engine.freeValue(content);
        if ((c.JS_IsUndefined(content) or c.JS_IsNull(content)) and (try same(engine, role, "system") or try same(engine, role, "user") or try same(engine, role, "assistant") or try same(engine, role, "toolResult"))) {
            const message = try spread(engine, original);
            defer engine.freeValue(message);
            try sdk.put(engine, message, "content", if (try same(engine, role, "system")) try sdk.text(engine, "") else try sdk.array(engine));
            try sdk.append(engine, result, c.JS_DupValue(engine.context, message));
        } else try sdk.append(engine, result, c.JS_DupValue(engine.context, original));
        return result;
    }
    const custom = try typeIs(engine, row, "custom_message");
    const branch = try typeIs(engine, row, "branch_summary");
    const compact = try typeIs(engine, row, "compaction");
    if (!custom and !branch and !compact) return result;
    const summary = if (branch or compact) try sdk.get(engine, row, "summary") else c.pi_js_undefined();
    defer engine.freeValue(summary);
    if (branch and c.JS_ToBool(engine.context, summary) != 1) return result;
    const message = try sdk.object(engine);
    defer engine.freeValue(message);
    try sdk.put(engine, message, "role", try sdk.text(engine, if (custom) "custom" else if (branch) "branchSummary" else "compactionSummary"));
    if (custom) {
        try sdk.put(engine, message, "customType", try sdk.get(engine, row, "customType"));
        const content = try sdk.get(engine, row, "content");
        defer engine.freeValue(content);
        try sdk.put(engine, message, "content", if (c.JS_IsUndefined(content) or c.JS_IsNull(content)) try sdk.array(engine) else c.JS_DupValue(engine.context, content));
        inline for (.{ "display", "details" }) |field| try sdk.put(engine, message, field, try sdk.get(engine, row, field));
    } else {
        try sdk.put(engine, message, "summary", c.JS_DupValue(engine.context, summary));
        try sdk.put(engine, message, if (branch) "fromId" else "tokensBefore", try sdk.get(engine, row, if (branch) "fromId" else "tokensBefore"));
    }
    const stamp = try sdk.get(engine, row, "timestamp");
    defer engine.freeValue(stamp);
    try sdk.put(engine, message, "timestamp", try dateTime(engine, stamp));
    if (compact) {
        const system = try sdk.get(engine, row, "systemMessage");
        defer engine.freeValue(system);
        if (c.JS_ToBool(engine.context, system) == 1) try sdk.append(engine, result, c.JS_DupValue(engine.context, system));
    }
    try sdk.append(engine, result, c.JS_DupValue(engine.context, message));
    return result;
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
