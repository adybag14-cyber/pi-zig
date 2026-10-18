//! Owner-frame binding for the reviewed native host-cancel publication design.
//! Engine is borrowed only by this owner object; native registries retain none.
const std = @import("std");
const em = @import("engine.zig");
const cancellation = @import("native_child_process_handshake_linux.zig");
const publication = @import("native_child_process_cancel_publication_linux.zig");
pub const Binding = struct {
    engine: *em.Engine, owner: std.Thread.Id,
    reference: cancellation.Cancellation, token: publication.Token,
    phase: enum { installed, cleared, detached, lease_released, done } = .installed,
    diagnostics: publication.Diagnostics = .{},
    /// The caller owns its existing live Engine reference through end(). No
    /// native registry/worker stores that pointer, even while ppoll is blocked.
    pub fn begin(engine: *em.Engine) !Binding {
        if (@import("builtin").os.tag != .linux) return error.RequiredLinuxChildReadiness;
        if (engine.native_sync_cancel_token.load(.seq_cst) != 0) return error.NativeSyncAdmissionAlreadyActive;
        const reference = try cancellation.reserveCancellation();
        errdefer cancellation.releaseCancellation(reference) catch @panic("unpublished native cancellation cleanup failed");
        const token = try publication.attach(reference);
        errdefer { _ = publication.detach(token) catch @panic("unpublished native cancellation publication cleanup failed"); }
        if (engine.native_sync_cancel_token.cmpxchgStrong(0, token, .seq_cst, .seq_cst) != null) return error.NativeSyncAdmissionAlreadyActive;
        // Together with Engine.cancel's SC store-then-load, both sides cannot
        // read the old values. Preinstall cancellation is a real native wake.
        if (engine.cancelled.load(.seq_cst)) publication.notify(token);
        return .{ .engine = engine, .owner = std.Thread.getCurrentId(), .reference = reference, .token = token };
    }
    /// Replace the publisher with a nonpublishing busy sentinel before detach.
    /// Only proven detach AND owner-lease release permit a final return to idle.
    /// Logical cleanup is resumable
    /// after a borrowed-wait rejection; no live token is blindly reset, no lease
    /// is dropped and no numeric eventfd is closed or retried.
    pub fn end(self: *Binding) !publication.Diagnostics {
        if (self.owner != std.Thread.getCurrentId()) return error.NativeSyncAdmissionOwnerThreadRequired;
        try self.releaseLease();
        if (self.phase == .lease_released) {
            if (self.engine.native_sync_cancel_token.cmpxchgStrong(publication.retiring_token, 0, .seq_cst, .seq_cst) != null) return error.NativeCancelPublicationOwnerMismatch;
            self.phase = .done;
        }
        return self.diagnostics;
    }
    fn releaseLease(self: *Binding) !void {
        if (self.phase == .installed) {
            if (self.engine.native_sync_cancel_token.cmpxchgStrong(self.token, publication.retiring_token, .seq_cst, .seq_cst) != null) return error.NativeCancelPublicationOwnerMismatch;
            self.phase = .cleared;
        }
        if (self.phase == .cleared) {
            self.diagnostics = try publication.detach(self.token); self.phase = .detached;
        }
        if (self.phase == .detached) {
            try cancellation.releaseCancellation(self.reference); self.phase = .lease_released;
        }
    }
};
pub const Testing = if (@import("builtin").is_test) struct {
    pub fn releaseLeaseOnly(binding: *Binding) !void {
        if (binding.owner != std.Thread.getCurrentId()) return error.NativeSyncAdmissionOwnerThreadRequired;
        try binding.releaseLease();
    }
} else struct {};

test "actual Engine cancel publishes before, during and after native binding install" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const engine = try em.Engine.init(std.testing.allocator, .{ .node_locale_compare = false });
    defer engine.deinit();
    // Cancellation before install must not disappear behind the new token.
    engine.cancel();
    var before = try Binding.begin(engine);
    var before_owned = true; defer if (before_owned) { _ = before.end() catch @panic("owned preinstall binding cleanup failed"); };
    try std.testing.expect(try cancellation.cancellationRequested(before.reference));
    _ = try before.end(); before_owned = false;
    // Genuine native producer races the owner installation; no guest thread,
    // replacement Engine or fake cancellation publisher is used.
    const Race = struct {
        engine: *em.Engine,
        start: std.Io.Event = .unset, done: std.Io.Event = .unset,
        fn run(self: *@This()) void {
            self.start.waitUncancelable(std.testing.io);
            self.engine.cancel(); self.done.set(std.testing.io);
        }
    };
    for (0..64) |_| {
        engine.beginInvocation();
        var race: Race = .{ .engine = engine };
        const producer = try std.Thread.spawn(.{ .stack_size = 128 * 1024, .allocator = std.testing.allocator }, Race.run, .{&race});
        defer { race.start.set(std.testing.io); producer.join(); }
        race.start.set(std.testing.io);
        var binding = try Binding.begin(engine);
        defer { _ = binding.end() catch @panic("owned racing binding cleanup failed"); }
        race.done.waitUncancelable(std.testing.io);
        try std.testing.expect(engine.cancelled.load(.seq_cst));
        try std.testing.expect(try cancellation.cancellationRequested(binding.reference));
    }
    engine.beginInvocation();
    var after = try Binding.begin(engine); defer { _ = after.end() catch @panic("owned postinstall binding cleanup failed"); }
    const token = after.token;
    try std.testing.expectError(error.NativeSyncAdmissionAlreadyActive, Binding.begin(engine));
    try std.testing.expectEqual(token, engine.native_sync_cancel_token.load(.seq_cst));
    engine.cancel(); try std.testing.expect(try cancellation.cancellationRequested(after.reference));
    _ = try after.end();
    try std.testing.expectEqual(@as(u64, 0), engine.native_sync_cancel_token.load(.seq_cst));
    engine.beginInvocation();
}

test "actual borrowed native wait keeps Engine busy until detach and complete release" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const linux = std.os.linux;
    const engine = try em.Engine.init(std.testing.allocator, .{ .node_locale_compare = false });
    defer engine.deinit();
    var binding = try Binding.begin(engine);
    defer { _ = binding.end() catch @panic("owned borrowed-wait binding cleanup failed"); }
    const Waiter = struct {
        reference: cancellation.Cancellation,
        started: std.Io.Event = .unset, done: std.Io.Event = .unset,
        failed: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This()) void {
            const borrow = cancellation.Testing.borrowWait(self.reference) catch {
                self.failed.store(true, .release); self.started.set(std.testing.io); self.done.set(std.testing.io); return;
            };
            defer { borrow.end(); self.done.set(std.testing.io); }
            self.started.set(std.testing.io);
            var descriptors = [_]linux.pollfd{.{ .fd = borrow.fd, .events = linux.POLL.IN, .revents = 0 }};
            var timeout: linux.timespec = .{ .sec = 1, .nsec = 0 };
            const ready = linux.ppoll(&descriptors, descriptors.len, &timeout, null);
            if (linux.errno(ready) != .SUCCESS or ready != 1) self.failed.store(true, .release);
        }
    };
    var waiter: Waiter = .{ .reference = binding.reference };
    const producer = try std.Thread.spawn(.{ .stack_size = 128 * 1024, .allocator = std.testing.allocator }, Waiter.run, .{&waiter});
    defer { cancellation.cancel(binding.reference) catch {}; producer.join(); }
    waiter.started.waitUncancelable(std.testing.io);
    try std.testing.expect(!waiter.failed.load(.acquire));
    try std.testing.expectError(error.NativeLinuxSpawnCancellationBorrowed, binding.end());
    try std.testing.expectEqual(publication.retiring_token, engine.native_sync_cancel_token.load(.seq_cst));
    try std.testing.expectError(error.NativeSyncAdmissionAlreadyActive, Binding.begin(engine));
    engine.cancel();
    try std.testing.expect(!try cancellation.cancellationRequested(binding.reference));
    try cancellation.cancel(binding.reference); // real native wake, not Engine republish
    waiter.done.waitUncancelable(std.testing.io);
    try std.testing.expect(!waiter.failed.load(.acquire));
    _ = try binding.end();
    try std.testing.expectEqual(@as(u64, 0), engine.native_sync_cancel_token.load(.seq_cst));
    engine.beginInvocation();
}

test "final Engine idle CAS retry cannot release an already reused cancellation lease" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const engine = try em.Engine.init(std.testing.allocator, .{ .node_locale_compare = false });
    defer engine.deinit();
    var binding = try Binding.begin(engine); var binding_owned = true;
    defer if (binding_owned) {
        engine.native_sync_cancel_token.store(publication.retiring_token, .seq_cst);
        _ = binding.end() catch @panic("owned final-CAS binding cleanup failed");
    };
    try Testing.releaseLeaseOnly(&binding);
    try std.testing.expect(binding.phase == .lease_released);
    const later = try cancellation.reserveCancellation(); defer cancellation.releaseCancellation(later) catch @panic("owned later cancellation cleanup failed");
    try std.testing.expectEqual(binding.reference.slot, later.slot);
    try std.testing.expect(binding.reference.generation != later.generation);
    // Deliberate private-host field corruption tests the FINAL CAS failure;
    // production does not expose this field to guest code.
    engine.native_sync_cancel_token.store(0, .seq_cst);
    try std.testing.expectError(error.NativeCancelPublicationOwnerMismatch, binding.end());
    try std.testing.expect(binding.phase == .lease_released);
    engine.native_sync_cancel_token.store(publication.retiring_token, .seq_cst);
    _ = try binding.end(); binding_owned = false;
    try std.testing.expect(!try cancellation.cancellationRequested(later));
    try std.testing.expectEqual(@as(u64, 0), engine.native_sync_cancel_token.load(.seq_cst));
}
