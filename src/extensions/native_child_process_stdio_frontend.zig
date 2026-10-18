//! Actual same-process frontend stdio capture. Worker bridge metadata is not a
//! file capability, and no remote HANDLE/fd is manufactured or serialized here.
const std = @import("std");
const builtin = @import("builtin");
const js = @import("native_js_values.zig");
const streams = @import("native_process_streams.zig");
const frontend_module = @import("native_stdio_frontend.zig");
const hub_module = @import("native_env_io.zig");
pub const native = if (builtin.os.tag == .windows) @import("native_child_process_stdio_windows.zig") else @import("native_child_process_stdio_linux.zig");
pub const Captured = struct {
    owner: *js.Engine, // borrowed by this host capture object only, never a worker
    map: native.Map,
    source: streams.Lease,
    /// Copies native map/source identities into namespace inputs. The source
    /// context is compared as an opaque identity, never dereferenced; this host
    /// object's borrowed Engine pointer is not copied into native registries.
    pub fn apply(self: Captured, engine: *js.Engine, inputs: anytype) !void {
        if (self.owner != engine or !streams.ownsLease(engine, self.source)) return error.NativeChildStdioFrontendLeaseMismatch;
        if (builtin.os.tag == .windows) inputs.windows_stdio = self.map else inputs.linux_stdio = self.map;
        inputs.stdio_source = self.source;
    }
};
const Owner = struct {
    hub: *hub_module.Hub,
    map: native.Map,
    source: streams.Lease,
    retired: bool = false,
    failure: ?anyerror = null,
    fn stop(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.retired) return;
        self.retired = true;
        // Each uncertain close remains charged in native static storage. No
        // child is signaled and no successfully admitted child copy is closed.
        native.releaseMap(self.map) catch |err| { self.failure = err; };
    }
    fn stopped(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw)); self.hub.engine.gpa.destroy(self);
    }
    fn poll(raw: *anyopaque) !bool {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.retired or streams.ownsLease(self.hub.engine, self.source)) return false;
        stop(raw); return true;
    }
};
/// Caller holds the genuine native Frontend and process standard descriptors
/// against concurrent close/replacement until this owner-thread call returns.
/// Only its already bound exact live process-stream lease authorizes capture.
/// Module admission rechecks that scalar source lease on every fd acquisition.
/// This is a clean trusted native bootstrap entry, not a guest callback. A real
/// pending VM event is left untouched and rejected before Hub/map/handle effects.
/// No guest operation/capture/stringification runs here; diagnostic suppression
/// and old captured-history classification are not part of this host boundary.
pub fn capture(engine: *js.Engine, frontend: *frontend_module.Frontend) !Captured {
    if (builtin.os.tag != .windows and builtin.os.tag != .linux) return error.RequiredActualPlatformStdioBorrower;
    if (frontend.engine != engine or frontend.owner != std.Thread.getCurrentId()) return error.NativeChildStdioFrontendOwner;
    if (js.c.JS_HasException(engine.context)) return error.JavaScriptException;
    if (!frontend.active.load(.acquire)) return error.NativeChildStdioFrontendRetired;
    const source = frontend.lease orelse return error.NativeChildStdioFrontendUnbound;
    if (source.context != @as(?*anyopaque, @ptrCast(frontend)) or !streams.ownsLease(engine, source)) return error.NativeChildStdioFrontendLeaseMismatch;
    const hub = try hub_module.get(engine); try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    const map = try native.reserveMap(); var map_owned = true;
    defer if (map_owned) native.releaseMap(map) catch {};
    const files = [_]std.Io.File{ std.Io.File.stdin(), std.Io.File.stdout(), std.Io.File.stderr() };
    for (files, 0..) |file, index| { _ = try native.authorize(map, @intCast(index), file.handle); }
    const owner = try engine.gpa.create(Owner); errdefer engine.gpa.destroy(owner);
    owner.* = .{ .hub = hub, .map = map, .source = source };
    try hub.addResource(.{ .raw = owner, .tag = &tag, .poll = Owner.poll, .stop = Owner.stop, .stopped = Owner.stopped });
    map_owned = false;
    return .{ .owner = engine, .map = map, .source = source };
}
const tag: u8 = 0;
