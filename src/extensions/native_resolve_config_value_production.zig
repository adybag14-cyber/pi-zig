//! Native body of coding-agent/core/resolve-config-value.ts at 4954d760.
//! Platform imports must be the genuine native process/child_process/shell bindings.
//! The namespace owns a VM Map, so cached undefined and cache lifetime match Source.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const nf = @import("native_node_function.zig");
const sc = @import("native_sdk_prompt_scope.zig");
const Scope = sc.Scope;
const c = em.c;
pub const Imports = struct { process: c.JSValue, getShellConfig: c.JSValue, spawnSync: c.JSValue, execSync: c.JSValue };
const Part = union(enum) { literal: []const u8, env: []const u8 };
fn first(b: u8) bool {
    return std.ascii.isAlphabetic(b) or b == '_';
}
fn rest(b: u8) bool {
    return first(b) or std.ascii.isDigit(b);
}
fn parse(gpa: std.mem.Allocator, raw: []const u8) !std.ArrayList(Part) {
    var parts: std.ArrayList(Part) = .empty;
    errdefer parts.deinit(gpa);
    var i: usize = 0;
    while (i < raw.len) {
        const start = i;
        if (raw[i] != '$') {
            while (i < raw.len and raw[i] != '$') i += 1;
            try parts.append(gpa, .{ .literal = raw[start..i] });
            continue;
        }
        if (i + 1 == raw.len) {
            i += 1;
            try parts.append(gpa, .{ .literal = raw[start..i] });
            continue;
        }
        const next = raw[i + 1];
        if (next == '$' or next == '!') {
            i += 2;
            try parts.append(gpa, .{ .literal = raw[i - 1 .. i] });
            continue;
        }
        if (next == '{') {
            if (std.mem.indexOfScalarPos(u8, raw, i + 2, '}')) |end| {
                const name = raw[i + 2 .. end];
                var valid = name.len > 0 and first(name[0]);
                for (name) |b| valid = valid and rest(b);
                try parts.append(gpa, if (valid) .{ .env = name } else .{ .literal = raw[i .. end + 1] });
                i = end + 1;
                continue;
            }
        } else if (first(next)) {
            i += 2;
            while (i < raw.len and rest(raw[i])) i += 1;
            try parts.append(gpa, .{ .env = raw[start + 1 .. i] });
            continue;
        }
        i += 1;
        try parts.append(gpa, .{ .literal = raw[start..i] });
    }
    return parts;
}
fn arg(args: []const c.JSValue, i: usize) c.JSValue {
    return if (i < args.len) args[i] else c.pi_js_undefined();
}
fn prop(s: *Scope, obj: c.JSValue, key: c.JSValue) !c.JSValue {
    return s.own(try js.getKey(s.engine, obj, key));
}
fn environment(s: *Scope, state: c.JSValue, env: c.JSValue, name: c.JSValue) !c.JSValue {
    if (!sc.nullish(env)) {
        const v = try prop(s, env, name);
        if (s.truthy(v)) return v;
    }
    const ambient = try s.get(try s.get(state, "process"), "env");
    const v = try prop(s, ambient, name);
    return if (s.truthy(v)) v else c.pi_js_undefined();
}
fn names(s: *Scope, raw: []const u8) !c.JSValue {
    const result = try s.array();
    if (std.mem.startsWith(u8, raw, "!")) return result;
    var parts = try parse(s.engine.gpa, raw);
    defer parts.deinit(s.engine.gpa);
    for (parts.items) |part| if (part == .env) {
        const key = try s.text(part.env);
        if (!s.truthy(try s.invoke(result, "includes", &.{key}))) _ = try s.invoke(result, "push", &.{key});
    };
    return result;
}
fn missing(s: *Scope, state: c.JSValue, raw: []const u8, env: c.JSValue) !c.JSValue {
    const result = try s.array();
    const refs = try names(s, raw);
    const len = try length(s, refs);
    for (0..len) |i| {
        const key = try at(s, refs, i);
        if (c.JS_IsUndefined(try environment(s, state, env, key))) _ = try s.invoke(result, "push", &.{key});
    }
    return result;
}
fn length(s: *Scope, value: c.JSValue) !u32 {
    var n: u32 = 0;
    if (c.JS_ToUint32(s.engine.context, &n, try s.get(value, "length")) < 0) return js.capture(s.engine);
    return n;
}
fn at(s: *Scope, array: c.JSValue, i: usize) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_GetPropertyUint32(s.engine.context, array, @intCast(i))));
}
fn trim(s: *Scope, value: c.JSValue) !c.JSValue {
    const v = try s.invoke(value, "trim", &.{});
    return if (s.truthy(v)) v else c.pi_js_undefined();
}
fn clearCaught(engine: *em.Engine) void {
    if (engine.captured_exception) |value| engine.freeValue(value);
    engine.captured_exception = null;
}
fn options(s: *Scope) !c.JSValue {
    const o = try s.object();
    try s.put(o, "encoding", try s.text("utf-8"));
    try s.put(o, "timeout", c.JS_NewInt32(s.engine.context, 10000));
    return o;
}
fn stdio(s: *Scope, stdin: []const u8) !c.JSValue {
    const a = try s.array();
    for ([_][]const u8{ stdin, "pipe", "ignore" }) |v| _ = try s.invoke(a, "push", &.{try s.text(v)});
    return a;
}
fn defaultShell(s: *Scope, state: c.JSValue, command: c.JSValue) !c.JSValue {
    const o = try options(s);
    try s.put(o, "stdio", try stdio(s, "ignore"));
    const value = s.call(try s.get(state, "execSync"), c.pi_js_undefined(), &.{ command, o }) catch |err| {
        if (err == error.JavaScriptException) {
            clearCaught(s.engine);
            return c.pi_js_undefined();
        }
        return err;
    };
    return trim(s, value);
}
const Execution = struct { executed: bool, value: c.JSValue };
fn configuredShell(s: *Scope, state: c.JSValue, command: c.JSValue) !Execution {
    return configuredShellInner(s, state, command) catch |err| {
        if (err == error.JavaScriptException) {
            clearCaught(s.engine);
            return .{ .executed = false, .value = c.pi_js_undefined() };
        }
        return err;
    };
}
fn configuredShellInner(s: *Scope, state: c.JSValue, command: c.JSValue) !Execution {
    const conf = try s.call(try s.get(state, "getShellConfig"), c.pi_js_undefined(), &.{});
    const from_stdin = s.equal(try s.get(conf, "commandTransport"), try s.text("stdin"));
    const args = try s.get(conf, "args");
    const argv = if (from_stdin) args else try s.invoke(args, "concat", &.{command});
    const o = try options(s);
    try s.put(o, "input", if (from_stdin) command else c.pi_js_undefined());
    try s.put(o, "stdio", try stdio(s, if (from_stdin) "pipe" else "ignore"));
    try s.put(o, "shell", c.pi_js_bool(s.engine.context, 0));
    try s.put(o, "windowsHide", c.pi_js_bool(s.engine.context, 1));
    const result = try s.call(try s.get(state, "spawnSync"), c.pi_js_undefined(), &.{ try s.get(conf, "shell"), argv, o });
    const err = try s.get(result, "error");
    if (s.truthy(err)) return .{ .executed = !s.equal(try s.get(err, "code"), try s.text("ENOENT")), .value = c.pi_js_undefined() };
    if (!s.equal(try s.get(result, "status"), c.JS_NewInt32(s.engine.context, 0))) return .{ .executed = true, .value = c.pi_js_undefined() };
    const out = try s.get(result, "stdout");
    return .{ .executed = true, .value = try trim(s, if (sc.nullish(out)) try s.text("") else out) };
}
fn execute(s: *Scope, state: c.JSValue, config: c.JSValue, cached: bool) !c.JSValue {
    const cache = try s.get(state, "cache");
    if (cached and s.truthy(try s.invoke(cache, "has", &.{config}))) return s.invoke(cache, "get", &.{config});
    const command = try s.invoke(config, "slice", &.{c.JS_NewInt32(s.engine.context, 1)});
    var result = c.pi_js_undefined();
    if (s.equal(try s.get(try s.get(state, "process"), "platform"), try s.text("win32"))) {
        const configured = try configuredShell(s, state, command);
        result = if (configured.executed) configured.value else try defaultShell(s, state, command);
    } else result = try defaultShell(s, state, command);
    if (cached) _ = try s.invoke(cache, "set", &.{ config, result });
    return result;
}
fn resolve(s: *Scope, state: c.JSValue, config: c.JSValue, env: c.JSValue, cached: bool) !c.JSValue {
    const raw = try s.engine.toString(config);
    defer s.engine.gpa.free(raw);
    if (std.mem.startsWith(u8, raw, "!")) return execute(s, state, config, cached);
    var parts = try parse(s.engine.gpa, raw);
    defer parts.deinit(s.engine.gpa);
    var result = try s.text("");
    for (parts.items) |part| switch (part) {
        .literal => |v| result = try s.concat(result, try s.text(v)),
        .env => |name| {
            const v = try environment(s, state, env, try s.text(name));
            if (c.JS_IsUndefined(v)) return v;
            result = try s.concat(result, v);
        },
    };
    return result;
}
fn throwMessage(s: *Scope, message: c.JSValue) anyerror {
    const err = js.builtin(s.engine, "Error", &.{message}) catch |e| return e;
    _ = s.engine.checked(c.JS_Throw(s.engine.context, err)) catch |e| return e;
    unreachable;
}
fn orThrow(s: *Scope, state: c.JSValue, config: c.JSValue, description: c.JSValue, env: c.JSValue) !c.JSValue {
    const value = try resolve(s, state, config, env, false);
    if (!c.JS_IsUndefined(value)) return value;
    const raw = try s.engine.toString(config);
    defer s.engine.gpa.free(raw);
    var message = try s.concat(try s.text("Failed to resolve "), description);
    if (std.mem.startsWith(u8, raw, "!")) message = try s.concat(try s.concat(message, try s.text(" from shell command: ")), try s.text(raw[1..])) else {
        const absent = try missing(s, state, raw, env);
        const count = try length(s, absent);
        if (count > 0) message = try s.concat(try s.concat(message, try s.text(if (count == 1) " from environment variable: " else " from environment variables: ")), try s.invoke(absent, "join", &.{try s.text(", ")}));
    }
    return throwMessage(s, message);
}
const Op = enum { name, names, missing, command, configured, resolve, uncached, or_throw, headers, headers_throw, clear };
fn callback(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    var op_int: u32 = 0;
    if (c.JS_ToUint32(engine.context, &op_int, roots[1]) < 0) return js.capture(engine);
    const op: Op = @enumFromInt(op_int);
    const value = arg(args, 0);
    const env = arg(args, if (op == .or_throw or op == .headers_throw) 2 else 1);
    if (op == .clear) {
        _ = try s.invoke(try s.get(state, "cache"), "clear", &.{});
        return c.pi_js_undefined();
    }
    if (op == .headers or op == .headers_throw) {
        if (!s.truthy(value)) return c.pi_js_undefined();
        const entries = try s.own(try js.objectMethod(engine, "entries", value));
        const result = try s.object();
        for (0..try length(&s, entries)) |i| {
            const entry = try at(&s, entries, i);
            const key = try at(&s, entry, 0);
            const raw = try at(&s, entry, 1);
            const desc = if (op == .headers_throw) try s.concat(try s.concat(try s.concat(arg(args, 1), try s.text(" header \"")), key), try s.text("\"")) else c.pi_js_undefined();
            const resolved = if (op == .headers_throw) try orThrow(&s, state, raw, desc, env) else try resolve(&s, state, raw, env, true);
            if (op == .headers_throw or s.truthy(resolved)) try js.setKey(engine, result, key, resolved);
        }
        const keys = try s.own(try js.objectMethod(engine, "keys", result));
        return c.JS_DupValue(engine.context, if (try length(&s, keys) > 0) result else c.pi_js_undefined());
    }
    if (op == .resolve or op == .uncached or op == .or_throw) return c.JS_DupValue(engine.context, if (op == .or_throw) try orThrow(&s, state, value, arg(args, 1), env) else try resolve(&s, state, value, env, op == .resolve));
    const raw = try engine.toString(value);
    defer engine.gpa.free(raw);
    const result = switch (op) {
        .name => blk: {
            var parts = try parse(engine.gpa, raw);
            defer parts.deinit(engine.gpa);
            break :blk if (!std.mem.startsWith(u8, raw, "!") and parts.items.len == 1 and parts.items[0] == .env) try s.text(parts.items[0].env) else c.pi_js_undefined();
        },
        .names => try names(&s, raw),
        .missing => try missing(&s, state, raw, env),
        .command => c.pi_js_bool(engine.context, @intFromBool(std.mem.startsWith(u8, raw, "!"))),
        .configured => c.pi_js_bool(engine.context, @intFromBool(try length(&s, try missing(&s, state, raw, env)) == 0)),
        else => unreachable,
    };
    return c.JS_DupValue(engine.context, result);
}
pub fn install(engine: *em.Engine, namespace: c.JSValue, imports: Imports) !void {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    inline for (.{ "process", "getShellConfig", "spawnSync", "execSync" }) |field| try s.put(state, field, @field(imports, field));
    try s.put(state, "cache", try s.own(try js.builtin(engine, "Map", &.{})));
    inline for (.{ .{ "getConfigValueEnvVarName", Op.name, 1 }, .{ "getConfigValueEnvVarNames", Op.names, 1 }, .{ "getMissingConfigValueEnvVarNames", Op.missing, 2 }, .{ "isCommandConfigValue", Op.command, 1 }, .{ "isConfigValueConfigured", Op.configured, 2 }, .{ "resolveConfigValue", Op.resolve, 2 }, .{ "resolveConfigValueUncached", Op.uncached, 2 }, .{ "resolveConfigValueOrThrow", Op.or_throw, 3 }, .{ "resolveHeaders", Op.headers, 2 }, .{ "resolveHeadersOrThrow", Op.headers_throw, 3 }, .{ "clearConfigValueCache", Op.clear, 0 } }) |row| {
        const f = try s.own(try nf.create(engine, row[0], row[2], callback, &.{ state, c.JS_NewInt32(engine.context, @intFromEnum(row[1])) }));
        try s.put(namespace, row[0], f);
    }
}
