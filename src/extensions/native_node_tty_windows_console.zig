//! Source-only real CRT/console admission. No public selection or shared ABI.
//! CRT integers are never HANDLE values or opaque registry tokens.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
const H = w.HANDLE;
const ownership = @import("native_node_fs_windows_crt_proposal.zig");
const output = @import("native_node_tty_windows_output.zig");
pub const selected_after_independent_review = false;
const InvalidHandler = ?*const fn (?[*:0]const u16, ?[*:0]const u16, ?[*:0]const u16, c_uint, usize) callconv(.c) void;
const api = struct {
    extern "c" fn _get_osfhandle(c_int) isize;
    extern "c" fn _set_thread_local_invalid_parameter_handler(InvalidHandler) InvalidHandler;
    extern "c" fn _get_errno(*c_int) c_int;
    extern "kernel32" fn GetFileType(H) callconv(.winapi) u32;
    extern "kernel32" fn GetConsoleMode(H, *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetConsoleMode(H, u32) callconv(.winapi) i32;
    extern "kernel32" fn GetNumberOfConsoleInputEvents(H, *u32) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleScreenBufferInfo(H, *BufferInfo) callconv(.winapi) i32;
    extern "kernel32" fn GetConsoleCursorInfo(H, *CursorInfo) callconv(.winapi) i32;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) H;
    extern "kernel32" fn DuplicateHandle(H, H, H, *H, u32, i32, u32) callconv(.winapi) i32;
    extern "kernel32" fn CloseHandle(H) callconv(.winapi) i32;
    extern "kernel32" fn GetLastError() callconv(.winapi) u32;
};
const BufferInfo = output.ScreenInfo;
const CursorInfo = output.CursorInfo;
pub const Kind = enum { input, output };
pub const Failure = union(enum) { crt: c_int, windows: u32, not_tty };
pub const Probe = union(enum) { console: struct { borrowed: H, kind: Kind, mode: ?u32, initial_output: ?struct { info: BufferInfo, cursor: CursorInfo } = null }, failed: Failure };
const Borrowed = union(enum) { handle: H, failed: c_int };
fn ignoreInvalidParameter(_: ?[*:0]const u16, _: ?[*:0]const u16, _: ?[*:0]const u16, _: c_uint, _: usize) callconv(.c) void {}
fn errno() c_int { var value: c_int = 0; _ = api._get_errno(&value); return value; }
/// uv_guess_handle checks FILE_TYPE_CHAR and GetConsoleMode. Reading the CRT
/// table is protected by a THREAD-local handler for invalid descriptor indices;
/// the previous handler is restored immediately, without a global process hook.
/// A successful result is BORROWED and never independently closed by probe.
fn borrow(fd: c_int) Borrowed {
    if (builtin.os.tag != .windows or fd < 0) return .{ .failed = 9 };
    const previous = api._set_thread_local_invalid_parameter_handler(ignoreInvalidParameter);
    const raw = api._get_osfhandle(fd);
    const failure_errno = if (raw == -1) errno() else @as(c_int, 0);
    _ = api._set_thread_local_invalid_parameter_handler(previous);
    if (raw == -1 or raw == -2) return .{ .failed = if (failure_errno != 0) failure_errno else 9 };
    return .{ .handle = @ptrFromInt(@as(usize, @bitCast(raw))) };
}
pub fn probe(fd: c_int) Probe {
    const handle = switch (borrow(fd)) { .handle => |value| value, .failed => |value| return .{ .failed = .{ .crt = value } } };
    var mode: u32 = 0;
    const observed_mode: ?u32 = if (api.GetConsoleMode(handle, &mode) != 0) mode else null;
    var available: u32 = 0;
    if (api.GetNumberOfConsoleInputEvents(handle, &available) != 0) return .{ .console = .{ .borrowed = handle, .kind = .input, .mode = observed_mode } };
    var info: BufferInfo = undefined;
    if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) return .{ .failed = .{ .windows = api.GetLastError() } };
    var cursor: CursorInfo = undefined;
    if (api.GetConsoleCursorInfo(handle, &cursor) == 0) return .{ .failed = .{ .windows = api.GetLastError() } };
    return .{ .console = .{ .borrowed = handle, .kind = .output, .mode = observed_mode, .initial_output = .{ .info = info, .cursor = cursor } } };
}
pub fn isTTY(fd: c_int) bool {
    // isTTY does not initialize/adopt/close a descriptor or mutate console mode.
    // uv_guess_handle does NOT require successful size/cursor/input queries.
    const handle = switch (borrow(fd)) { .handle => |value| value, .failed => return false };
    var mode: u32 = 0;
    return api.GetFileType(handle) == 2 and api.GetConsoleMode(handle, &mode) != 0;
}
pub const Size = struct { columns: i32, rows: i32 };
pub const QuerySize = union(enum) { size: Size, failed: u32 };
pub fn windowSize(handle: H) QuerySize {
    var info: BufferInfo = undefined;
    if (api.GetConsoleScreenBufferInfo(handle, &info) == 0) return .{ .failed = api.GetLastError() };
    // Exact libuv virtual window dimensions, not maximum size or window width.
    return .{ .size = .{ .columns = info.size.x, .rows = @as(i32, info.window.bottom) - info.window.top + 1 } };
}
// Direct rollback CloseHandle has a reserved, bounded native uncertainty slot.
// A false return is NEVER retried; the numeric value may already be recycled.
const RollbackSlot = union(enum) { free, reserved: u64, failed: struct { generation: u64, handle: H, error_code: u32 } };
const Rollback = struct { index: u8, generation: u64 };
var rollback_gate: std.atomic.Value(bool) = .init(false);
var rollback_slots: [16]RollbackSlot = @splat(.free);
var rollback_generation: u64 = 0;
fn lock() void { while (rollback_gate.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint(); }
fn unlock() void { rollback_gate.store(false, .release); }
fn reserveRollback() !Rollback {
    lock(); defer unlock();
    if (rollback_generation == std.math.maxInt(u64)) return error.NativeTtyGenerationExhausted;
    for (&rollback_slots, 0..) |*slot, index| if (slot.* == .free) {
        rollback_generation += 1; slot.* = .{ .reserved = rollback_generation };
        return .{ .index = @intCast(index), .generation = rollback_generation };
    };
    return error.NativeTtyRollbackCapacity;
}
fn releaseRollback(ticket: Rollback) void {
    lock(); defer unlock();
    const slot = &rollback_slots[ticket.index];
    std.debug.assert(slot.* == .reserved and slot.reserved == ticket.generation);
    slot.* = .free;
}
fn rollbackHandle(ticket: Rollback, handle: H) void {
    // This ticket is exclusively owned; no other path can close the duplicate.
    if (api.CloseHandle(handle) != 0) { releaseRollback(ticket); return; }
    const failure = api.GetLastError();
    lock(); defer unlock();
    const slot = &rollback_slots[ticket.index];
    std.debug.assert(slot.* == .reserved and slot.reserved == ticket.generation);
    slot.* = .{ .failed = .{ .generation = ticket.generation, .handle = handle, .error_code = failure } };
}
/// Inject exactly the canonical shared close pool, instantiated with the same
/// native_owner_wake facade as the filesystem lane. No second worker pool or
/// scheduler is instantiated by this module. Selection is still disabled.
pub fn Console(comptime ClosePool: type, comptime Wake: type) type {
    return struct {
        const Self = @This();
        // Use the actual canonical pool's return payload, whose Ticket is a
        // module-level type in the reviewed close worker (not Pool.Ticket).
        const CloseTicket = @typeInfo(@typeInfo(@TypeOf(ClosePool.reserve)).@"fn".return_type.?).error_union.payload;
        const Direct = @import("native_node_tty_windows_close.zig").Pool(Wake);
        const Target = union(enum) {
            crt: struct { lease: ownership.Lease, ticket: CloseTicket },
            direct: struct { handle: H, ticket: Direct.Ticket, phase: ownership.Phase = .owned, in_flight: usize = 0 },
        };
        pub const Admission = union(enum) { failure: Failure, console: Self };
        pub const Close = union(enum) { closed, failed: Failure };
        requested_fd: c_int,
        kind: Kind,
        target: Target,
        blocking: bool = false,
        raw: bool = false,
        vt_processing: bool = false,
        output_decoder: output.Decoder = .{},
        last_output: output.Result = .{},
        /// All reservations/worker wake entitlements precede native ownership.
        /// fd0-2 are duplicated; their original CRT descriptors stay borrowed.
        /// The duplicate retains HANDLE ownership, exactly as uv_tty_init;
        /// another CRT fd/EMFILE admission point is NOT introduced for stdio.
        /// For fd>=3, successful admission transfers the actual input CRT fd,
        /// matching uv_tty_init. Numeric fd registry coordination is required
        /// before selecting shared node:fs fd operations on the same descriptor.
        pub fn admit(fd: c_int, wake: Wake.Ref) !Admission {
            if (!selected_after_independent_review) return error.RequiredNativeTtyConsoleOwnershipReview;
            return admitOwned(fd, wake, false);
        }
        /// Explicit isolated qualification target ONLY. Default Engine/module
        /// construction still calls admit and retains its disabled selector.
        /// This performs the same genuine CRT/console ownership operations.
        pub fn admitForQualification(fd: c_int, wake: Wake.Ref) !Admission {
            return admitOwned(fd, wake, true);
        }
        fn admitOwned(fd: c_int, wake: Wake.Ref, qualification: bool) !Admission {
            const observed = switch (probe(fd)) { .console => |value| value, .failed => |failure| return .{ .failure = failure } };
            var handle = observed.borrowed;
            var target: Target = undefined;
            if (fd <= 2) {
                const close_ticket = try Direct.reserve(wake);
                var close_owned = true;
                defer if (close_owned) Direct.releaseUnassociated(close_ticket) catch {};
                const rollback = try reserveRollback();
                var rollback_owned = true;
                defer if (rollback_owned) releaseRollback(rollback);
                const current = api.GetCurrentProcess();
                var duplicate: H = undefined;
                if (api.DuplicateHandle(current, handle, current, &duplicate, 0, 0, 2) == 0) return .{ .failure = .{ .windows = api.GetLastError() } };
                // After DuplicateHandle, a single disarmed owner governs the
                // rollback before the exact direct-close ticket owns it.
                rollback_owned = false;
                var duplicate_owned = true;
                defer if (duplicate_owned) rollbackHandle(rollback, duplicate);
                try Direct.associate(close_ticket, duplicate);
                duplicate_owned = false; releaseRollback(rollback); handle = duplicate; close_owned = false;
                target = .{ .direct = .{ .handle = handle, .ticket = close_ticket } };
            } else {
                const native = try ownership.reserveBeforeOpen();
                var native_owned = true;
                defer if (native_owned) ownership.releaseReservation(native);
                // One canonical native pool, with pre-open qualification
                // entitlement carried on this ticket, never a global flip.
                const close_ticket = if (qualification) try ClosePool.reserveForQualification(wake) else try ClosePool.reserve(wake);
                var close_owned = true;
                defer if (close_owned) ClosePool.releaseUnassociated(close_ticket) catch {};
                // probe proved a real console buffer. File.Flags uses false
                // for non-file handles; this is not the public blocking policy.
                target = .{ .crt = .{ .lease = .{ .fd = fd, .borrowed_view = .{ .handle = handle, .flags = .{ .nonblocking = false } }, .generation = native.generation, .reservation = native,
                    .qualification_admission = qualification }, .ticket = close_ticket } };
                native_owned = false; close_owned = false;
            }
            // Native VT detection, captured style/cursor and virtual window
            // initialization share Source's single process-global output lock.
            // The exact queried buffer/cursor state travels from admission;
            // no extra fallible IO follows native ownership transfer.
            const vt = if (observed.initial_output) |initial| output.initialize(handle, &initial.info, &initial.cursor) else false;
            // No FALLIBLE ownership operation follows the transfer. VT failure
            // is recorded as an actual native capability, never assumed true.
            return .{ .console = .{ .requested_fd = fd, .kind = observed.kind, .target = target, .vt_processing = vt } };
        }
        pub fn getWindowSize(self: *@This()) QuerySize {
            if (self.phase() != .owned) return .{ .failed = 6 }; // ERROR_INVALID_HANDLE
            return windowSize(self.nativeHandle());
        }
        /// Native mode mutation; the actual input IO owner must first retire
        /// and later restart an outstanding read, as uv_tty_set_mode does.
        /// Legacy raw fallback additionally needs its real key-event translator.
        pub fn setRawModeAfterReadRetired(self: *@This(), flag: bool, legacy_translator_present: bool) !?u32 {
            if (self.kind != .input) return error.NativeTtyInputRequired;
            if (self.phase() != .owned or self.inFlight() != 0) return error.NativeTtyReadRetirementRequired;
            return self.applyRawMode(flag, legacy_translator_present);
        }
        /// Source stop/read-mode transition publishes a real cancellation
        /// request and changes mode before the old completion necessarily
        /// arrives. The IO owner must keep that exact read ticket/epoch and
        /// discard a cancelled completion before restarting in the new mode.
        pub fn applyRawMode(self: *@This(), flag: bool, legacy_translator_present: bool) !?u32 {
            if (self.kind != .input or self.phase() != .owned) return error.NativeTtyInputRequired;
            if (self.raw == flag) return null;
            const base: u32 = if (flag) 8 else 1 | 2 | 4;
            const requested = base | @as(u32, if (flag) 0x200 else 0);
            if (output.applyMode(self.nativeHandle(), requested)) |_| {
                if (flag and !legacy_translator_present) return error.RequiredNativeTtyLegacyKeyTranslator;
                if (output.applyMode(self.nativeHandle(), base)) |failure| return failure;
            }
            self.raw = flag; return null;
        }
        /// Real console operations are inherently blocking. This flag selects
        /// the actual native write dispatch policy in the IO owner; changing
        /// it alone is not an IO completion or an acknowledged write.
        pub fn setBlocking(self: *@This(), flag: bool) !void {
            if (self.phase() != .owned) return error.NativeTtyRetired;
            self.blocking = flag;
        }
        /// Called by the canonical Socket's genuine synchronous hook, receiving
        /// the WHOLE Source byte span. No NativeWake/tick/worker acknowledges a
        /// write which already completed synchronously in the Source frame.
        pub fn writeBlocking(self: *@This(), bytes: []const u8) !output.Result {
            if (self.kind != .output) return error.NativeTtyNotWritable;
            const handle = try self.beginIo();
            defer self.retireIo();
            self.last_output = self.output_decoder.writeBlocking(handle, bytes, self.vt_processing);
            return self.last_output;
        }
        pub fn phase(self: *const Self) ownership.Phase { return switch (self.target) { .crt => |*value| value.lease.phase, .direct => |*value| value.phase }; }
        fn nativeHandle(self: *const Self) H { return switch (self.target) { .crt => |*value| value.lease.borrowed_view.handle, .direct => |*value| value.handle }; }
        fn inFlight(self: *const Self) usize { return switch (self.target) { .crt => |*value| value.lease.in_flight, .direct => |*value| value.in_flight }; }
        pub fn beginIo(self: *Self) !H {
            switch (self.target) {
                .crt => |*value| try value.lease.startIo(value.lease.generation),
                .direct => |*value| { if (value.phase != .owned) return error.NativeTtyRetired; value.in_flight += 1; },
            }
            return self.nativeHandle();
        }
        pub fn retireIo(self: *Self) void { switch (self.target) { .crt => |*value| value.lease.retiredIo(value.lease.generation), .direct => |*value| { std.debug.assert(value.in_flight != 0); value.in_flight -= 1; } } }
        pub fn requestClose(self: *Self) !bool {
            switch (self.target) {
                .crt => |*value| return ClosePool.submit(value.ticket, &value.lease),
                .direct => |*value| {
                    if (value.phase == .owned) value.phase = .closing_wait;
                    if (value.in_flight != 0) return false;
                    if (value.phase == .closing_wait) { try Direct.submitAfterIo(value.ticket); value.phase = .closing_submitted; }
                    return true;
                },
            }
        }
        pub fn pollClose(self: *Self) !?Close {
            switch (self.target) {
                .crt => |*value| {
                    const result = try ClosePool.poll(value.ticket, &value.lease) orelse return null;
                    return switch (result) { .closed => .closed, .failed => |code| .{ .failed = .{ .crt = code } }, else => error.NativeTtyCloseProtocol };
                },
                .direct => |*value| {
                    const result = try Direct.poll(value.ticket) orelse return null;
                    switch (result) { .closed => { value.phase = .closed; return .closed; }, .failed => |code| { value.phase = .close_failed; return .{ .failed = .{ .windows = code } }; } }
                },
            }
        }
        pub fn detachAfterIoRetired(self: *Self) !void {
            if (!try self.requestClose()) return error.NativeTtyIoStillPending;
            switch (self.target) { .crt => |*value| try ClosePool.detach(value.ticket, &value.lease), .direct => |*value| try Direct.detachAfterIo(value.ticket) }
        }
    };
}
