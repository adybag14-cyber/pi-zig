//! A real filesystem-backed ExecutionEnv component for native output files.
//! This deliberately supplies the file interface, not the complete Node env ABI.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Method = enum(c_int) { createTempDir, writeFile };
pub fn create(engine: *em.Engine, root_path: []const u8) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const environment = try scope.object();
    const root = try scope.text(root_path);
    try scope.put(environment, "cwd", root);
    var captures = [_]c.JSValue{root};
    inline for (std.meta.fields(Method)) |field| try scope.put(environment, field.name, try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, dispatch, field.name, if (field.value == 0) 2 else 3, @intCast(field.value), captures.len, &captures))));
    return c.JS_DupValue(engine.context, environment);
}
fn resolved(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var functions: [2]c.JSValue = undefined;
    const promise = try engine.checked(c.JS_NewPromiseCapability(engine.context, &functions));
    errdefer engine.freeValue(promise);
    defer engine.freeValue(functions[0]);
    defer engine.freeValue(functions[1]);
    var args = [_]c.JSValue{value};
    const ignored = try engine.checked(c.JS_Call(engine.context, functions[0], c.pi_js_undefined(), 1, &args));
    engine.freeValue(ignored);
    return promise;
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, raw: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return invoke(engine, captures[0], @enumFromInt(raw), args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn result(scope: *Scope, ok: bool, value: c.JSValue) !c.JSValue {
    const object = try scope.object();
    try scope.put(object, "ok", c.pi_js_bool(scope.engine.context, @intFromBool(ok)));
    try scope.put(object, if (ok) "value" else "error", value);
    return object;
}
fn fileError(scope: *Scope, kind: []const u8, message: []const u8, path: ?c.JSValue) !c.JSValue {
    const reason = try scope.own(try js.builtin(scope.engine, "Error", &.{try scope.text(message)}));
    try scope.put(reason, "name", try scope.text("FileError"));
    try scope.put(reason, "kind", try scope.text(kind));
    if (path) |value| try scope.put(reason, "path", value);
    return result(scope, false, reason);
}
fn invoke(engine: *em.Engine, root_value: c.JSValue, method: Method, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const io = engine.native_io orelse return error.NativeIoRequired;
    const context = if (method == .createTempDir) (if (args.len > 1) args[1] else c.pi_js_undefined()) else (if (args.len > 2) args[2] else c.pi_js_undefined());
    const signal = try scope.get(context, "abortSignal");
    if (!c.JS_IsUndefined(signal) and scope.truthy(try scope.get(signal, "aborted"))) return resolved(engine, try fileError(&scope, "aborted", "aborted", if (method == .writeFile and args.len > 0) args[0] else null));
    const root = try engine.toString(root_value);
    defer engine.gpa.free(root);
    if (method == .createTempDir) {
        const prefix = if (args.len == 0 or c.JS_IsUndefined(args[0]) or c.JS_IsNull(args[0])) try scope.text("tmp-") else args[0];
        const text = try engine.toString(prefix);
        defer engine.gpa.free(text);
        for (0..64) |_| {
            var nonce: [8]u8 = undefined;
            try std.Io.randomSecure(io, &nonce);
            const leaf = try std.fmt.allocPrint(engine.gpa, "{s}{x}", .{ text, std.mem.readInt(u64, &nonce, .little) });
            defer engine.gpa.free(leaf);
            const path = try std.fs.path.join(engine.gpa, &.{ root, leaf });
            defer engine.gpa.free(path);
            std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| {
                if (err == error.PathAlreadyExists) continue;
                return resolved(engine, try fileError(&scope, "unknown", @errorName(err), null));
            };
            return resolved(engine, try result(&scope, true, try scope.text(path)));
        }
        return resolved(engine, try fileError(&scope, "unknown", "Could not create a unique temporary directory", null));
    }
    if (args.len < 2) return error.MissingFileArguments;
    const given = try engine.toString(args[0]);
    defer engine.gpa.free(given);
    const path = try std.fs.path.resolve(engine.gpa, &.{ root, given });
    defer engine.gpa.free(path);
    const parent = std.fs.path.dirname(path) orelse root;
    std.Io.Dir.cwd().createDirPath(io, parent) catch |err| return resolved(engine, try fileError(&scope, "unknown", @errorName(err), args[0]));
    if (!c.JS_IsUndefined(signal) and scope.truthy(try scope.get(signal, "aborted"))) return resolved(engine, try fileError(&scope, "aborted", "aborted", args[0]));
    const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| return resolved(engine, try fileError(&scope, "unknown", @errorName(err), args[0]));
    defer file.close(io);
    if (c.JS_IsString(args[1])) {
        const text = try engine.toString(args[1]);
        defer engine.gpa.free(text);
        const bytes = try @import("node_buffer.zig").encodings.encode(engine.gpa, text, .utf8);
        defer engine.gpa.free(bytes);
        file.writePositionalAll(io, bytes, 0) catch |err| return resolved(engine, try fileError(&scope, "unknown", @errorName(err), args[0]));
    } else {
        var offset: usize = 0;
        var length: usize = 0;
        var element_bytes: usize = 0;
        var backing_length: usize = 0;
        const backing = try scope.own(try engine.checked(c.JS_GetTypedArrayBuffer(engine.context, args[1], &offset, &length, &element_bytes)));
        const bytes = c.JS_GetArrayBuffer(engine.context, &backing_length, backing);
        if (offset > backing_length or length > backing_length - offset or (bytes == null and length > 0)) return error.InvalidFileByteView;
        file.writePositionalAll(io, if (length == 0) &.{} else bytes[offset..][0..length], 0) catch |err| return resolved(engine, try fileError(&scope, "unknown", @errorName(err), args[0]));
    }
    return resolved(engine, try result(&scope, true, c.pi_js_undefined()));
}
