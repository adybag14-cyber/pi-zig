//! Owner-side normalization for real native child-process requests. This is
//! shared by Node's direct spawn and Source's Windows cross-spawn boundary.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const c = js.c;
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const transport = @import("native_child_process_transport.zig");
const kernel = @import("native_file_stat.zig");
const Environment = @import("native_child_process_environment.zig").Environment;
pub const Config = struct {
    gpa: std.mem.Allocator,
    argv: std.ArrayList([]const u8) = .empty,
    environment: Environment,
    cwd: ?[]u8 = null,
    original_file: []u8,
    executable: ?[]u8 = null,
    spawn_file: ?[]u8 = null,
    cross_missing: bool = false,
    cross_hook: bool = false,
    encoding: ?@import("binary_encoding.zig").Encoding = null,
    input: ?[]u8 = null,
    timeout_ms: ?u64 = null,
    max_buffer: usize = 1024 * 1024,
    options: transport.Options = .{},
    kill_force: bool = false,
    kill_number: i32 = 15,
    pub fn deinit(self: *Config) void {
        if (builtin.os.tag == .linux) for (&self.options.linux_stdio) |*lease| if (lease.*) |actual| {
            lease.* = null;
            // release records uncertain close in stable bounded native storage
            // before reporting failure; no numeric close retry or dropped fd.
            @import("native_child_process_stdio_linux.zig").release(actual) catch {};
        };
        if (builtin.os.tag == .windows) for (&self.options.windows_stdio) |*lease| if (lease.*) |actual| {
            lease.* = null;
            @import("native_child_process_stdio_windows.zig").release(actual) catch {};
        };
        for (self.argv.items) |value| self.gpa.free(value);
        self.argv.deinit(self.gpa);
        self.environment.deinit();
        if (self.cwd) |value| self.gpa.free(value);
        if (self.input) |value| self.gpa.free(value);
        self.gpa.free(self.original_file);
        if (self.executable) |value| self.gpa.free(value);
        if (self.spawn_file) |value| self.gpa.free(value);
    }
    pub fn append(self: *Config, value: []const u8) !void {
        const copy = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(copy);
        try self.argv.append(self.gpa, copy);
    }
};
pub fn arg(args: []const c.JSValue, index: usize) c.JSValue { return if (index < args.len) args[index] else c.pi_js_undefined(); }
fn nullish(value: c.JSValue) bool { return c.JS_IsNull(value) or c.JS_IsUndefined(value); }
fn option(scope: *Scope, object: c.JSValue, name: [*:0]const u8) !c.JSValue { return if (nullish(object)) c.pi_js_undefined() else scope.get(object, name); }
fn invalid(engine: *js.Engine, code: []const u8, message: []const u8) anyerror { return @import("node_events.zig").codedError(engine, "TypeError", code, message); }
pub fn nullCheck(scope: *Scope, value: c.JSValue, label: []const u8) !void {
    if (!c.JS_IsString(value)) return;
    const text = try scope.engine.toString(value);
    defer scope.engine.gpa.free(text);
    if (std.mem.indexOfScalar(u8, text, 0) == null) return;
    const inspected = try @import("node_event_inspect.zig").inspect(scope.engine, value, 2);
    defer scope.engine.gpa.free(inspected);
    const inspected_value = try scope.text(inspected);
    const units = try @import("native_utf16.zig").unitsAlloc(scope.engine, inspected_value);
    defer scope.engine.gpa.free(units);
    const selected = if (units.len > 128) try scope.invoke(inspected_value, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 128) }) else inspected_value;
    const received = try scope.engine.toString(selected);
    defer scope.engine.gpa.free(received);
    const message = try std.fmt.allocPrint(scope.engine.gpa, "The {s} '{s}' must be a string without null bytes. Received {s}{s}", .{ if (std.mem.indexOfScalar(u8, label, '.') != null) "property" else "argument", label, received, if (units.len > 128) "..." else "" });
    defer scope.engine.gpa.free(message);
    _ = try @import("node_fs_metadata.zig").throwTyped(scope.engine, "ERR_INVALID_ARG_VALUE", message);
}
fn snapshot(scope: *Scope, object: c.JSValue) !c.JSValue {
    var allocation = @import("native_node_operation_scope.zig").Scope.init(scope.engine);
    const produced: anyerror!c.JSValue = created: {
        const value = allocation.objectProto(c.pi_js_null()) catch |err| break :created err;
        break :created c.JS_DupValue(scope.engine.context, value);
    };
    const copy = try @import("native_sdk_owned_completion.zig").ownRoot(scope, try allocation.finish(produced));
    if (!nullish(object)) try js.spreadInto(scope.engine, copy, object);
    return copy;
}
pub fn enumerableKeys(scope: *Scope, object: c.JSValue) !c.JSValue {
    if (!c.JS_IsObject(object)) return scope.own(try js.objectMethod(scope.engine, "keys", object));
    const result = try scope.array();
    var seen: std.StringHashMap(void) = .init(scope.engine.gpa);
    defer { var iterator = seen.keyIterator(); while (iterator.next()) |key| scope.engine.gpa.free(key.*); seen.deinit(); }
    var current = object;
    while (!c.JS_IsNull(current)) {
        var names: [*c]c.JSPropertyEnum = null; var count: u32 = 0;
        if (c.JS_GetOwnPropertyNames(scope.engine.context, &names, &count, current, c.JS_GPN_STRING_MASK) < 0) return @as(anyerror!c.JSValue, js.capture(scope.engine));
        defer c.JS_FreePropertyEnum(scope.engine.context, names, count);
        for (0..count) |index| {
            const key = try scope.own(try scope.engine.checked(c.JS_AtomToValue(scope.engine.context, names[index].atom)));
            const text = try scope.engine.toString(key);
            if (seen.contains(text)) { scope.engine.gpa.free(text); continue; }
            var descriptor: c.JSPropertyDescriptor = undefined;
            const present = c.JS_GetOwnProperty(scope.engine.context, &descriptor, current, names[index].atom);
            if (present < 0) { scope.engine.gpa.free(text); return @as(anyerror!c.JSValue, js.capture(scope.engine)); }
            if (present == 0) { scope.engine.gpa.free(text); continue; }
            defer { scope.engine.freeValue(descriptor.value); scope.engine.freeValue(descriptor.getter); scope.engine.freeValue(descriptor.setter); }
            seen.put(text, {}) catch |err| { scope.engine.gpa.free(text); return err; };
            if (descriptor.flags & c.JS_PROP_ENUMERABLE != 0) try js.push(scope.engine, result, key);
        }
        current = try scope.own(try scope.engine.checked(c.JS_GetPrototype(scope.engine.context, current)));
    }
    return result;
}
fn validatedText(engine: *js.Engine, value: c.JSValue, name: []const u8, stringify: bool) ![]u8 {
    if (!stringify and !c.JS_IsString(value)) return @as(anyerror![]u8, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process file must be a string"));
    const text = try engine.toString(value);
    errdefer engine.gpa.free(text);
    if (std.mem.indexOfScalar(u8, text, 0) != null) {
        const message = try std.fmt.allocPrint(engine.gpa, "The argument '{s}' must be a string without null bytes", .{name});
        defer engine.gpa.free(message);
        return @as(anyerror![]u8, invalid(engine, "ERR_INVALID_ARG_VALUE", message));
    }
    return text;
}
fn envMap(scope: *Scope, object: c.JSValue) !Environment {
    var result: Environment = .init(scope.engine.gpa);
    errdefer result.deinit();
    const keys = try enumerableKeys(scope, object);
    if (builtin.os.tag == .windows) _ = try scope.invoke(keys, "sort", &.{});
    var folded_names: std.ArrayList([]u8) = .empty;
    defer { for (folded_names.items) |name| scope.engine.gpa.free(name); folded_names.deinit(scope.engine.gpa); }
    var count: u32 = 0;
    if (c.JS_ToUint32(scope.engine.context, &count, try scope.get(keys, "length")) < 0) return @as(anyerror!Environment, js.capture(scope.engine));
    for (0..count) |index| {
        const key = try scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, keys, @intCast(index))));
        const name = try scope.engine.toString(key);
        defer scope.engine.gpa.free(name);
        if (builtin.os.tag == .windows) {
            const folded = try scope.engine.toString(try scope.invoke(key, "toUpperCase", &.{}));
            var duplicate = false;
            for (folded_names.items) |seen| if (std.mem.eql(u8, seen, folded)) { duplicate = true; break; };
            if (duplicate) { scope.engine.gpa.free(folded); continue; }
            folded_names.append(scope.engine.gpa, folded) catch |err| { scope.engine.gpa.free(folded); return err; };
        }
        const value = try scope.own(try js.getKey(scope.engine, object, key));
        if (c.JS_IsUndefined(value)) continue;
        const label = try std.fmt.allocPrint(scope.engine.gpa, "options.env['{s}']", .{name});
        defer scope.engine.gpa.free(label);
        try nullCheck(scope, key, label);
        try nullCheck(scope, value, label);
        const text = try scope.engine.toString(value);
        defer scope.engine.gpa.free(text);
        try result.append(name, text);
    }
    return result;
}
fn envValue(env: *const Environment, name: []const u8) ?[]const u8 { return env.get(name); }
fn existing(gpa: std.mem.Allocator, path: []const u8) !bool {
    const info = kernel.read(gpa, path) catch |err| { if (err == error.OutOfMemory) return err; return false; };
    return info.mode & 0o170000 == 0o100000;
}
pub fn resolved(gpa: std.mem.Allocator, cwd: []const u8, path: []const u8) ![]u8 {
    return @import("node_path.zig").resolve(gpa, cwd, &.{path}, if (builtin.os.tag == .windows) .win32 else .posix);
}
fn findExecutable(config: *Config, command: []const u8, cwd: []const u8, cross_spawn: bool) ![]u8 { return (try findExecutableFound(config, command, cwd, cross_spawn)) orelse try config.gpa.dupe(u8, command); }
pub fn findExecutableFound(config: *Config, command: []const u8, cwd: []const u8, cross_spawn: bool) !?[]u8 {
    const gpa = config.gpa;
    const contains_separator = std.mem.indexOfAny(u8, command, if (builtin.os.tag == .windows) "/\\" else "/") != null;
    var directories: std.ArrayList([]const u8) = .empty;
    defer directories.deinit(gpa);
    if (builtin.os.tag == .windows or contains_separator) try directories.append(gpa, cwd);
    if (!contains_separator) {
        var paths = std.mem.splitScalar(u8, envValue(&config.environment, "PATH") orelse if (builtin.os.tag == .windows) "" else "/usr/bin:/bin", if (builtin.os.tag == .windows) ';' else ':');
        while (paths.next()) |path| try directories.append(gpa, if (path.len == 0) cwd else path);
    }
    for (directories.items) |directory| {
        const base = try resolved(gpa, cwd, directory);
        defer gpa.free(base);
        const candidate = try resolved(gpa, base, command);
        defer gpa.free(candidate);
        if (try existing(gpa, candidate)) return try gpa.dupe(u8, candidate);
        if (builtin.os.tag == .windows and std.fs.path.extension(command).len == 0) {
            var extensions = std.mem.splitScalar(u8, if (cross_spawn) envValue(&config.environment, "PATHEXT") orelse ".COM;.EXE;.BAT;.CMD" else ".com;.exe", ';');
            while (extensions.next()) |extension| {
                const suffixed = try std.mem.concat(gpa, u8, &.{ candidate, extension });
                if (try existing(gpa, suffixed)) return suffixed;
                gpa.free(suffixed);
            }
        }
    }
    return null;
}
fn meta(byte: u8) bool { return std.mem.indexOfScalar(u8, "()[]%!^\"`<>&|;, *?", byte) != null; }
fn escapeMeta(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(gpa);
    for (bytes) |byte| { if (meta(byte)) try result.append(gpa, '^'); try result.append(gpa, byte); }
    return result.toOwnedSlice(gpa);
}
fn escapeArgument(gpa: std.mem.Allocator, bytes: []const u8, twice: bool) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gpa);
    try result.append(gpa, '"');
    var slashes: usize = 0;
    for (bytes) |byte| {
        if (byte == '\\') { slashes += 1; continue; }
        for (0..if (byte == '"') slashes * 2 + 1 else slashes) |_| try result.append(gpa, '\\');
        slashes = 0;
        try result.append(gpa, byte);
    }
    for (0..slashes * 2) |_| try result.append(gpa, '\\');
    try result.append(gpa, '"');
    const escaped = try escapeMeta(gpa, result.items);
    if (!twice) return escaped;
    defer gpa.free(escaped);
    return escapeMeta(gpa, escaped);
}
fn useShell(config: *Config, shell: []const u8, command: []const u8, windows_cmd: bool) !void {
    for (config.argv.items) |value| config.gpa.free(value);
    config.argv.clearRetainingCapacity();
    try config.append(shell);
    if (windows_cmd) {
        try config.append("/d"); try config.append("/s"); try config.append("/c");
        const quoted = try std.fmt.allocPrint(config.gpa, "\"{s}\"", .{command});
        defer config.gpa.free(quoted);
        try config.append(quoted);
        config.options.windows_verbatim_arguments = true;
    } else { try config.append("-c"); try config.append(command); }
}
pub const PublicOptions = struct { config: Config, signal: c.JSValue, kill_signal: c.JSValue, original_args: c.JSValue };
pub fn normalize(engine: *js.Engine, args: []const c.JSValue, exec: bool, cross_spawn: bool) !Config { return normalizeInto(engine, args, exec, cross_spawn, null, null, null); }
/// Retain VM-only options from the SAME Source shallow snapshot. They never
/// enter Config/native workers, and original getters are not evaluated twice.
pub fn normalizePublic(engine: *js.Engine, args: []const c.JSValue, cross_spawn: bool, actual_process: c.JSValue, array_slice: c.JSValue) !PublicOptions {
    var scope: Scope = .{ .engine = engine }; defer scope.deinit();
    var values = [_]c.JSValue{ c.pi_js_undefined(), c.pi_js_undefined(), c.pi_js_undefined() };
    errdefer for (values) |value| engine.freeValue(value);
    var call_args = [_]c.JSValue{ arg(args, 0), arg(args, 1), arg(args, 2) };
    if (cross_spawn) {
        // Actual cross-spawn parse: args.slice(0) precedes Object.assign and
        // Node validation. Unlike Node's clone, this is deliberately live slice.
        if (scope.truthy(call_args[1]) and !c.JS_IsArray(call_args[1])) { call_args[2] = call_args[1]; call_args[1] = c.pi_js_null(); }
        call_args[1] = if (scope.truthy(call_args[1])) try scope.invoke(call_args[1], "slice", &.{c.JS_NewInt32(engine.context, 0)}) else try scope.array();
        const object = try scope.global("Object");
        call_args[2] = try scope.invoke(object, "assign", &.{ try scope.object(), call_args[2] });
        values[2] = c.JS_DupValue(engine.context, call_args[1]);
    }
    const config = try normalizeInto(engine, &call_args, false, cross_spawn, &values, actual_process, array_slice);
    return .{ .config = config, .signal = values[0], .kill_signal = values[1], .original_args = values[2] };
}
fn normalizeInto(engine: *js.Engine, args: []const c.JSValue, exec: bool, cross_spawn: bool, public_values: ?*[3]c.JSValue, actual_process: ?c.JSValue, array_slice: ?c.JSValue) !Config {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const file = try validatedText(engine, arg(args, 0), if (exec) "command" else "file", false);
    var config: Config = .{ .gpa = engine.gpa, .environment = .init(engine.gpa), .original_file = file };
    config.cross_hook = public_values != null and cross_spawn and builtin.os.tag == .windows;
    // parse() leaves parsed.file undefined on the explicit shell path.
    config.cross_missing = config.cross_hook;
    errdefer config.deinit();
    if (file.len == 0) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_VALUE", "The argument 'file' cannot be empty. Received ''"));
    try config.append(file);
    var options = arg(args, if (exec) 1 else 2);
    var supplied_args = if (exec) c.pi_js_undefined() else arg(args, 1);
    if (!exec and !nullish(supplied_args) and !c.JS_IsArray(supplied_args)) {
        if (public_values != null and (!c.JS_IsObject(supplied_args) or c.JS_IsFunction(engine.context, supplied_args))) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process args must be an object"));
        options = supplied_args; supplied_args = c.pi_js_undefined();
    }
    if (public_values != null and c.JS_IsArray(supplied_args)) supplied_args = try scope.call(array_slice.?, supplied_args, &.{});
    if (public_values == null) {
        if (!c.JS_IsUndefined(options) and (!c.JS_IsObject(options) and !exec)) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process options must be an object"));
        options = try snapshot(&scope, options);
    }
    if (!nullish(supplied_args)) {
        var length: u32 = 0;
        if (c.JS_ToUint32(engine.context, &length, try scope.get(supplied_args, "length")) < 0) return @as(anyerror!Config, js.capture(engine));
        for (0..length) |index| {
            const value = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, supplied_args, @intCast(index))));
            const text = try validatedText(engine, value, "args", true);
            defer engine.gpa.free(text);
            try config.append(text);
        }
    }
    if (public_values) |values| {
        if (!c.JS_IsUndefined(options) and (!c.JS_IsObject(options) or c.JS_IsNull(options) or c.JS_IsFunction(engine.context, options))) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process options must be an object"));
        options = try snapshot(&scope, options);
        values[0] = c.JS_DupValue(engine.context, try scope.get(options, "signal"));
        values[1] = c.JS_DupValue(engine.context, try scope.get(options, "killSignal"));
    }
    const process = actual_process orelse try scope.global("process");
    const current = if (public_values != null) try std.process.currentPathAlloc(engine.native_io orelse return error.NativeIoUnavailable, engine.gpa) else try engine.toString(try scope.invoke(process, "cwd", &.{}));
    defer engine.gpa.free(current);
    const cwd = try option(&scope, options, "cwd");
    if (!nullish(cwd)) {
        const path = try @import("node_fs_metadata.zig").pathTextNamed(engine, cwd, false, "options.cwd");
        defer engine.gpa.free(path);
        config.cwd = try resolved(engine.gpa, current, path);
    }
    if (public_values != null) {
        const detached = try option(&scope, options, "detached");
        if (!nullish(detached) and !c.JS_IsBool(detached)) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "The options.detached property must be a boolean"));
        inline for (.{ "uid", "gid" }) |name| {
            const credential = try option(&scope, options, name);
            if (!nullish(credential)) {
                var number: f64 = 0;
                if (!c.JS_IsNumber(credential) or c.JS_ToFloat64(engine.context, &number, credential) < 0 or !std.math.isFinite(number) or @trunc(number) != number or number < std.math.minInt(i32) or number > std.math.maxInt(i32)) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process uid/gid must be int32"));
            }
        }
    }
    // Node snapshots the options first, validates shell before enumerating the
    // environment, and performs the NUL check only on a string shell value.
    const shell_value = try option(&scope, options, "shell");
    if (!nullish(shell_value) and !c.JS_IsBool(shell_value) and !c.JS_IsString(shell_value)) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "The options.shell property must be a boolean or string"));
    if (public_values != null) {
        const argv0 = try option(&scope, options, "argv0");
        if (!nullish(argv0)) { const checked = try validatedText(engine, argv0, "options.argv0", false); engine.gpa.free(checked); }
        inline for (.{ "windowsHide", "windowsVerbatimArguments" }) |name| {
            const flag = try option(&scope, options, name);
            if (!nullish(flag) and !c.JS_IsBool(flag)) return @as(anyerror!Config, invalid(engine, "ERR_INVALID_ARG_TYPE", "Child process Windows flags must be boolean"));
        }
    }
    if (exec or scope.truthy(shell_value)) try nullCheck(&scope, shell_value, "options.shell");
    if (public_values != null and (!nullish(try option(&scope, options, "uid")) or !nullish(try option(&scope, options, "gid")))) return error.RequiredNativeChildCredentialRouting;
    const env = try option(&scope, options, "env");
    const replacement_environment = try envMap(&scope, if (!scope.truthy(env)) try snapshot(&scope, try scope.get(process, "env")) else env);
    config.environment.deinit();
    config.environment = replacement_environment;
    const encoding = try option(&scope, options, "encoding");
    if (public_values == null and !nullish(encoding)) {
        const name = try engine.toString(encoding);
        defer engine.gpa.free(name);
        if (!std.mem.eql(u8, name, "buffer")) config.encoding = @import("binary_encoding.zig").parse(name) orelse return error.UnsupportedNativeChildEncoding;
    }
    const timeout = try option(&scope, options, "timeout");
    if (!nullish(timeout)) {
        var numeric: f64 = 0;
        if (!c.JS_IsNumber(timeout) or c.JS_ToFloat64(engine.context, &numeric, timeout) < 0 or !std.math.isFinite(numeric) or numeric < 0 or numeric > 9007199254740991 or @trunc(numeric) != numeric) return @as(anyerror!Config, invalid(engine, "ERR_OUT_OF_RANGE", "Child process timeout must be a nonnegative safe integer"));
        if (numeric > 0) config.timeout_ms = @intFromFloat(numeric);
    }
    const maximum = try option(&scope, options, "maxBuffer");
    if (public_values == null and !nullish(maximum)) { var numeric: f64 = 0; if (c.JS_ToFloat64(engine.context, &numeric, maximum) < 0 or !std.math.isFinite(numeric) or numeric < 0 or numeric > 9007199254740991) return error.InvalidNativeChildMaxBuffer; config.max_buffer = @intFromFloat(numeric); }
    const kill_signal = try option(&scope, options, "killSignal");
    if (public_values == null and !nullish(kill_signal)) {
        const name = try engine.toString(kill_signal); defer engine.gpa.free(name);
        if (std.mem.eql(u8, name, "SIGKILL") or std.mem.eql(u8, name, "9")) config.kill_force = true else if (!std.mem.eql(u8, name, "SIGTERM") and !std.mem.eql(u8, name, "15")) return error.UnsupportedNativeChildKillSignal;
        config.kill_number = if (config.kill_force) 9 else 15;
    }
    config.options.windows_hide = scope.truthy(try option(&scope, options, "windowsHide"));
    config.options.detached = scope.truthy(try option(&scope, options, "detached"));
    config.options.windows_verbatim_arguments = scope.truthy(try option(&scope, options, "windowsVerbatimArguments"));
    const stdio = try option(&scope, options, "stdio");
    for (&config.options.stdio, 0..) |*slot, index| {
        const value = if (c.JS_IsArray(stdio)) try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, stdio, @intCast(index)))) else stdio;
        if (nullish(value)) continue;
        const name = try engine.toString(value);
        defer engine.gpa.free(name);
        slot.* = if (std.mem.eql(u8, name, "pipe")) .pipe else if (std.mem.eql(u8, name, "ignore")) .ignore else return error.NativeInheritedStdioRequiresFrontendRouting;
    }
    const input = try option(&scope, options, "input");
    if (public_values == null and !nullish(input)) {
        if (c.JS_IsString(input)) {
            const text = try engine.toString(input); defer engine.gpa.free(text);
            config.input = try @import("binary_encoding.zig").encode(engine.gpa, text, config.encoding orelse .utf8);
        } else {
            var offset: usize = 0; var length: usize = 0; var element: usize = 0;
            const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, input, &offset, &length, &element)));
            var total: usize = 0; const bytes = c.JS_GetArrayBuffer(engine.context, &total, backing);
            if (offset > total or length > total - offset or (bytes == null and length != 0)) return error.InvalidNativeChildInput;
            config.input = try engine.gpa.dupe(u8, if (length == 0) &.{} else bytes[offset .. offset + length]);
        }
    }
    if (exec or scope.truthy(shell_value)) {
        const joined = try std.mem.join(engine.gpa, " ", config.argv.items); defer engine.gpa.free(joined);
        const custom_shell = if (c.JS_IsString(shell_value)) try validatedText(engine, shell_value, "options.shell", false) else null; defer if (custom_shell) |text| engine.gpa.free(text);
        const shell = custom_shell orelse if (builtin.os.tag == .windows) envValue(&config.environment, "ComSpec") orelse "cmd.exe" else "/bin/sh";
        try useShell(&config, shell, joined, builtin.os.tag == .windows and std.ascii.endsWithIgnoreCase(shell, "cmd.exe"));
    } else if (cross_spawn and builtin.os.tag == .windows) {
        const target: ?[]u8 = if (public_values != null) try findExecutableFound(&config, file, config.cwd orelse current, true) else try findExecutable(&config, file, config.cwd orelse current, true);
        if (public_values != null) config.cross_missing = target == null;
        defer if (target) |value| engine.gpa.free(value);
        if (target == null or (!std.ascii.endsWithIgnoreCase(target.?, ".exe") and !std.ascii.endsWithIgnoreCase(target.?, ".com"))) {
            const normalized = try @import("node_path.zig").normalize(engine.gpa, file, .win32); defer engine.gpa.free(normalized);
            var command: std.ArrayList(u8) = .empty; defer command.deinit(engine.gpa);
            const escaped = try escapeMeta(engine.gpa, normalized); defer engine.gpa.free(escaped); try command.appendSlice(engine.gpa, escaped);
            const twice = target != null and std.mem.indexOf(u8, target.?, "node_modules\\.bin\\") != null and std.ascii.endsWithIgnoreCase(target.?, ".cmd");
            for (config.argv.items[1..]) |value| { const escaped_arg = try escapeArgument(engine.gpa, value, twice); defer engine.gpa.free(escaped_arg); try command.append(engine.gpa, ' '); try command.appendSlice(engine.gpa, escaped_arg); }
            try useShell(&config, envValue(&config.environment, "ComSpec") orelse "cmd.exe", command.items, true);
        }
    }
    if (public_values != null) {
        config.spawn_file = try engine.gpa.dupe(u8, config.argv.items[0]);
        config.executable = (try findExecutableFound(&config, config.argv.items[0], config.cwd orelse current, cross_spawn)) orelse try resolved(engine.gpa, config.cwd orelse current, config.argv.items[0]);
        config.options.executable = config.executable;
        const argv0 = try option(&scope, options, "argv0");
        if (!nullish(argv0)) {
            const custom = try validatedText(engine, argv0, "options.argv0", false);
            engine.gpa.free(config.argv.items[0]); config.argv.items[0] = custom;
        }
    } else {
        const executable = try findExecutable(&config, config.argv.items[0], config.cwd orelse current, cross_spawn);
        engine.gpa.free(config.argv.items[0]); config.argv.items[0] = executable;
    }
    return config;
}
