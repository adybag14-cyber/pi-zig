//! Verification-only executable; invocation requires a fresh reviewed Root grant.
const std = @import("std");
const w = @import("win32.zig");
const Storage = @import("storage.zig").Storage;
const Deadline = @import("deadline.zig").Deadline;
const common = @import("common.zig");
const grant = @import("grant.zig");
pub fn main(init: std.process.Init.Minimal) void {
    // Start the absolute whole-phase clock before filesystem/hash/probe work.
    const deadline = Deadline.start();
    var storage = Storage.create() catch { w.ExitProcess(111); };
    const allocator = storage.retain();
    const args = init.args.toSlice(allocator) catch { w.ExitProcess(111); };
    const watchdog = allocator.create(common.Watchdog) catch { w.ExitProcess(111); };
    watchdog.* = .{ .hard_ms = .init(deadline.hard_ms) };
    watchdog.start() catch { w.ExitProcess(111); };
    dispatch(&storage, args, deadline, watchdog) catch {
        // No synchronous pipe write can extend the final failure path.
        // No stack/allocator destruction while a timed-out native thread or I/O
        // can still reference it. OS closes only this process's owned handles;
        // sole fresh job kill-on-close contains its workload on every failure.
        w.ExitProcess(1);
    };
    w.ExitProcess(0);
}
fn dispatch(storage: *Storage, args: []const []const u8, deadline: Deadline, watchdog: *common.Watchdog) !void {
    if (args.len < 2) return error.ExplicitOwnerModeRequired;
    if (std.mem.eql(u8, args[1], "--supervisor")) {
        if (args.len != 5) return error.SupervisorArguments;
        const selected = std.meta.stringToEnum(grant.Phase, args[4]) orelse return error.UnknownPhase;
        const controller = try @import("supervisor.zig").Controller.prepare(storage,
            .{ .grant_path = args[2], .grant_sha = args[3], .selected = selected }, deadline);
        const passed = try controller.execute();
        try watchdog.stopRetired(deadline.hard_ms);
        if (!passed) return error.ReproductionNegative;
    } else if (std.mem.eql(u8, args[1], "--worker")) {
        if (args.len != 11) return error.WorkerArguments;
        const selected = std.meta.stringToEnum(grant.Phase, args[4]) orelse return error.UnknownPhase;
        var nonce: [32]u8 = undefined;
        var intent: [32]u8 = undefined;
        if (args[8].len != 64 or args[9].len != 64) return error.WorkerNonceArguments;
        _ = try std.fmt.hexToBytes(&nonce, args[8]); _ = try std.fmt.hexToBytes(&intent, args[9]);
        const start = try std.fmt.parseInt(u64, args[5], 10);
        const inherited = try Deadline.inherited(start);
        // Supplied inherited deadline may only shorten, never lengthen, the
        // worker's independently started hard fallback.
        try watchdog.shorten(inherited.hard_ms);
        try @import("worker.zig").run(storage, .{ .grant_path = args[2], .grant_sha = args[3], .selected = selected,
            .start_ms = start, .supervisor_pid = try std.fmt.parseInt(u32, args[6], 10),
            .control = try std.fmt.parseInt(usize, args[7], 10), .nonce = nonce, .intent = intent, .run_root = args[10] });
        try watchdog.stopRetired(inherited.hard_ms);
    } else return error.ExplicitOwnerModeRequired;
}
