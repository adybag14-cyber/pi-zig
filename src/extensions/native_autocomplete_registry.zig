//! Extension wrapper factories over a native command-completion base.
//! Missing file/argument suggestions return null so the existing Main Tab path
//! remains the fallback; no JS/TS implementation is used for the base methods.
const std = @import("std");
const engine_mod = @import("engine.zig");
const autocomplete = @import("native_autocomplete.zig");
const c = engine_mod.c;
pub const Wrapper = struct { owner_id: u64, factory: c.JSValue };
fn put(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, object, name, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
}
fn get(engine: *engine_mod.Engine, object: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, object, name));
}
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native autocomplete base: %s", @as([*:0]const u8, @errorName(err)));
}
pub fn holder(engine: *engine_mod.Engine) !c.JSValue {
    const object = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(object);
    try put(engine, object, "active", c.pi_js_bool(engine.context, 1));
    try put(engine, object, "snapshot", try engine.checked(c.JS_NewObject(engine.context)));
    return object;
}
pub fn update(engine: *engine_mod.Engine, object: c.JSValue, snapshot: c.JSValue) !void {
    if (c.JS_SetPropertyStr(engine.context, object, "snapshot", c.JS_DupValue(engine.context, snapshot)) < 0) return error.JavaScriptException;
}
pub fn deactivate(engine: *engine_mod.Engine, object: c.JSValue) void {
    _ = c.JS_SetPropertyStr(engine.context, object, "active", c.pi_js_bool(engine.context, 0));
}
fn baseCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return base(engine, data[0], magic, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn dimension(engine: *engine_mod.Engine, value: c.JSValue, maximum: usize) !usize {
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) return error.JavaScriptException;
    if (!std.math.isFinite(number) or number < 0 or number != @floor(number) or number > @as(f64, @floatFromInt(maximum))) return error.InvalidAutocompletePosition;
    return @intFromFloat(number);
}
fn base(engine: *engine_mod.Engine, context_holder: c.JSValue, magic: c_int, args: []c.JSValue) !c.JSValue {
    const active = try get(engine, context_holder, "active");
    defer engine.freeValue(active);
    if (c.JS_ToBool(engine.context, active) == 0) return c.pi_js_null();
    if (magic == 2) return c.pi_js_bool(engine.context, 1);
    if (args.len < 3 or !c.JS_IsArray(args[0])) return error.InvalidAutocompletePosition;
    const row = try dimension(engine, args[1], 4096);
    const col = try dimension(engine, args[2], 1024 * 1024);
    const line_value = try engine.checked(c.JS_GetPropertyUint32(engine.context, args[0], @intCast(row)));
    defer engine.freeValue(line_value);
    if (!c.JS_IsString(line_value)) return error.InvalidAutocompletePosition;
    const line = try engine.toString(line_value);
    defer engine.gpa.free(line);
    const cursor = try autocomplete.byteColumn(line, col);
    if (magic == 0) {
        const before = line[0..cursor];
        const prefix = std.mem.trimStart(u8, before, " \t");
        if (!std.mem.startsWith(u8, prefix, "/") or std.mem.indexOfAny(u8, prefix, " \t") != null) return c.pi_js_null();
        const snapshot = try get(engine, context_holder, "snapshot");
        defer engine.freeValue(snapshot);
        const commands = try get(engine, snapshot, "commands");
        defer engine.freeValue(commands);
        if (!c.JS_IsArray(commands)) return c.pi_js_null();
        const length_value = try get(engine, commands, "length");
        defer engine.freeValue(length_value);
        const length = try dimension(engine, length_value, 4096);
        const items = try engine.checked(c.JS_NewArray(engine.context));
        var items_owned = true;
        defer if (items_owned) engine.freeValue(items);
        var count: u32 = 0;
        for (0..length) |index| {
            const command = try engine.checked(c.JS_GetPropertyUint32(engine.context, commands, @intCast(index)));
            defer engine.freeValue(command);
            const name_value = try get(engine, command, "name");
            defer engine.freeValue(name_value);
            if (!c.JS_IsString(name_value)) continue;
            const name = try engine.toString(name_value);
            defer engine.gpa.free(name);
            const value = try std.fmt.allocPrint(engine.gpa, "/{s}", .{std.mem.trimStart(u8, name, "/")});
            defer engine.gpa.free(value);
            if (!std.mem.startsWith(u8, value, prefix)) continue;
            const item = try engine.checked(c.JS_NewObject(engine.context));
            var item_owned = true;
            defer if (item_owned) engine.freeValue(item);
            try put(engine, item, "value", try engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len)));
            try put(engine, item, "label", try engine.checked(c.JS_NewStringLen(engine.context, value.ptr, value.len)));
            const description = try get(engine, command, "description");
            if (c.JS_IsString(description)) try put(engine, item, "description", description) else engine.freeValue(description);
            item_owned = false;
            if (c.JS_SetPropertyUint32(engine.context, items, count, item) < 0) return error.JavaScriptException;
            count += 1;
        }
        if (count == 0) return c.pi_js_null();
        const result = try engine.checked(c.JS_NewObject(engine.context));
        errdefer engine.freeValue(result);
        items_owned = false;
        try put(engine, result, "items", items);
        try put(engine, result, "prefix", try engine.checked(c.JS_NewStringLen(engine.context, prefix.ptr, prefix.len)));
        return result;
    }
    if (args.len < 5) return error.InvalidAutocompleteCompletion;
    const item_value = try get(engine, args[3], "value");
    defer engine.freeValue(item_value);
    if (!c.JS_IsString(item_value) or !c.JS_IsString(args[4])) return error.InvalidAutocompleteCompletion;
    const value = try engine.toString(item_value);
    defer engine.gpa.free(value);
    const prefix = try engine.toString(args[4]);
    defer engine.gpa.free(prefix);
    if (prefix.len > cursor or !std.mem.endsWith(u8, line[0..cursor], prefix)) return error.InvalidAutocompletePrefix;
    const updated = try std.mem.concat(engine.gpa, u8, &.{ line[0 .. cursor - prefix.len], value, line[cursor..] });
    defer engine.gpa.free(updated);
    const length_value = try get(engine, args[0], "length");
    defer engine.freeValue(length_value);
    const length = try dimension(engine, length_value, 4096);
    const lines = try engine.checked(c.JS_NewArray(engine.context));
    var lines_owned = true;
    defer if (lines_owned) engine.freeValue(lines);
    for (0..length) |index| {
        const copied = if (index == row) try engine.checked(c.JS_NewStringLen(engine.context, updated.ptr, updated.len)) else try engine.checked(c.JS_GetPropertyUint32(engine.context, args[0], @intCast(index)));
        if (c.JS_SetPropertyUint32(engine.context, lines, @intCast(index), copied) < 0) return error.JavaScriptException;
    }
    const result = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(result);
    lines_owned = false;
    try put(engine, result, "lines", lines);
    try put(engine, result, "cursorLine", c.JS_NewInt64(engine.context, @intCast(row)));
    try put(engine, result, "cursorCol", c.JS_NewInt64(engine.context, @intCast(autocomplete.utf16Length(updated[0 .. cursor - prefix.len + value.len]))));
    return result;
}
pub fn wrapped(engine: *engine_mod.Engine, context_holder: c.JSValue, wrappers: []const Wrapper) !c.JSValue {
    var current = try engine.checked(c.JS_NewObject(engine.context));
    errdefer engine.freeValue(current);
    var data = [_]c.JSValue{context_holder};
    inline for (.{ "getSuggestions", "applyCompletion", "shouldTriggerFileCompletion" }, 0..) |name, magic| try put(engine, current, name, try engine.checked(c.JS_NewCFunctionData2(engine.context, baseCall, name, 4, @intCast(magic), 1, &data)));
    const triggers = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(triggers);
    var trigger_count: u32 = 0;
    for (wrappers) |entry| {
        var args = [_]c.JSValue{current};
        const next = try engine.checked(c.JS_Call(engine.context, entry.factory, c.pi_js_undefined(), 1, &args));
        engine.freeValue(current);
        current = next;
        if (!c.JS_IsObject(current)) return error.InvalidAutocompleteProvider;
        const characters = try get(engine, current, "triggerCharacters");
        defer engine.freeValue(characters);
        if (c.JS_IsArray(characters)) {
            const length_value = try get(engine, characters, "length");
            defer engine.freeValue(length_value);
            const length = try dimension(engine, length_value, 4096);
            for (0..length) |index| {
                if (trigger_count >= 4096) return error.AutocompleteTriggerLimit;
                const character = try engine.checked(c.JS_GetPropertyUint32(engine.context, characters, @intCast(index)));
                if (c.JS_IsString(character)) {
                    if (c.JS_SetPropertyUint32(engine.context, triggers, trigger_count, character) < 0) return error.JavaScriptException;
                    trigger_count += 1;
                } else engine.freeValue(character);
            }
        }
    }
    if (trigger_count > 0) try put(engine, current, "triggerCharacters", c.JS_DupValue(engine.context, triggers));
    return current;
}
fn defaultCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const exports = engine.native_module_values.get("pi-coding-agent") orelse return fail(engine, error.NativeEditorModuleUnavailable);
    const constructor = get(engine, exports, "CustomEditor") catch |err| return fail(engine, err);
    defer engine.freeValue(constructor);
    return c.JS_CallConstructor(context, constructor, argc, argv);
}
pub fn defaultFactory(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.pi_js_function_magic(engine.context, defaultCall, "nativeDefaultEditor", 3, 0));
}
