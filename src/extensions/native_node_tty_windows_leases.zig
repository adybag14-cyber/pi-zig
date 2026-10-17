//! Bounded native-only console ownership; safe after Engine/wake detachment.
//! No Engine, JS, allocator or Io pointer is present in these registry slots.
const std = @import("std");
const w = std.os.windows;
const consoles = @import("native_node_tty_windows_console.zig");
const ownership = @import("native_node_fs_windows_crt_proposal.zig");
const output = @import("native_node_tty_windows_output.zig");
const Reference = struct { slot: u8, generation: u64 };
pub const Ref = Reference;
pub const maximum_leases = 16;
pub fn Registry(comptime ClosePool: type, comptime Wake: type) type {
    return struct {
        pub const Ref = Reference;
        const Console = consoles.Console(ClosePool, Wake);
        pub const Admission = union(enum) { reference: Ref, failure: consoles.Failure };
        pub const Close = Console.Close;
        const Phase = enum { free, live, closing, closed, failed, transferred };
        const Slot = struct {
            phase: Phase = .free,
            generation: u64 = 0,
            references: usize = 0,
            console: ?Console = null,
            read_in_flight: bool = false,
            write_in_flight: bool = false,
            detached: bool = false,
            retirement_failure: ?anyerror = null,
        };
        var gate: std.atomic.Value(bool) = .init(false);
        var slots: [maximum_leases]Slot = .{.{}} ** maximum_leases;
        fn lock() void { while (gate.cmpxchgWeak(false, true, .acquire, .monotonic) != null) std.atomic.spinLoopHint(); }
        fn unlock() void { gate.store(false, .release); }
        fn valid(reference: Ref) !*Slot {
            if (reference.slot >= slots.len) return error.NativeTtyLeaseMismatch;
            const slot = &slots[reference.slot];
            if (slot.phase == .free or slot.generation != reference.generation) return error.NativeTtyLeaseMismatch;
            return slot;
        }
        fn freeLocked(slot: *Slot) void {
            std.debug.assert(slot.references == 0 and !slot.read_in_flight and !slot.write_in_flight);
            const generation = slot.generation;
            slot.* = .{ .generation = generation };
        }
        fn retireLocked(slot: *Slot) void {
            if (slot.references != 0 or slot.read_in_flight or slot.write_in_flight) return;
            switch (slot.phase) {
                .closed, .transferred => freeLocked(slot),
                .live, .closing => {
                    // Native close pool owns a full native packet + its prior
                    // wake entitlements after detach. Registry storage need
                    // not stay alive for that packet to finish or retain error.
                    slot.console.?.detachAfterIoRetired() catch |err| { slot.retirement_failure = err; slot.phase = .failed; return; };
                    slot.phase = .transferred; freeLocked(slot);
                },
                .failed => {}, // bounded uncertainty, never retry or reuse.
                .free => unreachable,
            }
        }
        pub fn admit(fd: c_int, reference: Wake.Ref) !Admission {
            return admitOwned(fd, reference, false);
        }
        pub fn admitForQualification(fd: c_int, reference: Wake.Ref) !Admission {
            return admitOwned(fd, reference, true);
        }
        fn admitOwned(fd: c_int, reference: Wake.Ref, qualification: bool) !Admission {
            lock(); defer unlock();
            for (&slots, 0..) |*slot, index| if (slot.phase == .free and slot.generation != std.math.maxInt(u64)) {
                const admitted = if (qualification) try Console.admitForQualification(fd, reference) else try Console.admit(fd, reference);
                const console = switch (admitted) { .console => |value| value, .failure => |failure| return .{ .failure = failure } };
                const generation = slot.generation + 1;
                slot.* = .{ .phase = .live, .generation = generation, .references = 1, .console = console };
                return .{ .reference = .{ .slot = @intCast(index), .generation = generation } };
            };
            return error.NativeTtyLeaseCapacity;
        }
        /// Admission-only retain; all operation refs precede owner detachment.
        /// Existing native refs may retire afterward without reattaching a sink.
        pub fn retain(reference: Ref) !Ref {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase != .live or slot.detached) return error.NativeTtyLeaseRetired;
            if (slot.references == std.math.maxInt(usize)) return error.NativeTtyLeaseReferences;
            slot.references += 1; return reference;
        }
        pub fn release(reference: Ref) void {
            lock(); defer unlock();
            const slot = valid(reference) catch return;
            std.debug.assert(slot.references != 0);
            slot.references -= 1; retireLocked(slot);
        }
        pub fn requestedFd(reference: Ref) !c_int {
            lock(); defer unlock(); return (try valid(reference)).console.?.requested_fd;
        }
        pub fn kind(reference: Ref) !consoles.Kind {
            lock(); defer unlock(); return (try valid(reference)).console.?.kind;
        }
        pub fn beginReadIo(reference: Ref) !w.HANDLE {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase != .live or slot.detached or slot.read_in_flight or slot.console.?.kind != .input) return error.NativeTtyReadAdmission;
            const handle = try slot.console.?.beginIo();
            slot.read_in_flight = true; return handle;
        }
        pub fn retireReadIo(reference: Ref) void {
            lock(); defer unlock(); const slot = valid(reference) catch return;
            std.debug.assert(slot.read_in_flight);
            slot.read_in_flight = false; slot.console.?.retireIo();
            // Lifetime's pool-owned reference remains held until after this
            // acknowledgement. Last release, not elapsed time, transfers close.
            retireLocked(slot);
        }
        pub fn getWindowSize(reference: Ref) !consoles.QuerySize {
            lock(); defer unlock(); const slot = try valid(reference);
            return slot.console.?.getWindowSize();
        }
        pub fn setBlocking(reference: Ref, flag: bool) !void {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase != .live or slot.detached) return error.NativeTtyLeaseRetired;
            try slot.console.?.setBlocking(flag);
        }
        pub fn setRawModeAfterReadRetired(reference: Ref, flag: bool, legacy_translator: bool) !?u32 {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase != .live or slot.detached or slot.read_in_flight) return error.NativeTtyReadRetirementRequired;
            return slot.console.?.setRawModeAfterReadRetired(flag, legacy_translator);
        }
        pub fn rawMode(reference: Ref) !bool {
            lock(); defer unlock(); return (try valid(reference)).console.?.raw;
        }
        pub fn applyRawModeAfterCancelRequest(reference: Ref, flag: bool) !?u32 {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase != .live or slot.detached) return error.NativeTtyLeaseRetired;
            // Actual native KEY_EVENT translator is present, including the
            // Source fallback when VT input enablement is unsupported.
            return slot.console.?.applyRawMode(flag, true);
        }
        /// The calling VM owner is the sole synchronous writer. Registry guard
        /// only publishes native admission; no long console syscall runs under
        /// this spin guard. The output module owns its actual native mutex.
        pub fn writeBlocking(reference: Ref, bytes: []const u8) !output.Result {
            lock(); const slot = valid(reference) catch |err| { unlock(); return err; };
            if (slot.phase != .live or slot.detached or slot.write_in_flight or slot.console.?.kind != .output) { unlock(); return error.NativeTtyWriteAdmission; }
            slot.write_in_flight = true;
            // A class/resource holds the reference through the entire caller
            // frame; read worker/canceller never touches this Console decoder.
            const console = &slot.console.?;
            unlock();
            const result = console.writeBlocking(bytes);
            lock(); slot.write_in_flight = false; retireLocked(slot); unlock();
            return result;
        }
        /// Freeze all new native IO immediately. Already retained operation
        /// refs survive; no fake final/close completion follows this request.
        pub fn requestClose(reference: Ref) !bool {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.phase == .closed or slot.phase == .transferred) return true;
            if (slot.phase == .failed) return slot.retirement_failure orelse error.NativeTtyCloseRetained;
            slot.phase = .closing;
            if (slot.write_in_flight) return false;
            return slot.console.?.requestClose();
        }
        pub fn pollClose(reference: Ref) !?Close {
            lock(); defer unlock(); const slot = try valid(reference);
            if (slot.detached) return error.NativeTtyLeaseDetached;
            if (slot.phase == .closed) return .closed;
            if (slot.phase == .failed) return slot.retirement_failure orelse error.NativeTtyCloseRetained;
            if (slot.phase != .closing or slot.read_in_flight or slot.write_in_flight) return null;
            if (!try slot.console.?.requestClose()) return null;
            const result = try slot.console.?.pollClose();
            if (result) |value| switch (value) {
                .closed => slot.phase = .closed,
                .failed => { slot.phase = .failed; slot.retirement_failure = error.NativeTtyCrtCloseRetained; },
                else => {},
            };
            return result;
        }
        pub fn detach(reference: Ref) !void {
            lock(); defer unlock(); const slot = try valid(reference);
            slot.detached = true;
            if (slot.phase == .live) slot.phase = .closing;
            // Native read ticket owns a retained Ref until actual kernel return.
            // Only its later retire/release can drop the last reference.
            retireLocked(slot);
        }
        pub const Snapshot = struct { live: usize = 0, closing: usize = 0, retained_failures: usize = 0, detached: usize = 0, reads: usize = 0 };
        pub fn snapshot() Snapshot {
            lock(); defer unlock(); var value: Snapshot = .{};
            for (&slots) |*slot| {
                value.live += @intFromBool(slot.phase == .live);
                value.closing += @intFromBool(slot.phase == .closing);
                value.retained_failures += @intFromBool(slot.phase == .failed);
                value.detached += @intFromBool(slot.detached and slot.phase != .free);
                value.reads += @intFromBool(slot.read_in_flight);
            }
            return value;
        }
    };
}
