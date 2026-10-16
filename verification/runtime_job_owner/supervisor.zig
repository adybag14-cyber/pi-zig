//! Timing/control supervisor. Workload job is private; final checks are a thread.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const grant = @import("grant.zig");
const inputs = @import("inputs.zig");
const tools = @import("tools.zig");
const phase = @import("phase.zig");
const command = @import("command.zig");
const process = @import("process.zig");
const metadata = @import("metadata.zig");
const protocol = @import("protocol.zig");
const Channel = @import("transport.zig").Channel;
const Pair = @import("pipes.zig").Pair;
const Capture = @import("overlapped.zig").Capture;
const PrivateAcl = @import("security.zig").PrivateAcl;
const Job = @import("job.zig").Job;
const Queue = @import("persistence.zig").Queue;
const common = @import("common.zig");
const admission = @import("admission.zig");
const seals = @import("seal_set.zig");
const receipts = @import("receipts.zig");
const Storage = @import("storage.zig").Storage;
const Deadline = @import("deadline.zig").Deadline;
pub const Arguments = struct { grant_path: []const u8, grant_sha: []const u8, selected: grant.Phase };

const FinalTask = struct {
    set: seals.Set,
    completed: std.atomic.Value(bool) = .init(false),
    thread: ?w.H = null,
    pub fn start(self: *FinalTask) !void {
        if (self.thread != null) return error.FinalSealerOneShot;
        self.thread = w.CreateThread(null, 8 * 1024 * 1024, run, self, 0, null) orelse return error.FinalSealerThreadFailed;
    }
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *FinalTask = @ptrCast(@alignCast(raw.?));
        self.set.run();
        self.completed.store(true, .release);
        return 0;
    }
};

pub const Controller = struct {
    storage: *Storage,
    args: Arguments,
    deadline: Deadline,
    cfg: inputs.Config,
    granted: grant.Data,
    own: process.KernelIdentity,
    owner_path: []const u8,
    run_root: []const u8,
    nonce: [32]u8,
    intent: [32]u8,
    job: Job,
    acl: PrivateAcl,
    output_pair: Pair,
    error_pair: Pair,
    control_pair: Pair,
    channel: Channel,
    output: Capture,
    errors: Capture,
    log_queue: *Queue,
    worker: process.Launch = .{},
    worker_command: [:0]u16,
    worker_image: [:0]u16,
    node_command: [:0]u16,
    node_image: [:0]u16,
    node_handle: ?w.H = null,
    node_kernel: ?process.KernelIdentity = null,
    node_exit_code: ?u32 = null,
    node_identity_bound: bool = false,
    node_end_ms: ?u64 = null,
    worker_exit_code: ?u32 = null,
    receiver: protocol.Receiver,
    worker_meta: *metadata.Request,
    node_meta: ?*metadata.Request = null,
    first_error: ?anyerror = null,
    cleanup_error: ?anyerror = null,
    job_zero: bool = false,
    pipes_retired: bool = false,
    capture_complete: bool = false,
    metadata_retired: bool = false,
    early_retirement_ms: u64 = 0,
    final_task: ?*FinalTask = null,
    final_quota: receipts.Quota = .{ .limit = 192 * 1024 * 1024 },
    publication_quota: receipts.Quota = .{ .limit = 1024 * 1024 },
    ledger_retired: bool = false,
    capture_handles_closed: bool = false,
    last_snapshot: ?@import("job.zig").Snapshot = null,
    last_snapshot_logged_ms: u64 = 0,
    owner_pin: files.Pinned,
    node_pin: files.Pinned,

    pub fn prepare(storage: *Storage, args: Arguments, deadline: Deadline) !*Controller {
        const allocator = storage.retain();
        const owner_path = try common.selfPath(allocator);
        const loaded_grant = try grant.load(allocator, args.grant_path, args.grant_sha, args.selected, owner_path);
        const granted = loaded_grant.parsed.value;
        const loaded_inputs = try inputs.load(allocator, granted);
        const cfg = loaded_inputs.parsed.value;
        const own = try process.identity(w.GetCurrentProcess());
        const runs = try files.join(allocator, cfg.evidence_packet, "runs");
        try common.ensureDirectory(allocator, runs, cfg.evidence_packet);
        const attempt = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ @tagName(args.selected), granted.attempt });
        const run_root = try files.join(allocator, runs, attempt);
        try common.freshDirectory(allocator, run_root, cfg.evidence_packet);
        for ([_][]const u8{ "worker-pre", "supervisor-final", "home", "temp" }) |name|
            try common.freshDirectory(allocator, try files.join(allocator, run_root, name), run_root);
        const c = try allocator.create(Controller);
        const job = try Job.create(@intFromPtr(c));
        const acl = try PrivateAcl.create(allocator);
        const output_pair = try Pair.create(allocator, &acl, "stdout", false, deadline);
        const error_pair = try Pair.create(allocator, &acl, "stderr", false, deadline);
        const control_pair = try Pair.create(allocator, &acl, "control", true, deadline);
        const output_file = try files.openLeaf(allocator, try files.join(allocator, run_root, "stdout.log"),
            w.generic_write, w.create_new, w.file_flag_overlapped);
        const error_file = try files.openLeaf(allocator, try files.join(allocator, run_root, "stderr.log"),
            w.generic_write, w.create_new, w.file_flag_overlapped);
        const log_file = try files.openLeaf(allocator, try files.join(allocator, run_root, "owner-ledger.jsonl"),
            w.generic_write, w.create_new, 0);
        const queue = try allocator.create(Queue);
        queue.* = .{ .file = log_file };
        try queue.start();
        const nonce = try @import("security.zig").nonce();
        var intent: [32]u8 = undefined;
        _ = try std.fmt.hexToBytes(&intent, args.grant_sha);
        const nonce_hex = std.fmt.bytesToHex(nonce, .lower);
        const intent_hex = std.fmt.bytesToHex(intent, .lower);
        const worker_args = [_][]const u8{ owner_path, "--worker", args.grant_path, args.grant_sha, @tagName(args.selected),
            try std.fmt.allocPrint(allocator, "{d}", .{deadline.start_ms}),
            try std.fmt.allocPrint(allocator, "{d}", .{own.pid}),
            try std.fmt.allocPrint(allocator, "{d}", .{@intFromPtr(control_pair.client.?)}),
            &nonce_hex, &intent_hex, run_root };
        const worker_command = try command.serialize(allocator, &worker_args);
        try command.requireRoundTrip(allocator, worker_command, &worker_args);
        const node_args = try phase.argv(allocator, args.selected);
        const node_command = try command.serialize(allocator, node_args);
        try command.requireRoundTrip(allocator, node_command, node_args);
        const worker_meta = try allocator.create(metadata.Request);
        worker_meta.* = .{ .pid = 0 };
        var owner_pin = try files.Pinned.open(allocator, owner_path);
        try grant.sameHash(granted.owner_executable_sha256, try owner_pin.digest(std.crypto.hash.sha2.Sha256));
        var node_pin = try files.Pinned.open(allocator, tools.node_path);
        try grant.sameHash(tools.node_hash, try node_pin.digest(std.crypto.hash.sha2.Sha256));
        c.* = .{ .storage = storage, .args = args, .deadline = deadline, .cfg = cfg, .granted = granted,
            .own = own, .owner_path = owner_path, .run_root = run_root, .nonce = nonce, .intent = intent,
            .job = job, .acl = acl, .output_pair = output_pair, .error_pair = error_pair,
            .control_pair = control_pair, .channel = try Channel.init(control_pair.server.?),
            .output = try Capture.init(output_pair.server.?, output_file), .errors = try Capture.init(error_pair.server.?, error_file),
            .log_queue = queue, .worker_command = worker_command,
            .worker_image = try std.unicode.utf8ToUtf16LeAllocZ(allocator, owner_path),
            .node_command = node_command, .node_image = try std.unicode.utf8ToUtf16LeAllocZ(allocator, tools.node_path),
            .receiver = .{ .nonce = nonce, .direction = .from_worker, .worker_pid = 0 },
            .worker_meta = worker_meta, .owner_pin = owner_pin, .node_pin = node_pin };
        // No I/O is issued until the aggregate has reached its stable heap address.
        try c.output.advance(); try c.errors.advance(); try c.channel.receive();
        return c;
    }

    pub fn execute(self: *Controller) !bool {
        const successful = self.executePhases() catch |err| failed: {
            self.first_error = self.first_error orelse err;
            break :failed false;
        };
        // An unfinished final thread remains retained. Publication takes an
        // immutable outcome copy only after its release-store; otherwise final
        // coverage is explicitly unknown. It has a separate quota/allocator
        // region, never the sealer's mutable scratch or evidence counters.
        try self.publishTerminal(successful);
        return successful;
    }
    fn executePhases(self: *Controller) !bool {
        self.workload() catch |err| { self.first_error = err; };
        self.early_retirement_ms = w.GetTickCount64();
        self.retire() catch |err| { self.cleanup_error = err; };
        if (!self.job_zero) return error.JobRetirementUnproven;
        const allocator = self.storage.retain();
        const final = try allocator.create(FinalTask);
        const final_dir = try files.join(allocator, self.run_root, "supervisor-final");
        final.* = .{ .set = .{ .storage = self.storage, .cfg = self.cfg, .granted = self.granted,
            .deadline = self.deadline.regularUntil(self.deadline.finalStageEnd(self.early_retirement_ms)),
            .evidence = final_dir, .quota = &self.final_quota, .final = true } };
        self.final_task = final;
        try final.start();
        const final_end = self.deadline.finalStageEnd(self.early_retirement_ms);
        while (!final.completed.load(.acquire)) {
            if (w.GetTickCount64() >= final_end) return error.FinalSealerDeadline;
            try self.log_queue.requireResponsive();
            if (w.WaitForSingleObject(final.thread.?, @min(250, Deadline.remaining(final_end))) == w.wait_failed)
                return error.FinalSealerWaitFailed;
        }
        if (final.set.outcome.completed_ms > final_end) return error.FinalSealerLateCompletion;
        if (w.WaitForSingleObject(final.thread.?, Deadline.remaining(self.deadline.cutoff_ms)) != w.wait_object)
            return error.FinalSealerThreadNotRetired;
        if (w.CloseHandle(final.thread.?) == 0) return error.FinalSealerThreadCloseFailed;
        final.thread = null;
        self.settleReceipts() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
        const successful = self.first_error == null and self.cleanup_error == null and self.job_zero and self.pipes_retired and
            self.ledger_retired and self.capture_handles_closed and self.metadata_retired and self.capture_complete and
            self.worker_exit_code != null and self.worker_exit_code.? == 0 and self.node_exit_code != null and
            self.node_exit_code.? == 0 and self.node_identity_bound and final.set.outcome.exact();
        return successful;
    }
    fn workload(self: *Controller) !void {
        const allocator = self.storage.retain();
        var stdin_attrs = self.acl.attributes(true);
        const null_name = std.unicode.utf8ToUtf16LeStringLiteral("NUL");
        const stdin_handle = w.CreateFileW(null_name, w.generic_read, 1 | 2, &stdin_attrs, w.open_existing, 0, null);
        if (stdin_handle == w.invalid) return error.NullStdinFailed;
        defer _ = w.CloseHandle(stdin_handle);
        const home = try files.join(allocator, self.run_root, "home");
        const temp = try files.join(allocator, self.run_root, "temp");
        const prospective = try tools.loadProspective(allocator, self.cfg.prospective_tools,
            self.granted.prospective_tool_closure_sha256);
        defer tools.releaseProspective(allocator, prospective);
        const env = try phase.environment(allocator, self.cfg, prospective, self.args.selected, home, temp);
        const cwd = try std.unicode.utf8ToUtf16LeAllocZ(allocator, self.cfg.evidence_packet);
        try admission.requireQuietNative(&self.own, &self.job, .{ .context = self, .write_fn = nativeObservation });
        const intended = try self.log(.{ .state = "worker_intent", .executable = self.owner_path,
            .command_utf16 = self.worker_command[0..], .parent_pid = self.own.pid,
            .start_ms = self.deadline.start_ms, .hard_deadline_ms = self.deadline.hard_ms });
        try self.waitLogged(intended, @min(self.deadline.worker_cutoff_ms, w.GetTickCount64() + 2000));
        try self.worker.createWorkerInJob(&self.job, allocator, self.worker_image, self.worker_command, cwd, env,
            &.{ stdin_handle, self.output_pair.client.?, self.error_pair.client.?, self.control_pair.client.? },
            stdin_handle, self.output_pair.client.?, self.error_pair.client.?);
        // All returned PI bits/association already retained before these probes.
        _ = try self.log(.{ .state = "worker_created_job_associated", .pid = self.worker.info.pid,
            .tid = self.worker.info.tid, .created = self.worker.created_by_this_call });
        try self.output_pair.closeClient(); try self.error_pair.closeClient(); try self.control_pair.closeClient();
        try self.worker.queryKernel();
        self.receiver.worker_pid = self.worker.info.pid;
        self.worker_meta.* = .{ .pid = self.worker.info.pid };
        try self.worker_meta.start();
        try self.awaitMetadata(self.worker_meta);
        try metadata.requireMatch(&self.worker_meta.result, &self.worker.kernel.?, self.own.pid,
            self.worker_image, self.worker_command);
        const bound = try self.logIdentity("worker_bound", &self.worker_meta.result);
        try self.waitLogged(bound, @min(self.deadline.worker_cutoff_ms, w.GetTickCount64() + 2000));
        self.worker.full_identity_bound = true;
        var boot = common.frame(.worker_containment_ack, 0, self.nonce, self.worker.info.pid, self.own.pid,
            self.worker.kernel.?.creation_filetime_utc, self.intent);
        try common.send(&self.channel, &boot, self.deadline.worker_cutoff_ms);
        try self.worker.resume();
        while (true) {
            if (w.GetTickCount64() >= self.deadline.worker_cutoff_ms) return error.WorkerStageDeadline;
            if (self.node_end_ms) |end| if (self.node_exit_code == null and w.GetTickCount64() >= end)
                return error.SupervisorNode300SecondTimeout;
            try @import("deadline.zig").requirePressureMargin();
            try self.pump();
            if (self.channel.take()) |frame| {
                const kind = try self.receiver.accept(&frame);
                _ = try self.log(.{ .state = "worker_frame", .kind = kind, .sequence = frame.sequence,
                    .pid = frame.pid, .creation_filetime_utc = frame.creation_filetime_utc, .code = frame.code });
                switch (kind) {
                    .node_created_suspended => try self.bindNode(frame),
                    .node_resumed => if (self.node_end_ms == null) return error.NodeResumeNotAdmitted,
                    .node_exit_recorded => {
                        const handle = self.node_handle orelse return error.NodeHandleMissing;
                        if (w.WaitForSingleObject(handle, 0) != w.wait_object) return error.NodeExitNotSignaled;
                        var exit_code: u32 = 0;
                        if (w.GetExitCodeProcess(handle, &exit_code) == 0 or exit_code != frame.code) return error.NodeExitMismatch;
                        // A late signal/frame may arrive while pump/probe work
                        // crosses the boundary. Loop-entry checks alone cannot
                        // qualify completion observed after the Node deadline.
                        if (w.GetTickCount64() >= (self.node_end_ms orelse return error.NodeResumeNotAdmitted))
                            return error.SupervisorNodeLateCompletion;
                        self.node_exit_code = exit_code;
                        if (w.CloseHandle(handle) == 0) return error.NodeDuplicateCloseFailed;
                        self.node_handle = null;
                    },
                    .abort => return error.WorkerReportedAbort,
                    else => {},
                }
            }
            const wait = w.WaitForSingleObject(self.worker.info.process.?, 0);
            if (wait == w.wait_object) {
                const exit = try self.worker.exitRecord();
                if (self.worker_exit_code == null) {
                    self.worker_exit_code = exit.exit_code;
                    _ = try self.log(.{ .state = "worker_exit", .pid = exit.pid,
                        .creation_filetime_utc = exit.creation_filetime_utc, .exit_code = exit.exit_code });
                }
                if (exit.exit_code != 0) return error.WorkerNonzeroExit;
                if (self.receiver.state != .terminal) {
                    // Drain already written complete protocol frames before
                    // judging an exit; never fabricate a terminal frame.
                    try self.channel.receive();
                    if (self.channel.ready != null) continue;
                    if (self.channel.closed) return error.WorkerTerminalFrameMissing;
                    try self.waitEvents(self.deadline.worker_cutoff_ms);
                    continue;
                }
                return;
            }
            if (wait != w.wait_timeout) return error.WorkerWaitFailed;
            if (self.channel.closed and self.receiver.state != .terminal) return error.WorkerControlClosedEarly;
            try self.waitEvents(self.deadline.worker_cutoff_ms);
        }
    }
    fn bindNode(self: *Controller, frame: protocol.Frame) !void {
        if (self.node_handle != null or self.node_meta != null) return error.SecondNodeLaunchForbidden;
        const handle = try process.pullNode(self.worker.info.process.?, @intCast(frame.worker_local_node_handle), frame.pid, &self.job);
        self.node_handle = handle;
        self.node_kernel = try process.identity(handle);
        if (self.node_kernel.?.creation_filetime_utc != frame.creation_filetime_utc) return error.NodeCreationFrameMismatch;
        const request = try self.storage.retain().create(metadata.Request);
        request.* = .{ .pid = frame.pid };
        self.node_meta = request;
        try request.start();
        try self.awaitMetadata(request);
        try metadata.requireMatch(&request.result, &self.node_kernel.?, self.worker.info.pid, self.node_image, self.node_command);
        try self.job.requireMember(handle);
        const bound = try self.logIdentity("node_bound", &request.result);
        try self.waitLogged(bound, @min(self.deadline.worker_cutoff_ms, w.GetTickCount64() + 2000));
        try admission.requireQuietNative(&self.own, &self.job, .{ .context = self, .write_fn = nativeObservation });
        // ACK permits immediate resume; the supervisor's independent 300-second
        // bound begins before ACK and cannot be extended by a delayed frame.
        self.node_end_ms = try self.deadline.admitNode();
        self.node_identity_bound = true;
        var ack = common.frame(.node_resume_ack, 1, self.nonce, frame.pid, self.worker.info.pid,
            frame.creation_filetime_utc, frame.input_sha256);
        try common.send(&self.channel, &ack, self.deadline.worker_cutoff_ms);
        try self.receiver.acknowledgedNode();
    }
    fn awaitMetadata(self: *Controller, request: *metadata.Request) !void {
        while (true) {
            switch (request.poll()) {
                .timeout => return error.MetadataProbeTimeout,
                .ready => {
                    if (request.first_error) |err| return err;
                    return;
                },
                .pending => {},
            }
            try self.pump();
            try self.waitEvents(@min(self.deadline.worker_cutoff_ms, request.started_ms + 2000));
        }
    }
    fn pump(self: *Controller) !void {
        try self.output.advance(); try self.errors.advance();
        if (self.output.first_error) |err| return err;
        if (self.errors.first_error) |err| return err;
        try self.channel.advanceWrite();
        try self.channel.receive();
        try self.log_queue.requireResponsive();
        var notices: [64]@import("job.zig").Notice = undefined;
        var notice_count: usize = 0;
        var observed_limit = false;
        while (notice_count < notices.len) {
            const notice = (try self.job.notice(0)) orelse break;
            notices[notice_count] = notice;
            notice_count += 1;
            // ACTIVE_PROCESS_LIMIT, PROCESS_MEMORY_LIMIT, JOB_MEMORY_LIMIT.
            if (notice.message == 3 or notice.message == 9 or notice.message == 10) observed_limit = true;
        }
        if (notice_count != 0) _ = try self.log(.{ .state = "advisory_job_notices", .notices = notices[0..notice_count],
            .batch_bound = notices.len, .delivery_coverage = "not_guaranteed", .individual_identity_coverage = "not_implied" });
        const snapshot = try self.job.snapshot();
        try self.observeSnapshot(snapshot, false);
        if (observed_limit or snapshot.accounting.basic.terminated_for_limit != 0) return error.ObservedJobLimitTermination;
    }
    fn waitEvents(self: *Controller, end: u64) !void {
        if (w.GetTickCount64() >= end) return error.OperationDeadline;
        var events: [6]w.H = undefined;
        var count: usize = 0;
        inline for (.{ &self.output.read, &self.output.write, &self.errors.read,
            &self.errors.write, &self.channel.reader, &self.channel.writer }) |operation| {
            if (operation.pending) { events[count] = operation.event.?; count += 1; }
        }
        try common.waitPending(events[0..count], end);
    }
    fn observeSnapshot(self: *Controller, snapshot: @import("job.zig").Snapshot, force: bool) !void {
        const now = w.GetTickCount64();
        var changed = true;
        if (self.last_snapshot) |previous| changed = previous.accounting.basic.total_processes != snapshot.accounting.basic.total_processes or
            previous.accounting.basic.active_processes != snapshot.accounting.basic.active_processes or
            previous.members.returned != snapshot.members.returned or
            !std.mem.eql(usize, previous.members.pids[0..previous.members.returned], snapshot.members.pids[0..snapshot.members.returned]);
        self.last_snapshot = snapshot;
        if (force or changed or now - self.last_snapshot_logged_ms >= 250) {
            _ = try self.log(.{ .state = "job_snapshot", .observed_ms = now,
                .accounting = snapshot.accounting, .assigned = snapshot.members.assigned,
                .returned = snapshot.members.returned, .pids = snapshot.members.pids[0..snapshot.members.returned],
                .limits = snapshot.limits, .queries_are_separate_observations = true,
                .transient_individual_metadata_coverage = "partial", .memory_denial_attempt_coverage = "observed_only" });
            self.last_snapshot_logged_ms = now;
        }
    }
    fn retire(self: *Controller) !void {
        const end = @min(self.early_retirement_ms + 10000, self.deadline.cutoff_ms);
        self.output_pair.closeClient() catch |err| { self.cleanup_error = err; };
        self.error_pair.closeClient() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
        self.control_pair.closeClient() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
        // Always stop remaining owned descendants, including a service whose
        // root already exited. No PID/tree/global discovery selects this stop.
        self.job.abort(125) catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
        while (w.GetTickCount64() < end) {
            if (self.node_handle) |handle| {
                if (w.WaitForSingleObject(handle, 0) == w.wait_object) {
                    var code: u32 = 0;
                    if (w.GetExitCodeProcess(handle, &code) == 0) return error.NodeRetirementExitUnknown;
                    self.node_exit_code = self.node_exit_code orelse code;
                    const record = try self.log(.{ .state = "node_retired", .pid = w.GetProcessId(handle), .exit_code = code });
                    try self.waitLogged(record, @min(end, w.GetTickCount64() + 2000));
                    if (w.CloseHandle(handle) == 0) return error.NodeDuplicateCloseFailed;
                    self.node_handle = null;
                }
            }
            if (self.worker.created_by_this_call and self.worker.info.process != null and
                w.WaitForSingleObject(self.worker.info.process.?, 0) == w.wait_object) {
                const exit = try self.worker.exitRecord();
                self.worker_exit_code = self.worker_exit_code orelse exit.exit_code;
                const record = try self.log(.{ .state = "worker_retired", .pid = exit.pid,
                    .creation_filetime_utc = exit.creation_filetime_utc, .exit_code = exit.exit_code });
                try self.waitLogged(record, @min(end, w.GetTickCount64() + 2000));
                try self.worker.releaseExited();
            }
            if (self.worker_meta.completed.load(.acquire) and self.worker_meta.thread != null)
                self.worker_meta.closeCompleted() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
            if (self.node_meta) |request| if (request.completed.load(.acquire) and request.thread != null)
                request.closeCompleted() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
            self.metadata_retired = self.worker_meta.thread == null and
                (if (self.node_meta) |request| request.thread == null else true);
            self.output.advance() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
            self.errors.advance() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
            if (self.output.first_error) |err| self.cleanup_error = self.cleanup_error orelse err;
            if (self.errors.first_error) |err| self.cleanup_error = self.cleanup_error orelse err;
            self.channel.cancel() catch |err| { self.cleanup_error = self.cleanup_error orelse err; };
            const snapshot = try self.job.snapshot();
            try self.observeSnapshot(snapshot, snapshot.zero());
            if (snapshot.zero() and self.worker.info.process == null and self.node_handle == null) self.job_zero = true;
            self.pipes_retired = self.output.ioRetired() and self.errors.ioRetired() and self.channel.retired() and
                (self.output.state == .eof or self.output.state == .failed) and (self.errors.state == .eof or self.errors.state == .failed);
            self.capture_complete = self.pipes_retired and self.output.state == .eof and self.errors.state == .eof and
                self.output.first_error == null and self.errors.first_error == null and
                !self.output.overflow and !self.errors.overflow and
                self.output.bytes_received == self.output.bytes_written and self.errors.bytes_received == self.errors.bytes_written;
            if (self.job_zero and self.pipes_retired and self.metadata_retired) return;
            try self.waitEvents(end);
        }
        return error.SharedRetirementDeadline;
    }
    fn settleReceipts(self: *Controller) !void {
        if (!self.pipes_retired or !self.job_zero) return error.SettlementRequiresRetirement;
        const end = self.deadline.cutoff_ms;
        const stdout_flush = try self.log_queue.flushExternal(self.output.write.file);
        try self.waitLogged(stdout_flush, @min(end, w.GetTickCount64() + 2000));
        const stderr_flush = try self.log_queue.flushExternal(self.errors.write.file);
        try self.waitLogged(stderr_flush, @min(end, w.GetTickCount64() + 2000));
        var output_hash: [32]u8 = undefined;
        var error_hash: [32]u8 = undefined;
        self.output.hash.final(&output_hash); self.errors.hash.final(&error_hash);
        const last = try self.log(.{ .state = "retired_output_summary", .stdout_sha256 = std.fmt.bytesToHex(output_hash, .upper),
            .stderr_sha256 = std.fmt.bytesToHex(error_hash, .upper), .stdout_received = self.output.bytes_received,
            .stdout_written = self.output.bytes_written, .stderr_received = self.errors.bytes_received,
            .stderr_written = self.errors.bytes_written, .stdout_overflow = self.output.overflow,
            .stderr_overflow = self.errors.overflow, .pipes_retired = self.pipes_retired, .job_zero = self.job_zero });
        try self.waitLogged(last, @min(end, w.GetTickCount64() + 2000));
        try self.output.close(); try self.errors.close(); try self.channel.closeRetired();
        try self.output_pair.closeServer(false); try self.error_pair.closeServer(false); try self.control_pair.closeServer(false);
        if (w.CloseHandle(self.output.write.file) == 0) return error.StdoutSinkCloseFailed;
        if (w.CloseHandle(self.errors.write.file) == 0) return error.StderrSinkCloseFailed;
        self.capture_handles_closed = true;
        const stop = try self.log_queue.stop();
        while (!try self.log_queue.acknowledged(stop)) {
            try self.log_queue.requireResponsive();
            try common.waitPending(&.{self.log_queue.thread.?}, @min(end, w.GetTickCount64() + 250));
        }
        while (self.log_queue.thread != null or self.log_queue.wake != null) {
            self.log_queue.closeCompleted() catch |err| {
                if (w.GetTickCount64() >= end) return err;
                if (self.log_queue.thread) |thread| try common.waitPending(&.{thread}, end)
                    else return err;
                continue;
            };
        }
        if (w.CloseHandle(self.log_queue.file) == 0) return error.LedgerSinkCloseFailed;
        self.ledger_retired = true;
        try self.owner_pin.close(); try self.node_pin.close();
        try self.job.close(); try self.acl.close();
    }
    fn log(self: *Controller, value: anytype) !u64 {
        var buffer: [256 * 1024]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try std.json.Stringify.value(value, .{}, &writer);
        try writer.writeByte('\n');
        return self.log_queue.append(writer.buffered());
    }
    fn waitLogged(self: *Controller, sequence: u64, end: u64) !void {
        while (!try self.log_queue.acknowledged(sequence)) {
            try self.log_queue.requireResponsive();
            if (w.GetTickCount64() >= end) return error.PersistenceAckDeadline;
            try self.output.advance(); try self.errors.advance();
            try self.waitEvents(end);
        }
    }
    fn logIdentity(self: *Controller, state: []const u8, row: *const metadata.Result) !u64 {
        const allocator = self.storage.retain();
        const image = try std.unicode.utf16LeToUtf8Alloc(allocator, row.image[0..row.image_units]);
        defer allocator.free(image);
        const cmd = try std.unicode.utf16LeToUtf8Alloc(allocator, row.command[0..row.command_units]);
        defer allocator.free(cmd);
        return self.log(.{ .state = state, .pid = row.pid, .parent_pid = row.parent_pid,
            .creation_filetime_utc = row.creation_filetime_utc, .executable = image, .command_line = cmd });
    }
    fn publishTerminal(self: *Controller, success: bool) !void {
        // Publication runs in a separately bounded thread below, not this timing
        // loop. The worker/sealer state remains retained until actual completion.
        const allocator = self.storage.retain();
        const publish = try allocator.create(Publication);
        var outcome: ?seals.Outcome = null;
        if (self.final_task) |final| if (final.completed.load(.acquire)) { outcome = final.set.outcome; };
        publish.* = .{ .controller = self, .success = success, .outcome = outcome };
        const thread = w.CreateThread(null, 2 * 1024 * 1024, Publication.run, publish, 0, null) orelse return error.TerminalThreadFailed;
        while (!publish.completed.load(.acquire)) {
            if (w.GetTickCount64() >= self.deadline.cutoff_ms) return error.TerminalPublicationDeadline;
            if (w.WaitForSingleObject(thread, @min(250, Deadline.remaining(self.deadline.cutoff_ms))) == w.wait_failed)
                return error.TerminalPublicationWaitFailed;
        }
        if (publish.first_error) |err| return err;
        if (publish.completed_ms > self.deadline.cutoff_ms) return error.TerminalPublicationLate;
        if (w.WaitForSingleObject(thread, Deadline.remaining(self.deadline.hard_ms)) != w.wait_object) return error.TerminalThreadNotRetired;
        if (w.CloseHandle(thread) == 0) return error.TerminalThreadCloseFailed;
    }
};

const Publication = struct {
    controller: *Controller,
    success: bool,
    outcome: ?seals.Outcome,
    completed: std.atomic.Value(bool) = .init(false),
    completed_ms: u64 = 0,
    first_error: ?anyerror = null,
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Publication = @ptrCast(@alignCast(raw.?));
        self.write() catch |err| { self.first_error = err; };
        self.completed_ms = w.GetTickCount64();
        self.completed.store(true, .release);
        return 0;
    }
    fn write(self: *Publication) !void {
        const c = self.controller;
        const allocator = c.storage.retain();
        const temp = try files.join(allocator, c.run_root, "phase-terminal.tmp.json");
        const target = try files.join(allocator, c.run_root, "phase-terminal.json");
        var writer = try receipts.Writer.create(allocator, c.run_root, temp, &c.publication_quota, c.deadline);
        defer writer.closePartial() catch {};
        const count = if (c.last_snapshot) |snapshot| snapshot.accounting.basic.total_processes else 0;
        const known: u32 = @as(u32, @intFromBool(c.worker.created_by_this_call)) + @as(u32, @intFromBool(c.node_identity_bound));
        try writer.json(.{ .schema = 1, .phase = c.args.selected,
            .status = if (self.success) (if (c.args.selected == .npm_ci_offline) "ci_reproduced_exact" else "reproduced_exact_pending_independent_review") else "negative",
            .first_error = if (c.first_error) |err| @errorName(err) else @as(?[]const u8, null),
            .cleanup_error = if (c.cleanup_error) |err| @errorName(err) else @as(?[]const u8, null),
            .worker_exit_code = c.worker_exit_code, .node_exit_code = c.node_exit_code,
            .root_identity_complete = c.worker.full_identity_bound, .node_identity_complete = c.node_identity_bound,
            .job_zero = c.job_zero, .pipes_retired = c.pipes_retired, .capture_complete = c.capture_complete,
            .ledger_retired = c.ledger_retired,
            .metadata_retired = c.metadata_retired,
            .capture_handles_closed = c.capture_handles_closed, .lifetime_total_processes = count,
            .unattributed_lifetime_process_count = count -| known,
            .individual_descendant_identity_coverage = if (count > known) "partial" else "complete",
            .memory_denial_attempt_coverage = "observed_only", .job_commit_cap = @import("job.zig").caps.job_memory,
            .process_commit_cap = @import("job.zig").caps.process_memory, .active_cap = 64,
            .job_accounting = if (c.last_snapshot) |snapshot| snapshot.accounting else null,
            .peak_job_commit = if (c.last_snapshot) |snapshot| snapshot.limits.peak_job_memory else null,
            .early_retirement_ms = c.early_retirement_ms, .final_stage_end_ms = c.deadline.finalStageEnd(c.early_retirement_ms),
            .all_final_assertions_exact = if (self.outcome) |outcome| outcome.exact() else false,
            .final_assertion_coverage = if (self.outcome != null) "recorded" else "unknown_or_unfinished",
            .final_assertions = self.outcome,
            .runtime_status = "recovery_pending", .authority_complete = false, .grant_id = c.granted.grant_id });
        _ = try writer.finish();
        const from = try std.unicode.utf8ToUtf16LeAllocZ(allocator, temp);
        const to = try std.unicode.utf8ToUtf16LeAllocZ(allocator, target);
        if (w.MoveFileExW(from.ptr, to.ptr, 8) == 0) return error.AtomicTerminalPublicationFailed;
    }
};
fn nativeObservation(raw: *anyopaque, observation: admission.Observation) !void {
    const c: *Controller = @ptrCast(@alignCast(raw));
    switch (observation) {
        .candidate => |row| {
            const image = try std.unicode.utf16LeToUtf8Alloc(c.storage.retain(), row.kernel.path());
            defer c.storage.retain().free(image);
            _ = try c.log(.{ .state = "native_candidate", .pid = row.pid, .executable = image,
                .creation_filetime_utc = row.kernel.creation_filetime_utc,
                .own_attempt = row.is_own_attempt_member, .blocks_admission = row.blocks_admission });
        },
        .metadata_unavailable => |row| {
            const name = try std.unicode.utf16LeToUtf8Alloc(c.storage.retain(), row.name);
            defer c.storage.retain().free(name);
            _ = try c.log(.{ .state = "native_metadata_unavailable", .pid = row.pid, .name = name,
                .required_by_name = row.required_by_name, .required_by_path = row.required_by_path, .win32_error = row.win32_error });
        },
        .gone_before_probe => |row| { _ = try c.log(.{ .state = "inventory_pid_gone_before_probe", .pid = row.pid }); },
    }
}
