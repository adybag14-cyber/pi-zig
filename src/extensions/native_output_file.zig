//! Private streamed-output lease. Writes retain the exclusive original file
//! handle, so later path replacement cannot redirect subsequent chunks.
const std = @import("std");
const em = @import("engine.zig");
const c = em.c;
const Lease = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    position: u64 = 0,
    closed: bool = false,
};
fn state(value: c.JSValue) *Lease {
    return @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)).?));
}
fn finalizer(_: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    if (!lease.closed) lease.file.close(lease.io);
    lease.gpa.destroy(lease);
}
pub fn registerClass(engine: *em.Engine) !c.JSClassID {
    var class_id: c.JSClassID = 0;
    _ = c.JS_NewClassID(engine.runtime, &class_id);
    const definition: c.JSClassDef = .{ .class_name = "NativeOutputFileLease", .finalizer = finalizer };
    if (c.JS_NewClass(engine.runtime, class_id, &definition) < 0) return error.NativeOutputFileClass;
    return class_id;
}
pub fn create(engine: *em.Engine, class_id: c.JSClassID, path: []const u8) !c.JSValue {
    const object = try engine.checked(c.JS_NewObjectClass(engine.context, class_id));
    errdefer engine.freeValue(object);
    const lease = try engine.gpa.create(Lease);
    errdefer engine.gpa.destroy(lease);
    const io = engine.native_io orelse return error.NativeOutputFileIo;
    const permissions = if (@hasDecl(std.Io.File.Permissions, "fromMode")) std.Io.File.Permissions.fromMode(0o600) else std.Io.File.Permissions.default_file;
    const file = try std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true, .permissions = permissions });
    lease.* = .{ .gpa = engine.gpa, .io = io, .file = file };
    _ = c.JS_SetOpaque(object, lease);
    return object;
}
pub fn append(value: c.JSValue, bytes: []const u8) !void {
    const lease = state(value);
    if (lease.closed) return error.NativeOutputFileClosed;
    try lease.file.writePositionalAll(lease.io, bytes, lease.position);
    lease.position += bytes.len;
}
pub fn close(value: c.JSValue) void {
    const lease = state(value);
    if (lease.closed) return;
    lease.file.close(lease.io);
    lease.closed = true;
}
