//! Retained Theme instances and source-authentic color/token resolution.
const std = @import("std");
const engine_mod = @import("engine.zig");
const color_api = @import("native_color.zig");
const colors = color_api.colors;
const c = engine_mod.c;
pub const ColorMode = colors.ColorMode;
const Method = enum(c_int) { fg, bg, getFgAnsi, getBgAnsi, getColorMode, style, bold, italic, underline, inverse, strikethrough, getThinkingBorderColor, getBashModeBorderColor, appearance, concreteColors };
const ModuleMethod = enum(c_int) { setTerminalColors, setTerminalColorScheme, markTerminalColorsPending, getTerminalTheme, loadThemeFromPath, initTheme, getSelectListTheme, getSettingsListTheme };
const Node = struct {
    engine: *engine_mod.Engine,
    module: c.JSValue,
    fg: c.JSValue,
    bg: c.JSValue,
    concrete: c.JSValue,
    default_fg: c.JSValue,
    default_bg: c.JSValue,
    dim: c.JSValue,
    own_appearance: c.JSValue,
    color_mode: c.JSValue,
    resolved: c.JSValue,
    last_terminal: c.JSValue,
};
const Constructor = struct { engine: *engine_mod.Engine, prototype: c.JSValue, module: c.JSValue, class_id: c.JSClassID };
const Proxy = struct { engine: *engine_mod.Engine, module: c.JSValue };
fn put(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8, value: c.JSValue) !void {
    if (c.JS_DefinePropertyValueStr(engine.context, receiver, name, value, c.JS_PROP_C_W_E) < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
}
fn get(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return engine.checked(c.JS_GetPropertyStr(engine.context, receiver, name));
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn jsString(engine: *engine_mod.Engine, text: []const u8) !c.JSValue {
    return engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
}
fn invoke(engine: *engine_mod.Engine, receiver: c.JSValue, name: [*:0]const u8, args: []const c.JSValue) !c.JSValue {
    const function = try get(engine, receiver, name);
    defer engine.freeValue(function);
    return engine.checked(c.JS_Call(engine.context, function, receiver, @intCast(args.len), @constCast(args.ptr)));
}
fn object(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObject(engine.context));
}
fn dictionary(engine: *engine_mod.Engine) !c.JSValue {
    return engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null()));
}
fn fail(engine: *engine_mod.Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native Theme: %s", @as([*:0]const u8, @errorName(err)));
}
const OwnNames = struct {
    engine: *engine_mod.Engine,
    values: [*c]c.JSPropertyEnum,
    length: u32,
    fn init(engine: *engine_mod.Engine, value: c.JSValue) !OwnNames {
        var result: OwnNames = .{ .engine = engine, .values = null, .length = 0 };
        if (c.JS_GetOwnPropertyNames(engine.context, &result.values, &result.length, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) {
            _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
            return error.JavaScriptException;
        }
        return result;
    }
    fn deinit(self: OwnNames) void {
        c.JS_FreePropertyEnum(self.engine.context, self.values, self.length);
    }
};
fn snapshot(engine: *engine_mod.Engine, source: c.JSValue) !c.JSValue {
    const result = try object(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsNull(source) or c.JS_IsUndefined(source)) return result;
    const names = try OwnNames.init(engine, source);
    defer names.deinit();
    for (names.values[0..names.length]) |entry| {
        const value = try engine.checked(c.JS_GetProperty(engine.context, source, entry.atom));
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, value, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    return result;
}
fn finalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (std.meta.fields(Node)) |field| if (field.type == c.JSValue) c.JS_FreeValueRT(runtime, @field(node, field.name));
    node.engine.gpa.destroy(node);
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const node: *Node = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    inline for (std.meta.fields(Node)) |field| if (field.type == c.JSValue) c.JS_MarkValue(runtime, @field(node, field.name), callback);
}
fn constructorFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.module);
    state.engine.gpa.destroy(state);
}
fn constructorMark(runtime: ?*c.JSRuntime, value: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, callback);
    c.JS_MarkValue(runtime, state.module, callback);
}
fn proxyFinalizer(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *Proxy = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.module);
    state.engine.gpa.destroy(state);
}
fn proxyMark(runtime: ?*c.JSRuntime, value: c.JSValue, callback: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *Proxy = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.module, callback);
}
fn proxyGet(context: ?*c.JSContext, value: c.JSValue, atom: c.JSAtom, _: c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const state: *Proxy = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    const selected = get(engine, state.module, "current") catch |err| return fail(engine, err);
    defer engine.freeValue(selected);
    if (c.JS_IsUndefined(selected)) return fail(engine, color_api.throwError(engine, "Theme not initialized. Call initTheme() first."));
    return c.JS_GetProperty(context, selected, atom);
}
const proxy_exotic: c.JSClassExoticMethods = .{ .get_property = proxyGet };
fn constructorCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "Class constructor Theme cannot be invoked without 'new'");
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return construct(state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn fallback(engine: *engine_mod.Engine, values: c.JSValue, token: [*:0]const u8, base: [*:0]const u8) !void {
    const selected = try get(engine, values, token);
    defer engine.freeValue(selected);
    if (c.JS_IsUndefined(selected) or c.JS_IsNull(selected)) try put(engine, values, token, try get(engine, values, base));
}
fn fallbackFrom(engine: *engine_mod.Engine, target: c.JSValue, source: c.JSValue, token: [*:0]const u8, base: [*:0]const u8) !void {
    const value = try get(engine, source, token);
    defer engine.freeValue(value);
    try put(engine, target, token, if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) try get(engine, source, base) else c.JS_DupValue(engine.context, value));
}
fn addTokens(node: *Node, values: c.JSValue, background: bool, average: *f64, count: *usize) !void {
    const engine = node.engine;
    const names = try OwnNames.init(engine, values);
    defer names.deinit();
    for (names.values[0..names.length]) |entry| {
        const value = try engine.checked(c.JS_GetProperty(engine.context, values, entry.atom));
        defer engine.freeValue(value);
        const text = if (c.JS_IsString(value)) try engine.toString(value) else null;
        defer if (text) |bytes| engine.gpa.free(bytes);
        const slot = if (background) node.bg else node.fg;
        if (text != null and text.?.len == 0) {
            if (c.JS_DefinePropertyValue(engine.context, if (background) node.default_bg else node.default_fg, entry.atom, c.JS_NewBool(engine.context, true), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            if (c.JS_DefinePropertyValue(engine.context, slot, entry.atom, try jsString(engine, if (background) "\x1b[49m" else "\x1b[39m"), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
            continue;
        }
        const color = try color_api.parse(engine, value);
        const fixed = switch (color) {
            .indexed => |index| index >= 16,
            else => true,
        };
        if (fixed) {
            average.* += colors.colorToOklch(color).l;
            count.* += 1;
        }
        const ansi = try colors.colorAnsi(engine.gpa, color, try color_api.mode(engine, node.color_mode), background);
        defer engine.gpa.free(ansi);
        if (c.JS_DefinePropertyValue(engine.context, slot, entry.atom, try jsString(engine, ansi), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
        if (c.JS_DefinePropertyValue(engine.context, node.concrete, entry.atom, try color_api.create(engine, color), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
}
fn construct(state: *Constructor, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const engine = state.engine;
    const selected = try get(engine, target, "prototype");
    defer engine.freeValue(selected);
    const value = try engine.checked(c.JS_NewObjectProtoClass(engine.context, if (c.JS_IsObject(selected)) selected else state.prototype, state.class_id));
    errdefer engine.freeValue(value);
    const node = try engine.gpa.create(Node);
    node.engine = engine;
    inline for (std.meta.fields(Node)) |field| {
        if (field.type == c.JSValue) @field(node, field.name) = c.pi_js_undefined();
    }
    _ = c.JS_SetOpaque(value, node);
    node.module = c.JS_DupValue(engine.context, state.module);
    node.fg = try dictionary(engine);
    node.bg = try dictionary(engine);
    node.concrete = try object(engine);
    node.default_fg = try dictionary(engine);
    node.default_bg = try dictionary(engine);
    const options = if (c.JS_IsUndefined(arg(args, 3))) try object(engine) else c.JS_DupValue(engine.context, arg(args, 3));
    defer engine.freeValue(options);
    inline for (.{ "name", "sourcePath", "sourceInfo" }) |name| try put(engine, value, name, try get(engine, options, name));
    node.color_mode = c.JS_DupValue(engine.context, arg(args, 2));
    const dim_value = try get(engine, options, "dim");
    defer engine.freeValue(dim_value);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const set = try get(engine, global, "Set");
    defer engine.freeValue(set);
    var set_args = [_]c.JSValue{dim_value};
    node.dim = try engine.checked(c.JS_CallConstructor(engine.context, set, 1, &set_args));
    const fg = try snapshot(engine, arg(args, 0));
    defer engine.freeValue(fg);
    const bg = try snapshot(engine, arg(args, 1));
    defer engine.freeValue(bg);
    inline for (.{ .{ "scrollbarTrack", "muted" }, .{ "scrollbarThumb", "text" }, .{ "thinkingMax", "thinkingXhigh" }, .{ "searchMatchText", "text" } }) |pair| try fallbackFrom(engine, fg, arg(args, 0), pair[0], pair[1]);
    try fallbackFrom(engine, bg, arg(args, 1), "searchMatchBg", "selectedBg");
    var fg_average: f64 = 0;
    var bg_average: f64 = 0;
    var fg_count: usize = 0;
    var bg_count: usize = 0;
    try addTokens(node, fg, false, &fg_average, &fg_count);
    try addTokens(node, bg, true, &bg_average, &bg_count);
    const declared_appearance = try get(engine, options, "appearance");
    if (!c.JS_IsUndefined(declared_appearance) and !c.JS_IsNull(declared_appearance)) {
        node.own_appearance = declared_appearance;
    } else {
        engine.freeValue(declared_appearance);
        if (fg_count != 0) fg_average /= @floatFromInt(fg_count);
        if (bg_count != 0) bg_average /= @floatFromInt(bg_count);
        const dark: ?bool = if (fg_count != 0 and bg_count != 0) bg_average < fg_average else if (bg_count != 0) bg_average < 0.5 else if (fg_count != 0) fg_average > 0.5 else null;
        if (dark) |is_dark| node.own_appearance = try jsString(engine, if (is_dark) "dark" else "light");
    }
    return value;
}
fn dimToken(node: *Node, token: c.JSValue) !bool {
    const engine = node.engine;
    const has = try get(engine, node.dim, "has");
    defer engine.freeValue(has);
    var args = [_]c.JSValue{token};
    const result = try engine.checked(c.JS_Call(engine.context, has, node.dim, 1, &args));
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn tokenAnsi(node: *Node, token: c.JSValue, background: bool) !c.JSValue {
    const engine = node.engine;
    if (c.JS_IsString(token)) {
        const name = try engine.toString(token);
        defer engine.gpa.free(name);
        const name_z = try engine.gpa.dupeZ(u8, name);
        defer engine.gpa.free(name_z);
        const result = try get(engine, if (background) node.bg else node.fg, name_z.ptr);
        if (!c.JS_IsUndefined(result)) return result;
        engine.freeValue(result);
    }
    const text = try engine.toString(token);
    defer engine.gpa.free(text);
    const message = try std.fmt.allocPrint(engine.gpa, "Unknown theme color: {s}", .{text});
    defer engine.gpa.free(message);
    return color_api.throwError(engine, message);
}
fn terminalAppearance(engine: *engine_mod.Engine, module: c.JSValue) !c.JSValue {
    const terminal = try get(engine, module, "terminal");
    defer engine.freeValue(terminal);
    const bg = try get(engine, terminal, "background");
    defer engine.freeValue(bg);
    if (c.JS_ToBool(engine.context, bg) != 0) {
        const color = (try color_api.read(engine, bg)) orelse blk: {
            const r = try get(engine, bg, "r");
            defer engine.freeValue(r);
            const g = try get(engine, bg, "g");
            defer engine.freeValue(g);
            const b = try get(engine, bg, "b");
            defer engine.freeValue(b);
            break :blk colors.Color{ .rgb = .{ .r = try color_api.number(engine, r), .g = try color_api.number(engine, g), .b = try color_api.number(engine, b) } };
        };
        const fg = try get(engine, terminal, "foreground");
        defer engine.freeValue(fg);
        const foreground = if (c.JS_ToBool(engine.context, fg) != 0) (try terminalColor(engine, terminal, "foreground", .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } })).rgb else null;
        return jsString(engine, @tagName(@import("../themes/system_theme.zig").terminalAppearance(colors.colorToRgb(color), foreground)));
    }
    const scheme = try get(engine, module, "scheme");
    if (!c.JS_IsUndefined(scheme) and !c.JS_IsNull(scheme)) return scheme;
    engine.freeValue(scheme);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try get(engine, global, "process");
    defer engine.freeValue(process);
    if (c.JS_IsObject(process)) {
        const env = try get(engine, process, "env");
        defer engine.freeValue(env);
        if (c.JS_IsObject(env)) {
            const setting = try get(engine, env, "COLORFGBG");
            defer engine.freeValue(setting);
            if (c.JS_IsString(setting)) {
                const text = try engine.toString(setting);
                defer engine.gpa.free(text);
                const start = if (std.mem.lastIndexOfScalar(u8, text, ';')) |index| index + 1 else 0;
                const value = std.mem.trim(u8, text[start..], " \t\r\n");
                if (value.len > 0 and value.len <= 2) {
                    var digits = true;
                    for (value) |byte| if (!std.ascii.isDigit(byte)) {
                        digits = false;
                    };
                    if (digits) {
                        const index = try std.fmt.parseInt(u8, value, 10);
                        if (index <= 15) return jsString(engine, if (index <= 6 or index == 8) "dark" else "light");
                    }
                }
            }
        }
    }
    return jsString(engine, "dark");
}
fn appearance(node: *Node) !c.JSValue {
    return if (!c.JS_IsUndefined(node.own_appearance)) c.JS_DupValue(node.engine.context, node.own_appearance) else terminalAppearance(node.engine, node.module);
}
fn terminalColor(engine: *engine_mod.Engine, terminal: c.JSValue, name: [*:0]const u8, fallback_color: colors.Color) !colors.Color {
    const value = try get(engine, terminal, name);
    defer engine.freeValue(value);
    if (c.JS_ToBool(engine.context, value) == 0) return fallback_color;
    const r = try get(engine, value, "r");
    defer engine.freeValue(r);
    const g = try get(engine, value, "g");
    defer engine.freeValue(g);
    const b = try get(engine, value, "b");
    defer engine.freeValue(b);
    return colors.rgbColor(try color_api.number(engine, r), try color_api.number(engine, g), try color_api.number(engine, b));
}
fn concreteColors(node: *Node) !c.JSValue {
    const engine = node.engine;
    const terminal = try get(engine, node.module, "terminal");
    defer engine.freeValue(terminal);
    if (c.JS_IsStrictEqual(engine.context, terminal, node.last_terminal)) return c.JS_DupValue(engine.context, node.resolved);
    const designed = try appearance(node);
    defer engine.freeValue(designed);
    const appearance_name = try engine.toString(designed);
    defer engine.gpa.free(appearance_name);
    const light = std.mem.eql(u8, appearance_name, "light");
    const fg = try terminalColor(engine, terminal, "foreground", try colors.parseColor(if (light) "#000000" else "#e5e5e7"));
    const bg = try terminalColor(engine, terminal, "background", try colors.parseColor(if (light) "#ffffff" else "#000000"));
    const result = try snapshot(engine, node.concrete);
    errdefer engine.freeValue(result);
    inline for (.{ .{ node.default_fg, fg }, .{ node.default_bg, bg } }) |pair| {
        const names = try OwnNames.init(engine, pair[0]);
        defer names.deinit();
        const value = try color_api.create(engine, pair[1]);
        defer engine.freeValue(value);
        for (names.values[0..names.length]) |entry| if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, c.JS_DupValue(engine.context, value), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const names = try OwnNames.init(engine, result);
    defer names.deinit();
    for (names.values[0..names.length]) |entry| {
        const token = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
        defer engine.freeValue(token);
        if (!try dimToken(node, token)) continue;
        const value = try engine.checked(c.JS_GetProperty(engine.context, result, entry.atom));
        defer engine.freeValue(value);
        const color = (try color_api.read(engine, value)).?;
        if (c.JS_DefinePropertyValue(engine.context, result, entry.atom, try color_api.create(engine, try colors.mixColors(color, bg, 0.4, .oklch)), c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    try color_api.freeze(engine, result);
    engine.freeValue(node.last_terminal);
    engine.freeValue(node.resolved);
    node.last_terminal = c.JS_DupValue(engine.context, terminal);
    node.resolved = c.JS_DupValue(engine.context, result);
    return result;
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    var class_id: u32 = 0;
    if (c.JS_ToUint32(context, &class_id, data[0]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
    var retained = c.pi_js_undefined();
    defer engine.freeValue(retained);
    var node_handle = c.JS_GetOpaque(receiver, class_id);
    if (node_handle == null) {
        var proxy_class: u32 = 0;
        if (c.JS_ToUint32(context, &proxy_class, data[1]) < 0) return c.JS_Throw(context, c.JS_GetException(context));
        const proxy_state: *Proxy = @ptrCast(@alignCast(c.JS_GetOpaque(receiver, proxy_class) orelse return c.JS_ThrowTypeError(context, "Illegal Theme receiver")));
        retained = get(engine, proxy_state.module, "current") catch |err| return fail(engine, err);
        node_handle = c.JS_GetOpaque(retained, class_id);
    }
    const node: *Node = @ptrCast(@alignCast(node_handle orelse return c.JS_ThrowTypeError(context, "Illegal Theme receiver")));
    return methodOperation(node, receiver, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn borderCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const method = get(engine, data[0], "fg") catch |err| return fail(engine, err);
    defer engine.freeValue(method);
    var args = [_]c.JSValue{ data[1], if (argc != 0) argv[0] else c.pi_js_undefined() };
    return c.JS_Call(context, method, data[0], 2, &args);
}
fn methodOperation(node: *Node, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const engine = node.engine;
    switch (method) {
        .appearance => return appearance(node),
        .concreteColors => return concreteColors(node),
        .getColorMode => return c.JS_DupValue(engine.context, node.color_mode),
        .getThinkingBorderColor, .getBashModeBorderColor => {
            var token: []const u8 = "bashMode";
            if (method == .getThinkingBorderColor) {
                const level = try engine.toString(arg(args, 0));
                defer engine.gpa.free(level);
                token = "thinkingOff";
                inline for (.{ .{ "minimal", "thinkingMinimal" }, .{ "low", "thinkingLow" }, .{ "medium", "thinkingMedium" }, .{ "high", "thinkingHigh" }, .{ "xhigh", "thinkingXhigh" }, .{ "max", "thinkingMax" } }) |pair| if (std.mem.eql(u8, level, pair[0])) {
                    token = pair[1];
                };
            }
            var data = [_]c.JSValue{ receiver, try jsString(engine, token) };
            defer engine.freeValue(data[1]);
            return engine.checked(c.JS_NewCFunctionData2(engine.context, borderCall, "", 1, 0, 2, &data));
        },
        .fg, .bg, .getFgAnsi, .getBgAnsi => {
            const background = method == .bg or method == .getBgAnsi;
            const opening_value = try tokenAnsi(node, arg(args, 0), background);
            defer engine.freeValue(opening_value);
            const opening = try engine.toString(opening_value);
            defer engine.gpa.free(opening);
            const dim = !background and try dimToken(node, arg(args, 0));
            const just_opening = method == .getFgAnsi or method == .getBgAnsi;
            const text = if (just_opening) try engine.gpa.dupe(u8, "") else try engine.toString(arg(args, 1));
            defer engine.gpa.free(text);
            const result = try std.fmt.allocPrint(engine.gpa, "{s}{s}{s}{s}", .{ opening, if (dim) "\x1b[2m" else "", text, if (just_opening) "" else if (background) "\x1b[49m" else if (dim) "\x1b[22;39m" else "\x1b[39m" });
            defer engine.gpa.free(result);
            return jsString(engine, result);
        },
        .style => {
            const source = arg(args, 1);
            const fg = try get(engine, source, "fg");
            defer engine.freeValue(fg);
            const bg = try get(engine, source, "bg");
            defer engine.freeValue(bg);
            const options = if (c.JS_IsString(fg) and try dimToken(node, fg)) blk: {
                const value = try snapshot(engine, source);
                errdefer engine.freeValue(value);
                try put(engine, value, "dim", c.JS_NewBool(engine.context, true));
                break :blk value;
            } else c.JS_DupValue(engine.context, source);
            defer engine.freeValue(options);
            const foreground = try styleColor(node, fg, false);
            defer engine.freeValue(foreground);
            const background = try styleColor(node, bg, true);
            defer engine.freeValue(background);
            return color_api.style(engine, arg(args, 0), foreground, background, options);
        },
        else => {
            const enabled = try get(engine, node.module, "chalkEnabled");
            defer engine.freeValue(enabled);
            return chalkStyle(engine, c.JS_ToBool(engine.context, enabled) != 0, method, arg(args, 0));
        },
    }
}
fn styleColor(node: *Node, value: c.JSValue, background: bool) !c.JSValue {
    if (c.JS_IsUndefined(value)) return c.pi_js_undefined();
    if (c.JS_IsString(value)) return tokenAnsi(node, value, background);
    return color_api.ansiValue(node.engine, value, try color_api.mode(node.engine, node.color_mode), background);
}
fn chalkStyle(engine: *engine_mod.Engine, enabled: bool, method: Method, value: c.JSValue) !c.JSValue {
    const opening, const closing = switch (method) {
        .bold => .{ "\x1b[1m", "\x1b[22m" },
        .italic => .{ "\x1b[3m", "\x1b[23m" },
        .underline => .{ "\x1b[4m", "\x1b[24m" },
        .inverse => .{ "\x1b[7m", "\x1b[27m" },
        .strikethrough => .{ "\x1b[9m", "\x1b[29m" },
        else => unreachable,
    };
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    if (!enabled or text.len == 0) return jsString(engine, text);
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(engine.gpa);
    try result.appendSlice(engine.gpa, opening);
    var index: usize = 0;
    while (index < text.len) {
        if (std.mem.startsWith(u8, text[index..], closing)) {
            // Chalk 6 preserves each existing closing code, then reopens it.
            try result.appendSlice(engine.gpa, closing);
            try result.appendSlice(engine.gpa, opening);
            index += closing.len;
        } else if (text[index] == '\n' or (text[index] == '\r' and index + 1 < text.len and text[index + 1] == '\n')) {
            try result.appendSlice(engine.gpa, closing);
            if (text[index] == '\r') {
                try result.append(engine.gpa, '\r');
                index += 1;
            }
            try result.append(engine.gpa, '\n');
            try result.appendSlice(engine.gpa, opening);
            index += 1;
        } else {
            try result.append(engine.gpa, text[index]);
            index += 1;
        }
    }
    try result.appendSlice(engine.gpa, closing);
    return jsString(engine, result.items);
}
fn moduleCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    return moduleOperation(engine, data[0], @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn moduleOperation(engine: *engine_mod.Engine, module: c.JSValue, method: ModuleMethod, args: []const c.JSValue) !c.JSValue {
    switch (method) {
        .getSelectListTheme => return getSelectListTheme(engine),
        .getSettingsListTheme => return getSettingsListTheme(engine),
        .setTerminalColors => {
            try put(engine, module, "terminal", try snapshot(engine, arg(args, 0)));
            try put(engine, module, "pending", c.JS_NewBool(engine.context, false));
        },
        .setTerminalColorScheme => try put(engine, module, "scheme", c.JS_DupValue(engine.context, arg(args, 0))),
        .markTerminalColorsPending => try put(engine, module, "pending", c.JS_NewBool(engine.context, true)),
        .getTerminalTheme => return terminalAppearance(engine, module),
        .loadThemeFromPath => {
            const path = try engine.toString(arg(args, 0));
            defer engine.gpa.free(path);
            return loadFile(engine, engine.native_io orelse return error.NativeIoUnavailable, path, if (c.JS_IsUndefined(arg(args, 1))) null else try color_api.mode(engine, arg(args, 1)));
        },
        .initTheme => {
            const name = if (c.JS_IsUndefined(arg(args, 0))) try engine.gpa.dupe(u8, "system") else try engine.toString(arg(args, 0));
            defer engine.gpa.free(name);
            const selected = loadByName(engine, name, null) catch |err| blk: {
                if (err == error.OutOfMemory) return err;
                break :blk try createSystem(engine, null);
            };
            try put(engine, module, "current", selected);
            try put(engine, module, "resourceSignature", c.pi_js_undefined());
        },
    }
    return c.pi_js_undefined();
}
const ComponentMethod = enum(c_int) { accent, muted, dim, borderMuted, label, value };
fn componentCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    const kind: ComponentMethod = @enumFromInt(magic);
    const text = if (argc > 0) argv[0] else c.pi_js_undefined();
    const selected = argc > 1 and c.JS_ToBool(context, argv[1]) != 0;
    if (kind == .label and !selected) return c.JS_DupValue(context, text);
    const token: []const u8 = switch (kind) {
        .accent => "accent",
        .muted => "muted",
        .dim => "dim",
        .borderMuted => "borderMuted",
        .label => "accent",
        .value => if (selected) "accent" else "muted",
    };
    const fg = get(engine, data[0], "fg") catch |err| return fail(engine, err);
    defer engine.freeValue(fg);
    const name = jsString(engine, token) catch |err| return fail(engine, err);
    defer engine.freeValue(name);
    var args = [_]c.JSValue{ name, text };
    return c.JS_Call(context, fg, data[0], args.len, &args);
}
fn componentFunction(engine: *engine_mod.Engine, proxy: c.JSValue, name: [*:0]const u8, kind: ComponentMethod) !c.JSValue {
    var data = [_]c.JSValue{proxy};
    return engine.checked(c.JS_NewCFunctionData2(engine.context, componentCall, name, if (kind == .label or kind == .value) 2 else 1, @intFromEnum(kind), data.len, &data));
}
pub fn getSelectListTheme(engine: *engine_mod.Engine) !c.JSValue {
    const proxy = try current(engine);
    defer engine.freeValue(proxy);
    const result = try object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "selectedPrefix", ComponentMethod.accent }, .{ "selectedText", ComponentMethod.accent }, .{ "description", ComponentMethod.muted }, .{ "scrollInfo", ComponentMethod.muted }, .{ "noMatch", ComponentMethod.muted } }) |entry| try put(engine, result, entry[0], try componentFunction(engine, proxy, entry[0], entry[1]));
    return result;
}
pub fn getEditorTheme(engine: *engine_mod.Engine) !c.JSValue {
    const proxy = try current(engine);
    defer engine.freeValue(proxy);
    const result = try object(engine);
    errdefer engine.freeValue(result);
    try put(engine, result, "borderColor", try componentFunction(engine, proxy, "borderColor", .borderMuted));
    try put(engine, result, "selectList", try getSelectListTheme(engine));
    return result;
}
pub fn getSettingsListTheme(engine: *engine_mod.Engine) !c.JSValue {
    const proxy = try current(engine);
    defer engine.freeValue(proxy);
    const result = try object(engine);
    errdefer engine.freeValue(result);
    inline for (.{ .{ "label", ComponentMethod.label }, .{ "value", ComponentMethod.value }, .{ "description", ComponentMethod.dim } }) |entry| try put(engine, result, entry[0], try componentFunction(engine, proxy, entry[0], entry[1]));
    const arrow = try jsString(engine, "→ ");
    defer engine.freeValue(arrow);
    const paint = try componentFunction(engine, proxy, "cursor", .accent);
    defer engine.freeValue(paint);
    var args = [_]c.JSValue{arrow};
    try put(engine, result, "cursor", try engine.checked(c.JS_Call(engine.context, paint, c.pi_js_undefined(), args.len, &args)));
    try put(engine, result, "hint", try componentFunction(engine, proxy, "hint", .dim));
    return result;
}
fn supportsModifiers(engine: *engine_mod.Engine, tty_override: ?bool) !bool {
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const process = try get(engine, global, "process");
    defer engine.freeValue(process);
    if (!c.JS_IsObject(process)) return tty_override orelse false;
    const env = try get(engine, process, "env");
    defer engine.freeValue(env);
    var force: ?bool = null;
    const argv = try get(engine, process, "argv");
    defer engine.freeValue(argv);
    inline for (.{ "no-color", "no-colors", "color=false", "color=never" }) |flag| if (try hasFlag(engine, argv, flag)) {
        force = false;
    };
    if (force == null) inline for (.{ "color", "colors", "color=true", "color=always" }) |flag| if (try hasFlag(engine, argv, flag)) {
        force = true;
    };
    if (c.JS_IsObject(env)) {
        const forced = try get(engine, env, "FORCE_COLOR");
        defer engine.freeValue(forced);
        if (c.JS_IsString(forced)) {
            const text = try engine.toString(forced);
            defer engine.gpa.free(text);
            if (std.mem.eql(u8, text, "false")) force = false;
            if (text.len == 0 or std.mem.eql(u8, text, "true")) force = true;
            var numeric = text.len > 0;
            var nonzero = false;
            for (text) |byte| {
                numeric = numeric and std.ascii.isDigit(byte);
                nonzero = nonzero or byte != '0';
            }
            if (numeric) force = nonzero;
        }
    }
    if (force) |enabled| return enabled;
    inline for (.{ "color=16m", "color=full", "color=truecolor", "color=256" }) |flag| if (try hasFlag(engine, argv, flag)) return true;
    if (try envHas(engine, env, "TF_BUILD") and try envHas(engine, env, "AGENT_NAME")) return true;
    const stdout = try get(engine, process, "stdout");
    defer engine.freeValue(stdout);
    const tty = if (c.JS_IsObject(stdout)) try get(engine, stdout, "isTTY") else c.pi_js_undefined();
    defer engine.freeValue(tty);
    if (!(tty_override orelse (c.JS_ToBool(engine.context, tty) != 0))) return false;
    var arena = std.heap.ArenaAllocator.init(engine.gpa);
    defer arena.deinit();
    const term = try envText(engine, arena.allocator(), env, "TERM");
    if (std.mem.eql(u8, term, "dumb")) return false;
    const platform = try get(engine, process, "platform");
    defer engine.freeValue(platform);
    const platform_text = try engine.toString(platform);
    defer engine.gpa.free(platform_text);
    if (std.mem.eql(u8, platform_text, "win32")) return true;
    if (try envHas(engine, env, "CI")) {
        inline for (.{ "GITHUB_ACTIONS", "GITEA_ACTIONS", "CIRCLECI", "TRAVIS", "APPVEYOR", "GITLAB_CI", "BUILDKITE", "DRONE" }) |name| if (try envHas(engine, env, name)) return true;
        return std.mem.eql(u8, try envText(engine, arena.allocator(), env, "CI_NAME"), "codeship");
    }
    if (try envHas(engine, env, "TEAMCITY_VERSION")) {
        const version = try envText(engine, arena.allocator(), env, "TEAMCITY_VERSION");
        const first_dot = std.mem.indexOfScalar(u8, version, '.') orelse return false;
        const major_text = version[0..first_dot];
        const major = std.fmt.parseInt(u32, major_text, 10) catch return false;
        if (major_text.len >= 2 and major >= 10) return true;
        if (major != 9) return false;
        const rest = version[first_dot + 1 ..];
        const second_dot = std.mem.indexOfScalar(u8, rest, '.') orelse return false;
        return (std.fmt.parseInt(u64, rest[0..second_dot], 10) catch return false) > 0;
    }
    if (std.mem.eql(u8, try envText(engine, arena.allocator(), env, "COLORTERM"), "truecolor")) return true;
    inline for (.{ "xterm-kitty", "xterm-ghostty", "wezterm" }) |name| if (std.mem.eql(u8, term, name)) return true;
    const program = try envText(engine, arena.allocator(), env, "TERM_PROGRAM");
    if (std.mem.eql(u8, program, "iTerm.app") or std.mem.eql(u8, program, "Apple_Terminal")) return true;
    const lower = try std.ascii.allocLowerString(arena.allocator(), term);
    if (std.mem.endsWith(u8, lower, "-256") or std.mem.endsWith(u8, lower, "-256color")) return true;
    inline for (.{ "screen", "xterm", "vt100", "vt220", "rxvt" }) |prefix| if (std.mem.startsWith(u8, lower, prefix)) return true;
    inline for (.{ "color", "ansi", "cygwin", "linux" }) |part| if (std.mem.indexOf(u8, lower, part) != null) return true;
    return envHas(engine, env, "COLORTERM");
}
fn envHas(engine: *engine_mod.Engine, env: c.JSValue, name: [*:0]const u8) !bool {
    if (!c.JS_IsObject(env)) return false;
    const atom = c.JS_NewAtom(engine.context, name);
    defer c.JS_FreeAtom(engine.context, atom);
    const result = c.JS_HasProperty(engine.context, env, atom);
    if (result < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    return result != 0;
}
fn envText(engine: *engine_mod.Engine, gpa: std.mem.Allocator, env: c.JSValue, name: [*:0]const u8) ![]const u8 {
    if (!c.JS_IsObject(env)) return "";
    const value = try get(engine, env, name);
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value)) return "";
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return gpa.dupe(u8, text);
}
fn hasFlag(engine: *engine_mod.Engine, argv: c.JSValue, flag: []const u8) !bool {
    if (!c.JS_IsObject(argv)) return false;
    const length_value = try get(engine, argv, "length");
    defer engine.freeValue(length_value);
    var length: u32 = 0;
    if (c.JS_ToUint32(engine.context, &length, length_value) < 0) return error.JavaScriptException;
    if (length > 65536) return error.ThemeArgumentLimit;
    const expected = try std.fmt.allocPrint(engine.gpa, "--{s}", .{flag});
    defer engine.gpa.free(expected);
    for (0..length) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, argv, @intCast(index)));
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) continue;
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        if (std.mem.eql(u8, text, "--")) return false;
        if (std.mem.eql(u8, text, expected)) return true;
    }
    return false;
}
pub fn install(engine: *engine_mod.Engine, exports: c.JSValue) !void {
    var class_id: c.JSClassID = 0;
    var constructor_class: c.JSClassID = 0;
    var proxy_class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    _ = c.JS_NewClassID(engine.runtime, &constructor_class);
    _ = c.JS_NewClassID(engine.runtime, &proxy_class);
    const definition: c.JSClassDef = .{ .class_name = "Theme", .finalizer = finalizer, .gc_mark = mark };
    const constructor_definition: c.JSClassDef = .{ .class_name = "Theme Constructor", .finalizer = constructorFinalizer, .gc_mark = constructorMark, .call = constructorCall };
    const proxy_definition: c.JSClassDef = .{ .class_name = "Native Theme Proxy", .finalizer = proxyFinalizer, .gc_mark = proxyMark, .exotic = @constCast(&proxy_exotic) };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0 or c.JS_NewClass(engine.runtime, constructor_class, &constructor_definition) < 0 or c.JS_NewClass(engine.runtime, proxy_class, &proxy_definition) < 0) return error.OutOfMemory;
    const prototype = try object(engine);
    defer engine.freeValue(prototype);
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = if (field.value == @intFromEnum(Method.concreteColors)) "colors" else field.name;
        var data = [_]c.JSValue{ c.JS_NewInt64(engine.context, class_id), c.JS_NewInt64(engine.context, proxy_class) };
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, 1, @intCast(field.value), data.len, &data));
        if (field.value == @intFromEnum(Method.appearance) or field.value == @intFromEnum(Method.concreteColors)) {
            const atom = c.JS_NewAtom(engine.context, name.ptr);
            defer c.JS_FreeAtom(engine.context, atom);
            if (c.JS_DefinePropertyGetSet(engine.context, prototype, atom, callback, c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE) < 0) return error.JavaScriptException;
        } else try put(engine, prototype, name.ptr, callback);
    }
    const module = try object(engine);
    defer engine.freeValue(module);
    try put(engine, module, "chalkEnabled", c.JS_NewBool(engine.context, try supportsModifiers(engine, null)));
    try put(engine, module, "terminal", try object(engine));
    try put(engine, module, "pending", c.JS_NewBool(engine.context, false));
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const map_constructor = try get(engine, global, "Map");
    defer engine.freeValue(map_constructor);
    try put(engine, module, "registeredThemes", try engine.checked(c.JS_CallConstructor(engine.context, map_constructor, 0, null)));
    const symbol = try get(engine, global, "Symbol");
    defer engine.freeValue(symbol);
    try put(engine, module, "iteratorSymbol", try get(engine, symbol, "iterator"));
    const function = try get(engine, global, "Function");
    defer engine.freeValue(function);
    const function_prototype = try get(engine, function, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, constructor_class));
    defer engine.freeValue(constructor);
    const state = try engine.gpa.create(Constructor);
    state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .module = c.JS_DupValue(engine.context, module), .class_id = class_id };
    _ = c.JS_SetOpaque(constructor, state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_SetConstructor(engine.context, constructor, prototype) < 0) return error.JavaScriptException;
    try put(engine, constructor, "name", try jsString(engine, "Theme"));
    try put(engine, exports, "Theme", c.JS_DupValue(engine.context, constructor));
    const proxy = try engine.checked(c.JS_NewObjectClass(engine.context, @intCast(proxy_class)));
    defer engine.freeValue(proxy);
    const proxy_state = try engine.gpa.create(Proxy);
    proxy_state.* = .{ .engine = engine, .module = c.JS_DupValue(engine.context, module) };
    _ = c.JS_SetOpaque(proxy, proxy_state);
    try put(engine, exports, "theme", c.JS_DupValue(engine.context, proxy));
    inline for (std.meta.fields(ModuleMethod)) |field| {
        const name: [:0]const u8 = field.name;
        var data = [_]c.JSValue{module};
        const arity: c_int = if (field.value == @intFromEnum(ModuleMethod.getSelectListTheme) or field.value == @intFromEnum(ModuleMethod.getSettingsListTheme)) 0 else 1;
        try put(engine, exports, name.ptr, try engine.checked(c.JS_NewCFunctionData2(engine.context, moduleCall, name.ptr, arity, @intCast(field.value), 1, &data)));
    }
}
pub fn defaultMode(engine: *engine_mod.Engine) !ColorMode {
    if (engine.native_module_values.contains("pi-coding-agent")) {
        const module = try moduleState(engine);
        defer engine.freeValue(module);
        const bound = try get(engine, module, "boundMode");
        defer engine.freeValue(bound);
        if (c.JS_IsString(bound)) return color_api.mode(engine, bound);
    }
    return if (try @import("native_tui.zig").themeTrueColor(engine)) .truecolor else .@"256color";
}

fn revision(engine: *engine_mod.Engine, value: c.JSValue) !u64 {
    if (!c.JS_IsString(value)) return error.InvalidThemeStateRevision;
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    if (text.len == 0 or (text.len > 1 and text[0] == '0')) return error.InvalidThemeStateRevision;
    for (text) |byte| if (!std.ascii.isDigit(byte)) return error.InvalidThemeStateRevision;
    return std.fmt.parseInt(u64, text, 10) catch error.InvalidThemeStateRevision;
}

/// Apply only cached host state on the owning VM. Late renderer snapshots
/// cannot restore an older palette; equal revisions must have equal content.
pub fn hydrateState(engine: *engine_mod.Engine, state: c.JSValue) !void {
    if (c.JS_IsNull(state) or c.JS_IsUndefined(state)) return;
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const revision_value = try get(engine, state, "revision");
    defer engine.freeValue(revision_value);
    const incoming = try revision(engine, revision_value);
    const previous_revision = try get(engine, module, "stateRevision");
    defer engine.freeValue(previous_revision);
    const signature = try engine.stringify(state);
    defer engine.gpa.free(signature);
    if (!c.JS_IsUndefined(previous_revision)) {
        const previous = try revision(engine, previous_revision);
        if (incoming < previous) return;
        if (incoming == previous) {
            const previous_signature = try get(engine, module, "stateSignature");
            defer engine.freeValue(previous_signature);
            const text = try engine.toString(previous_signature);
            defer engine.gpa.free(text);
            if (!std.mem.eql(u8, text, signature)) return error.ConflictingThemeStateRevision;
            return;
        }
    }
    const mode_value = try get(engine, state, "colorMode");
    defer engine.freeValue(mode_value);
    const mode_text = try engine.toString(mode_value);
    defer engine.gpa.free(mode_text);
    const color_mode = std.meta.stringToEnum(ColorMode, mode_text) orelse return error.InvalidThemeStateMode;
    const tty = try get(engine, state, "stdoutIsTTY");
    defer engine.freeValue(tty);
    const pending = try get(engine, state, "terminalColorsPending");
    defer engine.freeValue(pending);
    const scheme = try get(engine, state, "terminalColorScheme");
    defer engine.freeValue(scheme);
    const terminal = try get(engine, state, "terminalColors");
    defer engine.freeValue(terminal);
    if (!c.JS_IsObject(terminal)) return error.InvalidThemeStateReports;
    const terminal_signature = try engine.stringify(terminal);
    defer engine.gpa.free(terminal_signature);
    const previous_terminal_signature = try get(engine, module, "terminalSignature");
    defer engine.freeValue(previous_terminal_signature);
    var same_reports = false;
    if (c.JS_IsString(previous_terminal_signature)) {
        const text = try engine.toString(previous_terminal_signature);
        defer engine.gpa.free(text);
        same_reports = std.mem.eql(u8, text, terminal_signature);
    }
    const resource = try get(engine, state, "resource");
    defer engine.freeValue(resource);
    const resource_identity = try get(engine, state, "resourceIdentity");
    defer engine.freeValue(resource_identity);
    // Retain the preceding report state until a complete candidate is ready.
    const names = .{ "terminal", "pending", "scheme", "boundMode", "chalkEnabled" };
    var old: [names.len]c.JSValue = undefined;
    var count: usize = 0;
    defer for (old[0..count]) |value| engine.freeValue(value);
    inline for (names, 0..) |name, index| {
        old[index] = try get(engine, module, name);
        count += 1;
    }
    var committed = false;
    defer if (!committed) {
        inline for (names, 0..) |name, index| put(engine, module, name, c.JS_DupValue(engine.context, old[index])) catch {};
    };
    if (!same_reports) try put(engine, module, "terminal", try snapshot(engine, terminal));
    try put(engine, module, "pending", c.JS_DupValue(engine.context, pending));
    try put(engine, module, "scheme", if (c.JS_IsNull(scheme)) c.pi_js_undefined() else c.JS_DupValue(engine.context, scheme));
    try put(engine, module, "boundMode", c.JS_DupValue(engine.context, mode_value));
    try put(engine, module, "chalkEnabled", c.JS_NewBool(engine.context, try supportsModifiers(engine, c.JS_ToBool(engine.context, tty) != 0)));
    const resource_signature = if (c.JS_IsNull(resource)) null else try engine.stringify(resource);
    defer if (resource_signature) |raw| engine.gpa.free(raw);
    var reuse = false;
    if (resource_signature) |raw| {
        const prior_signature = try get(engine, module, "selectedResourceSignature");
        defer engine.freeValue(prior_signature);
        const prior_identity = try get(engine, module, "resourceIdentity");
        defer engine.freeValue(prior_identity);
        if (c.JS_IsString(prior_signature) and c.JS_IsStrictEqual(engine.context, prior_identity, resource_identity) and c.JS_IsStrictEqual(engine.context, old[3], mode_value)) {
            const prior = try engine.toString(prior_signature);
            defer engine.gpa.free(prior);
            reuse = std.mem.eql(u8, prior, raw);
        }
    }
    const candidate = if (reuse) try get(engine, module, "current") else if (resource_signature) |raw| try fromJson(engine, raw, null, color_mode) else try createSystem(engine, color_mode);
    var transferred = false;
    defer if (!transferred) engine.freeValue(candidate);
    const signature_value = try jsString(engine, signature);
    defer engine.freeValue(signature_value);
    const reports_value = try jsString(engine, terminal_signature);
    defer engine.freeValue(reports_value);
    transferred = true;
    try put(engine, module, "current", candidate);
    try put(engine, module, "resourceIdentity", c.JS_DupValue(engine.context, resource_identity));
    try put(engine, module, "terminalSignature", c.JS_DupValue(engine.context, reports_value));
    try put(engine, module, "stateSignature", c.JS_DupValue(engine.context, signature_value));
    try put(engine, module, "stateRevision", c.JS_DupValue(engine.context, revision_value));
    try put(engine, module, "selectedResourceSignature", if (resource_signature) |raw| try jsString(engine, raw) else c.pi_js_undefined());
    try put(engine, module, "resourceSignature", c.pi_js_undefined());
    committed = true;
}
fn moduleState(engine: *engine_mod.Engine) !c.JSValue {
    const exports = engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeModuleUnavailable;
    const constructor = try get(engine, exports, "Theme");
    defer engine.freeValue(constructor);
    const state: *Constructor = @ptrCast(@alignCast(c.JS_GetOpaque(constructor, c.JS_GetClassID(constructor)) orelse return error.NativeThemeConstructorUnavailable));
    return c.JS_DupValue(engine.context, state.module);
}
pub fn createSystem(engine: *engine_mod.Engine, color_mode: ?ColorMode) !c.JSValue {
    const system = @import("../themes/system_theme.zig");
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const terminal = try get(engine, module, "terminal");
    defer engine.freeValue(terminal);
    var input: system.Input = .{};
    inline for (.{ .{ "foreground", "foreground" }, .{ "background", "background" } }) |pair| {
        const value = try get(engine, terminal, pair[0]);
        defer engine.freeValue(value);
        if (c.JS_ToBool(engine.context, value) != 0) @field(input, pair[1]) = (try terminalColor(engine, terminal, pair[0], .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } })).rgb;
    }
    const pending = try get(engine, module, "pending");
    defer engine.freeValue(pending);
    input.saturation = if (c.JS_ToBool(engine.context, pending) != 0) 0 else 1;
    const hint = try terminalAppearance(engine, module);
    defer engine.freeValue(hint);
    const hint_text = try engine.toString(hint);
    defer engine.gpa.free(hint_text);
    input.appearance_hint = std.meta.stringToEnum(system.Appearance, hint_text);
    var palette: [16]colors.Rgb = undefined;
    const palette_value = try get(engine, terminal, "palette");
    defer engine.freeValue(palette_value);
    if (!c.JS_IsUndefined(palette_value) and !c.JS_IsNull(palette_value)) {
        const length_value = try get(engine, palette_value, "length");
        defer engine.freeValue(length_value);
        if ((try color_api.number(engine, length_value)) == 16) {
            for (&palette, 0..) |*rgb, index| {
                const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, palette_value, @intCast(index)));
                defer engine.freeValue(value);
                const wrapper = try object(engine);
                defer engine.freeValue(wrapper);
                try put(engine, wrapper, "rgb", c.JS_DupValue(engine.context, value));
                rgb.* = (try terminalColor(engine, wrapper, "rgb", .{ .rgb = .{ .r = 0, .g = 0, .b = 0 } })).rgb;
            }
            input.palette = &palette;
        }
    }
    const generated = system.generate(input);
    const fg = try object(engine);
    defer engine.freeValue(fg);
    const bg = try object(engine);
    defer engine.freeValue(bg);
    const dim = try engine.checked(c.JS_NewArray(engine.context));
    defer engine.freeValue(dim);
    var dim_count: u32 = 0;
    for (system.recipe.tokens, 0..) |token, index| {
        const name = try engine.gpa.dupeZ(u8, token.name);
        defer engine.gpa.free(name);
        const value = switch (generated.values[index]) {
            .default => try jsString(engine, ""),
            .indexed => |slot| c.JS_NewInt32(engine.context, slot),
            .rgb => |rgb| blk: {
                const text = try colors.colorToHex(engine.gpa, .{ .rgb = rgb });
                defer engine.gpa.free(text);
                break :blk try jsString(engine, text);
            },
        };
        try put(engine, if (token.panel) bg else fg, name.ptr, value);
        if (generated.dim[index]) {
            if (c.JS_SetPropertyUint32(engine.context, dim, dim_count, try jsString(engine, token.name)) < 0) return error.JavaScriptException;
            dim_count += 1;
        }
    }
    const options = try object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "name", try jsString(engine, "system"));
    try put(engine, options, "dim", c.JS_DupValue(engine.context, dim));
    if (generated.appearance) |designed| try put(engine, options, "appearance", try jsString(engine, @tagName(designed)));
    const exports = engine.native_module_values.get("pi-coding-agent").?;
    const constructor = try get(engine, exports, "Theme");
    defer engine.freeValue(constructor);
    const mode_value = try jsString(engine, @tagName(color_mode orelse try defaultMode(engine)));
    defer engine.freeValue(mode_value);
    var args = [_]c.JSValue{ fg, bg, mode_value, options };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, args.len, &args));
}
pub fn loadByName(engine: *engine_mod.Engine, name: []const u8, color_mode: ?ColorMode) !c.JSValue {
    if (std.mem.eql(u8, name, "system")) return createSystem(engine, color_mode);
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const registered = try get(engine, module, "registeredThemes");
    defer engine.freeValue(registered);
    const key = try jsString(engine, name);
    defer engine.freeValue(key);
    var args = [_]c.JSValue{key};
    const existing = try invoke(engine, registered, "get", &args);
    if (!c.JS_IsUndefined(existing)) return existing;
    engine.freeValue(existing);
    if (std.mem.eql(u8, name, "dark")) return fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), null, color_mode);
    if (std.mem.eql(u8, name, "light")) return fromJson(engine, @embedFile("../themes/fixtures/light-original-7fb.json"), null, color_mode);
    const message = try std.fmt.allocPrint(engine.gpa, "Theme not found: {s}", .{name});
    defer engine.gpa.free(message);
    return color_api.throwError(engine, message);
}
fn registerTheme(engine: *engine_mod.Engine, registry: c.JSValue, theme: c.JSValue) !void {
    // Source reads this getter independently for truthiness, validation and key.
    const present = try get(engine, theme, "name");
    defer engine.freeValue(present);
    if (c.JS_ToBool(engine.context, present) == 0) return;
    const validated = try get(engine, theme, "name");
    defer engine.freeValue(validated);
    const slash = try jsString(engine, "/");
    defer engine.freeValue(slash);
    var includes_args = [_]c.JSValue{slash};
    const includes = try invoke(engine, validated, "includes", &includes_args);
    defer engine.freeValue(includes);
    if (c.JS_ToBool(engine.context, includes) != 0) {
        const text = try engine.toString(validated);
        defer engine.gpa.free(text);
        const message = try std.fmt.allocPrint(engine.gpa, "Invalid theme name \"{s}\": theme names cannot contain \"/\" because it is reserved for automatic light/dark theme settings.", .{text});
        defer engine.gpa.free(message);
        return color_api.throwError(engine, message);
    }
    const key = try get(engine, theme, "name");
    defer engine.freeValue(key);
    var set_args = [_]c.JSValue{ key, theme };
    const result = try invoke(engine, registry, "set", &set_args);
    engine.freeValue(result);
}
fn closeRegistrationIterator(engine: *engine_mod.Engine, iterator: c.JSValue) void {
    // IteratorClose preserves an already thrown body completion even if return
    // itself throws. Keep its exact object rooted across that user callback.
    const original = if (engine.captured_exception) |value| c.JS_DupValue(engine.context, value) else null;
    defer if (original) |value| engine.freeValue(value);
    if (get(engine, iterator, "return")) |function| {
        defer engine.freeValue(function);
        if (!c.JS_IsUndefined(function) and !c.JS_IsNull(function)) {
            if (engine.checked(c.JS_Call(engine.context, function, iterator, 0, null))) |value| engine.freeValue(value) else |_| {}
        }
    } else |_| {}
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = if (original) |value| c.JS_DupValue(engine.context, value) else null;
}
/// Source module-global registry admission. Clear first, then retain each exact
/// instance in iteration order. A later failure leaves its successful prefix.
pub fn setRegisteredThemes(engine: *engine_mod.Engine, themes: c.JSValue) !void {
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const registry = try get(engine, module, "registeredThemes");
    defer engine.freeValue(registry);
    const cleared = try invoke(engine, registry, "clear", &.{});
    engine.freeValue(cleared);
    const symbol = try get(engine, module, "iteratorSymbol");
    defer engine.freeValue(symbol);
    const atom = c.JS_ValueToAtom(engine.context, symbol);
    defer c.JS_FreeAtom(engine.context, atom);
    if (atom == c.JS_ATOM_NULL) return error.OutOfMemory;
    const method = try engine.checked(c.JS_GetProperty(engine.context, themes, atom));
    defer engine.freeValue(method);
    const iterator = try engine.checked(c.JS_Call(engine.context, method, themes, 0, null));
    defer engine.freeValue(iterator);
    const next = try get(engine, iterator, "next");
    defer engine.freeValue(next);
    while (true) {
        const entry = try engine.checked(c.JS_Call(engine.context, next, iterator, 0, null));
        defer engine.freeValue(entry);
        if (!c.JS_IsObject(entry)) {
            _ = try engine.checked(c.JS_ThrowTypeError(engine.context, "Iterator result is not an object"));
            return error.JavaScriptException;
        }
        const done = try get(engine, entry, "done");
        defer engine.freeValue(done);
        if (c.JS_ToBool(engine.context, done) != 0) return;
        const theme = try get(engine, entry, "value");
        defer engine.freeValue(theme);
        registerTheme(engine, registry, theme) catch |err| {
            closeRegistrationIterator(engine, iterator);
            return err;
        };
    }
}
/// Registered instances retain identity; system remains reserved. As Source,
/// lookup failures produce undefined rather than a rejected UI operation.
pub fn getThemeByName(engine: *engine_mod.Engine, name: []const u8) !c.JSValue {
    return loadByName(engine, name, null) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (engine.captured_exception) |value| engine.freeValue(value);
        engine.captured_exception = null;
        return c.pi_js_undefined();
    };
}
pub fn current(engine: *engine_mod.Engine) !c.JSValue {
    if (!engine.native_module_names.contains("pi-coding-agent")) try @import("native_tui.zig").install(engine);
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const selected = try get(engine, module, "current");
    defer engine.freeValue(selected);
    if (c.JS_IsUndefined(selected)) try put(engine, module, "current", try createSystem(engine, null));
    return get(engine, engine.native_module_values.get("pi-coding-agent").?, "theme");
}
pub fn hydrate(engine: *engine_mod.Engine, resource: c.JSValue) !void {
    const encoded = try engine.stringify(resource);
    defer engine.gpa.free(encoded);
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const previous = try get(engine, module, "resourceSignature");
    defer engine.freeValue(previous);
    if (c.JS_IsString(previous)) {
        const signature = try engine.toString(previous);
        defer engine.gpa.free(signature);
        if (std.mem.eql(u8, signature, encoded)) return;
    }
    const selected = try fromJson(engine, encoded, null, null);
    var transferred = false;
    defer if (!transferred) engine.freeValue(selected);
    const signature = try jsString(engine, encoded);
    defer engine.freeValue(signature);
    transferred = true;
    try put(engine, module, "current", selected);
    try put(engine, module, "resourceSignature", c.JS_DupValue(engine.context, signature));
}
fn resolve(engine: *engine_mod.Engine, value: c.JSValue, vars: c.JSValue, visited: *std.StringHashMapUnmanaged(void)) !c.JSValue {
    if (c.JS_IsNumber(value)) return c.JS_DupValue(engine.context, value);
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    if (text.len == 0 or text[0] == '#' or (text.len >= 6 and (std.ascii.eqlIgnoreCase(text[0..6], "oklch(") or std.ascii.eqlIgnoreCase(text[0..6], "okhsl(")))) return c.JS_DupValue(engine.context, value);
    if (visited.contains(text)) {
        const message = try std.fmt.allocPrint(engine.gpa, "Circular variable reference detected: {s}", .{text});
        defer engine.gpa.free(message);
        return color_api.throwError(engine, message);
    }
    if (visited.count() >= 4096) return error.ThemeVariableLimit;
    const name = try engine.gpa.dupeZ(u8, text);
    defer engine.gpa.free(name);
    const atom = c.JS_NewAtom(engine.context, name.ptr);
    defer c.JS_FreeAtom(engine.context, atom);
    const exists = c.JS_HasProperty(engine.context, vars, atom);
    if (exists < 0) {
        _ = try engine.checked(c.JS_Throw(engine.context, c.JS_GetException(engine.context)));
        return error.JavaScriptException;
    }
    if (exists == 0) {
        const message = try std.fmt.allocPrint(engine.gpa, "Variable reference not found: {s}", .{text});
        defer engine.gpa.free(message);
        return color_api.throwError(engine, message);
    }
    {
        const owned = try engine.gpa.dupe(u8, text);
        errdefer engine.gpa.free(owned);
        try visited.put(engine.gpa, owned, {});
    }
    const selected = try get(engine, vars, name.ptr);
    defer engine.freeValue(selected);
    return resolve(engine, selected, vars, visited);
}
pub fn fromJson(engine: *engine_mod.Engine, raw_json: []const u8, source_path: ?[]const u8, color_mode: ?ColorMode) !c.JSValue {
    const input = if (std.mem.startsWith(u8, raw_json, "\xef\xbb\xbf")) raw_json[3..] else raw_json;
    const input_z = try engine.gpa.dupeZ(u8, input);
    defer engine.gpa.free(input_z);
    const label = source_path orelse "theme.json";
    const json = engine.checked(c.JS_ParseJSON(engine.context, input_z.ptr, input_z.len, "theme.json")) catch |err| {
        if (err != error.JavaScriptException) return err;
        const detail = try engine.toString(engine.captured_exception orelse return err);
        defer engine.gpa.free(detail);
        const message = try std.fmt.allocPrint(engine.gpa, "Failed to parse theme {s}: {s}", .{ label, detail });
        defer engine.gpa.free(message);
        return color_api.throwError(engine, message);
    };
    defer engine.freeValue(json);
    const colors_atom = c.JS_NewAtom(engine.context, "colors");
    defer c.JS_FreeAtom(engine.context, colors_atom);
    if (!c.JS_IsObject(json) or c.JS_HasProperty(engine.context, json, colors_atom) <= 0) {
        const message = try std.fmt.allocPrint(engine.gpa, "Invalid theme \"{s}\": expected an object with a \"colors\" map.", .{label});
        defer engine.gpa.free(message);
        return color_api.throwError(engine, message);
    }
    const values = try get(engine, json, "colors");
    defer engine.freeValue(values);
    const with_fallbacks = try snapshot(engine, values);
    defer engine.freeValue(with_fallbacks);
    inline for (.{ .{ "scrollbarTrack", "muted" }, .{ "scrollbarThumb", "text" }, .{ "thinkingMax", "thinkingXhigh" }, .{ "searchMatchBg", "selectedBg" }, .{ "searchMatchText", "text" } }) |pair| try fallbackFrom(engine, with_fallbacks, values, pair[0], pair[1]);
    const vars_value = try get(engine, json, "vars");
    defer engine.freeValue(vars_value);
    const vars = if (c.JS_IsUndefined(vars_value)) try object(engine) else c.JS_DupValue(engine.context, vars_value);
    defer engine.freeValue(vars);
    const fg = try object(engine);
    defer engine.freeValue(fg);
    const bg = try object(engine);
    defer engine.freeValue(bg);
    const names = try OwnNames.init(engine, with_fallbacks);
    defer names.deinit();
    for (names.values[0..names.length]) |entry| {
        const token = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
        defer engine.freeValue(token);
        const name = try engine.toString(token);
        defer engine.gpa.free(name);
        var background = false;
        inline for (.{ "selectedBg", "searchMatchBg", "userMessageBg", "customMessageBg", "toolPendingBg", "toolSuccessBg", "toolErrorBg" }) |bg_name| if (std.mem.eql(u8, name, bg_name)) {
            background = true;
        };
        const value = try engine.checked(c.JS_GetProperty(engine.context, with_fallbacks, entry.atom));
        defer engine.freeValue(value);
        var visited: std.StringHashMapUnmanaged(void) = .empty;
        defer {
            var it = visited.keyIterator();
            while (it.next()) |key| engine.gpa.free(key.*);
            visited.deinit(engine.gpa);
        }
        const resolved = try resolve(engine, value, vars, &visited);
        if (c.JS_DefinePropertyValue(engine.context, if (background) bg else fg, entry.atom, resolved, c.JS_PROP_C_W_E) < 0) return error.JavaScriptException;
    }
    const options = try object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "name", try get(engine, json, "name"));
    try put(engine, options, "appearance", try get(engine, json, "appearance"));
    if (source_path) |path| try put(engine, options, "sourcePath", try jsString(engine, path));
    const exports = engine.native_module_values.get("pi-coding-agent") orelse return error.NativeThemeModuleUnavailable;
    const constructor = try get(engine, exports, "Theme");
    defer engine.freeValue(constructor);
    const selected_mode = color_mode orelse try defaultMode(engine);
    const mode_value = try jsString(engine, @tagName(selected_mode));
    defer engine.freeValue(mode_value);
    var args = [_]c.JSValue{ fg, bg, mode_value, options };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 4, &args));
}
pub fn loadFile(engine: *engine_mod.Engine, io: std.Io, path: []const u8, color_mode: ?ColorMode) !c.JSValue {
    const content = try std.Io.Dir.cwd().readFileAlloc(io, path, engine.gpa, .limited(4 * 1024 * 1024));
    defer engine.gpa.free(content);
    return fromJson(engine, content, path, color_mode);
}

test "actual original Theme constructor defaults dim cache terminal replacement and styles replay on native VM" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/theme-constructor-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "themeOracle", try engine.fromJsonValue(fixture.value));
    const module = try engine.evalModule(
        \\import {Theme,setTerminalColors} from 'pi-coding-agent';
        \\function compare(expected,actual,path='root'){if(typeof expected==='number'&&typeof actual==='number'){if(Math.abs(expected-actual)>1e-10)throw Error(path+': '+expected+' != '+actual);return}if(expected&&typeof expected==='object'){if(!actual||Object.keys(expected).sort().join('|')!==Object.keys(actual).sort().join('|'))throw Error(path+' keys');for(const key of Object.keys(expected))compare(expected[key],actual[key],path+'.'+key);return}if(expected!==actual)throw Error(path+': '+expected+' != '+actual)}
        \\for(const item of themeOracle.cases){setTerminalColors({});const input=item.input,theme=new Theme(input.fg,input.bg,input.mode,input.options);const observe=()=>({appearance:theme.appearance,fg:Object.fromEntries(Object.keys(item.before.fg).map(key=>[key,theme.getFgAnsi(key)])),bg:Object.fromEntries(Object.keys(item.before.bg).map(key=>[key,theme.getBgAnsi(key)])),colors:theme.colors,colorsFrozen:Object.isFrozen(theme.colors),valuesFrozen:Object.values(theme.colors).every(Object.isFrozen),sameColors:theme.colors===theme.colors,fgText:theme.fg('accent','x\ny'),bgText:theme.bg('selectedBg','x'),style:theme.style('x\ny',{fg:'accent',bg:'selectedBg',bold:true}),thinking:['off','minimal','low','medium','high','xhigh','max','invalid'].map(level=>theme.getThinkingBorderColor(level)('x')),bash:theme.getBashModeBorderColor()('x')});compare(item.before,observe(),item.name+'/'+item.variant+'/'+input.mode+'/before');const old=theme.colors;setTerminalColors({foreground:{r:20,g:30,b:40},background:{r:180,g:170,b:160}});compare(item.after,observe(),'after');compare(item.oldColors,old,'retained-old');if((old!==theme.colors)!==item.changedColors)throw Error('cache identity');globalThis.retainedTheme=theme;}
        \\const marker={};let threw=false;try{new Theme({}, {},'truecolor',{get name(){throw marker}})}catch(error){threw=error===marker}if(!threw)throw Error('constructor exception identity');
        \\const theme=retainedTheme;for(const invoke of [()=>theme.fg('missing','x'),()=>theme.bg('accent','x'),()=>theme.getFgAnsi('selectedBg')]){let message;try{invoke()}catch(error){message=error.message}if(!message?.startsWith('Unknown theme color: '))throw Error('token partition '+message)}
    , "native-theme-constructor-original.mjs");
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const retained = try engine.eval("if(retainedTheme.getThinkingBorderColor('max')('x').length===0)throw Error('retained');delete globalThis.retainedTheme;delete globalThis.themeOracle;", "native-theme-retained.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}

test "native Theme JSON resolves actual OKHSL builtins and preserves variable cycle missing and parse failures" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    engine.native_io = std.testing.io;
    try @import("native_tui.zig").install(engine);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    inline for (.{ .{ "darkLoaded", @embedFile("../themes/fixtures/dark-original-7fb.json") }, .{ "lightLoaded", @embedFile("../themes/fixtures/light-original-7fb.json") } }) |item| try put(engine, global, item[0], try fromJson(engine, item[1], "source-theme.json", .truecolor));
    const module = try engine.evalModule(
        \\import {Theme} from 'pi-coding-agent';
        \\import {parseColor,foregroundAnsi} from 'pi-tui';
        \\if(!(darkLoaded instanceof Theme)||!(lightLoaded instanceof Theme)||darkLoaded.sourcePath!=='source-theme.json'||darkLoaded.name!=='dark'||darkLoaded.appearance!=='dark'||lightLoaded.appearance!=='light')throw Error('loader metadata');
        \\if(darkLoaded.getFgAnsi('accent')!==foregroundAnsi(parseColor('okhsl(295 50% 67%)'),'truecolor'))throw Error('builtin variable resolution');
        \\if(Object.keys(darkLoaded.colors).length!==56||!Object.isFrozen(darkLoaded.colors))throw Error('56 real builtin tokens');delete globalThis.darkLoaded;delete globalThis.lightLoaded;
    , "native-theme-json-builtins.mjs");
    defer engine.freeValue(module);
    const invalid = [_]struct { json: []const u8, message: []const u8 }{
        .{ .json = "{}", .message = "Invalid theme \"fixture.json\": expected an object with a \"colors\" map." },
        .{ .json = "null", .message = "Invalid theme \"fixture.json\": expected an object with a \"colors\" map." },
        .{ .json = "{\"vars\":{\"one\":\"two\",\"two\":\"one\"},\"colors\":{\"accent\":\"one\"}}", .message = "Circular variable reference detected: one" },
        .{ .json = "{\"colors\":{\"accent\":\"missing\"}}", .message = "Variable reference not found: missing" },
    };
    for (invalid) |item| {
        try std.testing.expectError(error.JavaScriptException, fromJson(engine, item.json, "fixture.json", .truecolor));
        const message = try get(engine, engine.captured_exception.?, "message");
        defer engine.freeValue(message);
        const text = try engine.toString(message);
        defer engine.gpa.free(text);
        try std.testing.expectEqualStrings(item.message, text);
    }
    const loaded = try loadFile(engine, std.testing.io, "src/themes/fixtures/dark-original-7fb.json", .@"256color");
    defer engine.freeValue(loaded);
    c.JS_RunGC(engine.runtime);
}

fn allocationError(engine: *engine_mod.Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        defer engine.freeValue(message);
        if (!c.JS_IsException(message)) {
            const text = c.JS_ToCString(engine.context, message);
            if (text != null) {
                defer c.JS_FreeCString(engine.context, text);
                if (std.mem.indexOf(u8, std.mem.span(text), "out of memory") != null) return error.OutOfMemory;
            }
        }
    };
    return err;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const theme = fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), "allocation.json", .truecolor) catch |err| return allocationError(engine, err);
    defer engine.freeValue(theme);
    const resolved = get(engine, theme, "colors") catch |err| return allocationError(engine, err);
    defer engine.freeValue(resolved);
    c.JS_RunGC(engine.runtime);
}
test "native Theme allocation failures release maps colors constructor state and failed variable resolution" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

test "actual Chalk 6 source nested modifier CRLF and color support enablement replay through Theme" {
    const fixture = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, @embedFile("fixtures/theme-constructor-original-7fb.json"), .{});
    defer fixture.deinit();
    for (fixture.value.object.get("chalk").?.array.items) |item| {
        const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        const global = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(global);
        try put(engine, global, "chalkCase", try engine.fromJsonValue(item));
        const setup = try engine.eval("const input=chalkCase.input;globalThis.process={env:input.env,platform:input.platform??'linux',stdout:{isTTY:input.tty},argv:['node','fixture',...(input.argv??[])]};", "source-chalk-process.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(setup);
        try @import("native_tui.zig").install(engine);
        try put(engine, global, "sourceTheme", try fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), "chalk-theme.json", .truecolor));
        const checked = try engine.eval("const texts=['','plain','a\\nb','a\\r\\nb','a\\x1b[22mb\\x1b[23mc\\x1b[24md\\x1b[27me\\x1b[29mf'];for(const method of Object.keys(chalkCase.outputs))for(let i=0;i<texts.length;i++){const actual=sourceTheme[method](texts[i]),expected=chalkCase.outputs[method][i];if(actual!==expected)throw Error(method+' case '+JSON.stringify(chalkCase.input)+' '+JSON.stringify(actual)+' != '+JSON.stringify(expected))}delete globalThis.sourceTheme;", "native-theme-chalk-original.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(checked);
        c.JS_RunGC(engine.runtime);
    }
}

test "native system Theme VM routes all original palette tokens pending reports modes and stable live proxy" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("../themes/fixtures/system-theme-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    const setup = try engine.evalModule(
        \\import {setTerminalColors,setTerminalColorScheme,markTerminalColorsPending,initTheme,theme} from 'pi-coding-agent';
        \\globalThis.prepareSystem=input=>{setTerminalColors(input);setTerminalColorScheme(input.appearanceHint);if(input.saturation===0)markTerminalColorsPending()};
        \\globalThis.checkSystem=(item,mode)=>{const bg=new Set(['selectedBg','searchMatchBg','userMessageBg','customMessageBg','toolPendingBg','toolSuccessBg','toolErrorBg']);for(const [name,expected]of Object.entries(item.ansi[mode])){const actual=bg.has(name)?systemTheme.getBgAnsi(name):systemTheme.getFgAnsi(name);if(actual!==expected)throw Error(name+' '+JSON.stringify(item.input)+' '+JSON.stringify(actual)+' != '+JSON.stringify(expected))}if(systemTheme.name!=='system'||!Object.isFrozen(systemTheme.colors))throw Error('system metadata');};
        \\globalThis.checkLiveProxy=()=>{initTheme('dark');const retained=theme;const first=theme.getFgAnsi('accent');const border=theme.getThinkingBorderColor('max');initTheme('light');if(retained!==theme||theme.name!=='light'||first===retained.getFgAnsi('accent')||border('x')!==theme.fg('thinkingMax','x'))throw Error('live proxy');let failed=false;const detached=theme.fg;try{detached('accent','x')}catch(error){failed=error instanceof TypeError}if(!failed)throw Error('detached proxy method');initTheme('missing');if(retained.name!=='system')throw Error('fallback');};
    , "native-system-oracle-helpers.mjs");
    defer engine.freeValue(setup);
    for (fixture.value.object.get("cases").?.array.items) |item| {
        const saturation = item.object.get("input").?.object.get("saturation").?;
        const amount: f64 = if (saturation == .integer) @floatFromInt(saturation.integer) else saturation.float;
        if (amount != 0 and amount != 1) continue; // Public terminal reports expose pending/full saturation.
        try put(engine, global, "systemCase", try engine.fromJsonValue(item));
        const prepared = try engine.eval("prepareSystem(systemCase.input)", "native-system-prepare.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(prepared);
        inline for (.{ ColorMode.truecolor, ColorMode.@"256color" }) |color_mode| {
            try put(engine, global, "systemTheme", try createSystem(engine, color_mode));
            const source = "checkSystem(systemCase,'" ++ @tagName(color_mode) ++ "')";
            const checked = try engine.eval(source, "native-system-check.js", c.JS_EVAL_TYPE_GLOBAL);
            defer engine.freeValue(checked);
        }
        c.JS_RunGC(engine.runtime);
    }
    const checked = try engine.eval("checkLiveProxy();delete globalThis.systemCase;delete globalThis.systemTheme;", "native-system-proxy.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(checked);
    c.JS_RunGC(engine.runtime);
}

test "native retained theme proxy preserves cache across unchanged snapshots and swaps only after complete hydration" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const proxy = try current(engine);
    defer engine.freeValue(proxy);
    const dark = try engine.checked(c.JS_ParseJSON(engine.context, @embedFile("../themes/fixtures/dark-original-7fb.json"), @embedFile("../themes/fixtures/dark-original-7fb.json").len, "dark.json"));
    defer engine.freeValue(dark);
    try hydrate(engine, dark);
    const initial = try get(engine, proxy, "colors");
    defer engine.freeValue(initial);
    try hydrate(engine, dark);
    const unchanged = try get(engine, proxy, "colors");
    defer engine.freeValue(unchanged);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, initial, unchanged));
    const invalid = try engine.checked(c.JS_ParseJSON(engine.context, "{\"colors\":{\"accent\":\"missing\"}}", 31, "invalid.json"));
    defer engine.freeValue(invalid);
    try std.testing.expectError(error.JavaScriptException, hydrate(engine, invalid));
    const after_failure = try get(engine, proxy, "colors");
    defer engine.freeValue(after_failure);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, initial, after_failure));
    const light = try engine.checked(c.JS_ParseJSON(engine.context, @embedFile("../themes/fixtures/light-original-7fb.json"), @embedFile("../themes/fixtures/light-original-7fb.json").len, "light.json"));
    defer engine.freeValue(light);
    try hydrate(engine, light);
    const changed = try get(engine, proxy, "colors");
    defer engine.freeValue(changed);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, initial, changed));
    c.JS_RunGC(engine.runtime);
    const retained = try get(engine, initial, "accent");
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_IsObject(retained));
}

fn stateValue(engine: *engine_mod.Engine, state: @import("theme_state.zig").State) !c.JSValue {
    const encoded = try @import("theme_state.zig").encode(engine.gpa, state);
    defer engine.gpa.free(encoded);
    const text = try engine.gpa.dupeZ(u8, encoded);
    defer engine.gpa.free(text);
    return engine.checked(c.JS_ParseJSON(engine.context, text.ptr, text.len, "theme-state.json"));
}
test "actual owner cached theme reports fence replay preserve custom instances and rollback failed hydration through GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const proxy = try current(engine);
    defer engine.freeValue(proxy);
    const old_instance = try fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), null, .truecolor);
    defer engine.freeValue(old_instance);
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "retainedTheme", c.JS_DupValue(engine.context, proxy));
    try put(engine, global, "oldThemeInstance", c.JS_DupValue(engine.context, old_instance));
    const pending_state = try stateValue(engine, .{ .revision = 1, .color_mode = .@"256color", .stdout_is_tty = false, .terminal_colors_pending = true });
    defer engine.freeValue(pending_state);
    try hydrateState(engine, pending_state);
    const initial_colors = try get(engine, proxy, "colors");
    defer engine.freeValue(initial_colors);
    try hydrateState(engine, pending_state);
    const same_colors = try get(engine, proxy, "colors");
    defer engine.freeValue(same_colors);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, initial_colors, same_colors));
    const first = try engine.eval("if(retainedTheme.name!=='system'||retainedTheme.getFgAnsi('accent')!=='\\x1b[39m'||retainedTheme.bold('x')!=='x')throw Error('pending source defaults')", "native-theme-state-pending.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(first);
    const report = try stateValue(engine, .{ .revision = 2, .color_mode = .truecolor, .stdout_is_tty = true, .terminal_colors = .{ .background = .{ .r = 0, .g = 0, .b = 0 }, .foreground = .{ .r = 240, .g = 240, .b = 240 } } });
    defer engine.freeValue(report);
    try hydrateState(engine, report);
    const report_colors = try get(engine, proxy, "colors");
    defer engine.freeValue(report_colors);
    const second = try engine.eval("if(retainedTheme.getColorMode()!=='truecolor'||retainedTheme.getFgAnsi('accent')==='\\x1b[39m'||oldThemeInstance.bold('x')!=='\\x1b[1mx\\x1b[22m')throw Error('report mode/shared modifier capability')", "native-theme-state-report.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(second);
    try hydrateState(engine, pending_state);
    const after_stale = try get(engine, proxy, "colors");
    defer engine.freeValue(after_stale);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, report_colors, after_stale));
    const conflict = try stateValue(engine, .{ .revision = 2, .color_mode = .@"256color", .stdout_is_tty = false });
    defer engine.freeValue(conflict);
    try std.testing.expectError(error.ConflictingThemeStateRevision, hydrateState(engine, conflict));
    const bad = try stateValue(engine, .{ .revision = 3, .color_mode = .@"256color", .stdout_is_tty = false, .resource_json = "{\"colors\":{\"accent\":\"missing\"}}", .terminal_colors = .{ .background = .{ .r = 255, .g = 255, .b = 255 } } });
    defer engine.freeValue(bad);
    try std.testing.expectError(error.JavaScriptException, hydrateState(engine, bad));
    const after_failure = try get(engine, proxy, "colors");
    defer engine.freeValue(after_failure);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, report_colors, after_failure));
    const custom = try stateValue(engine, .{ .revision = 4, .color_mode = .truecolor, .stdout_is_tty = true, .resource_json = @embedFile("../themes/fixtures/dark-original-7fb.json"), .resource_identity = "loader-1/theme-1" });
    defer engine.freeValue(custom);
    try hydrateState(engine, custom);
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    const selected = try get(engine, module, "current");
    defer engine.freeValue(selected);
    const marker = try object(engine);
    defer engine.freeValue(marker);
    try put(engine, selected, "sourceInfo", c.JS_DupValue(engine.context, marker));
    const custom_report = try stateValue(engine, .{ .revision = 5, .color_mode = .truecolor, .stdout_is_tty = true, .resource_json = @embedFile("../themes/fixtures/dark-original-7fb.json"), .resource_identity = "loader-1/theme-1", .terminal_colors = .{ .background = .{ .r = 180, .g = 170, .b = 160 } } });
    defer engine.freeValue(custom_report);
    try hydrateState(engine, custom_report);
    const preserved = try get(engine, module, "current");
    defer engine.freeValue(preserved);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, selected, preserved));
    const info = try get(engine, preserved, "sourceInfo");
    defer engine.freeValue(info);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, info, marker));
    c.JS_RunGC(engine.runtime);
    const retained = try get(engine, report_colors, "accent");
    defer engine.freeValue(retained);
    try std.testing.expect(c.JS_IsObject(retained));
}

fn stateAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const proxy = current(engine) catch |err| return allocationError(engine, err);
    defer engine.freeValue(proxy);
    const first = try stateValue(engine, .{ .revision = 1, .color_mode = .truecolor, .stdout_is_tty = true, .resource_json = @embedFile("../themes/fixtures/dark-original-7fb.json"), .resource_identity = "loader-1/theme-1" });
    defer engine.freeValue(first);
    hydrateState(engine, first) catch |err| return allocationError(engine, err);
    const previous = get(engine, proxy, "colors") catch |err| return allocationError(engine, err);
    defer engine.freeValue(previous);
    const second = try stateValue(engine, .{ .revision = 2, .color_mode = .truecolor, .stdout_is_tty = true, .resource_json = @embedFile("../themes/fixtures/light-original-7fb.json"), .resource_identity = "loader-2/theme-1", .terminal_colors = .{ .background = .{ .r = 180, .g = 170, .b = 160 } } });
    defer engine.freeValue(second);
    hydrateState(engine, second) catch |err| return allocationError(engine, err);
    const after = get(engine, proxy, "colors") catch |err| return allocationError(engine, err);
    defer engine.freeValue(after);
    c.JS_RunGC(engine.runtime);
}
test "cached theme owner allocation failures release candidate reports roots signatures and retained old colors" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, stateAllocationProbe, .{});
}

test "actual original component Theme callbacks retain live palette closures and captured settings cursor through GC" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/theme-components-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "componentOracle", try engine.fromJsonValue(fixture.value));
    const script = try engine.evalModule(
        \\import {Theme,getSelectListTheme,getSettingsListTheme} from 'pi-coding-agent';
        \\const helperShape=Object.fromEntries([getSelectListTheme,getSettingsListTheme].map(fn=>[fn.name,fn.length]));if(JSON.stringify(helperShape)!==JSON.stringify(componentOracle.helperShape))throw Error('Source helper function shape');
        \\globalThis.makeComponentTheme=(input)=>new Theme(input.fg,input.bg,componentItem.mode,input.options);
        \\globalThis.makeComponentHelpers=()=>[getSelectListTheme(),getSettingsListTheme()];
        \\globalThis.observeComponents=(select,editor,settings)=>{const samples=componentOracle.samples,marker={};return{keys:[Object.keys(select),Object.keys(editor),Object.keys(editor.selectList),Object.keys(settings)],select:Object.fromEntries(Object.keys(select).map(key=>[key,samples.map(text=>select[key](text))])),border:samples.map(text=>editor.borderColor(text)),editorSelect:Object.fromEntries(Object.keys(editor.selectList).map(key=>[key,samples.map(text=>editor.selectList[key](text))])),settings:{label:samples.map(text=>[settings.label(text,false),settings.label(text,true),settings.label(text,'selected')]),value:samples.map(text=>[settings.value(text,false),settings.value(text,true)]),description:samples.map(text=>settings.description(text)),hint:samples.map(text=>settings.hint(text)),cursor:settings.cursor,labelIdentity:settings.label(marker,false)===marker}}};
        \\globalThis.compareComponents=(expected,actual)=>{if(JSON.stringify(expected)!==JSON.stringify(actual))throw Error(JSON.stringify({expected,actual}))};
    , "native-component-theme-functions.mjs");
    defer engine.freeValue(script);
    const module = try moduleState(engine);
    defer engine.freeValue(module);
    for (fixture.value.object.get("cases").?.array.items) |item| {
        try put(engine, global, "componentItem", try engine.fromJsonValue(item));
        try put(engine, module, "current", try engine.eval("makeComponentTheme(componentItem.first)", "native-component-first.js", c.JS_EVAL_TYPE_GLOBAL));
        try put(engine, global, "componentEditor", try getEditorTheme(engine));
        const before = try engine.eval("var componentHelpers=makeComponentHelpers();compareComponents(componentItem.before,observeComponents(componentHelpers[0],componentEditor,componentHelpers[1]));", "native-component-before.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(before);
        c.JS_RunGC(engine.runtime);
        try put(engine, module, "current", try engine.eval("makeComponentTheme(componentItem.second)", "native-component-second.js", c.JS_EVAL_TYPE_GLOBAL));
        const after = try engine.eval("compareComponents(componentItem.after,observeComponents(componentHelpers[0],componentEditor,componentHelpers[1]));", "native-component-after.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(after);
        try put(engine, global, "freshComponentEditor", try getEditorTheme(engine));
        const fresh = try engine.eval("var freshHelpers=makeComponentHelpers();compareComponents(componentItem.fresh,observeComponents(freshHelpers[0],freshComponentEditor,freshHelpers[1]));", "native-component-fresh.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(fresh);
        c.JS_RunGC(engine.runtime);
    }
}

fn componentAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const module = moduleState(engine) catch |err| return allocationError(engine, err);
    defer engine.freeValue(module);
    const selected = fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), null, .truecolor) catch |err| return allocationError(engine, err);
    try put(engine, module, "current", selected);
    const editor = getEditorTheme(engine) catch |err| return allocationError(engine, err);
    defer engine.freeValue(editor);
    const settings = getSettingsListTheme(engine) catch |err| return allocationError(engine, err);
    defer engine.freeValue(settings);
    c.JS_RunGC(engine.runtime);
    const paint = get(engine, editor, "borderColor") catch |err| return allocationError(engine, err);
    defer engine.freeValue(paint);
    const text = jsString(engine, "retained") catch |err| return allocationError(engine, err);
    defer engine.freeValue(text);
    var args = [_]c.JSValue{text};
    const result = engine.checked(c.JS_Call(engine.context, paint, c.pi_js_undefined(), args.len, &args)) catch |err| return allocationError(engine, err);
    defer engine.freeValue(result);
}
test "component theme closure allocation failures release proxy roots and partially built helper objects" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, componentAllocationProbe, .{});
}

fn registryProbeCallback(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = engine_mod.Engine.fromContext(context.?);
    if (magic == 0) {
        setRegisteredThemes(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| return fail(engine, err);
        return c.pi_js_undefined();
    }
    const module = moduleState(engine) catch |err| return fail(engine, err);
    defer engine.freeValue(module);
    return get(engine, module, "registeredThemes") catch |err| fail(engine, err);
}
test "actual original Theme registry clear prefix getter order synchronous reentry iterator close and thrown identity replay" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/theme-registry-original-7fb.json"), .{});
    defer fixture.deinit();
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    try put(engine, global, "registryOracle", try engine.fromJsonValue(fixture.value));
    const component_fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/theme-components-original-7fb.json"), .{});
    defer component_fixture.deinit();
    try put(engine, global, "registryOracleInput", try engine.fromJsonValue(component_fixture.value.object.get("cases").?.array.items[0].object.get("first").?));
    try put(engine, global, "registerThemeProbe", try engine.checked(c.pi_js_function_magic(engine.context, registryProbeCallback, "register", 1, 0)));
    try put(engine, global, "getRegistryProbe", try engine.checked(c.pi_js_function_magic(engine.context, registryProbeCallback, "getRegistry", 0, 1)));
    const script = try engine.evalModule(
        \\import {Theme} from 'pi-coding-agent';
        \\const input=registryOracleInput,labels=new WeakMap();function instance(name,label){const t=new Theme(input.fg,input.bg,'truecolor',{...input.options,name});labels.set(t,label);return t}
        \\const a=instance('alpha','alpha-first'),a2=instance('alpha','alpha-last'),b=instance('beta','beta'),unnamed=instance(undefined,'unnamed'),invalid=instance('not/valid','invalid');
        \\const register=registerThemeProbe,traces=[],snapshot=()=>Array.from(getRegistryProbe().entries()).map(([name,t])=>[name,labels.get(t)??'probe']);
        \\register([a,a2,unnamed]);traces.push({case:'duplicates-and-unnamed',entries:snapshot(),sameLast:Array.from(getRegistryProbe().entries())[0][1]===a2});
        \\let message;try{register([b,invalid,a])}catch(error){message=error.message};traces.push({case:'invalid-name-partial-registry',entries:snapshot(),message});
        \\let reads=0;const probe={get name(){reads++;return reads===1?'truthy':reads===2?'allowed':'actual-key'}};register([probe]);traces.push({case:'name-getter-order',reads,entries:snapshot()});
        \\const marker={};let sameMarker=false;try{register([{get name(){throw marker}}])}catch(error){sameMarker=error===marker};traces.push({case:'getter-throw-cleared-registry',sameMarker,entries:snapshot()});
        \\let entered=false;const reentry={get name(){if(!entered){entered=true;register([a])}return 'outer'}};register([reentry]);traces.push({case:'synchronous-getter-reentry',entries:snapshot()});
        \\const iteratorLog=[];const iterable={*[Symbol.iterator](){try{iteratorLog.push('yield-beta');yield b;iteratorLog.push('yield-invalid');yield invalid;iteratorLog.push('unexpected')}finally{iteratorLog.push('finally')}}};message=undefined;try{register(iterable)}catch(error){message=error.message};traces.push({case:'iterator-close-on-body-throw',entries:snapshot(),iteratorLog,message});
        \\register([]);traces.push({case:'explicit-clear',entries:snapshot()});if(JSON.stringify(traces)!==JSON.stringify(registryOracle.traces))throw Error(JSON.stringify({traces,expected:registryOracle.traces}));
        \\globalThis.retainedRegisteredTheme=a2;register([a2]);a2.sourceInfo={metadata:'same-instance'};globalThis.iteratorOriginal=marker;let same=false;try{register({[Symbol.iterator](){return {next(){return {value:{get name(){throw marker}},done:false}},return(){throw Error('close failure')}}}})}catch(error){same=error===marker}if(!same)throw Error('IteratorClose replaced body exception');register([a2]);
    , "native-theme-registry-original.mjs");
    defer engine.freeValue(script);
    c.JS_RunGC(engine.runtime);
    const found = try getThemeByName(engine, "alpha");
    defer engine.freeValue(found);
    const saved = try get(engine, global, "retainedRegisteredTheme");
    defer engine.freeValue(saved);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, found, saved));
    const metadata = try get(engine, found, "sourceInfo");
    defer engine.freeValue(metadata);
    try std.testing.expect(c.JS_IsObject(metadata));
    const missing = try getThemeByName(engine, "nonexistent-registry-fixture");
    defer engine.freeValue(missing);
    try std.testing.expect(c.JS_IsUndefined(missing));
}

fn registryAllocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const theme = fromJson(engine, @embedFile("../themes/fixtures/dark-original-7fb.json"), "registry-allocation.json", .truecolor) catch |err| return allocationError(engine, err);
    defer engine.freeValue(theme);
    const themes = engine.checked(c.JS_NewArray(engine.context)) catch |err| return allocationError(engine, err);
    defer engine.freeValue(themes);
    if (c.JS_SetPropertyUint32(engine.context, themes, 0, c.JS_DupValue(engine.context, theme)) < 0) return error.OutOfMemory;
    setRegisteredThemes(engine, themes) catch |err| return allocationError(engine, err);
    c.JS_RunGC(engine.runtime);
    const found = getThemeByName(engine, "dark") catch |err| return allocationError(engine, err);
    defer engine.freeValue(found);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, found, theme));
    const empty = engine.checked(c.JS_NewArray(engine.context)) catch |err| return allocationError(engine, err);
    defer engine.freeValue(empty);
    setRegisteredThemes(engine, empty) catch |err| return allocationError(engine, err);
    c.JS_RunGC(engine.runtime);
}
test "Theme registry admission lookup explicit clear and final VM retirement release every induced allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, registryAllocationProbe, .{});
}
