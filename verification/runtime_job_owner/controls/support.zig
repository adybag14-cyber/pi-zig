//! Owned real-process/pipe fixture support. No unverified PID/tree termination.
const std = @import("std");
const w = @import("../win32.zig");
const files = @import("../files.zig");
const gate = @import("gate.zig");
const common = @import("../common.zig");
const command = @import("../command.zig");
const process = @import("../process.zig");
const metadata = @import("../metadata.zig");
const admission = @import("../admission.zig");
const Job = @import("../job.zig").Job;
const Pair = @import("../pipes.zig").Pair;
const Capture = @import("../overlapped.zig").Capture;
const PrivateAcl = @import("../security.zig").PrivateAcl;
const Deadline = @import("../deadline.zig").Deadline;
pub const Host = struct {
    pub const ExpectedNegativeCapture = enum { overflow, cancelled_read };
    allocator: std.mem.Allocator,
    loaded: gate.Loaded,
    deadline: Deadline,
    watchdog: *common.Watchdog,
    root: []const u8,
    evidence: []const u8,
    job: Job,
    acl: PrivateAcl,
    ready: w.H,
    release: w.H,
    hold: w.H,
    std_in: w.H,
    std_err: w.H,
    output_pair: Pair,
    capture: Capture,
    actor: process.Launch = .{},
    actor_pin: files.Pinned,
    launched_image_pin: ?files.Pinned = null,
    meta: ?*metadata.Request = null,
    ledger: w.H,
    ledger_bytes: usize = 0,
    actor_command: ?[:0]u16 = null,
    actor_image: ?[:0]u16 = null,
    identity: process.KernelIdentity,
    known_exit: ?process.ExitRecord = null,
    cleanup_proven: bool = false,
    job_generation: u32 = 1,
    diagnostic_enabled: bool = false,
    diagnostic_records: usize = 0,

    pub fn create(comptime id: []const u8) !*Host {
        const allocator = std.heap.page_allocator;
        const h = try allocator.create(Host);
        const deadline = Deadline.start().regularUntil(w.GetTickCount64() + 120000);
        const watchdog = try allocator.create(common.Watchdog);
        watchdog.* = .{ .hard_ms = .init(w.GetTickCount64() + 120000) };
        try watchdog.start();
        const loaded = gate.load(allocator, false) catch |admission_error| {
            // Admission still runs under the hard watchdog. If it rejects,
            // retire this exact private thread before releasing its storage;
            // keep the original rejection even if retirement itself fails.
            watchdog.stopRetired(w.GetTickCount64() + 1000) catch |cleanup_error| {
                std.debug.print("native_fixture_admission_watchdog_retirement_failed admission={s} cleanup={s}\n",
                    .{ @errorName(admission_error), @errorName(cleanup_error) });
                return admission_error; // Retain live/uncertain thread storage.
            };
            allocator.destroy(watchdog);
            allocator.destroy(h);
            return admission_error;
        };
        try common.ensureDirectory(allocator, loaded.data.working_root, files.container ++ "\\upstream\\runtime");
        try common.ensureDirectory(allocator, loaded.data.evidence_root, files.container ++ "\\evidence");
        const root = try files.join(allocator, loaded.data.working_root, id);
        const evidence = try files.join(allocator, loaded.data.evidence_root, id);
        try common.freshDirectory(allocator, root, loaded.data.working_root);
        try common.freshDirectory(allocator, evidence, loaded.data.evidence_root);
        const job = try Job.create(@intFromPtr(h));
        const acl = try PrivateAcl.create(allocator);
        var attrs = acl.attributes(true);
        const ready = w.CreateEventW(&attrs, 1, 0, null) orelse return error.FixtureReadyEvent;
        const release = w.CreateEventW(&attrs, 1, 0, null) orelse return error.FixtureReleaseEvent;
        const hold = w.CreateEventW(&attrs, 1, 0, null) orelse return error.FixtureHoldEvent;
        const nul = std.unicode.utf8ToUtf16LeStringLiteral("NUL");
        const std_in = w.CreateFileW(nul, w.generic_read, 3, &attrs, w.open_existing, 0, null);
        const std_err = w.CreateFileW(nul, w.generic_write, 3, &attrs, w.open_existing, 0, null);
        if (std_in == w.invalid or std_err == w.invalid) return error.FixtureNullStdio;
        const pair = try Pair.create(allocator, &acl, "native-fixture", false, deadline);
        const sink = try files.openLeaf(allocator, try files.join(allocator, evidence, "stdout.bin"),
            w.generic_write, w.create_new, w.file_flag_overlapped);
        const ledger = try files.openLeaf(allocator, try files.join(allocator, evidence, "identity-ledger.jsonl"),
            w.generic_write, w.create_new, 0);
        var actor_pin = try files.Pinned.open(allocator, loaded.data.actor_executable);
        try @import("../grant.zig").sameHash(loaded.data.actor_sha256, try actor_pin.digest(std.crypto.hash.sha2.Sha256));
        h.* = .{ .allocator = allocator, .loaded = loaded, .deadline = deadline, .watchdog = watchdog,
            .root = root, .evidence = evidence, .job = job, .acl = acl, .ready = ready, .release = release,
            .hold = hold, .std_in = std_in, .std_err = std_err, .output_pair = pair,
            .capture = try Capture.init(pair.server.?, sink), .actor_pin = actor_pin,
            .ledger = ledger, .identity = try process.identity(w.GetCurrentProcess()),
            .diagnostic_enabled = std.mem.eql(u8, id, "control01-family") or std.mem.eql(u8, id, "control21-retained-exit-handles") };
        try admission.requireQuietNative(&h.identity, &h.job, .{ .context = h, .write_fn = observeNative });
        try h.capture.advance();
        return h;
    }
    pub fn record(self: *Host, value: anytype) !void {
        var buffer: [64 * 1024]u8 = undefined;
        var writer: std.Io.Writer = .fixed(&buffer);
        try std.json.Stringify.value(value, .{}, &writer);
        try writer.writeByte('\n');
        var offset: usize = 0;
        const bytes = writer.buffered();
        if (bytes.len > 16 * 1024 * 1024 - self.ledger_bytes) return error.FixtureLedgerLimit;
        while (offset < bytes.len) {
            var count: u32 = 0;
            if (w.WriteFile(self.ledger, bytes[offset..].ptr, @intCast(bytes.len - offset), &count, null) == 0 or count == 0)
                return error.FixtureLedgerWrite;
            offset += count;
            self.ledger_bytes += count;
        }
        if (w.FlushFileBuffers(self.ledger) == 0) return error.FixtureLedgerFlush;
    }
    fn diagnosticRecord(self: *Host, value: anytype) !void {
        if (self.diagnostic_records >= 256) return error.FixtureDiagnosticRecordLimit;
        self.diagnostic_records += 1;
        try self.record(value);
    }
    /// Advisory observations only: neither notices nor reopened PIDs authorize
    /// admission, termination or a claim about an already-exited identity.
    pub fn diagnosticSnapshot(self: *Host, boundary: []const u8) !usize {
        if (!self.diagnostic_enabled) return 0;
        try self.deadline.normal();
        const snapshot = try self.job.snapshot();
        try self.diagnosticRecord(.{ .state = "diagnostic_job_snapshot", .boundary = boundary,
            .accounting = snapshot.accounting, .pids = snapshot.members.pids[0..snapshot.members.returned] });
        var actors: usize = 0;
        for (snapshot.members.pids[0..snapshot.members.returned]) |raw_pid| {
            if (raw_pid == 0 or raw_pid > std.math.maxInt(u32)) return error.FixtureDiagnosticPidRange;
            if (try self.diagnosticProcess(@intCast(raw_pid), boundary, "current_member")) actors += 1;
        }
        while (try self.job.notice(0)) |notice| {
            try self.deadline.normal();
            try self.diagnosticRecord(.{ .state = "diagnostic_job_notice", .boundary = boundary,
                .message = notice.message, .raw_pid = notice.raw_pid, .identity_coverage = "advisory_only" });
            if (notice.message == 6 and notice.raw_pid != 0 and notice.raw_pid <= std.math.maxInt(u32))
                _ = try self.diagnosticProcess(@intCast(notice.raw_pid), boundary, "new_process_notice");
        }
        return actors;
    }
    fn diagnosticProcess(self: *Host, pid: u32, boundary: []const u8, origin: []const u8) !bool {
        const handle = w.OpenProcess(w.process_query_limited | w.process_synchronize, 0, pid) orelse {
            try self.diagnosticRecord(.{ .state = "diagnostic_process_unavailable", .boundary = boundary,
                .origin = origin, .requested_pid = pid, .open_error = w.GetLastError() });
            return false;
        };
        defer _ = w.CloseHandle(handle);
        const kernel = process.identity(handle) catch |err| {
            try self.diagnosticRecord(.{ .state = "diagnostic_process_partial", .boundary = boundary,
                .origin = origin, .requested_pid = pid, .identity_error = @errorName(err),
                .wait_result = w.WaitForSingleObject(handle, 0) });
            return false;
        };
        var member: w.B = 0;
        const member_ok = w.IsProcessInJob(handle, self.job.handle.?, &member) != 0;
        var parent: ?u32 = null;
        var parent_error: ?u32 = null;
        const toolhelp = w.CreateToolhelp32Snapshot(2, 0);
        if (toolhelp == w.invalid) { parent_error = w.GetLastError(); } else {
            defer _ = w.CloseHandle(toolhelp);
            var entry: w.ProcessEntry = std.mem.zeroes(w.ProcessEntry);
            entry.size = @sizeOf(w.ProcessEntry);
            var more = w.Process32FirstW(toolhelp, &entry);
            var scanned: usize = 0;
            while (more != 0) {
                try self.deadline.normal();
                scanned += 1;
                if (scanned > 16384) return error.FixtureDiagnosticToolhelpLimit;
                if (entry.pid == pid) { parent = entry.parent_pid; break; }
                more = w.Process32NextW(toolhelp, &entry);
            }
            if (more == 0 and w.GetLastError() != 18) parent_error = w.GetLastError();
        }
        const wait_result = w.WaitForSingleObject(handle, 0);
        try self.diagnosticRecord(.{ .state = "diagnostic_process_observed", .boundary = boundary,
            .origin = origin, .requested_pid = pid, .kernel_pid = kernel.pid,
            .kernel_creation_filetime_utc = kernel.creation_filetime_utc, .image_utf16 = kernel.path(),
            .wait_result = wait_result, .job_membership_query_succeeded = member_ok,
            .is_current_job_member = member_ok and member != 0,
            .toolhelp_parent_pid = parent, .toolhelp_error = parent_error,
            .parent_binding = "separate_toolhelp_pid_observation_not_identity_authority" });
        return member_ok and member != 0 and wait_result == w.wait_timeout and
            self.actor_image != null and w.CompareStringOrdinal(kernel.path().ptr, @intCast(kernel.path().len),
                self.actor_image.?.ptr, @intCast(self.actor_image.?.len), 1) == 2;
    }
    pub fn waitDiagnosticFamily(self: *Host, expected_actors: usize, end: u64) !void {
        if (!self.diagnostic_enabled) return error.FixtureDiagnosticNotEnabled;
        while (true) {
            if (w.GetTickCount64() >= end) return error.FixtureDiagnosticFamilyDeadline;
            if (try self.diagnosticSnapshot("live_family_hold_gate") >= expected_actors) return;
            try self.step(end);
        }
    }
    pub fn spawn(self: *Host, mode: []const u8, amount: usize, depth: u32, zero_first: bool) !void {
        return self.spawnAt(self.loaded.data.actor_executable, mode, amount, depth, zero_first);
    }
    pub fn spawnSuspended(self: *Host, mode: []const u8) !void {
        return self.spawnBound(self.loaded.data.actor_executable, mode, 0, 0, false, false);
    }
    pub fn spawnAt(self: *Host, actor_path: []const u8, mode: []const u8, amount: usize, depth: u32, zero_first: bool) !void {
        return self.spawnBound(actor_path, mode, amount, depth, zero_first, true);
    }
    fn spawnBound(self: *Host, actor_path: []const u8, mode: []const u8, amount: usize, depth: u32, zero_first: bool, resume_child: bool) !void {
        const a = self.allocator;
        var actual_pin = try files.Pinned.open(a, actor_path);
        try @import("../grant.zig").sameHash(self.loaded.data.actor_sha256, try actual_pin.digest(std.crypto.hash.sha2.Sha256));
        self.launched_image_pin = actual_pin;
        const args = [_][]const u8{ actor_path, "--native-fixture", mode,
            try std.fmt.allocPrint(a, "{d}", .{@intFromPtr(self.ready)}),
            try std.fmt.allocPrint(a, "{d}", .{@intFromPtr(self.release)}),
            try std.fmt.allocPrint(a, "{d}", .{amount}), try std.fmt.allocPrint(a, "{d}", .{depth}),
            if (zero_first) "zero-first" else "normal", try std.fmt.allocPrint(a, "{d}", .{@intFromPtr(self.hold)}) };
        const cmd = try command.serialize(a, &args);
        try command.requireRoundTrip(a, cmd, &args);
        const image = try std.unicode.utf8ToUtf16LeAllocZ(a, actor_path);
        const cwd = try std.unicode.utf8ToUtf16LeAllocZ(a, self.root);
        const env = try command.environment(a, &.{ .{ .key = "SystemRoot", .value = "C:\\Windows" },
            .{ .key = "PI_ZIG_FIXTURE_GRANT", .value = self.loaded.path },
            .{ .key = "PI_ZIG_FIXTURE_GRANT_SHA256", .value = self.loaded.sha } });
        try self.record(.{ .state = "actor_intent", .argv = args, .parent_pid = self.identity.pid,
            .actor_sha256 = self.loaded.data.actor_sha256, .working_directory = self.root });
        self.actor_command = cmd; self.actor_image = image;
        try self.actor.createWorkerInJob(&self.job, a, image, cmd, cwd, env,
            &.{ self.std_in, self.output_pair.client.?, self.std_err, self.ready, self.release, self.hold },
            self.std_in, self.output_pair.client.?, self.std_err);
        try self.actor.queryKernel();
        try self.job.requireMember(self.actor.info.process.?);
        _ = try self.diagnosticSnapshot("suspended_create_before_metadata");
        const request = try a.create(metadata.Request);
        request.* = .{ .pid = self.actor.info.pid };
        self.meta = request;
        try request.startBound(self.actor.info.process.?);
        while (true) {
            switch (request.poll()) { .timeout => return error.FixtureMetadataTimeout, .ready => break, .pending => {} }
            try self.step(w.GetTickCount64() + 100);
        }
        // poll(.ready) acquired the worker's immutable completed result. Keep
        // its actual error and partial fields before returning that same error;
        // a stack trace alone does not identify the failed metadata operation.
        try self.record(.{ .state = "actor_metadata_completed", .queried_pid = request.pid,
            .started_ms = request.started_ms, .completed_ms = request.completed_ms,
            .error_name = if (request.first_error) |err| @errorName(err) else @as(?[]const u8, null),
            .property_diagnostic = request.property_diagnostic,
            .image_authority = request.result.image_authority,
            .kernel_pid = request.result.kernel_pid,
            .kernel_creation_filetime_utc = request.result.kernel_creation_filetime_utc,
            .wmi_image_available = request.result.wmi_image_available,
            .wmi_image_property = request.result.wmi_image_property,
            .query_handle_duplicated = request.query_handle_duplicated,
            .query_handle_close_succeeded = request.query_handle_close_succeeded,
            .query_handle_close_error = request.query_handle_close_error,
            .observed_pid = request.result.pid, .observed_parent_pid = request.result.parent_pid,
            .image_units = request.result.image_units, .command_units = request.result.command_units,
            .creation_filetime_utc = request.result.creation_filetime_utc });
        if (request.first_error) |err| return err;
        try metadata.requireMatch(&request.result, &self.actor.kernel.?, self.identity.pid, image, cmd);
        try self.record(.{ .state = "actor_bound", .pid = request.result.pid, .parent_pid = request.result.parent_pid,
            .creation_filetime_utc = request.result.creation_filetime_utc,
            .command_utf16 = request.result.command[0..request.result.command_units],
            .image_utf16 = request.result.image[0..request.result.image_units],
            .image_authority = request.result.image_authority,
            .wmi_image_available = request.result.wmi_image_available,
            .wmi_image_property = request.result.wmi_image_property,
            .wmi_image_utf16 = request.result.wmi_image[0..request.result.wmi_image_units] });
        self.actor.full_identity_bound = true;
        if (!resume_child) return;
        try self.actor.resumeVerified();
        try self.output_pair.closeClient();
        if (w.WaitForSingleObject(self.ready, 10000) != w.wait_object) return error.ActorReadyDeadline;
        _ = try self.diagnosticSnapshot("actor_ready_before_release");
    }
    pub fn releaseActor(self: *Host) !void { if (w.SetEvent(self.release) == 0) return error.FixtureReleaseFailed; }
    pub fn releaseDescendants(self: *Host) !void { if (w.SetEvent(self.hold) == 0) return error.FixtureHoldReleaseFailed; }
    pub fn nativeSink(self: *Host) admission.Sink { return .{ .context = self, .write_fn = observeNative }; }
    pub fn step(self: *Host, end: u64) !void {
        try self.deadline.normal();
        try self.capture.advance();
        // Immediately arm the next genuine read after counting a completed
        // sink write/zero-byte read. Do not impose a polling delay per chunk.
        if (self.capture.state == .idle) try self.capture.advance();
        var events: [2]w.H = undefined;
        var count: usize = 0;
        if (self.capture.read.pending) { events[count] = self.capture.read.event.?; count += 1; }
        if (self.capture.write.pending) { events[count] = self.capture.write.event.?; count += 1; }
        try common.waitPending(events[0..count], @min(end, self.deadline.cutoff_ms));
    }
    pub fn waitActor(self: *Host, end: u64) !process.ExitRecord {
        while (true) {
            const wait = w.WaitForSingleObject(self.actor.info.process.?, 0);
            if (wait == w.wait_object) {
                if (w.GetTickCount64() >= end) return error.FixtureLateActorExit;
                const exit = try self.actor.exitRecord();
                try self.record(.{ .state = "actor_exit", .identity = exit });
                self.known_exit = exit;
                return exit;
            }
            if (wait != w.wait_timeout) return error.FixtureActorWait;
            if (w.GetTickCount64() >= end) return error.FixtureActorDeadline;
            try self.step(end);
        }
    }
    pub fn drain(self: *Host, end: u64) !void {
        while (self.capture.state != .eof and self.capture.state != .failed) {
            if (w.GetTickCount64() >= end) return error.FixtureCaptureDeadline;
            try self.step(end);
        }
    }
    pub fn stop(self: *Host) void {
        if (self.cleanup_proven) return;
        self.retire() catch {
            // Keep pending OVERLAPPED/metadata/watchdog storage alive. Closing
            // only our fresh job is a contained fallback, never zero evidence.
            self.job.close() catch {};
            return;
        };
    }
    pub fn finish(self: *Host) !void { try self.retireWithCapture(null); if (!self.cleanup_proven) return error.FixtureCleanupNotProven; }
    pub fn finishExpectedCapture(self: *Host, expected: ExpectedNegativeCapture) !void {
        try self.retireWithCapture(expected);
        if (!self.cleanup_proven) return error.FixtureCleanupNotProven;
    }
    pub fn retire(self: *Host) !void { return self.retireWithCapture(null); }
    fn captureAccepted(self: *const Host, expected: ?ExpectedNegativeCapture) bool {
        if (expected) |negative| return switch (negative) {
            .overflow => self.capture.state == .failed and (if (self.capture.first_error) |err| err == error.OutputLimitExceeded else false) and
                self.capture.overflow and self.capture.bytes_written == self.capture.limit and
                self.capture.bytes_received > self.capture.bytes_written,
            .cancelled_read => self.capture.state == .failed and (if (self.capture.first_error) |err| err == error.OutputReadFailed else false) and
                !self.capture.overflow and self.capture.bytes_received == 0 and self.capture.bytes_written == 0 and
                self.capture.read.cancellation_requested and
                (if (self.capture.read.completion) |completion| switch (completion) { .failed => |code| code == 995, else => false } else false),
        };
        return self.capture.state == .eof and self.capture.first_error == null and !self.capture.overflow and
            self.capture.bytes_received == self.capture.bytes_written;
    }
    fn retireWithCapture(self: *Host, expected: ?ExpectedNegativeCapture) !void {
        const end = w.GetTickCount64() + 10000;
        try self.job.abort(125);
        try self.output_pair.closeClient();
        while (w.GetTickCount64() < end) {
            if (self.actor.created_by_this_call and self.actor.info.process != null and
                w.WaitForSingleObject(self.actor.info.process.?, 0) == w.wait_object) {
                const exit = try self.actor.exitRecord();
                try self.record(.{ .state = "actor_retired", .identity = exit });
                try self.actor.releaseExited();
            }
            try self.capture.advance();
            if (self.capture.first_error != null or w.GetTickCount64() >= end - 1000) try self.capture.cancel();
            if (self.meta) |request| if (request.completed.load(.acquire) and request.thread != null and
                w.WaitForSingleObject(request.thread.?, 0) == w.wait_object) try request.closeCompleted();
            const snapshot = try self.job.snapshot();
            try self.record(.{ .state = "retirement_snapshot", .accounting = snapshot.accounting,
                .pids = snapshot.members.pids[0..snapshot.members.returned], .job_generation = self.job_generation });
            if (snapshot.zero() and self.actor.info.process == null and self.capture.ioRetired() and
                (self.capture.state == .eof or self.capture.state == .failed) and
                (self.meta == null or self.meta.?.retired())) {
                const capture_accepted = self.captureAccepted(expected);
                try self.record(.{ .state = "retired_capture_assertion", .accepted = capture_accepted,
                    .expected_negative = expected, .read_state = self.capture.state,
                    .first_error = if (self.capture.first_error) |err| @errorName(err) else @as(?[]const u8, null),
                    .overflow = self.capture.overflow, .received = self.capture.bytes_received, .written = self.capture.bytes_written });
                try self.capture.close();
                try self.output_pair.closeServer(false);
                if (w.FlushFileBuffers(self.capture.write.file) == 0 or w.CloseHandle(self.capture.write.file) == 0)
                    return error.FixtureSinkRetirement;
                try self.actor_pin.close();
                if (self.launched_image_pin) |*pin| try pin.close();
                try self.job.close(); try self.acl.close();
                for ([_]w.H{ self.ready, self.release, self.hold, self.std_in, self.std_err, self.ledger }) |handle|
                    if (w.CloseHandle(handle) == 0) return error.FixtureHandleClose;
                try self.watchdog.stopRetired(w.GetTickCount64() + 1000);
                self.cleanup_proven = true;
                if (!capture_accepted) return error.UnexpectedFixtureCaptureOutcome;
                return;
            }
            try self.step(end);
        }
        return error.FixtureRetirementUnproven;
    }
};
fn observeNative(raw: *anyopaque, observation: admission.Observation) !void {
    const h: *Host = @ptrCast(@alignCast(raw));
    switch (observation) {
        .candidate => |row| try h.record(.{ .state = "native_candidate", .pid = row.pid,
            .path_utf16 = row.kernel.path(), .own_attempt = row.is_own_attempt_member, .blocks = row.blocks_admission }),
        .metadata_unavailable => |row| try h.record(.{ .state = "native_metadata_unavailable", .pid = row.pid,
            .name_utf16 = row.name, .required_by_name = row.required_by_name, .required_by_path = row.required_by_path }),
        .gone_before_probe => |row| try h.record(.{ .state = "native_gone_before_probe", .pid = row.pid }),
    }
}
