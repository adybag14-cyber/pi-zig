//! Native public TUI keybinding registry. Definitions and overrides remain JS
//! objects on the VM owner; algorithms and callback ordering are native Zig.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const engine_mod = @import("engine.zig");
const keys = @import("../tui/keys.zig");
const c = js.c;
const Engine = js.Engine;
const ClassState = struct { engine: *Engine, prototype: c.JSValue, state: c.JSValue };
const Method = enum(c_int) { rebuild, matches, getKeys, getDefinition, getConflicts, setUserBindings, getUserBindings, getResolvedBindings };
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn fail(engine: *Engine, err: anyerror) c.JSValue {
    if (err == error.JavaScriptException) return engine.throwCaptured();
    if (err == error.OutOfMemory) return c.JS_ThrowOutOfMemory(engine.context);
    return c.JS_ThrowTypeError(engine.context, "Native keybindings: %s", @as([*:0]const u8, @errorName(err)));
}
fn mark(runtime: ?*c.JSRuntime, value: c.JSValue, visit: ?*const c.JS_MarkFunc) callconv(.c) void {
    const state: *ClassState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_MarkValue(runtime, state.prototype, visit);
    c.JS_MarkValue(runtime, state.state, visit);
}
fn finalize(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const state: *ClassState = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    c.JS_FreeValueRT(runtime, state.prototype);
    c.JS_FreeValueRT(runtime, state.state);
    state.engine.gpa.destroy(state);
}
fn constructCall(context: ?*c.JSContext, function: c.JSValue, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue, flags: c_int) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (flags & c.JS_CALL_FLAG_CONSTRUCTOR == 0) return c.JS_ThrowTypeError(context, "KeybindingsManager requires new");
    const state: *ClassState = @ptrCast(@alignCast(c.JS_GetOpaque(function, c.JS_GetClassID(function)).?));
    return construct(state, target, if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn construct(state: *ClassState, target: c.JSValue, args: []const c.JSValue) !c.JSValue {
    const engine = state.engine;
    const prototype = try js.get(engine, target, "prototype");
    defer engine.freeValue(prototype);
    const value = try engine.checked(if (c.JS_IsObject(prototype)) c.JS_NewObjectProto(engine.context, prototype) else c.JS_NewObject(engine.context));
    errdefer engine.freeValue(value);
    try js.define(engine, value, "definitions", c.pi_js_undefined());
    try js.define(engine, value, "userBindings", c.pi_js_undefined());
    try js.define(engine, value, "keysById", try js.builtin(engine, "Map", &.{}));
    try js.define(engine, value, "conflicts", try js.array(engine));
    const definitions = try engine.checked(c.JS_NewString(engine.context, "definitions"));
    defer engine.freeValue(definitions);
    const user = try engine.checked(c.JS_NewString(engine.context, "userBindings"));
    defer engine.freeValue(user);
    try js.setKey(engine, value, definitions, arg(args, 0));
    const config = if (c.JS_IsUndefined(arg(args, 1))) try js.object(engine) else c.JS_DupValue(engine.context, arg(args, 1));
    defer engine.freeValue(config);
    try js.setKey(engine, value, user, config);
    const ignored = try js.invoke(engine, value, "rebuild", &.{});
    engine.freeValue(ignored);
    return value;
}
fn normalize(engine: *Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    if (c.JS_IsUndefined(value)) return result;
    const array_type = try js.global(engine, "Array");
    defer engine.freeValue(array_type);
    const check = try js.invoke(engine, array_type, "isArray", &.{value});
    defer engine.freeValue(check);
    const list = if (c.JS_ToBool(engine.context, check) != 0) c.JS_DupValue(engine.context, value) else try js.array(engine);
    defer engine.freeValue(list);
    if (c.JS_ToBool(engine.context, check) == 0) try js.push(engine, list, value);
    const seen = try js.builtin(engine, "Set", &.{});
    defer engine.freeValue(seen);
    var iterator = try js.Iterator.init(engine, list, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |key| {
        defer engine.freeValue(key);
        const has = try js.invoke(engine, seen, "has", &.{key});
        defer engine.freeValue(has);
        if (c.JS_ToBool(engine.context, has) != 0) continue;
        const added = try js.invoke(engine, seen, "add", &.{key});
        engine.freeValue(added);
        try js.push(engine, result, key);
    }
    return result;
}
fn entries(engine: *Engine, value: c.JSValue, symbol: c.JSValue) !js.Iterator {
    const list = try js.objectMethod(engine, "entries", value);
    defer engine.freeValue(list);
    return js.Iterator.init(engine, list, symbol);
}
fn rebuild(engine: *Engine, receiver: c.JSValue, symbol: c.JSValue) !void {
    const old = try js.get(engine, receiver, "keysById");
    defer engine.freeValue(old);
    const cleared = try js.invoke(engine, old, "clear", &.{});
    engine.freeValue(cleared);
    const conflicts_key = try engine.checked(c.JS_NewString(engine.context, "conflicts"));
    defer engine.freeValue(conflicts_key);
    const conflicts = try js.array(engine);
    defer engine.freeValue(conflicts);
    try js.setKey(engine, receiver, conflicts_key, conflicts);
    const claims = try js.builtin(engine, "Map", &.{});
    defer engine.freeValue(claims);
    const user = try js.get(engine, receiver, "userBindings");
    defer engine.freeValue(user);
    var user_entries = try entries(engine, user, symbol);
    defer user_entries.deinit();
    errdefer user_entries.closePreserving();
    while (try user_entries.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |v| engine.freeValue(v);
        const defs = try js.get(engine, receiver, "definitions");
        defer engine.freeValue(defs);
        if (!try js.hasKey(engine, defs, pair[0])) continue;
        const normalized = try normalize(engine, pair[1], symbol);
        defer engine.freeValue(normalized);
        var key_entries = try js.Iterator.init(engine, normalized, symbol);
        defer key_entries.deinit();
        errdefer key_entries.closePreserving();
        while (try key_entries.next()) |key| {
            defer engine.freeValue(key);
            const previous = try js.invoke(engine, claims, "get", &.{key});
            defer engine.freeValue(previous);
            const claimants = if (c.JS_IsNull(previous) or c.JS_IsUndefined(previous)) try js.builtin(engine, "Set", &.{}) else c.JS_DupValue(engine.context, previous);
            defer engine.freeValue(claimants);
            const added = try js.invoke(engine, claimants, "add", &.{pair[0]});
            engine.freeValue(added);
            const stored = try js.invoke(engine, claims, "set", &.{ key, claimants });
            engine.freeValue(stored);
        }
    }
    var claim_entries = try js.Iterator.init(engine, claims, symbol);
    defer claim_entries.deinit();
    errdefer claim_entries.closePreserving();
    while (try claim_entries.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |v| engine.freeValue(v);
        const size = try js.get(engine, pair[1], "size");
        defer engine.freeValue(size);
        var count: f64 = undefined;
        if (c.JS_ToFloat64(engine.context, &count, size) < 0) return js.capture(engine);
        if (count <= 1 or std.math.isNan(count)) continue;
        const conflict = try js.object(engine);
        defer engine.freeValue(conflict);
        try js.define(engine, conflict, "key", c.JS_DupValue(engine.context, pair[0]));
        try js.define(engine, conflict, "keybindings", try js.collect(engine, pair[1], symbol));
        const target = try js.get(engine, receiver, "conflicts");
        defer engine.freeValue(target);
        try js.push(engine, target, conflict);
    }
    const defs = try js.get(engine, receiver, "definitions");
    defer engine.freeValue(defs);
    var definition_entries = try entries(engine, defs, symbol);
    defer definition_entries.deinit();
    errdefer definition_entries.closePreserving();
    while (try definition_entries.next()) |entry| {
        defer engine.freeValue(entry);
        const pair = try js.pair(engine, entry, symbol);
        defer for (pair) |v| engine.freeValue(v);
        const current = try js.get(engine, receiver, "userBindings");
        defer engine.freeValue(current);
        const override = try js.getKey(engine, current, pair[0]);
        defer engine.freeValue(override);
        const defaults = if (c.JS_IsUndefined(override)) try js.get(engine, pair[1], "defaultKeys") else c.JS_DupValue(engine.context, override);
        defer engine.freeValue(defaults);
        const normalized = try normalize(engine, defaults, symbol);
        defer engine.freeValue(normalized);
        const target = try js.get(engine, receiver, "keysById");
        defer engine.freeValue(target);
        const stored = try js.invoke(engine, target, "set", &.{ pair[0], normalized });
        engine.freeValue(stored);
    }
}
fn keysFor(engine: *Engine, receiver: c.JSValue, id: c.JSValue) !c.JSValue {
    const map = try js.get(engine, receiver, "keysById");
    defer engine.freeValue(map);
    const list = try js.invoke(engine, map, "get", &.{id});
    if (!c.JS_IsNull(list) and !c.JS_IsUndefined(list)) return list;
    engine.freeValue(list);
    return js.array(engine);
}
fn cloneConflict(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return cloneConflictImpl(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), data[0]) catch |err| fail(engine, err);
}
fn cloneConflictImpl(engine: *Engine, value: c.JSValue, symbol: c.JSValue) !c.JSValue {
    const result = try js.spread(engine, value);
    errdefer engine.freeValue(result);
    const bindings = try js.get(engine, value, "keybindings");
    defer engine.freeValue(bindings);
    try js.define(engine, result, "keybindings", try js.collect(engine, bindings, symbol));
    return result;
}
fn methodCall(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return operation(engine, data[0], receiver, @enumFromInt(magic), if (argc == 0) &.{} else argv[0..@intCast(argc)]) catch |err| fail(engine, err);
}
fn operation(engine: *Engine, state: c.JSValue, receiver: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    const symbol = try js.get(engine, state, "iteratorSymbol");
    defer engine.freeValue(symbol);
    switch (method) {
        .rebuild => {
            try rebuild(engine, receiver, symbol);
            return c.pi_js_undefined();
        },
        .getDefinition => {
            const defs = try js.get(engine, receiver, "definitions");
            defer engine.freeValue(defs);
            return js.getKey(engine, defs, arg(args, 0));
        },
        .getKeys => {
            const list = try keysFor(engine, receiver, arg(args, 0));
            defer engine.freeValue(list);
            return js.collect(engine, list, symbol);
        },
        .getUserBindings => {
            const value = try js.get(engine, receiver, "userBindings");
            defer engine.freeValue(value);
            return js.spread(engine, value);
        },
        .setUserBindings => {
            const name = try engine.checked(c.JS_NewString(engine.context, "userBindings"));
            defer engine.freeValue(name);
            try js.setKey(engine, receiver, name, arg(args, 0));
            const ignored = try js.invoke(engine, receiver, "rebuild", &.{});
            engine.freeValue(ignored);
            return c.pi_js_undefined();
        },
        .getConflicts => {
            const value = try js.get(engine, receiver, "conflicts");
            defer engine.freeValue(value);
            var callback_data = [_]c.JSValue{symbol};
            const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, cloneConflict, "", 1, 0, 1, &callback_data));
            defer engine.freeValue(callback);
            return js.invoke(engine, value, "map", &.{callback});
        },
        .matches => {
            const list = try keysFor(engine, receiver, arg(args, 1));
            defer engine.freeValue(list);
            var iterator = try js.Iterator.init(engine, list, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |key| {
                defer engine.freeValue(key);
                if (!c.JS_IsString(arg(args, 0))) return js.typeError(engine, "Key data must be a string");
                // Source key IDs call toLowerCase; preserve callback/exception
                // identity for malformed string-like values rather than coerce.
                const lower = try js.invoke(engine, key, "toLowerCase", &.{});
                defer engine.freeValue(lower);
                if (!c.JS_IsString(lower)) return js.typeError(engine, "Key identifier must lowercase to a string");
                const key_text = try engine.toString(lower);
                defer engine.gpa.free(key_text);
                const input = try engine.toString(arg(args, 0));
                defer engine.gpa.free(input);
                if (keys.matchesKey(input, key_text)) {
                    try iterator.close();
                    return c.pi_js_bool(engine.context, 1);
                }
            }
            return c.pi_js_bool(engine.context, 0);
        },
        .getResolvedBindings => {
            const result = try js.object(engine);
            errdefer engine.freeValue(result);
            const defs = try js.get(engine, receiver, "definitions");
            defer engine.freeValue(defs);
            const names = try js.objectMethod(engine, "keys", defs);
            defer engine.freeValue(names);
            var iterator = try js.Iterator.init(engine, names, symbol);
            defer iterator.deinit();
            errdefer iterator.closePreserving();
            while (try iterator.next()) |id| {
                defer engine.freeValue(id);
                const list = try keysFor(engine, receiver, id);
                defer engine.freeValue(list);
                const length = try js.get(engine, list, "length");
                defer engine.freeValue(length);
                var count: f64 = 0;
                if (c.JS_IsNumber(length) and c.JS_ToFloat64(engine.context, &count, length) < 0) return js.capture(engine);
                const value = if (c.JS_IsNumber(length) and count == 1) try engine.checked(c.JS_GetPropertyUint32(engine.context, list, 0)) else try js.collect(engine, list, symbol);
                defer engine.freeValue(value);
                try js.setKey(engine, result, id, value);
            }
            return result;
        },
    }
}
fn stateFor(engine: *Engine) !c.JSValue {
    const exports = engine.native_module_values.get("pi-tui") orelse return error.NativeKeybindingsUnavailable;
    const constructor = try js.get(engine, exports, "KeybindingsManager");
    defer engine.freeValue(constructor);
    const state: *ClassState = @ptrCast(@alignCast(c.JS_GetOpaque(constructor, c.JS_GetClassID(constructor)) orelse return error.NativeKeybindingsUnavailable));
    return c.JS_DupValue(engine.context, state.state);
}
fn create(engine: *Engine, state: c.JSValue, defs: c.JSValue, config: c.JSValue) !c.JSValue {
    const constructor = try js.get(engine, state, "constructor");
    defer engine.freeValue(constructor);
    var args = [_]c.JSValue{ defs, config };
    return engine.checked(c.JS_CallConstructor(engine.context, constructor, 2, &args));
}
fn globalFor(engine: *Engine, state: c.JSValue) !c.JSValue {
    const current = try js.get(engine, state, "current");
    if (c.JS_ToBool(engine.context, current) != 0) return current;
    engine.freeValue(current);
    const defs = try js.get(engine, state, "definitions");
    defer engine.freeValue(defs);
    const manager = try create(engine, state, defs, c.pi_js_undefined());
    errdefer engine.freeValue(manager);
    try js.define(engine, state, "current", c.JS_DupValue(engine.context, manager));
    return manager;
}
pub fn getGlobal(engine: *Engine) !c.JSValue {
    const state = try stateFor(engine);
    defer engine.freeValue(state);
    return globalFor(engine, state);
}
pub fn getEditor(engine: *Engine) !c.JSValue {
    const state = try stateFor(engine);
    defer engine.freeValue(state);
    const current = try js.get(engine, state, "editor");
    if (!c.JS_IsUndefined(current)) return current;
    engine.freeValue(current);
    const defs = try js.get(engine, state, "appDefinitions");
    defer engine.freeValue(defs);
    const manager = try create(engine, state, defs, c.pi_js_undefined());
    errdefer engine.freeValue(manager);
    try js.define(engine, state, "editor", c.JS_DupValue(engine.context, manager));
    return manager;
}

fn hashValue(engine: *Engine, hash: *std.crypto.hash.sha2.Sha256, value: c.JSValue, depth: usize) anyerror!void {
    if (depth > 64) return error.InvalidNativeKeybindingsContext;
    if (c.JS_IsString(value)) {
        hash.update("s");
        const text = try engine.toString(value);
        defer engine.gpa.free(text);
        const length: u64 = text.len;
        hash.update(std.mem.asBytes(&length));
        hash.update(text);
    } else if (c.JS_IsArray(value)) {
        hash.update("a");
        const raw = try js.get(engine, value, "length");
        defer engine.freeValue(raw);
        var length: u64 = 0;
        if (c.JS_ToIndex(engine.context, &length, raw) < 0) return js.capture(engine);
        hash.update(std.mem.asBytes(&length));
        for (0..@as(usize, @intCast(length))) |index| {
            const item = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
            defer engine.freeValue(item);
            try hashValue(engine, hash, item, depth + 1);
        }
    } else if (c.JS_IsNull(value)) {
        hash.update("n");
    } else if (c.JS_IsBool(value)) {
        hash.update(if (c.JS_ToBool(engine.context, value) != 0) "t" else "f");
    } else if (c.JS_IsNumber(value)) {
        hash.update("d");
        var number: f64 = 0;
        if (c.JS_ToFloat64(engine.context, &number, value) < 0) return js.capture(engine);
        hash.update(std.mem.asBytes(&number));
    } else if (c.JS_IsObject(value)) {
        hash.update("o");
        var properties: [*c]c.JSPropertyEnum = null;
        var length: u32 = 0;
        if (c.JS_GetOwnPropertyNames(engine.context, &properties, &length, value, c.JS_GPN_STRING_MASK | c.JS_GPN_ENUM_ONLY) < 0) return js.capture(engine);
        defer c.JS_FreePropertyEnum(engine.context, properties, length);
        hash.update(std.mem.asBytes(&length));
        for (properties[0..length]) |entry| {
            const name = try engine.checked(c.JS_AtomToValue(engine.context, entry.atom));
            defer engine.freeValue(name);
            try hashValue(engine, hash, name, depth + 1);
            const item = try engine.checked(c.JS_GetProperty(engine.context, value, entry.atom));
            defer engine.freeValue(item);
            try hashValue(engine, hash, item, depth + 1);
        }
    } else return error.InvalidNativeKeybindingsContext;
}

/// Consume only Main-admitted cached context. Repeated snapshots do not erase
/// extension overrides, and this path performs no file or terminal queries.
pub fn hydrateAdmittedConfig(engine: *Engine, snapshot: c.JSValue) !void {
    const state = try stateFor(engine);
    defer engine.freeValue(state);
    const config = try js.get(engine, snapshot, "keybindingsConfig");
    defer engine.freeValue(config);
    if (!c.JS_IsUndefined(config)) {
        if (!c.JS_IsObject(config) or c.JS_IsArray(config)) return error.InvalidNativeKeybindingsContext;
        // Avoid JSON.stringify/toJSON on internal admission metadata.
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        try hashValue(engine, &hash, config, 0);
        const signature = std.fmt.bytesToHex(hash.finalResult(), .lower);
        const encoded = try engine.checked(c.JS_NewStringLen(engine.context, &signature, signature.len));
        defer engine.freeValue(encoded);
        const old = try js.get(engine, state, "admittedConfigSignature");
        defer engine.freeValue(old);
        if (!c.JS_IsStrictEqual(engine.context, old, encoded)) {
            const manager = try getEditor(engine);
            defer engine.freeValue(manager);
            const ignored = try js.invoke(engine, manager, "setUserBindings", &.{config});
            engine.freeValue(ignored);
            // Source InteractiveMode installs its app registry before session
            // callbacks; later updates retain the same factory-facing object.
            if (c.JS_IsUndefined(old)) try js.define(engine, state, "current", c.JS_DupValue(engine.context, manager));
            try js.define(engine, state, "admittedConfigSignature", c.JS_DupValue(engine.context, encoded));
        }
    }
    const kitty = try js.get(engine, snapshot, "kittyActive");
    defer engine.freeValue(kitty);
    if (!c.JS_IsUndefined(kitty)) {
        if (!c.JS_IsBool(kitty)) return error.InvalidNativeKeybindingsContext;
        const old = try js.get(engine, state, "admittedKitty");
        defer engine.freeValue(old);
        if (!c.JS_IsStrictEqual(engine.context, old, kitty)) {
            keys.setKittyProtocolActive(c.JS_ToBool(engine.context, kitty) != 0);
            try js.define(engine, state, "admittedKitty", c.JS_DupValue(engine.context, kitty));
        }
    }
}
fn globalCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    if (magic == 0) return globalFor(engine, data[0]) catch |err| fail(engine, err);
    js.define(engine, data[0], "current", c.JS_DupValue(engine.context, if (argc > 0) argv[0] else c.pi_js_undefined())) catch |err| return fail(engine, err);
    return c.pi_js_undefined();
}
fn appDefinitionJson(engine: *Engine) ![]const u8 {
    const process = try js.global(engine, "process");
    defer engine.freeValue(process);
    var platform: []const u8 = switch (builtin.os.tag) {
        .windows => "win32",
        .macos => "darwin",
        else => "linux",
    };
    var owned: ?[]u8 = null;
    defer if (owned) |value| engine.gpa.free(value);
    var wsl = false;
    if (c.JS_IsObject(process)) {
        const value = try js.get(engine, process, "platform");
        defer engine.freeValue(value);
        if (c.JS_IsString(value)) {
            owned = try engine.toString(value);
            platform = owned.?;
        }
        const env = try js.get(engine, process, "env");
        defer engine.freeValue(env);
        if (c.JS_IsObject(env)) {
            const distro = try js.get(engine, env, "WSL_DISTRO_NAME");
            defer engine.freeValue(distro);
            const interop = try js.get(engine, env, "WSL_INTEROP");
            defer engine.freeValue(interop);
            wsl = c.JS_ToBool(engine.context, distro) != 0 or c.JS_ToBool(engine.context, interop) != 0;
        }
    }
    if (std.mem.eql(u8, platform, "win32")) return @embedFile("fixtures/app-keybinding-definitions-windows-original-6fb.json");
    if (std.mem.eql(u8, platform, "darwin")) return @embedFile("fixtures/app-keybinding-definitions-darwin-original-6fb.json");
    if (wsl) return @embedFile("fixtures/app-keybinding-definitions-wsl-original-6fb.json");
    return @embedFile("fixtures/app-keybinding-definitions-linux-original-6fb.json");
}
pub fn install(engine: *Engine, exports: c.JSValue) !void {
    var class: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class);
    const definition: c.JSClassDef = .{ .class_name = "Native KeybindingsManager Constructor", .finalizer = finalize, .gc_mark = mark, .call = constructCall };
    if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
    const state = try js.object(engine);
    defer engine.freeValue(state);
    const tui_json = @embedFile("fixtures/tui-keybinding-definitions-original-6fb.json");
    const defs = try engine.checked(c.JS_ParseJSON(engine.context, tui_json.ptr, tui_json.len, "tui-keybindings.json"));
    defer engine.freeValue(defs);
    try js.define(engine, state, "definitions", c.JS_DupValue(engine.context, defs));
    const app_json = try appDefinitionJson(engine);
    try js.define(engine, state, "appDefinitions", try engine.checked(c.JS_ParseJSON(engine.context, app_json.ptr, app_json.len, "app-keybindings.json")));
    const symbol_type = try js.global(engine, "Symbol");
    defer engine.freeValue(symbol_type);
    try js.define(engine, state, "iteratorSymbol", try js.get(engine, symbol_type, "iterator"));
    const prototype = try js.object(engine);
    defer engine.freeValue(prototype);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.pi_js_undefined(), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return error.JavaScriptException;
    inline for (std.meta.fields(Method)) |field| {
        const name: [:0]const u8 = field.name;
        const length: c_int = if (field.value == @intFromEnum(Method.matches)) 2 else if (field.value == @intFromEnum(Method.getKeys) or field.value == @intFromEnum(Method.getDefinition) or field.value == @intFromEnum(Method.setUserBindings)) 1 else 0;
        var data = [_]c.JSValue{state};
        const callback = try engine.checked(c.JS_NewCFunctionData2(engine.context, methodCall, name.ptr, length, @intCast(field.value), 1, &data));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name.ptr, callback, c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    }
    const function_type = try js.global(engine, "Function");
    defer engine.freeValue(function_type);
    const function_prototype = try js.get(engine, function_type, "prototype");
    defer engine.freeValue(function_prototype);
    const constructor = try engine.checked(c.JS_NewObjectProtoClass(engine.context, function_prototype, class));
    defer engine.freeValue(constructor);
    const class_state = try engine.gpa.create(ClassState);
    class_state.* = .{ .engine = engine, .prototype = c.JS_DupValue(engine.context, prototype), .state = c.JS_DupValue(engine.context, state) };
    _ = c.JS_SetOpaque(constructor, class_state);
    _ = c.JS_SetConstructorBit(engine.context, constructor, true);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "length", c.JS_NewInt32(engine.context, 1), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "name", try engine.checked(c.JS_NewString(engine.context, "KeybindingsManager")), c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, constructor, "prototype", c.JS_DupValue(engine.context, prototype), 0) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "constructor", c.JS_DupValue(engine.context, constructor), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    try js.define(engine, state, "constructor", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "KeybindingsManager", c.JS_DupValue(engine.context, constructor));
    try js.define(engine, exports, "TUI_KEYBINDINGS", c.JS_DupValue(engine.context, defs));
    inline for (.{ .{ "getKeybindings", 0, 0 }, .{ "setKeybindings", 1, 1 } }) |item| {
        var data = [_]c.JSValue{state};
        try js.define(engine, exports, item[0], try engine.checked(c.JS_NewCFunctionData2(engine.context, globalCall, item[0], item[2], item[1], 1, &data)));
    }
}

test "Source6fb public KeybindingsManager original defaults overrides conflicts matching and class traces" {
    defer keys.setKittyProtocolActive(false);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, @embedFile("fixtures/keybindings-manager-original-6fb.json"), .{});
    defer fixture.deinit();
    const global_object = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global_object);
    try js.define(engine, global_object, "keyOracle", try engine.fromJsonValue(fixture.value));
    const module = try engine.evalModule(
        \\import{KeybindingsManager,TUI_KEYBINDINGS,getKeybindings,setKeybindings}from'pi-tui';globalThis.KeybindingsManager=KeybindingsManager;globalThis.getKeybindings=getKeybindings;globalThis.setKeybindings=setKeybindings;
        \\globalThis.compareKeys=(a,b,p='root')=>{if(a&&typeof a==='object'){if(!b||Object.keys(a).sort().join('|')!==Object.keys(b).sort().join('|'))throw Error(p+' keys');for(const key of Object.keys(a))compareKeys(a[key],b[key],p+'.'+key);return}if(a!==b)throw Error(p+':'+a+' != '+b)};
        \\if(KeybindingsManager.name!==keyOracle.shape.name||KeybindingsManager.length!==keyOracle.shape.length)throw Error('constructor shape');const shape=Object.fromEntries(Object.getOwnPropertyNames(KeybindingsManager.prototype).filter(k=>k!=='constructor').map(k=>[k,{length:KeybindingsManager.prototype[k].length,enumerable:Object.getOwnPropertyDescriptor(KeybindingsManager.prototype,k).enumerable}]));compareKeys(keyOracle.shape.methods,shape);
        \\globalThis.replayKeyCase=item=>{const m=new KeybindingsManager(item.definitions,item.userBindings);compareKeys(item.resolved,m.getResolvedBindings());compareKeys(item.conflicts,m.getConflicts());for(const [id,wanted]of Object.entries(item.keys))compareKeys(wanted,m.getKeys(id));for(const match of item.matches){let actual;try{actual=m.matches(match.data,match.id)}catch(e){if(e.name!==match.errorName)throw Error('match error '+e.name+' != '+match.errorName);continue}if(match.errorName)throw Error('missing match error');compareKeys(match.value,actual)}};
        \\for(const item of keyOracle.structural){let result;try{result=new Function(item.source)()}catch(e){if(e.name!==item.errorName)throw Error('structural exception '+e.name+' '+item.source);continue}if(item.errorName)throw Error('missing structural exception '+item.source);compareKeys(item.result,result,'structural')}
    , "source-key-manager-original.mjs");
    defer engine.freeValue(module);
    for (fixture.value.object.get("cases").?.array.items) |item| {
        keys.setKittyProtocolActive(item.object.get("kitty").?.bool);
        try js.define(engine, global_object, "currentKeyCase", try engine.fromJsonValue(item));
        const actual = try engine.eval("replayKeyCase(currentKeyCase)", "key-case.js", c.JS_EVAL_TYPE_GLOBAL);
        engine.freeValue(actual);
        c.JS_RunGC(engine.runtime);
    }
    keys.setKittyProtocolActive(false);
}

test "Source6fb public KeybindingsManager admitted snapshots retain overrides factory identity and cached protocol" {
    defer keys.setKittyProtocolActive(false);
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const bindings = try @import("native_bindings.zig").Bindings.init(engine.gpa, engine);
    defer bindings.deinit();
    const root = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(root);
    const factory = try getEditor(engine);
    defer engine.freeValue(factory);
    try js.define(engine, root, "factoryKeys", c.JS_DupValue(engine.context, factory));
    const initial = "{\"keybindingsConfig\":{\"tui.select.confirm\":[],\"tui.select.down\":\"ctrl+n\"},\"kittyActive\":true}";
    try bindings.setContext(initial);
    const first = try engine.evalModule(
        \\import {getKeybindings,setKeybindings} from 'pi-tui';if(getKeybindings()!==factoryKeys||factoryKeys.matches('\r','tui.select.confirm')||!factoryKeys.matches('\x0e','tui.select.down'))throw Error('admission');globalThis.overrideKeys={matches(){return 7}};setKeybindings(overrideKeys);factoryKeys.setUserBindings({'tui.select.down':'ctrl+p'});
    , "admitted-keys-first.mjs");
    defer engine.freeValue(first);
    keys.setKittyProtocolActive(false);
    try bindings.setContext(initial);
    try std.testing.expect(!keys.isKittyProtocolActive());
    const second = try engine.evalModule("import {getKeybindings} from 'pi-tui';if(getKeybindings()!==overrideKeys||!factoryKeys.matches('\\x10','tui.select.down'))throw Error('unchanged snapshot erased override')", "admitted-keys-retained.mjs");
    defer engine.freeValue(second);
    const poison = try engine.eval("Object.prototype.toJSON=function(){throw Error('internal signature invoked toJSON')}", "key-signature-no-callback.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(poison);
    try bindings.setContext("{\"keybindingsConfig\":{\"tui.select.down\":\"ctrl+b\"},\"kittyActive\":false}");
    const clear = try engine.eval("delete Object.prototype.toJSON", "key-signature-clear.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(clear);
    const third = try engine.evalModule("import {getKeybindings} from 'pi-tui';if(getKeybindings()!==overrideKeys||!factoryKeys.matches('\\x02','tui.select.down'))throw Error('changed snapshot or global override');", "admitted-keys-changed.mjs");
    defer engine.freeValue(third);
    const again = try getEditor(engine);
    defer engine.freeValue(again);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, factory, again));
    try std.testing.expectError(error.InvalidExtensionContext, bindings.setContext("{\"keybindingsConfig\":[]}"));
    try std.testing.expectError(error.InvalidExtensionContext, bindings.setContext("{\"kittyActive\":1}"));
}

test "Source6fb public KeybindingsManager app defaults match original Windows Linux WSL and Darwin captures" {
    const inputs = .{
        .{ "win32", "{}", @embedFile("fixtures/app-keybinding-definitions-windows-original-6fb.json") },
        .{ "linux", "{}", @embedFile("fixtures/app-keybinding-definitions-linux-original-6fb.json") },
        .{ "linux", "{WSL_DISTRO_NAME:'fixture'}", @embedFile("fixtures/app-keybinding-definitions-wsl-original-6fb.json") },
        .{ "darwin", "{}", @embedFile("fixtures/app-keybinding-definitions-darwin-original-6fb.json") },
    };
    inline for (inputs) |input| {
        const engine = try Engine.init(std.testing.allocator, .{});
        defer engine.deinit();
        const setup = try engine.eval("globalThis.process={platform:'" ++ input[0] ++ "',env:" ++ input[1] ++ "};", "app-key-platform.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(setup);
        try @import("native_tui.zig").install(engine);
        const fixture = try std.json.parseFromSlice(std.json.Value, engine.gpa, input[2], .{});
        defer fixture.deinit();
        const expected = try engine.fromJsonValue(fixture.value);
        defer engine.freeValue(expected);
        const manager = try getEditor(engine);
        defer engine.freeValue(manager);
        const root = c.JS_GetGlobalObject(engine.context);
        defer engine.freeValue(root);
        try js.define(engine, root, "appDefinitions", c.JS_DupValue(engine.context, expected));
        try js.define(engine, root, "appKeys", c.JS_DupValue(engine.context, manager));
        const checked = try engine.eval("for(const [id,definition] of Object.entries(appDefinitions)){const keys=Array.isArray(definition.defaultKeys)?[...new Set(definition.defaultKeys)]:definition.defaultKeys===undefined?[]:[definition.defaultKeys];if(JSON.stringify(appKeys.getKeys(id))!==JSON.stringify(keys))throw Error(id+' platform defaults');if(JSON.stringify(appKeys.getDefinition(id))!==JSON.stringify(definition))throw Error(id+' definition');}", "app-key-defaults.js", c.JS_EVAL_TYPE_GLOBAL);
        defer engine.freeValue(checked);
    }
}

fn allocationError(engine: *Engine, err: anyerror) anyerror {
    if (err == error.JavaScriptException) if (engine.captured_exception) |exception| {
        const message = c.JS_GetPropertyStr(engine.context, exception, "message");
        defer engine.freeValue(message);
        const text = c.JS_ToCString(engine.context, message);
        if (text != null) {
            defer c.JS_FreeCString(engine.context, text);
            if (std.mem.indexOf(u8, std.mem.span(text), "out of memory") != null) return error.OutOfMemory;
        }
    };
    return err;
}
fn allocationProbe(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    const bindings = @import("native_bindings.zig").Bindings.init(gpa, engine) catch |err| return allocationError(engine, err);
    defer bindings.deinit();
    bindings.setContext("{\"keybindingsConfig\":{\"tui.select.confirm\":[],\"tui.select.down\":\"ctrl+n\"},\"kittyActive\":true}") catch |err| return allocationError(engine, err);
    const module = engine.evalModule(
        \\import{KeybindingsManager,getKeybindings}from'pi-tui';const definitions={a:{defaultKeys:['ctrl+a','ctrl+a']},b:{defaultKeys:'ctrl+b'}};const registry=new KeybindingsManager(definitions,{a:['ctrl+x','ctrl+y'],b:'ctrl+x'});if(!registry.matches('\x18','a')||registry.getConflicts().length!==1)throw Error('registry');registry.getKeys('a');registry.getUserBindings();registry.getResolvedBindings();registry.setUserBindings({a:[]});globalThis.retainedKeyRegistry=registry;
    , "keybindings-allocation.mjs") catch |err| return allocationError(engine, err);
    defer engine.freeValue(module);
    c.JS_RunGC(engine.runtime);
    const retained = engine.eval("if(retainedKeyRegistry.getKeys('a').length!==0)throw Error('retained');delete globalThis.retainedKeyRegistry;", "retained-keys.js", c.JS_EVAL_TYPE_GLOBAL) catch |err| return allocationError(engine, err);
    defer engine.freeValue(retained);
    c.JS_RunGC(engine.runtime);
}
test "Source6fb public KeybindingsManager admission iteration callbacks and retained state release all allocation failures" {
    defer keys.setKittyProtocolActive(false);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}

test "Source6fb public KeybindingsManager native iteration respects engine interrupt budget" {
    const engine = try Engine.init(std.testing.allocator, .{ .interrupt_budget = 2 });
    defer engine.deinit();
    try @import("native_tui.zig").install(engine);
    try std.testing.expectError(error.JavaScriptException, engine.evalModule("import {KeybindingsManager} from 'pi-tui';new KeybindingsManager({a:{defaultKeys:new Array(2048)}});", "bounded-key-iteration.mjs"));
    const message = try js.get(engine, engine.captured_exception.?, "message");
    defer engine.freeValue(message);
    const text = try engine.toString(message);
    defer engine.gpa.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "interrupted") != null);
}
