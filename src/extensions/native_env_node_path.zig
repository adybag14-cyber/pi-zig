//! Original NodeExecutionEnv local path rules, including the platform's home and temp queries.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = js.c;
extern "c" fn _NSGetEnviron() *[*:null]?[*:0]u8;
pub fn environment(gpa: std.mem.Allocator) !std.process.Environ.Map {
    if (builtin.os.tag == .windows) return (std.process.Environ{ .block = .global }).createMap(gpa);
    const variables = if (builtin.os.tag.isDarwin()) _NSGetEnviron().* else std.c.environ;
    return (std.process.Environ{ .block = .{ .slice = std.mem.span(variables) } }).createMap(gpa);
}
fn environmentValue(scope: *Scope, comptime name: []const u8) !?c.JSValue {
    if (builtin.os.tag == .windows) {
        const value = std.process.Environ.getWindows(.{ .block = .global }, std.unicode.utf8ToUtf16LeStringLiteral(name)) orelse return null;
        return try scope.own(try scope.engine.checked(c.JS_NewStringUTF16(scope.engine.context, value.ptr, value.len)));
    }
    var inherited = try environment(scope.engine.gpa);
    defer inherited.deinit();
    return if (inherited.get(name)) |value| try scope.text(value) else null;
}
fn systemAlias(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, kind: c_int) callconv(.c) c.JSValue {
    const engine = js.Engine.fromContext(context.?);
    const info = c.JS_GetPropertyStr(engine.context, receiver, "info");
    if (c.JS_IsException(info)) return info;
    defer engine.freeValue(info);
    const key: [*:0]const u8 = if (kind < 2) "errno" else "syscall";
    if (@mod(kind, 2) == 0) return c.JS_GetPropertyStr(engine.context, info, key);
    if (c.JS_SetPropertyStr(engine.context, info, key, c.JS_DupValue(engine.context, if (argc > 0) argv[0] else c.pi_js_undefined())) < 0) return c.JS_Throw(engine.context, c.JS_GetException(engine.context));
    return c.pi_js_undefined();
}
fn missingHome(scope: *Scope) anyerror {
    const engine = scope.engine;
    const value = scope.own(engine.checked(c.JS_NewError(engine.context)) catch |err| return err) catch |err| return err;
    scope.put(value, "code", scope.text("ERR_SYSTEM_ERROR") catch |err| return err) catch |err| return err;
    inline for (.{ .{ "name", "SystemError" }, .{ "message", "A system error occurred: uv_os_homedir returned ENOENT (no such file or directory)" } }) |entry| if (c.JS_DefinePropertyValueStr(engine.context, value, entry[0], c.JS_DupValue(engine.context, scope.text(entry[1]) catch |err| return err), c.JS_PROP_CONFIGURABLE | c.JS_PROP_WRITABLE) < 0) return js.capture(engine);
    const info = scope.object() catch |err| return err;
    scope.put(info, "errno", c.JS_NewInt32(engine.context, if (builtin.os.tag == .windows) -4058 else -2)) catch |err| return err;
    inline for (.{ .{ "code", "ENOENT" }, .{ "message", "no such file or directory" }, .{ "syscall", "uv_os_homedir" } }) |entry| scope.put(info, entry[0], scope.text(entry[1]) catch |err| return err) catch |err| return err;
    if (c.JS_DefinePropertyValueStr(engine.context, value, "info", c.JS_DupValue(engine.context, info), c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    inline for (.{ "errno", "syscall" }, 0..) |key, index| {
        const atom = c.JS_NewAtom(engine.context, key);
        defer c.JS_FreeAtom(engine.context, atom);
        const getter = engine.checked(c.JS_NewCFunctionMagic(engine.context, systemAlias, "get", 0, c.JS_CFUNC_generic_magic, @intCast(index * 2))) catch |err| return err;
        const setter = engine.checked(c.JS_NewCFunctionMagic(engine.context, systemAlias, "set", 1, c.JS_CFUNC_generic_magic, @intCast(index * 2 + 1))) catch |err| {
            engine.freeValue(getter);
            return err;
        };
        if (c.JS_DefinePropertyGetSet(engine.context, value, atom, getter, setter, c.JS_PROP_CONFIGURABLE | c.JS_PROP_ENUMERABLE) < 0) return js.capture(engine);
    }
    _ = c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value));
    return js.capture(engine);
}
pub fn home(scope: *Scope) !c.JSValue {
    if (builtin.os.tag == .windows) {
        if (try environmentValue(scope, "USERPROFILE")) |value| {
            if (scope.equal(try scope.get(value, "length"), c.JS_NewInt32(scope.engine.context, 0))) return missingHome(scope);
            return value;
        }
        const windows = std.os.windows;
        const Native = struct {
            extern "advapi32" fn OpenProcessToken(windows.HANDLE, u32, *windows.HANDLE) callconv(.winapi) windows.BOOL;
            extern "userenv" fn GetUserProfileDirectoryW(windows.HANDLE, ?[*]u16, *u32) callconv(.winapi) windows.BOOL;
        };
        var token: windows.HANDLE = undefined;
        if (Native.OpenProcessToken(windows.GetCurrentProcess(), 8, &token) == 0) return missingHome(scope);
        defer windows.CloseHandle(token);
        var count: u32 = 0;
        _ = Native.GetUserProfileDirectoryW(token, null, &count);
        if (count == 0) return missingHome(scope);
        const buffer = try scope.engine.gpa.alloc(u16, count);
        defer scope.engine.gpa.free(buffer);
        if (Native.GetUserProfileDirectoryW(token, buffer.ptr, &count) == 0 or count == 0) return missingHome(scope);
        return scope.own(try scope.engine.checked(c.JS_NewStringUTF16(scope.engine.context, buffer.ptr, count - 1)));
    }
    if (try environmentValue(scope, "HOME")) |value| return value;
    const entry = std.c.getpwuid(std.c.getuid()) orelse return missingHome(scope);
    return scope.text(std.mem.span(entry.pw_dir));
}
pub fn temporary(scope: *Scope) !c.JSValue {
    var value: ?c.JSValue = null;
    inline for (if (builtin.os.tag == .windows) .{ "TEMP", "TMP" } else .{ "TMPDIR", "TMP", "TEMP" }) |name| {
        if (value == null) if (try environmentValue(scope, name)) |given| {
            if (scope.truthy(given)) value = given;
        };
    }
    const chosen = value orelse if (builtin.os.tag == .windows) fallback: {
        const root = try environmentValue(scope, "SystemRoot");
        const system = if (root != null and scope.truthy(root.?)) root.? else (try environmentValue(scope, "windir")) orelse c.pi_js_undefined();
        break :fallback try scope.concat(system, try scope.text("\\temp"));
    } else try scope.text("/tmp");
    const length = try scope.get(chosen, "length");
    const beyond = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 6, length, c.JS_NewInt32(scope.engine.context, 1))));
    const ending = try scope.invoke(chosen, "endsWith", &.{try scope.text(if (builtin.os.tag == .windows) "\\" else "/")});
    if (scope.truthy(beyond) and scope.truthy(ending)) {
        if (builtin.os.tag == .windows) {
            const before = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, length, c.JS_NewInt32(scope.engine.context, 2))));
            if (scope.equal(try scope.own(try js.getKey(scope.engine, chosen, before)), try scope.text(":"))) return chosen;
        }
        return scope.invoke(chosen, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, -1) });
    }
    return chosen;
}
pub fn resolve(scope: *Scope, bindings: c.JSValue, cwd: c.JSValue, input: c.JSValue) !c.JSValue {
    const paths = try scope.get(bindings, "paths");
    var normalized = input;
    if (scope.equal(normalized, try scope.text("~"))) normalized = try home(scope) else if (scope.truthy(try scope.invoke(normalized, "startsWith", &.{try scope.text("~/")})) or (builtin.os.tag == .windows and scope.truthy(try scope.invoke(normalized, "startsWith", &.{try scope.text("~\\")})))) {
        normalized = try scope.invoke(paths, "join", &.{ try home(scope), try scope.invoke(normalized, "slice", &.{c.JS_NewInt32(scope.engine.context, 2)}) });
    } else if (scope.truthy(try scope.invoke(normalized, "startsWith", &.{try scope.text("file://")}))) {
        normalized = scope.call(try scope.get(bindings, "fileURLToPath"), c.pi_js_undefined(), &.{normalized}) catch |err| ignored: {
            if (err != error.JavaScriptException) return err;
            if (scope.engine.captured_exception) |reason| scope.engine.freeValue(reason);
            scope.engine.captured_exception = null;
            break :ignored input;
        };
    }
    return if (scope.truthy(try scope.invoke(paths, "isAbsolute", &.{normalized}))) scope.invoke(paths, "resolve", &.{normalized}) else scope.invoke(paths, "resolve", &.{ cwd, normalized });
}
