//! Shared native completion wake entitlement. This has no child process/pipe
//! dependency, wait loop or VM callback. TTY, file-close and child owners share
//! one attached wake lifetime per Hub and pre-retain their worker entitlements.
const std = @import("std");
const js = @import("native_js_values.zig");
const hub_module = @import("native_env_io.zig");
const wake = @import("native_owner_wake.zig");
const tag: u8 = 0;
const Owner = struct {
    hub: *hub_module.Hub,
    reference: wake.Ref,
    stopped: bool = false,
    fn bindHost(raw: *anyopaque, publish: *const fn (?*anyopaque) void, context: ?*anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (!self.stopped) wake.bindHost(self.reference, publish, context);
    }
    fn detachHost(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw)); wake.detachHost(self.reference);
    }
    fn stop(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        if (self.stopped) return;
        self.stopped = true;
        // Clears borrowed signal/Io/host sink before any Engine teardown.
        // Native workers keep only their already-retained generation token.
        wake.detach(self.reference);
    }
    fn release(raw: *anyopaque) void {
        const self: *Owner = @ptrCast(@alignCast(raw));
        std.debug.assert(self.stopped);
        wake.release(self.reference);
        const engine = self.hub.engine;
        engine.gpa.destroy(self);
        js.c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
    }
};
/// Returns one owned reference. This resource never keeps the event loop alive
/// by itself; actual read/write/close owners provide referenced/poll predicates.
pub fn acquireNativeWake(engine: *js.Engine) !wake.Ref {
    const hub = try hub_module.get(engine); try hub.assertOwner();
    if (hub.stopping) return error.NativeEnvClosed;
    for (hub.resources.items) |resource| if (resource.tag == @as(?*const anyopaque, @ptrCast(&tag))) {
        const existing: *Owner = @ptrCast(@alignCast(resource.raw));
        if (existing.hub != hub or existing.stopped) return error.NativeOwnerCompletionClosed;
        return wake.retain(existing.reference);
    };
    const io = engine.native_io orelse return error.NativeIoRequired;
    const reference = try wake.create(.{ .signal = &engine.native_owner_signal, .io = io, .host_notify = engine.host_owner_notify, .host_context = engine.host_owner_notify_context });
    errdefer { wake.detach(reference); wake.release(reference); }
    const result = try wake.retain(reference); errdefer wake.release(result);
    if (js.c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Owner)) == 0) return error.OutOfMemory;
    errdefer js.c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Owner));
    const self = try engine.gpa.create(Owner); errdefer engine.gpa.destroy(self);
    self.* = .{ .hub = hub, .reference = reference };
    try hub.addResource(.{ .raw = self, .tag = &tag, .bind_host_wake = Owner.bindHost, .detach_host_wake = Owner.detachHost, .stop = Owner.stop, .stopped = Owner.release });
    return result;
}

test "completion owners share one generation and detach before retained native references retire" {
    const engine = try js.Engine.init(std.testing.allocator, .{}); defer engine.deinit();
    engine.native_io = std.testing.io;
    const first = try acquireNativeWake(engine); defer wake.release(first);
    const second = try acquireNativeWake(engine); defer wake.release(second);
    try std.testing.expectEqual(first.slot, second.slot);
    try std.testing.expectEqual(first.generation, second.generation);
    const before = engine.native_owner_signal.observe();
    wake.notify(first);
    try std.testing.expectEqual(before + 1, engine.native_owner_signal.observe());
    engine.native_env_deinit.?(engine);
    const detached = engine.native_owner_signal.observe();
    wake.notify(first);
    try std.testing.expectEqual(detached, engine.native_owner_signal.observe());
    try std.testing.expectError(error.NativeOwnerWakeDetached, wake.retain(second));
}
