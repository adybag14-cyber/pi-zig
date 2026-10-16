//! Phase worker: no job handle; supervisor must authenticate and acknowledge Node.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const grant = @import("grant.zig");
const inputs = @import("inputs.zig");
const phase = @import("phase.zig");
const command = @import("command.zig");
const process = @import("process.zig");
const protocol = @import("protocol.zig");
const Channel = @import("transport.zig").Channel;
const common = @import("common.zig");
const seals = @import("seal_set.zig");
const receipts = @import("receipts.zig");
const tools = @import("tools.zig");
const Storage = @import("storage.zig").Storage;
const Deadline = @import("deadline.zig").Deadline;
pub const Arguments = struct {
    grant_path: []const u8,
    grant_sha: []const u8,
    selected: grant.Phase,
    start_ms: u64,
    supervisor_pid: u32,
    control: usize,
    nonce: [32]u8,
    intent: [32]u8,
    run_root: []const u8,
};
pub fn run(storage: *Storage, args: Arguments) !void {
    const permanent = storage.retain();
    const deadline = try Deadline.inherited(args.start_ms);
    const self_path = try common.selfPath(permanent);
    var loaded_grant = try grant.load(permanent, args.grant_path, args.grant_sha, args.selected, self_path);
    const granted = loaded_grant.parsed.value;
    var loaded_inputs = try inputs.load(permanent, granted);
    const cfg = loaded_inputs.parsed.value;
    try files.contained(args.run_root, cfg.evidence_packet);
    const actual = try process.identity(w.GetCurrentProcess());
    if (args.control == 0 or args.control == std.math.maxInt(usize)) return error.InvalidInheritedControl;
    var channel = try Channel.init(@ptrFromInt(args.control));
    const boot_frame = try common.receive(&channel, @min(deadline.worker_cutoff_ms, w.GetTickCount64() + 10000));
    var bootstrap: protocol.WorkerBootstrap = .{ .frame = boot_frame };
    try bootstrap.authenticate(args.nonce, args.intent, actual.pid, args.supervisor_pid,
        actual.creation_filetime_utc, channel.handle);
    const worker_context = try process.VerifiedWorkerContext.fromAuthenticatedBootstrap(&bootstrap);
    var sequence: u64 = 1;
    var ready = common.frame(.ready, sequence, args.nonce, actual.pid, args.supervisor_pid,
        actual.creation_filetime_utc, args.intent);
    try common.send(&channel, &ready, deadline.worker_cutoff_ms);
    sequence += 1;
    var quota: receipts.Quota = .{ .limit = 64 * 1024 * 1024 };
    const pre_dir = try files.join(permanent, args.run_root, "worker-pre");
    if (args.selected == .build_offline) {
        // Only this separate worker step may create planned reproduction links.
        const allocator = try storage.leaseScratch();
        var namespace_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "before-links.namespace.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var file_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "before-links.files.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var diff_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "before-links.differences.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var adapter: receipts.InventorySink = .{ .observed_files = &file_writer,
            .namespace = &namespace_writer, .differences = &diff_writer };
        try phase.prepareBuildLinks(allocator, cfg, deadline.regularUntil(deadline.worker_cutoff_ms), adapter.sink());
        _ = try namespace_writer.finish(); _ = try file_writer.finish(); _ = try diff_writer.finish();
        try storage.releaseScratch();
    }
    var pre: seals.Set = .{ .storage = storage, .cfg = cfg, .granted = granted,
        .deadline = deadline.regularUntil(deadline.worker_cutoff_ms), .evidence = pre_dir, .quota = &quota, .final = false };
    pre.run();
    if (!pre.outcome.exact()) return error.WorkerPreflightNegative;
    const node_args = try phase.argv(permanent, args.selected);
    const node_command = try command.serialize(permanent, node_args);
    try command.requireRoundTrip(permanent, node_command, node_args);
    const executable = try std.unicode.utf8ToUtf16LeAllocZ(permanent, tools.node_path);
    const cwd_utf8 = if (args.selected == .npm_ci_offline) cfg.metadata else cfg.reproduction;
    const cwd = try std.unicode.utf8ToUtf16LeAllocZ(permanent, cwd_utf8);
    // Hash/scope validation consumes the exact bytes used for environment data.
    // Full prospective file inventory is separately asserted in preflight/final.
    const scratch = try storage.leaseScratch();
    const prospective = try tools.loadProspective(scratch, cfg.prospective_tools,
        granted.prospective_tool_closure_sha256);
    const home = try files.join(permanent, args.run_root, "home");
    const temp = try files.join(permanent, args.run_root, "temp");
    const env = try phase.environment(permanent, cfg, prospective, args.selected, home, temp);
    tools.releaseProspective(scratch, prospective);
    try storage.releaseScratch();
    const std_in = w.GetStdHandle(0xfffffff6) orelse return error.WorkerStdinUnavailable;
    const std_out = w.GetStdHandle(0xfffffff5) orelse return error.WorkerStdoutUnavailable;
    const std_err = w.GetStdHandle(0xfffffff4) orelse return error.WorkerStderrUnavailable;
    var node = process.Launch{};
    var pin = try files.Pinned.open(permanent, tools.node_path);
    try grant.sameHash(tools.node_hash, try pin.digest(std.crypto.hash.sha2.Sha256));
    const node_intent_path = try files.join(permanent, args.run_root, "node-intent.json");
    var intent_writer = try receipts.Writer.create(permanent, args.run_root, node_intent_path, &quota,
        deadline.regularUntil(deadline.worker_cutoff_ms));
    try intent_writer.json(.{ .phase = args.selected, .executable = tools.node_path, .argv = node_args,
        .working_directory = cwd_utf8, .heap_mib = 1536, .parent_pid = actual.pid,
        .deadline_ms = deadline.worker_cutoff_ms, .intent_hash = args.intent });
    const node_intent_hash = try intent_writer.finish();
    var intent_frame = common.frame(.node_intent, sequence, args.nonce, 0, actual.pid, 0, node_intent_hash);
    try common.send(&channel, &intent_frame, deadline.worker_cutoff_ms);
    sequence += 1;
    _ = try deadline.admitNode();
    try node.createInheritedNode(worker_context, permanent, executable, node_command, cwd, env,
        &.{ std_in, std_out, std_err }, std_in, std_out, std_err);
    try node.queryKernel();
    var created = common.frame(.node_created_suspended, sequence, args.nonce, node.info.pid, actual.pid,
        node.kernel.?.creation_filetime_utc, node_intent_hash);
    created.worker_local_node_handle = @intFromPtr(node.info.process.?);
    try common.send(&channel, &created, deadline.worker_cutoff_ms);
    sequence += 1;
    var ack_receiver: protocol.Receiver = .{ .nonce = args.nonce, .direction = .from_supervisor, .worker_pid = actual.pid };
    try ack_receiver.expectNodeAcknowledgement(node.info.pid, node.kernel.?.creation_filetime_utc);
    const ack = try common.receive(&channel, @min(deadline.worker_cutoff_ms, w.GetTickCount64() + 10000));
    if (try ack_receiver.accept(&ack) != .node_resume_ack) return error.NodeAcknowledgementRequired;
    try node.acknowledgeInheritedNode(ack.pid, ack.creation_filetime_utc);
    node.full_identity_bound = true; // authenticated supervisor completed independent binding
    const node_end = try deadline.admitNode();
    try node.resume();
    var resumed = common.frame(.node_resumed, sequence, args.nonce, node.info.pid, actual.pid,
        node.kernel.?.creation_filetime_utc, node_intent_hash);
    try common.send(&channel, &resumed, deadline.worker_cutoff_ms);
    sequence += 1;
    while (true) {
        const wait = w.WaitForSingleObject(node.info.process.?, @min(250, Deadline.remaining(node_end)));
        if (wait == w.wait_object) {
            if (w.GetTickCount64() >= node_end) return error.NodeLateCompletion;
            break;
        }
        if (wait != w.wait_timeout) return error.NodeWaitFailed;
        if (w.GetTickCount64() >= node_end) return error.Node300SecondTimeout;
        try @import("deadline.zig").requirePressureMargin();
        try channel.receive();
        if (channel.take()) |message| {
            if (try ack_receiver.accept(&message) == .abort) return error.SupervisorAbort;
            return error.UnexpectedSupervisorFrame;
        }
    }
    const exit = try node.exitRecord();
    var exited = common.frame(.node_exit_recorded, sequence, args.nonce, exit.pid, actual.pid,
        exit.creation_filetime_utc, node_intent_hash);
    exited.code = exit.exit_code;
    try common.send(&channel, &exited, deadline.worker_cutoff_ms);
    sequence += 1;
    try node.releaseExited();
    try pin.close();
    var released = common.frame(.node_references_released, sequence, args.nonce, exit.pid, actual.pid,
        exit.creation_filetime_utc, node_intent_hash);
    try common.send(&channel, &released, deadline.worker_cutoff_ms);
    sequence += 1;
    if (exit.exit_code != 0) return error.NodeNonzeroExit;
    if (args.selected == .npm_ci_offline) {
        const allocator = try storage.leaseScratch();
        var namespace_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "ci-before-transfer.namespace.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var file_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "ci-before-transfer.files.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var diff_writer = try receipts.Writer.create(allocator, pre_dir,
            try files.join(allocator, pre_dir, "ci-before-transfer.differences.jsonl"), &quota, deadline.regularUntil(deadline.worker_cutoff_ms));
        var adapter: receipts.InventorySink = .{ .observed_files = &file_writer, .namespace = &namespace_writer, .differences = &diff_writer };
        try phase.checkCiOutput(allocator, cfg, deadline.regularUntil(deadline.worker_cutoff_ms), adapter.sink());
        _ = try namespace_writer.finish(); _ = try file_writer.finish(); _ = try diff_writer.finish();
        try phase.transferExactHiddenLock(allocator, cfg);
        try storage.releaseScratch();
    }
    var primary = common.frame(.postseals_complete, sequence, args.nonce, actual.pid, args.supervisor_pid,
        actual.creation_filetime_utc, args.intent);
    // This frame is only primary payload completion. Supervisor final assertions
    // remain mandatory on both positive and negative paths after whole-job zero.
    try common.send(&channel, &primary, deadline.worker_cutoff_ms);
    sequence += 1;
    var terminal = common.frame(.worker_terminal, sequence, args.nonce, actual.pid, args.supervisor_pid,
        actual.creation_filetime_utc, args.intent);
    try common.send(&channel, &terminal, deadline.worker_cutoff_ms);
    try channel.cancel();
    while (!channel.retired() and w.GetTickCount64() < deadline.worker_cutoff_ms) try common.waitChannel(&channel, deadline.worker_cutoff_ms);
    if (!channel.retired()) return error.WorkerControlRetirementUnproven;
    try channel.closeRetired();
    // No asynchronous state remains in worker. Kernel process exit closes stdin/
    // stdout/control handles; supervisor records actual exit then releases refs.
    loaded_inputs.close();
    loaded_grant.deinit();
}
