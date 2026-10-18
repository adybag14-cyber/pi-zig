//! Native host-cancel publication registry. No Engine/VM/allocator/context
//! pointer is retained; Engine publishes only the scalar native token.
const std = @import("std");
const cancellation = @import("native_child_process_handshake_linux.zig");
const Mutex = @import("native_child_process_linux_mutex.zig").Mutex;
pub const Token = u64;
// Lifecycle remains busy after cancellation publication is logically cleared.
// This value is NEVER issued as a publication token or sent to a native sink.
pub const retiring_token: Token = std.math.maxInt(Token);
const Slot = struct {
    token: Token = 0,
    reference: ?cancellation.Cancellation = null,
    wake_failure: ?anyerror = null,
};
var guard: Mutex = .{};
var next_token: Token = 0;
var slots: [16]Slot = .{.{}} ** 16;
fn successor(previous: Token) !Token {
    if (previous >= retiring_token - 1) return error.NativeCancelPublicationTokenExhausted;
    return previous + 1;
}
/// Takes an independent native lease reference. Owner publishes the returned
/// token before checking its preexisting cancel flag; no lost install race.
pub fn attach(reference: cancellation.Cancellation) !Token {
    guard.lock(); defer guard.unlock();
    const token = try successor(next_token);
    for (&slots) |*slot| if (slot.token == 0) {
        const retained = try cancellation.retainCancellation(reference);
        next_token = token; slot.* = .{ .token = token, .reference = retained }; return token;
    };
    return error.NativeCancelPublicationCapacity;
}
/// Valid while an Engine publisher owns its existing live Engine reference.
/// The scalar token cannot dereference Engine memory. Holding this native guard
/// through cancel serializes detach before lease reuse (lockorder binding→cancel).
pub fn notify(token: Token) void {
    if (token == 0 or token == retiring_token) return;
    guard.lock(); defer guard.unlock();
    for (&slots) |*slot| if (slot.token == token) {
        cancellation.cancel(slot.reference.?) catch |failure| { slot.wake_failure = failure; };
        return;
    };
    // Delayed publication for a detached operation is intentionally inert.
}
pub const Diagnostics = struct { wake_failure: ?anyerror = null };
/// Caller replaces its publisher with the nonpublishing busy sentinel FIRST.
/// Success releases the
/// registry's retained lease, making every old token inert before slot reuse.
/// A borrowed-wait error leaves the entire registration/entitlement intact.
pub fn detach(token: Token) !Diagnostics {
    guard.lock(); defer guard.unlock();
    for (&slots) |*slot| if (slot.token == token and token != 0) {
        try cancellation.releaseCancellation(slot.reference.?);
        const result: Diagnostics = .{ .wake_failure = slot.wake_failure };
        slot.* = .{}; return result;
    };
    return error.NativeCancelPublicationStale;
}
test "publication token exhaustion cannot issue the retiring sentinel or wrap" {
    try std.testing.expectEqual(retiring_token - 1, try successor(retiring_token - 2));
    try std.testing.expectError(error.NativeCancelPublicationTokenExhausted, successor(retiring_token - 1));
    try std.testing.expectError(error.NativeCancelPublicationTokenExhausted, successor(retiring_token));
}
test "detached native host cancel token cannot cancel a later owned generation" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const first = try cancellation.reserveCancellation();
    var first_owned = true; defer if (first_owned) cancellation.releaseCancellation(first) catch @panic("owned first cancellation cleanup failed");
    const old_token = try attach(first); var old_owned = true;
    defer if (old_owned) { _ = detach(old_token) catch @panic("owned first publication cleanup failed"); };
    notify(old_token); try std.testing.expect(try cancellation.cancellationRequested(first));
    _ = try detach(old_token); old_owned = false;
    try cancellation.releaseCancellation(first); first_owned = false;
    const second = try cancellation.reserveCancellation(); defer cancellation.releaseCancellation(second) catch @panic("owned second cancellation cleanup failed");
    const current_token = try attach(second); defer { _ = detach(current_token) catch @panic("owned second publication cleanup failed"); }
    try std.testing.expect(old_token != current_token);
    notify(old_token); try std.testing.expect(!try cancellation.cancellationRequested(second));
    notify(current_token); try std.testing.expect(try cancellation.cancellationRequested(second));
}
