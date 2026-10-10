//! SDK session append operations retain supplied values and branch provenance.
const std = @import("std");
const sdk = @import("native_sdk.zig");
const projection = @import("native_sdk_session_projection.zig");
const engine_mod = @import("engine.zig");
const c = engine_mod.c;
const Method = enum(c_int) { appendUsage, appendCompaction, appendCustomMessageEntry, appendContextEdit, branchWithSummary };
pub fn install(engine: *engine_mod.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const length: c_int = switch (@as(Method, @enumFromInt(field.value))) {
            .appendUsage => 5,
            .appendCompaction => 6,
            .appendCustomMessageEntry => 4,
            .appendContextEdit => 2,
            .branchWithSummary => 5,
        };
        const function = try engine.checked(c.pi_js_function_magic(engine.context, callback, field.name, length, @intCast(field.value)));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
    }
}
fn callback(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const self = sdk.state(engine, receiver) catch |err| return sdk.fail(engine, err);
    if (self.kind != .session_manager) return sdk.fail(engine, error.InvalidNativeSDKReceiver);
    var args = [_]c.JSValue{c.pi_js_undefined()} ** 6;
    for (0..@min(args.len, @as(usize, @intCast(@max(argc, 0))))) |index| args[index] = argv[index];
    return dispatch(self, @enumFromInt(magic), &args) catch |err| sdk.fail(engine, err);
}
fn same(engine: *engine_mod.Engine, value: c.JSValue, expected: []const u8) !bool {
    const text = try sdk.text(engine, expected);
    defer engine.freeValue(text);
    return c.JS_IsStrictEqual(engine.context, value, text);
}
fn entryError(self: *sdk.State, id: c.JSValue, suffix: []const u8) !c.JSValue {
    const raw = try self.engine.toString(id);
    defer self.engine.gpa.free(raw);
    const message = try std.fmt.allocPrint(self.engine.gpa, "Entry {s} {s}", .{ raw, suffix });
    defer self.engine.gpa.free(message);
    return sdk.sourceError(self.engine, message);
}
fn requireEntry(self: *sdk.State, id: c.JSValue) !c.JSValue {
    const entry = try sdk.findEntry(self, id);
    if (!c.JS_IsUndefined(entry)) return entry;
    return entryError(self, id, "not found");
}
fn contextEdit(self: *sdk.State, id: c.JSValue, replacement: c.JSValue) !c.JSValue {
    const engine = self.engine;
    const content = if (c.JS_IsObject(replacement)) try sdk.get(engine, replacement, "content") else c.pi_js_undefined();
    defer engine.freeValue(content);
    if (!c.JS_IsNull(replacement) and (!c.JS_IsObject(replacement) or c.JS_IsFunction(engine.context, replacement) or (!c.JS_IsString(content) and !c.JS_IsArray(content)))) return sdk.sourceError(engine, "Context edit replacement must be null or contain string/array content");
    const target = try requireEntry(self, id);
    defer engine.freeValue(target);
    const leaf = try sdk.get(engine, self.data, "leafId");
    defer engine.freeValue(leaf);
    const branch = try sdk.branchEntries(self, leaf);
    defer engine.freeValue(branch);
    var found = false;
    for (0..try sdk.length(engine, branch)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, branch, @intCast(index)));
        defer engine.freeValue(row);
        const candidate = try sdk.get(engine, row, "id");
        defer engine.freeValue(candidate);
        if (c.JS_IsStrictEqual(engine.context, id, candidate)) found = true;
    }
    if (!found) return entryError(self, id, "is not on the active branch");
    const typ = try sdk.get(engine, target, "type");
    defer engine.freeValue(typ);
    var role = try sdk.text(engine, "custom");
    defer engine.freeValue(role);
    var editable = try same(engine, typ, "custom_message");
    if (try same(engine, typ, "message")) {
        const message = try sdk.get(engine, target, "message");
        defer engine.freeValue(message);
        const next = try sdk.get(engine, message, "role");
        engine.freeValue(role);
        role = next;
        editable = try same(engine, role, "user") or try same(engine, role, "assistant") or try same(engine, role, "toolResult");
    }
    if (!editable) return entryError(self, id, "does not contribute editable model content");
    const row = try sdk.entry(self, "context_edit");
    defer engine.freeValue(row);
    try sdk.put(engine, row, "targetId", c.JS_DupValue(engine.context, id));
    if (!c.JS_IsNull(replacement) and c.JS_IsString(content) and (try same(engine, role, "assistant") or try same(engine, role, "toolResult"))) {
        const normalized = try sdk.object(engine);
        defer engine.freeValue(normalized);
        const parts = try sdk.array(engine);
        defer engine.freeValue(parts);
        const text = try sdk.object(engine);
        defer engine.freeValue(text);
        try sdk.put(engine, text, "type", try sdk.text(engine, "text"));
        try sdk.put(engine, text, "text", c.JS_DupValue(engine.context, content));
        try sdk.append(engine, parts, c.JS_DupValue(engine.context, text));
        try sdk.put(engine, normalized, "content", c.JS_DupValue(engine.context, parts));
        try sdk.put(engine, row, "replacement", c.JS_DupValue(engine.context, normalized));
    } else try sdk.put(engine, row, "replacement", c.JS_DupValue(engine.context, replacement));
    return sdk.commitEntry(self, row);
}
fn dispatch(self: *sdk.State, method: Method, args: []const c.JSValue) !c.JSValue {
    const engine = self.engine;
    if (method == .appendContextEdit) return contextEdit(self, args[0], args[1]);
    var from = c.pi_js_undefined();
    defer engine.freeValue(from);
    if (method == .branchWithSummary) {
        if (!c.JS_IsNull(args[0])) {
            const target = try requireEntry(self, args[0]);
            engine.freeValue(target);
        }
        from = try sdk.get(engine, self.data, "leafId");
        if (c.JS_IsNull(from) or c.JS_IsUndefined(from)) {
            engine.freeValue(from);
            from = try sdk.text(engine, "root");
        }
        try sdk.put(engine, self.data, "leafId", c.JS_DupValue(engine.context, args[0]));
    }
    const row = try sdk.entry(self, switch (method) {
        .appendUsage => "usage",
        .appendCompaction => "compaction",
        .appendCustomMessageEntry => "custom_message",
        .branchWithSummary => "branch_summary",
        .appendContextEdit => unreachable,
    });
    defer engine.freeValue(row);
    switch (method) {
        .appendUsage => {
            inline for (.{ "kind", "provider", "model", "usage" }, 0..) |field, index| try sdk.put(engine, row, field, c.JS_DupValue(engine.context, args[index]));
            if (c.JS_ToBool(engine.context, args[4]) == 1) try sdk.put(engine, row, "note", c.JS_DupValue(engine.context, args[4]));
        },
        .appendCustomMessageEntry => inline for (.{ "customType", "content", "display", "details" }, 0..) |field, index| try sdk.put(engine, row, field, c.JS_DupValue(engine.context, args[index])),
        .branchWithSummary => {
            try sdk.put(engine, row, "fromId", c.JS_DupValue(engine.context, from));
            inline for (.{ "summary", "details", "fromHook", "usage" }, 1..) |field, index| try sdk.put(engine, row, field, c.JS_DupValue(engine.context, args[index]));
        },
        .appendCompaction => {
            try sdk.put(engine, row, "summary", c.JS_DupValue(engine.context, args[0]));
            try sdk.put(engine, row, "firstKeptEntryId", if (c.JS_IsNull(args[1]) or c.JS_IsUndefined(args[1])) try sdk.get(engine, row, "id") else c.JS_DupValue(engine.context, args[1]));
            try sdk.put(engine, row, "tokensBefore", c.JS_DupValue(engine.context, args[2]));
            try sdk.put(engine, row, "details", c.JS_DupValue(engine.context, args[3]));
            try sdk.put(engine, row, "usage", c.JS_DupValue(engine.context, args[5]));
            try sdk.put(engine, row, "fromHook", c.JS_DupValue(engine.context, args[4]));
            const leaf = try sdk.get(engine, self.data, "leafId");
            defer engine.freeValue(leaf);
            const path = try sdk.branchEntries(self, leaf);
            defer engine.freeValue(path);
            const context = try projection.project(engine, path);
            defer engine.freeValue(context);
            const messages = try sdk.get(engine, context, "messages");
            defer engine.freeValue(messages);
            var index = try sdk.length(engine, messages);
            while (index > 0) {
                index -= 1;
                const message = try engine.checked(c.JS_GetPropertyUint32(engine.context, messages, index));
                defer engine.freeValue(message);
                const role = try sdk.get(engine, message, "role");
                defer engine.freeValue(role);
                if (!try same(engine, role, "system")) continue;
                const system = try sdk.object(engine);
                defer engine.freeValue(system);
                try @import("native_sdk_models.zig").copy(engine, system, message);
                const stamp = try sdk.get(engine, row, "timestamp");
                defer engine.freeValue(stamp);
                try sdk.put(engine, system, "timestamp", try projection.dateTime(engine, stamp));
                try sdk.put(engine, row, "systemMessage", c.JS_DupValue(engine.context, system));
                break;
            }
        },
        .appendContextEdit => unreachable,
    }
    const id = try sdk.commitEntry(self, row);
    if (method != .appendUsage) return id;
    engine.freeValue(id);
    return c.JS_DupValue(engine.context, row);
}
