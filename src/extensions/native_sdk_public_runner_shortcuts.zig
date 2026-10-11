//! Real public shortcut resolution and ordinary diagnostics/console receivers.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
const reserved = .{ "app.interrupt", "app.clear", "app.exit", "app.suspend", "app.thinking.cycle", "app.model.cycleForward", "app.model.cycleBackward", "app.model.select", "app.tools.expand", "app.thinking.toggle", "app.editor.external", "app.message.copy", "app.message.followUp", "tui.input.submit", "tui.select.confirm", "tui.select.cancel", "tui.input.copy", "tui.editor.deleteToLineEnd" };
pub fn initialize(engine: *em.Engine) !void {
    if (engine.native_sdk_reserved_shortcuts != null) return;
    const names = try sdk.array(engine);
    errdefer engine.freeValue(names);
    inline for (reserved, 0..) |name, index| if (c.JS_DefinePropertyValueUint32(engine.context, names, index, try sdk.text(engine, name), c.JS_PROP_C_W_E) < 0) return js.capture(engine);
    engine.native_sdk_reserved_shortcuts = names;
}
fn builtinBindings(engine: *em.Engine, config: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try sdk.object(engine);
    errdefer engine.freeValue(result);
    try initialize(engine);
    const names = c.JS_DupValue(engine.context, engine.native_sdk_reserved_shortcuts.?);
    defer engine.freeValue(names);
    const entries = try js.objectMethod(engine, "entries", config);
    defer engine.freeValue(entries);
    var outer = try js.Iterator.init(engine, entries, symbol);
    defer outer.deinit();
    errdefer outer.closePreserving();
    while (try outer.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |value| engine.freeValue(value);
        if (c.JS_IsUndefined(pair[1])) continue;
        const array = try js.global(engine, "Array");
        defer engine.freeValue(array);
        const is_array = try js.invoke(engine, array, "isArray", &.{pair[1]});
        defer engine.freeValue(is_array);
        const keys = if (c.JS_ToBool(engine.context, is_array) == 1) c.JS_DupValue(engine.context, pair[1]) else blk: {
            const wrapped = try sdk.array(engine);
            errdefer engine.freeValue(wrapped);
            try sdk.append(engine, wrapped, c.JS_DupValue(engine.context, pair[1]));
            break :blk wrapped;
        };
        defer engine.freeValue(keys);
        const restrict = try js.invoke(engine, names, "includes", &.{pair[0]});
        defer engine.freeValue(restrict);
        var inner = try js.Iterator.init(engine, keys, symbol);
        defer inner.deinit();
        errdefer inner.closePreserving();
        while (try inner.next()) |key| {
            defer engine.freeValue(key);
            const normalized = try js.invoke(engine, key, "toLowerCase", &.{});
            defer engine.freeValue(normalized);
            const existing = try js.getKey(engine, result, normalized);
            defer engine.freeValue(existing);
            const restriction = if (c.JS_IsNull(existing) or c.JS_IsUndefined(existing)) c.pi_js_undefined() else try sdk.get(engine, existing, "restrictOverride");
            defer engine.freeValue(restriction);
            if (c.JS_ToBool(engine.context, restriction) == 1 and c.JS_ToBool(engine.context, restrict) != 1) continue;
            const value = try sdk.object(engine);
            defer engine.freeValue(value);
            try sdk.put(engine, value, "keybinding", c.JS_DupValue(engine.context, pair[0]));
            try sdk.put(engine, value, "restrictOverride", c.JS_DupValue(engine.context, restrict));
            try js.setKey(engine, result, normalized, c.JS_DupValue(engine.context, value));
        }
    }
    return result;
}
pub fn get(engine: *em.Engine, runner: c.JSValue, config: c.JSValue) !c.JSValue {
    if (c.JS_SetPropertyStr(engine.context, runner, "shortcutDiagnostics", try sdk.array(engine)) < 0) return js.capture(engine);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    const builtins = try builtinBindings(engine, config, symbol);
    defer engine.freeValue(builtins);
    const result = try js.builtin(engine, "Map", &.{});
    errdefer engine.freeValue(result);
    const extensions = try sdk.get(engine, runner, "extensions");
    defer engine.freeValue(extensions);
    var outer = try js.Iterator.init(engine, extensions, symbol);
    defer outer.deinit();
    errdefer outer.closePreserving();
    while (try outer.next()) |extension| {
        defer engine.freeValue(extension);
        const shortcuts = try sdk.get(engine, extension, "shortcuts");
        defer engine.freeValue(shortcuts);
        var inner = try js.Iterator.init(engine, shortcuts, symbol);
        defer inner.deinit();
        errdefer inner.closePreserving();
        while (try inner.next()) |entry| {
            defer engine.freeValue(entry);
            const pair = try js.pair(engine, entry, symbol);
            defer for (pair) |value| engine.freeValue(value);
            const key = try js.invoke(engine, pair[0], "toLowerCase", &.{});
            defer engine.freeValue(key);
            const builtin = try js.getKey(engine, builtins, key);
            defer engine.freeValue(builtin);
            const restriction = if (c.JS_IsNull(builtin) or c.JS_IsUndefined(builtin)) c.pi_js_undefined() else try sdk.get(engine, builtin, "restrictOverride");
            defer engine.freeValue(restriction);
            if (c.JS_IsStrictEqual(engine.context, restriction, c.pi_js_bool(engine.context, 1))) {
                try addMessage(engine, runner, .reserved, pair[0], builtin, pair[1]);
                continue;
            }
            const second_restriction = if (c.JS_IsNull(builtin) or c.JS_IsUndefined(builtin)) c.pi_js_undefined() else try sdk.get(engine, builtin, "restrictOverride");
            defer engine.freeValue(second_restriction);
            if (c.JS_IsStrictEqual(engine.context, second_restriction, c.pi_js_bool(engine.context, 0))) try addMessage(engine, runner, .builtin, pair[0], builtin, pair[1]);
            const existing = try js.invoke(engine, result, "get", &.{key});
            defer engine.freeValue(existing);
            if (c.JS_ToBool(engine.context, existing) == 1) try addMessage(engine, runner, .extension, pair[0], existing, pair[1]);
            const ignored = try js.invoke(engine, result, "set", &.{ key, pair[1] });
            engine.freeValue(ignored);
        }
    }
    return result;
}
const Conflict = enum { reserved, builtin, extension };
const Builder = struct {
    engine: *em.Engine,
    value: c.JSValue,
    fn append(self: *Builder, value: c.JSValue) !void {
        const converted = try self.engine.checked(c.JS_ToString(self.engine.context, value));
        defer self.engine.freeValue(converted);
        const combined = try self.engine.checked(c.JS_PiBinaryOperator(self.engine.context, 0, self.value, converted));
        self.engine.freeValue(self.value);
        self.value = combined;
    }
    fn text(self: *Builder, value: []const u8) !void {
        const literal = try sdk.text(self.engine, value);
        defer self.engine.freeValue(literal);
        try self.append(literal);
    }
    fn property(self: *Builder, value: c.JSValue, name: [*:0]const u8) !void {
        const field_value = try sdk.get(self.engine, value, name);
        defer self.engine.freeValue(field_value);
        try self.append(field_value);
    }
};
fn addMessage(engine: *em.Engine, runner: c.JSValue, kind: Conflict, key: c.JSValue, existing: c.JSValue, shortcut: c.JSValue) !void {
    var message: Builder = .{ .engine = engine, .value = try sdk.text(engine, "") };
    defer engine.freeValue(message.value);
    try message.text(if (kind == .reserved) "Extension shortcut '" else "Extension shortcut conflict: '");
    try message.append(key);
    switch (kind) {
        .reserved => {
            try message.text("' from ");
            try message.property(shortcut, "extensionPath");
            try message.text(" conflicts with built-in shortcut. Skipping.");
        },
        .builtin, .extension => {
            try message.text(if (kind == .builtin) "' is built-in shortcut for " else "' registered by both ");
            try message.property(existing, if (kind == .builtin) "keybinding" else "extensionPath");
            try message.text(" and ");
            try message.property(shortcut, "extensionPath");
            try message.text(". Using ");
            try message.property(shortcut, "extensionPath");
            try message.text(".");
        },
    }
    const path = try sdk.get(engine, shortcut, "extensionPath");
    defer engine.freeValue(path);
    const diagnostics = try sdk.get(engine, runner, "shortcutDiagnostics");
    defer engine.freeValue(diagnostics);
    const push = try sdk.get(engine, diagnostics, "push");
    defer engine.freeValue(push);
    const diagnostic = try sdk.object(engine);
    defer engine.freeValue(diagnostic);
    try sdk.put(engine, diagnostic, "type", try sdk.text(engine, "warning"));
    try sdk.put(engine, diagnostic, "message", c.JS_DupValue(engine.context, message.value));
    try sdk.put(engine, diagnostic, "path", c.JS_DupValue(engine.context, path));
    const ignored = try js.call(engine, push, diagnostics, &.{diagnostic});
    engine.freeValue(ignored);
    const has_ui = try js.invoke(engine, runner, "hasUI", &.{});
    defer engine.freeValue(has_ui);
    if (c.JS_ToBool(engine.context, has_ui) != 1) {
        const console = try js.global(engine, "console");
        defer engine.freeValue(console);
        const warned = try js.invoke(engine, console, "warn", &.{message.value});
        engine.freeValue(warned);
    }
}
