//! Source1692 processLock backed by an exclusive kernel pipe/socket, retained until release or engine shutdown.
const std = @import("std");
const builtin = @import("builtin");
const r = @import("native_chord_reload_values.zig");
const h = r.h;
const c = h.c;
const js = h.js;
const Kernel = extern struct { handle: isize = -1, file: c_int = 0, path: [104]u8 = @splat(0) };
extern "c" fn pi_chord_lock_acquire(*Kernel, [*:0]const u8, [*:0]const u8, *c_ulong) c_int;
extern "c" fn pi_chord_lock_release(*Kernel) c_int;
const Owner = struct { engine: *h.Engine, kernel: Kernel = .{}, active: bool = false };
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const owner: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (owner.active) _ = pi_chord_lock_release(&owner.kernel);
    owner.engine.gpa.destroy(owner);
}
fn releaseCallback(ctx: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue, _: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = h.Engine.fromContext(ctx.?);
    const value = release(engine, captures[0]) catch |err| return @import("native_durable.zig").rejectedPromise(engine, err);
    defer engine.freeValue(value);
    return h.resolved(engine, value) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn release(engine: *h.Engine, value: c.JSValue) !c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const owner: *Owner = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
    if (!owner.active) {
        const failure = try s.keep(try js.builtin(engine, "Error", &.{try s.text("Server is not running.")}));
        try h.field(&s, failure, "code", try s.text("ERR_SERVER_NOT_RUNNING"));
        return h.throwValue(&s, failure);
    }
    const error_code = pi_chord_lock_release(&owner.kernel);
    owner.active = false;
    _ = try h.invoke(&s, engine.native_chord_process_locks.?, "delete", &.{value});
    if (error_code != 0) return h.ordinaryError(&s, &.{ try s.text("Native kernel lock close failed: "), c.JS_NewInt32(engine.context, error_code) });
    return c.pi_js_undefined();
}
pub fn acquire(engine: *h.Engine, bindings: c.JSValue, name: c.JSValue) anyerror!c.JSValue {
    var s: h.Scope = .{ .engine = engine };
    defer s.deinit();
    const bytes = try engine.toString(name);
    defer engine.gpa.free(bytes);
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    const key = std.fmt.bytesToHex(digest, .lower);
    const key_z = try engine.gpa.dupeZ(u8, key[0..32]);
    defer engine.gpa.free(key_z);
    var temporary: []const u8 = "/tmp";
    var owned_temporary: ?[]u8 = null;
    defer if (owned_temporary) |value| engine.gpa.free(value);
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) {
        const process = try s.keep(try js.global(engine, "process"));
        const environment = if (h.nullish(process)) c.pi_js_undefined() else try s.get(process, "env");
        inline for (.{ "TMPDIR", "TMP", "TEMP" }) |environment_key| {
            if (owned_temporary == null) {
                const value = if (h.nullish(environment)) c.pi_js_undefined() else try s.get(environment, environment_key);
                if (c.JS_ToBool(engine.context, value) != 0) {
                    owned_temporary = try engine.toString(value);
                } else if (h.nullish(environment)) {
                    if (std.c.getenv(environment_key)) |bytes_value| if (bytes_value[0] != 0) {
                        owned_temporary = try engine.gpa.dupe(u8, std.mem.span(bytes_value));
                    };
                }
            }
        }
        if (owned_temporary) |value| temporary = value;
        if (temporary.len > 1 and temporary[temporary.len - 1] == '/') temporary = temporary[0 .. temporary.len - 1];
    }
    const temporary_z = try engine.gpa.dupeZ(u8, temporary);
    defer engine.gpa.free(temporary_z);
    if (engine.native_chord_process_locks == null) engine.native_chord_process_locks = try js.builtin(engine, "Set", &.{});
    var identifier: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &identifier);
    const definition: c.JSClassDef = .{ .class_name = "NativeChordKernelLock", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, identifier, &definition) < 0) return error.OutOfMemory;
    const value = try s.keep(try engine.checked(c.JS_NewObjectClass(engine.context, identifier)));
    const owner = try engine.gpa.create(Owner);
    owner.* = .{ .engine = engine };
    _ = c.JS_SetOpaque(value, owner);
    var captures = [_]c.JSValue{value};
    const callback = try s.keep(try engine.checked(c.JS_NewCFunctionData2(engine.context, releaseCallback, "", 0, 0, 1, &captures)));
    var system_error: c_ulong = 0;
    switch (pi_chord_lock_acquire(&owner.kernel, key_z, temporary_z, &system_error)) {
        0 => {},
        1 => return h.throwValue(&s, try h.errorValue(&s, bindings, "unavailable", &.{ try s.text("lock "), name, try s.text(" is held by another process") }, try r.reason(&s, "locked"))),
        2 => return h.throwValue(&s, try h.errorValue(&s, bindings, "unavailable", &.{ try s.text("lock directory "), try s.text(std.mem.sliceTo(&owner.kernel.path, 0)), try s.text(" must be a directory only its owner can access") }, c.pi_js_undefined())),
        else => return h.ordinaryError(&s, &.{ try s.text("Native kernel lock acquisition failed: "), c.JS_NewInt64(engine.context, @intCast(system_error)) }),
    }
    owner.active = true;
    errdefer {
        if (owner.active) {
            _ = pi_chord_lock_release(&owner.kernel);
            owner.active = false;
        }
    }
    _ = try h.invoke(&s, engine.native_chord_process_locks.?, "add", &.{value});
    return h.resolved(engine, callback);
}
