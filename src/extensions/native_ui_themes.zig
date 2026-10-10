//! Main UI theme queries over the genuine module registry and filesystem assets.
const std = @import("std");
const builtin = @import("builtin");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const v = @import("native_select_list.zig");
const array_values = @import("native_values.zig");
const theme = @import("native_theme.zig");
const assets = @import("native_theme_assets.zig");
const c = em.c;
const paths = @import("node_path.zig");
const flavor: paths.Flavor = if (builtin.os.tag == .windows) .win32 else .posix;
fn add(engine: *em.Engine, result: c.JSValue, seen: c.JSValue, name: c.JSValue, path: c.JSValue) !void {
    const present = try js.invoke(engine, seen, "has", &.{name});
    defer engine.freeValue(present);
    if (v.truthy(engine, present)) return;
    const ignored = try js.invoke(engine, seen, "add", &.{name});
    engine.freeValue(ignored);
    const info = try js.object(engine);
    defer engine.freeValue(info);
    try js.define(engine, info, "name", c.JS_DupValue(engine.context, name));
    try js.define(engine, info, "path", c.JS_DupValue(engine.context, path));
    try js.push(engine, result, info);
}
fn compare(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return compareValues(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| {
        if (err == error.JavaScriptException) return engine.throwCaptured();
        return c.JS_ThrowOutOfMemory(context);
    };
}
fn compareValues(engine: *em.Engine, a: c.JSValue, b: c.JSValue) !c.JSValue {
    const left = try js.get(engine, a, "name");
    defer engine.freeValue(left);
    const right = try js.get(engine, b, "name");
    defer engine.freeValue(right);
    const system = try v.text(engine, "system");
    defer engine.freeValue(system);
    if (c.JS_IsStrictEqual(engine.context, left, system)) return c.JS_NewInt32(engine.context, -1);
    if (c.JS_IsStrictEqual(engine.context, right, system)) return c.JS_NewInt32(engine.context, 1);
    return js.invoke(engine, left, "localeCompare", &.{right});
}
pub fn all(engine: *em.Engine) !c.JSValue {
    const root = try assets.directory(engine);
    defer engine.gpa.free(root);
    const builtins = try assets.builtinSources(engine);
    defer engine.freeValue(builtins);
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const seen = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(seen);
    const system = try v.text(engine, "system");
    defer engine.freeValue(system);
    try add(engine, result, seen, system, c.pi_js_undefined());
    inline for (.{ "dark", "light" }) |name| {
        const key = try v.text(engine, name);
        defer engine.freeValue(key);
        const path = try paths.join(engine.gpa, &.{ root, name ++ ".json" }, flavor);
        defer engine.gpa.free(path);
        const value = try v.text(engine, path);
        defer engine.freeValue(value);
        try add(engine, result, seen, key, value);
    }
    const io = engine.native_io orelse return error.NativeIoUnavailable;
    const custom = try @import("native_theme_watch.zig").directory(engine);
    defer engine.gpa.free(custom);
    if (std.Io.Dir.cwd().openDir(io, custom, .{ .iterate = true })) |directory| {
        defer directory.close(io);
        var iterator = directory.iterate();
        while (try iterator.next(io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            const path = try paths.join(engine.gpa, &.{ custom, entry.name }, flavor);
            defer engine.gpa.free(path);
            const loaded = theme.loadFile(engine, io, path, null) catch |err| {
                if (err == error.OutOfMemory) return err;
                if (engine.captured_exception) |exception| engine.freeValue(exception);
                engine.captured_exception = null;
                continue;
            };
            defer engine.freeValue(loaded);
            const name = try js.get(engine, loaded, "name");
            defer engine.freeValue(name);
            if (!v.truthy(engine, name)) continue;
            const value = try v.text(engine, path);
            defer engine.freeValue(value);
            try add(engine, result, seen, name, value);
        }
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    }
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    const registry = try js.get(engine, module, "registeredThemes");
    defer engine.freeValue(registry);
    const entries = try js.invoke(engine, registry, "entries", &.{});
    defer engine.freeValue(entries);
    const array = try js.global(engine, "Array");
    defer engine.freeValue(array);
    const rows = try js.invoke(engine, array, "from", &.{entries});
    defer engine.freeValue(rows);
    for (0..try array_values.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const name = try engine.checked(c.JS_GetPropertyUint32(engine.context, row, 0));
        defer engine.freeValue(name);
        const instance = try engine.checked(c.JS_GetPropertyUint32(engine.context, row, 1));
        defer engine.freeValue(instance);
        const path = try js.get(engine, instance, "sourcePath");
        defer engine.freeValue(path);
        try add(engine, result, seen, name, path);
    }
    const comparator = try engine.checked(c.JS_NewCFunction(engine.context, compare, "", 2));
    defer engine.freeValue(comparator);
    const sorted = try js.invoke(engine, result, "sort", &.{comparator});
    engine.freeValue(sorted);
    return result;
}
pub fn get(engine: *em.Engine, name: c.JSValue) !c.JSValue {
    return theme.loadByValue(engine, name, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (engine.captured_exception) |exception| engine.freeValue(exception);
        engine.captured_exception = null;
        return c.pi_js_undefined();
    };
}
pub fn hydrateCatalog(engine: *em.Engine, catalog: c.JSValue) !void {
    if (c.JS_IsUndefined(catalog) or c.JS_IsNull(catalog)) return;
    const encoded = try engine.stringify(catalog);
    defer engine.gpa.free(encoded);
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    const signature = try v.text(engine, encoded);
    defer engine.freeValue(signature);
    const old = try js.get(engine, module, "nativeMainThemeCatalogSignature");
    defer engine.freeValue(old);
    if (c.JS_IsStrictEqual(engine.context, old, signature)) return;
    const rows = try js.get(engine, catalog, "records");
    defer engine.freeValue(rows);
    const instances = try js.array(engine);
    defer engine.freeValue(instances);
    for (0..try array_values.length(engine, rows)) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, @intCast(index)));
        defer engine.freeValue(row);
        const resource = try js.get(engine, row, "resource");
        defer engine.freeValue(resource);
        const raw = try engine.stringify(resource);
        defer engine.gpa.free(raw);
        const path = try js.get(engine, row, "path");
        defer engine.freeValue(path);
        const source = if (c.JS_IsString(path)) try engine.toString(path) else null;
        defer if (source) |text| engine.gpa.free(text);
        const instance = try theme.fromJson(engine, raw, source, null);
        defer engine.freeValue(instance);
        try js.push(engine, instances, instance);
    }
    try theme.setRegisteredThemes(engine, instances);
    try js.define(engine, module, "nativeMainThemeCatalogSignature", c.JS_DupValue(engine.context, signature));
}

pub const Selection = struct {
    result: c.JSValue,
    payload: c.JSValue,
    pub fn deinit(self: Selection, engine: *em.Engine) void {
        engine.freeValue(self.result);
        engine.freeValue(self.payload);
    }
};
pub fn select(engine: *em.Engine, input: c.JSValue, generation: u64) !Selection {
    const exports = engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeConstructorUnavailable;
    const constructor = try js.get(engine, exports, "Theme");
    defer engine.freeValue(constructor);
    const is_instance = c.JS_IsInstanceOf(engine.context, input, constructor);
    if (is_instance < 0) return js.capture(engine);
    const result = if (is_instance != 0) instance: {
        try theme.setThemeInstance(engine, input);
        const value = try js.object(engine);
        errdefer engine.freeValue(value);
        try js.define(engine, value, "success", c.pi_js_bool(engine.context, 1));
        break :instance value;
    } else try theme.setTheme(engine, input, true);
    errdefer engine.freeValue(result);
    const module = try theme.moduleState(engine);
    defer engine.freeValue(module);
    const current_name = try js.get(engine, module, "currentThemeName");
    defer engine.freeValue(current_name);
    const system = try v.text(engine, "system");
    defer engine.freeValue(system);
    const adaptive_system = is_instance == 0 and c.JS_IsStrictEqual(engine.context, current_name, system);
    const payload = try js.object(engine);
    errdefer engine.freeValue(payload);
    try js.define(engine, payload, "name", c.JS_DupValue(engine.context, current_name));
    const success = try js.get(engine, result, "success");
    defer engine.freeValue(success);
    try js.define(engine, payload, "settingName", if (is_instance == 0 and v.truthy(engine, success) and c.JS_IsString(input)) c.JS_DupValue(engine.context, input) else c.pi_js_null());
    if (adaptive_system) {
        try js.define(engine, payload, "resource", c.pi_js_null());
        try js.define(engine, payload, "resourceIdentity", c.pi_js_null());
    } else {
        const proxy = try theme.current(engine);
        defer engine.freeValue(proxy);
        const colors = try js.get(engine, proxy, "colors");
        defer engine.freeValue(colors);
        const values = try js.object(engine);
        defer engine.freeValue(values);
        var names: [*c]c.JSPropertyEnum = null;
        var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &names, &count, colors, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
        defer c.JS_FreePropertyEnum(engine.context, names, count);
        for (names[0..count]) |entry| {
            const value = try engine.checked(c.JS_GetProperty(engine.context, colors, entry.atom));
            defer engine.freeValue(value);
            const color = (try @import("native_color.zig").read(engine, value)) orelse return error.InvalidNativeThemeColor;
            const encoded = switch (color) {
                .indexed => |index| c.JS_NewInt32(engine.context, index),
                else => encoded: {
                    const text = try @import("../tui/colors.zig").colorToHex(engine.gpa, color);
                    defer engine.gpa.free(text);
                    break :encoded try v.text(engine, text);
                },
            };
            if (c.JS_DefinePropertyValue(engine.context, values, entry.atom, encoded, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
        }
        const resource = try js.object(engine);
        defer engine.freeValue(resource);
        try js.define(engine, resource, "name", c.JS_DupValue(engine.context, current_name));
        try js.define(engine, resource, "colors", c.JS_DupValue(engine.context, values));
        const appearance = try js.get(engine, proxy, "appearance");
        defer engine.freeValue(appearance);
        if (!c.JS_IsUndefined(appearance)) try js.define(engine, resource, "appearance", c.JS_DupValue(engine.context, appearance));
        const identity_text = try std.fmt.allocPrint(engine.gpa, "main-ui-theme/{d}", .{generation});
        defer engine.gpa.free(identity_text);
        const identity = try v.text(engine, identity_text);
        defer engine.freeValue(identity);
        try js.define(engine, payload, "resource", c.JS_DupValue(engine.context, resource));
        try js.define(engine, payload, "resourceIdentity", c.JS_DupValue(engine.context, identity));
        const signature = try engine.stringify(resource);
        defer engine.gpa.free(signature);
        try js.define(engine, module, "selectedResourceSignature", try v.text(engine, signature));
        try js.define(engine, module, "resourceIdentity", c.JS_DupValue(engine.context, identity));
    }
    return .{ .result = result, .payload = payload };
}
