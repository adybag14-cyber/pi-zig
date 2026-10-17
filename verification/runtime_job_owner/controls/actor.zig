//! Genuine native peer. No Node, shell, external executable or synthetic stream.
const std = @import("std");
const w = @import("../win32.zig");
const gate = @import("gate.zig");
const common = @import("../common.zig");
const process = @import("../process.zig");
const command = @import("../command.zig");
const metadata = @import("../metadata.zig");
const Ledger = @import("ledger.zig").Ledger;
const protocol = @import("../protocol.zig");
const Mode = enum { exit, gated_output, family, family_root_exit, leaf, emergency_owner, commit_pressure, clean_environment, ack_pipeline };
extern "kernel32" fn VirtualAlloc(?*anyopaque, usize, u32, u32) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
pub fn main(init: std.process.Init.Minimal) void {
    const allocator = std.heap.page_allocator;
    run(allocator, init.args.toSlice(allocator) catch { w.ExitProcess(111); }) catch { w.ExitProcess(112); };
    w.ExitProcess(0);
}
fn writeAll(handle: w.H, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u32 = 0;
        const amount: u32 = @intCast(@min(65536, bytes.len - offset));
        if (w.WriteFile(handle, bytes[offset..].ptr, amount, &count, null) == 0 or count == 0 or count > amount)
            return error.ActorWriteFailed;
        offset += count;
    }
}
fn run(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len != 9 or !std.mem.eql(u8, args[1], "--native-fixture")) return error.ActorArguments;
    const loaded = try gate.load(allocator, true);
    const mode = std.meta.stringToEnum(Mode, args[2]) orelse return error.ActorMode;
    const ready: w.H = @ptrFromInt(try std.fmt.parseInt(usize, args[3], 10));
    const release: w.H = @ptrFromInt(try std.fmt.parseInt(usize, args[4], 10));
    const amount = try std.fmt.parseInt(usize, args[5], 10);
    const depth = try std.fmt.parseInt(u32, args[6], 10);
    const zero_first = std.mem.eql(u8, args[7], "zero-first");
    const hold: w.H = @ptrFromInt(try std.fmt.parseInt(usize, args[8], 10));
    if (amount > 8 * 1024 * 1024 + 1 or depth > 2) return error.ActorBounds;
    var member: w.B = 0;
    if (w.IsProcessInJob(w.GetCurrentProcess(), null, &member) == 0 or member == 0) return error.ActorOutsideJob;
    if (w.SetEvent(ready) == 0) return error.ActorReadyFailed;
    if (w.WaitForSingleObject(release, 10000) != w.wait_object) return error.ActorGateDeadline;
    switch (mode) {
        .exit => {},
        .leaf => if (w.WaitForSingleObject(hold, 10000) != w.wait_object) return error.LeafGateDeadline,
        .gated_output => {
            const stdout = w.GetStdHandle(0xfffffff5) orelse return error.ActorStdout;
            if (zero_first) {
                var zero: u32 = 123;
                if (w.WriteFile(stdout, "".ptr, 0, &zero, null) == 0 or zero != 0) return error.ZeroWriteFailed;
            }
            const block: [65536]u8 = @splat(0x5a);
            var remaining = amount;
            while (remaining != 0) {
                const count = @min(remaining, block.len);
                try writeAll(stdout, block[0..count]);
                remaining -= count;
            }
        },
        .family, .family_root_exit => if (depth != 0)
            try spawnDescendant(allocator, loaded, ready, release, hold, depth - 1, mode == .family, false),
        .ack_pipeline => try spawnDescendant(allocator, loaded, ready, release, hold, 0, true, true),
        .emergency_owner => {
            // The fixture (not production topology) has a fresh inner unnamed
            // job solely to exercise supervisor-death kill-on-close, bounded by
            // the fixture's separately owned outer job. No host job is edited.
            // Peer review must explicitly admit this native-control topology.
            var owned = try @import("../job.zig").Job.create(@intFromPtr(&args));
            const descendant_args = [_][]const u8{ loaded.data.actor_executable, "--native-fixture", "gated_output",
                args[3], args[4], "1", "0", "normal", args[8] };
            const cmd = try command.serialize(allocator, &descendant_args);
            const image = try std.unicode.utf8ToUtf16LeAllocZ(allocator, loaded.data.actor_executable);
            const cwd = try std.unicode.utf8ToUtf16LeAllocZ(allocator, loaded.data.working_root);
            const env = try command.environment(allocator, &.{ .{ .key = "SystemRoot", .value = "C:\\Windows" },
                .{ .key = "PI_ZIG_FIXTURE_GRANT", .value = loaded.path }, .{ .key = "PI_ZIG_FIXTURE_GRANT_SHA256", .value = loaded.sha } });
            const stdin = w.GetStdHandle(0xfffffff6) orelse return error.ActorStdin;
            const stdout = w.GetStdHandle(0xfffffff5) orelse return error.ActorStdout;
            const stderr = w.GetStdHandle(0xfffffff4) orelse return error.ActorStderr;
            var child: process.Launch = .{};
            try child.createWorkerInJob(&owned, allocator, image, cmd, cwd, env,
                &.{ stdin, stdout, stderr, ready, release, hold }, stdin, stdout, stderr);
            // Deliberate death after the creation helper's membership probe,
            // before metadata binding/resume. This does not claim coverage of
            // the immediate raw CreateProcessW-return-before-probe boundary.
            w.ExitProcess(124);
        },
        .commit_pressure => {
            // One commit larger than the enforced per-process4GiB cap must be
            // denied. We do not infer absence of other denials from telemetry.
            if (VirtualAlloc(null, 4 * 1024 * 1024 * 1024 + 65536, 0x3000, 4) != null)
                return error.ProcessCommitCapNotEnforced;
        },
        .clean_environment => {
            var value: [32]u16 = undefined;
            if (GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("NODE_OPTIONS"), &value, value.len) != 0 or
                GetEnvironmentVariableW(std.unicode.utf8ToUtf16LeStringLiteral("PATH"), &value, value.len) != 0)
                return error.UnreviewedInheritedEnvironment;
        },
    }
}
fn spawnDescendant(allocator: std.mem.Allocator, loaded: gate.Loaded, ready: w.H, release: w.H,
    hold: w.H, depth: u32, wait_child: bool, ack_probe: bool) !void {
    const actual = try process.identity(w.GetCurrentProcess());
    var ledger = try Ledger.open(allocator, loaded.data.evidence_root, &actual);
    const own_meta = try allocator.create(metadata.Request);
    own_meta.* = .{ .pid = actual.pid };
    try own_meta.start();
    while (true) {
        switch (own_meta.poll()) { .timeout => return error.ActorOwnMetadataTimeout, .ready => break, .pending => {} }
        if (w.WaitForSingleObject(own_meta.thread.?, 100) == w.wait_failed) return error.ActorOwnMetadataWait;
    }
    if (own_meta.first_error) |err| return err;
    const context: process.VerifiedWorkerContext = .{ .worker_pid = actual.pid,
        .creation_filetime_utc = actual.creation_filetime_utc, .supervisor_pid = own_meta.result.parent_pid };
    try waitMetadataThread(own_meta);
    try own_meta.closeCompleted();
    const args = [_][]const u8{ loaded.data.actor_executable, "--native-fixture", if (ack_probe) "gated_output" else if (depth == 0) "leaf" else if (wait_child) "family" else "family_root_exit",
        try std.fmt.allocPrint(allocator, "{d}", .{@intFromPtr(ready)}),
        try std.fmt.allocPrint(allocator, "{d}", .{@intFromPtr(release)}), if (ack_probe) "1" else "0",
        try std.fmt.allocPrint(allocator, "{d}", .{depth}), "normal", try std.fmt.allocPrint(allocator, "{d}", .{@intFromPtr(hold)}) };
    const cmd = try command.serialize(allocator, &args);
    const image = try std.unicode.utf8ToUtf16LeAllocZ(allocator, loaded.data.actor_executable);
    const cwd = try std.unicode.utf8ToUtf16LeAllocZ(allocator, loaded.data.working_root);
    const env = try command.environment(allocator, &.{ .{ .key = "SystemRoot", .value = "C:\\Windows" },
        .{ .key = "PI_ZIG_FIXTURE_GRANT", .value = loaded.path }, .{ .key = "PI_ZIG_FIXTURE_GRANT_SHA256", .value = loaded.sha } });
    const stdin = w.GetStdHandle(0xfffffff6) orelse return error.ActorStdin;
    const stdout = w.GetStdHandle(0xfffffff5) orelse return error.ActorStdout;
    const stderr = w.GetStdHandle(0xfffffff4) orelse return error.ActorStderr;
    var child: process.Launch = .{};
    try ledger.append(.{ .state = "descendant_intent", .argv = args, .executable_sha256 = loaded.data.actor_sha256,
        .parent_pid = actual.pid, .parent_creation_filetime_utc = actual.creation_filetime_utc,
        .working_directory = loaded.data.working_root });
    try child.createInheritedNode(context, allocator, image, cmd, cwd, env, &.{ stdin, stdout, stderr, ready, release, hold }, stdin, stdout, stderr);
    try ledger.append(.{ .state = "descendant_created_suspended", .pid = child.info.pid, .tid = child.info.tid });
    try child.queryKernel();
    const request = try allocator.create(metadata.Request);
    request.* = .{ .pid = child.info.pid };
    try request.startBound(child.info.process.?);
    while (true) {
        switch (request.poll()) { .timeout => return error.ActorMetadataTimeout, .ready => break, .pending => {} }
        if (w.WaitForSingleObject(request.thread.?, 100) == w.wait_failed) return error.ActorMetadataWait;
    }
    if (request.first_error) |err| return err;
    try metadata.requireMatch(&request.result, &child.kernel.?, actual.pid, image, cmd);
    try ledger.append(.{ .state = "descendant_bound", .pid = request.result.pid, .parent_pid = request.result.parent_pid,
        .creation_filetime_utc = request.result.creation_filetime_utc, .image_utf16 = request.result.image[0..request.result.image_units],
        .command_utf16 = request.result.command[0..request.result.command_units],
        .image_authority = request.result.image_authority,
        .wmi_image_available = request.result.wmi_image_available,
        .wmi_image_property = request.result.wmi_image_property,
        .wmi_image_utf16 = request.result.wmi_image[0..request.result.wmi_image_units] });
    child.full_identity_bound = true;
    if (ack_probe) try exerciseAckPipeline(&child, actual.pid, &ledger) else
        try child.acknowledgeInheritedNode(child.info.pid, child.kernel.?.creation_filetime_utc);
    try child.resumeVerified();
    try ledger.append(.{ .state = "descendant_resumed", .pid = child.info.pid,
        .creation_filetime_utc = child.kernel.?.creation_filetime_utc, .ack_probe = ack_probe });
    if (!wait_child) {
        try ledger.append(.{ .state = "live_descendant_references_retire_at_actor_exit", .pid = child.info.pid,
            .live_at_observation = w.WaitForSingleObject(child.info.process.?, 0) == w.wait_timeout });
        try waitMetadataThread(request); try request.closeCompleted(); try ledger.close();
        return;
    }
    if (w.WaitForSingleObject(child.info.process.?, 10000) != w.wait_object) return error.ActorDescendantDeadline;
    const exited = try child.exitRecord();
    try ledger.append(.{ .state = "descendant_exit_before_reference_release", .identity = exited });
    if (exited.exit_code != 0) return error.ActorDescendantFailed;
    // The fixture root preserves actual kernel lifetime accounting; this local
    // native peer does not claim production supervisor Node-ACK qualification.
    try child.releaseExited();
    try ledger.append(.{ .state = "descendant_references_released", .pid = exited.pid });
    try waitMetadataThread(request);
    try request.closeCompleted();
    try ledger.close();
}
fn waitMetadataThread(request: *metadata.Request) !void {
    if (w.WaitForSingleObject(request.thread orelse return error.ActorMetadataThreadMissing, 2000) != w.wait_object)
        return error.ActorMetadataThreadRetirement;
}
fn exerciseAckPipeline(child: *process.Launch, parent: u32, ledger: *Ledger) !void {
    const nonce = try @import("../security.zig").nonce();
    const wrong_nonce = try @import("../security.zig").nonce();
    var receiver: protocol.Receiver = .{ .nonce = nonce, .direction = .from_supervisor, .worker_pid = parent };
    try receiver.expectNodeAcknowledgement(child.info.pid, child.kernel.?.creation_filetime_utc);
    var invalid = common.frame(.node_resume_ack, 1, wrong_nonce, child.info.pid, parent,
        child.kernel.?.creation_filetime_utc, @splat(0));
    if (receiver.accept(&invalid)) |_| return error.BadNonceAccepted else |err| if (err != error.InvalidProtocolFrame) return err;
    if (child.resumeVerified()) |_| return error.InvalidAckResumedChild else |err| if (err != error.UnacknowledgedResumeForbidden) return err;
    var reordered = common.frame(.node_resume_ack, 2, nonce, child.info.pid, parent,
        child.kernel.?.creation_filetime_utc, @splat(0));
    if (receiver.accept(&reordered)) |_| return error.ReorderedAckAccepted else |err| if (err != error.InvalidProtocolFrame) return err;
    if (child.resumeVerified()) |_| return error.ReorderedAckResumedChild else |err| if (err != error.UnacknowledgedResumeForbidden) return err;
    try ledger.append(.{ .state = "invalid_ack_actual_node_resume_rejected", .pid = child.info.pid,
        .resumed = child.resumed, .actual_process_signaled = w.WaitForSingleObject(child.info.process.?, 0) == w.wait_object });
    if (child.resumed or w.WaitForSingleObject(child.info.process.?, 0) != w.wait_timeout) return error.InvalidAckChildState;
    var valid = common.frame(.node_resume_ack, 1, nonce, child.info.pid, parent,
        child.kernel.?.creation_filetime_utc, @splat(0));
    if (try receiver.accept(&valid) != .node_resume_ack) return error.ValidAckRejected;
    try child.acknowledgeInheritedNode(valid.pid, valid.creation_filetime_utc);
    if (receiver.accept(&valid)) |_| return error.DuplicateAckAccepted else |err| if (err != error.InvalidProtocolFrame) return err;
    try ledger.append(.{ .state = "valid_ack_bound_before_actual_resume", .pid = child.info.pid,
        .creation_filetime_utc = child.kernel.?.creation_filetime_utc });
}
