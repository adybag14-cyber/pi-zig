//! 29 original native control groups. Real peers/threads/files; no Node or skips.
//! This source is uncompiled and grants no control/runtime qualification.
const std = @import("std");
const t = std.testing;
const w = @import("../win32.zig");
const Host = @import("support.zig").Host;
const process = @import("../process.zig");
const metadata = @import("../metadata.zig");
const protocol = @import("../protocol.zig");
const common = @import("../common.zig");
const command = @import("../command.zig");
const files = @import("../files.zig");
const manifest = @import("../manifest.zig");
const absence = @import("../absence.zig");
const junctions = @import("../junctions.zig");
const cache = @import("../cache.zig");
const admission = @import("../admission.zig");
const Queue = @import("../persistence.zig").Queue;
const Pair = @import("../pipes.zig").Pair;
const Deadline = @import("../deadline.zig").Deadline;
const gate = @import("gate.zig");
const lease_policy = @import("../grant.zig");
const completion = @import("../completion.zig");
extern "kernel32" fn SuspendThread(w.H) callconv(.winapi) u32;
extern "kernel32" fn SetEnvironmentVariableW([*:0]const u16, ?[*:0]const u16) callconv(.winapi) w.B;
extern "kernel32" fn GetEnvironmentVariableW([*:0]const u16, ?[*]u16, u32) callconv(.winapi) u32;
extern "advapi32" fn SetSecurityInfo(w.H, u32, u32, ?*anyopaque, ?*anyopaque, ?*anyopaque, ?*anyopaque) callconv(.winapi) u32;
extern "advapi32" fn GetSecurityDescriptorDacl(*anyopaque, *w.B, *?*anyopaque, *w.B) callconv(.winapi) w.B;

fn until(seconds: u64) u64 { return w.GetTickCount64() + seconds * 1000; }
fn expectCapture(h: *Host, amount: u64) !void {
    try t.expect(h.capture.state == .eof and h.capture.first_error == null and !h.capture.overflow);
    try t.expectEqual(amount, h.capture.bytes_received);
    try t.expectEqual(amount, h.capture.bytes_written);
    var digest: [32]u8 = undefined;
    h.capture.hash.final(&digest);
    var expected = std.crypto.hash.sha2.Sha256.init(.{});
    const block: [65536]u8 = @splat(0x5a);
    var left = amount;
    while (left != 0) { const count: usize = @intCast(@min(left, block.len)); expected.update(block[0..count]); left -= count; }
    var expected_digest: [32]u8 = undefined;
    expected.final(&expected_digest);
    try t.expectEqualSlices(u8, &expected_digest, &digest);
    try verifySink(h, amount, expected_digest);
}
fn verifySink(h: *Host, amount: u64, expected: [32]u8) !void {
    try t.expect(h.capture.ioRetired());
    if (w.FlushFileBuffers(h.capture.write.file) == 0) return error.ControlSinkFlush;
    const path = try files.join(h.allocator, h.evidence, "stdout.bin");
    try files.requirePhysicalAncestors(h.allocator, path);
    const wide = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, path);
    // The already retired capture retains its write handle. This independent
    // verifier permits that known handle's access while reading the regular
    // file; no peer or pending operation remains able to append bytes.
    const file = w.CreateFileW(wide.ptr, w.generic_read, 3, null, w.open_existing, w.file_flag_open_reparse_point, null);
    if (file == w.invalid) return error.ControlSinkOpen;
    defer _ = w.CloseHandle(file);
    _ = try files.requirePhysical(file);
    var size: i64 = 0;
    if (w.GetFileSizeEx(file, &size) == 0 or size < 0) return error.ControlSinkSize;
    try t.expectEqual(amount, @as(u64, @intCast(size)));
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [65536]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        try h.deadline.normal();
        var count: u32 = 0;
        if (w.ReadFile(file, &buffer, buffer.len, &count, null) == 0 or count > buffer.len) return error.ControlSinkRead;
        if (count == 0) break;
        total += count; if (total > amount) return error.ControlSinkGrew;
        hasher.update(buffer[0..count]);
    }
    try t.expectEqual(amount, total);
    var actual: [32]u8 = undefined; hasher.final(&actual);
    try t.expectEqualSlices(u8, &expected, &actual);
}
fn queueFile(h: *Host, name: []const u8) !*Queue {
    const file = try files.openLeaf(h.allocator, try files.join(h.allocator, h.root, name), w.generic_write, w.create_new, 0);
    const queue = try h.allocator.create(Queue);
    queue.* = .{ .file = file };
    try queue.start(); return queue;
}
fn waitQueue(queue: *Queue, sequence: u64, end: u64) !void {
    while (true) {
        if (w.GetTickCount64() >= end) return error.ControlQueueDeadline;
        if (try queue.acknowledged(sequence)) return;
        try queue.requireResponsive();
        if (w.WaitForSingleObject(queue.thread.?, 25) == w.wait_failed) return error.ControlQueueWait;
    }
}
fn stopQueue(queue: *Queue) !void {
    try waitQueue(queue, try queue.stop(), until(2));
    if (w.WaitForSingleObject(queue.thread.?, 2000) != w.wait_object) return error.ControlQueueThreadDeadline;
    try queue.closeCompleted();
    if (w.CloseHandle(queue.file) == 0) return error.ControlQueueFileClose;
}
fn put(h: *Host, relative: []const u8, bytes: []const u8, overwrite: bool) ![]const u8 {
    const path = try files.join(h.allocator, h.root, relative);
    try files.contained(path, h.root);
    const file = try files.openLeaf(h.allocator, path, w.generic_write, if (overwrite) w.open_existing else w.create_new, 0);
    defer _ = w.CloseHandle(file);
    var offset: usize = 0;
    while (offset < bytes.len) {
        var count: u32 = 0;
        if (w.WriteFile(file, bytes[offset..].ptr, @intCast(bytes.len - offset), &count, null) == 0 or count == 0)
            return error.ControlFileWrite;
        offset += count;
    }
    if (w.FlushFileBuffers(file) == 0) return error.ControlFileFlush;
    return path;
}
fn metadataDone(h: *Host, request: *metadata.Request) !void {
    const end = until(5);
    while (!request.completed.load(.acquire)) {
        if (w.GetTickCount64() >= end) return error.ControlMetadataDeadline;
        if (w.WaitForSingleObject(request.thread.?, 100) == w.wait_failed) return error.ControlMetadataWait;
    }
    try h.record(.{ .state = "metadata_actual_completion", .started_ms = request.started_ms,
        .completed_ms = request.completed_ms, .error_name = if (request.first_error) |err| @errorName(err) else @as(?[]const u8, null) });
    if (w.WaitForSingleObject(request.thread.?, 2000) != w.wait_object) return error.ControlMetadataRetirement;
}
fn imageAuthorityControls(h: *Host, request: *metadata.Request, kernel: *const process.KernelIdentity,
    parent: u32, expected_image: []const u16, expected_command: []const u16) !void
{
    try t.expect(request.completed.load(.acquire));
    if (request.first_error) |err| return err;
    try t.expect(request.query_handle_duplicated and request.query_handle_close_succeeded);
    try t.expect(request.query_handle.load(.acquire) == 0 and request.query_handle_close_error == null);
    const row = &request.result;
    try t.expect(row.image_authority == .owned_kernel_handle);
    try metadata.requireMatch(row, kernel, parent, expected_image, expected_command);
    if (row.wmi_image_property.variant_kind == 1) {
        try t.expect(!row.wmi_image_available and row.wmi_image_units == 0);
        try t.expect(row.wmi_image_property.hresult == 0 and row.wmi_image_property.cim_type == 8);
    } else {
        try t.expect(row.wmi_image_property.variant_kind == 8 and row.wmi_image_available);
        try metadata.requireImageAgreement(row.wmi_image[0..row.wmi_image_units], row.image[0..row.image_units]);
    }
    const wrong_image = try h.allocator.dupe(u16, expected_image);
    defer h.allocator.free(wrong_image);
    if (wrong_image.len == 0) return error.ControlMissingActualImage;
    wrong_image[0] = if (wrong_image[0] == 'X') 'Y' else 'X';
    try t.expectError(error.MetadataImageMismatch, metadata.requireMatch(row, kernel, parent, wrong_image, expected_command));
    if (row.wmi_image_available) try t.expectError(error.MetadataWmiImageMismatch,
        metadata.requireImageAgreement(row.wmi_image[0..row.wmi_image_units], wrong_image));
    var wrong_kernel = kernel.*;
    wrong_kernel.creation_filetime_utc +%= 1;
    try t.expectError(error.MetadataKernelBindingMismatch,
        metadata.requireMatch(row, &wrong_kernel, parent, expected_image, expected_command));
    try h.record(.{ .state = "actual_image_authority_controls", .image_authority = row.image_authority,
        .wmi_image_available = row.wmi_image_available, .wmi_image_property = row.wmi_image_property,
        .queried_pid = row.kernel_pid, .query_handle_close_succeeded = request.query_handle_close_succeeded });
}

test "native owner control01 real worker child grandchild full kernel lifetime and zero" {
    const h = try Host.create("control01-family"); defer h.stop();
    try h.spawn("family", 0, 2, false);
    try imageAuthorityControls(h, h.meta.?, &h.actor.kernel.?, h.identity.pid, h.actor_image.?, h.actor_command.?);
    try h.releaseActor();
    try h.waitDiagnosticFamily(3, until(10));
    try h.releaseDescendants();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(10))).exit_code);
    try h.drain(until(2)); try expectCapture(h, 0);
    _ = try h.diagnosticSnapshot("family_pre_original_count_assertion");
    const snapshot = try h.job.snapshot();
    try t.expectEqual(@as(u32, 3), snapshot.accounting.basic.total_processes);
    try h.finish(); try t.expect(h.cleanup_proven);
}
test "native owner control02 mandatory creation job rejects unavailable admission without fallback" {
    const h = try Host.create("control02-job-reject"); defer h.stop();
    // Exercise genuine kernel attribute rejection before any process creation.
    // This is malformed JOB_LIST admission on the current OS, not a claim that
    // the control ran on an older OS lacking JOB_LIST support.
    var bytes: usize = 0;
    _ = w.InitializeProcThreadAttributeList(null, 1, 0, &bytes);
    const storage = try h.allocator.alloc(usize, (bytes + @sizeOf(usize) - 1) / @sizeOf(usize));
    const attributes: *anyopaque = @ptrCast(storage.ptr);
    if (w.InitializeProcThreadAttributeList(attributes, 1, 0, &bytes) == 0) return error.ControlAttributeInit;
    defer w.DeleteProcThreadAttributeList(attributes);
    const owned_job = h.job.handle.?;
    try t.expectEqual(@as(w.B, 0), w.UpdateProcThreadAttribute(attributes, 0, w.attribute_job_list,
        @ptrCast(@constCast(&owned_job)), 0, null, null));
    // Actual closed kernel job, not a guest callback that fabricates success.
    try h.job.close();
    const args = [_][]const u8{h.loaded.data.actor_executable};
    const cmd = try command.serialize(h.allocator, &args);
    const image = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, args[0]);
    const cwd = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, h.root);
    const env = try command.environment(h.allocator, &.{.{ .key = "SystemRoot", .value = "C:\\Windows" }});
    try t.expectError(error.JobClosed, h.actor.createWorkerInJob(&h.job, h.allocator, image, cmd, cwd, env,
        &.{h.std_in, h.output_pair.client.?, h.std_err}, h.std_in, h.output_pair.client.?, h.std_err));
    try t.expect(!h.actor.created_by_this_call and !h.actor.resumed);
    try t.expect(w.WaitForSingleObject(h.ready, 0) == w.wait_timeout);
    // Replacing the closed *fixture-owned empty* job enables ordinary teardown;
    // no launch retry or two-step assignment exists in the API under test.
    h.job = try @import("../job.zig").Job.create(@intFromPtr(h));
    h.job_generation = 2;
    try h.finish();
}
test "native owner control03 supervisor death after atomic suspended creation leaves no guest output" {
    const h = try Host.create("control03-create-death"); defer h.stop();
    try h.spawn("emergency_owner", 0, 0, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 124), (try h.waitActor(until(10))).exit_code);
    try h.drain(until(2)); try expectCapture(h, 0);
    try t.expectEqual(@as(u32, 2), (try h.job.snapshot()).accounting.basic.total_processes);
    try h.finish();
}
test "native owner control04 genuinely delayed owned WMI thread completion remains timeout" {
    const h = try Host.create("control04-late-metadata"); defer h.stop();
    const request = try h.allocator.create(metadata.Request);
    request.* = .{ .pid = w.GetCurrentProcessId() }; h.meta = request;
    try request.start();
    const previous = SuspendThread(request.thread.?);
    try t.expectEqual(@as(u32, 0), previous);
    var suspended = true;
    defer if (suspended) { _ = w.ResumeThread(request.thread.?); };
    // Real kernel timed wait while this exact newly owned thread is suspended.
    // No timestamps/completion bits are invented or changed by the fixture.
    try t.expectEqual(w.wait_timeout, w.WaitForSingleObject(h.hold, 2100));
    try t.expectEqual(@as(u32, 1), w.ResumeThread(request.thread.?)); suspended = false;
    try metadataDone(h, request);
    try t.expect(request.query_handle_duplicated and request.query_handle_close_succeeded);
    try t.expect(request.query_handle.load(.acquire) == 0 and request.query_handle_close_error == null);
    try request.closeCompleted();
    try t.expect(request.retired());
    try t.expect(request.completed_ms - request.started_ms >= 2000);
    switch (request.poll()) { .timeout => {}, else => return error.LateMetadataAccepted }
    try h.finish();
}
test "native owner control05 completed real WMI request cannot restart" {
    const h = try Host.create("control05-metadata-one-shot"); defer h.stop();
    const request = try h.allocator.create(metadata.Request);
    request.* = .{ .pid = w.GetCurrentProcessId() }; h.meta = request;
    try request.start(); try metadataDone(h, request); try request.closeCompleted();
    if (request.first_error) |err| return err;
    // This real self-process probe exercises the available WMI image path. The
    // bound suspended actor in control01 separately records its actual NULL/BSTR.
    try t.expect(request.result.wmi_image_available and request.result.wmi_image_property.variant_kind == 8);
    try imageAuthorityControls(h, request, &h.identity, request.result.parent_pid,
        request.result.image[0..request.result.image_units], request.result.command[0..request.result.command_units]);
    try t.expect(request.retired());
    try t.expectError(error.InvalidMetadataRequest, request.start()); try h.finish();
}
test "native owner control06 CreateProcess FALSE disarms PI and rejects poisoned unowned fields" {
    const h = try Host.create("control06-failed-create"); defer h.stop();
    const missing = try files.join(h.allocator, h.root, "does-not-exist.exe");
    const cmd = try command.serialize(h.allocator, &.{missing});
    const image = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, missing);
    const cwd = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, h.root);
    const env = try command.environment(h.allocator, &.{.{ .key = "SystemRoot", .value = "C:\\Windows" }});
    try t.expectError(error.CreateSuspendedFailed, h.actor.createWorkerInJob(&h.job, h.allocator, image, cmd, cwd, env,
        &.{h.std_in, h.output_pair.client.?, h.std_err}, h.std_in, h.output_pair.client.?, h.std_err));
    try t.expect(h.actor.info.process == null and h.actor.info.thread == null and !h.actor.created_by_this_call);
    var unowned: process.Launch = .{};
    unowned.info.thread = @ptrFromInt(0x1234); unowned.info.process = @ptrFromInt(0x5678);
    try t.expectError(error.NoSuccessfulCreationAuthority, unowned.queryKernel());
    try t.expectError(error.NoSuccessfulCreationAuthority, unowned.exitRecord());
    try t.expectError(error.NoSuccessfulCreationAuthority, unowned.releaseExited());
    try h.finish();
}
test "native owner control07 actual zero-byte pipe write does not hide later native peer bytes" {
    const h = try Host.create("control07-zero-write"); defer h.stop();
    try h.spawn("gated_output", 4097, 0, true); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(10))).exit_code);
    try h.drain(until(2)); try expectCapture(h, 4097); try h.finish();
}
test "native owner control08 exact eight MiB peer output preserved with original cap" {
    const h = try Host.create("control08-exact-cap"); defer h.stop();
    try h.spawn("gated_output", 8 * 1024 * 1024, 0, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(10))).exit_code);
    try h.drain(until(2)); try expectCapture(h, 8 * 1024 * 1024); try h.finish();
}
test "native owner control09 peer eight MiB plus one latches overflow without sink growth" {
    const h = try Host.create("control09-over-cap"); defer h.stop();
    try h.spawn("gated_output", 8 * 1024 * 1024 + 1, 0, false); try h.releaseActor();
    _ = try h.waitActor(until(10)); try h.drain(until(2));
    try t.expect((if (h.capture.first_error) |err| err == error.OutputLimitExceeded else false) and h.capture.overflow);
    try t.expectEqual(@as(u64, 8 * 1024 * 1024), h.capture.bytes_written);
    try t.expectEqual(@as(u64, 8 * 1024 * 1024 + 1), h.capture.bytes_received);
    var hash = std.crypto.hash.sha2.Sha256.init(.{}); const block: [65536]u8 = @splat(0x5a);
    for (0..128) |_| hash.update(&block);
    var digest: [32]u8 = undefined; hash.final(&digest);
    try verifySink(h, 8 * 1024 * 1024, digest); try h.finishExpectedCapture(.overflow);
}
test "native owner control10 pending real pipe read cancellation requires observed completion" {
    const h = try Host.create("control10-cancel-read"); defer h.stop();
    try t.expect(h.capture.read.pending);
    try h.capture.cancel();
    const end = until(2);
    while (!h.capture.ioRetired()) { if (w.GetTickCount64() >= end) return error.ControlCancelDeadline; try h.step(end); }
    try t.expect(h.capture.read.cancellation_requested and !h.capture.read.pending);
    try h.capture.advance(); try t.expect(h.capture.state == .failed); try h.finishExpectedCapture(.cancelled_read);
}
test "native owner control11 real blocked pipe persistence trips watchdog and retires after peer disconnect" {
    const h = try Host.create("control11-stalled-persistence"); defer h.stop();
    var pair = try Pair.create(h.allocator, &h.acl, "flush-stall", false, h.deadline);
    var writer: w.H = undefined;
    if (w.DuplicateHandle(w.GetCurrentProcess(), pair.client.?, w.GetCurrentProcess(), &writer, 0, 0, w.duplicate_same_access) == 0)
        return error.ControlPipeDuplicate;
    const queue = try h.allocator.create(Queue); queue.* = .{ .file = writer }; try queue.start();
    const payload = try h.allocator.alloc(u8, 200000); @memset(payload, 'x'); payload[payload.len - 1] = '\n';
    _ = try queue.append(payload);
    try t.expectEqual(w.wait_timeout, w.WaitForSingleObject(h.hold, 2100));
    try t.expectError(error.PersistenceWatchdogExpired, queue.requireResponsive());
    try pair.closeServer(false); try pair.closeClient();
    if (w.WaitForSingleObject(queue.thread.?, 2000) != w.wait_object) return error.ControlStalledThreadNotRetired;
    try t.expect(queue.failed.load(.acquire)); try queue.closeCompleted();
    if (w.CloseHandle(writer) == 0) return error.ControlWriterClose;
    try h.finish();
}
test "native owner control12 append after real idle receives fresh persistence budget" {
    const h = try Host.create("control12-idle-append"); defer h.stop();
    const queue = try queueFile(h, "idle-ledger.jsonl");
    try t.expectEqual(w.wait_timeout, w.WaitForSingleObject(h.hold, 2100));
    const sequence = try queue.append("{\"real\":true}\n");
    try queue.requireResponsive(); try waitQueue(queue, sequence, until(2)); try stopQueue(queue); try h.finish();
}
test "native owner control13 retired persistence queue is one shot" {
    const h = try Host.create("control13-queue-one-shot"); defer h.stop();
    const queue = try queueFile(h, "one-shot.jsonl");
    try waitQueue(queue, try queue.append("{}\n"), until(2));
    try stopQueue(queue); try t.expectError(error.PersistenceAlreadyStarted, queue.start()); try h.finish();
}
test "native owner control14 record queue and ledger bounds preserve whole accepted records" {
    const h = try Host.create("control14-persistence-bounds"); defer h.stop();
    const queue = try queueFile(h, "bounded-ledger.jsonl");
    const invalid = try h.allocator.alloc(u8, 256 * 1024); @memset(invalid, 'x'); invalid[invalid.len - 1] = '\n';
    try t.expectError(error.PersistenceRecordInvalid, queue.append(invalid));
    const record = try h.allocator.alloc(u8, 128 * 1024); @memset(record, 'a'); record[record.len - 1] = '\n';
    var accepted: usize = 0;
    while (accepted < 32 * 1024 * 1024) : (accepted += record.len) try waitQueue(queue, try queue.append(record), until(2));
    try t.expectError(error.PersistenceLedgerLimit, queue.append("x\n"));
    try t.expectEqual(@as(usize, 32 * 1024 * 1024), queue.bytes_submitted); try stopQueue(queue);
    var pinned = try files.Pinned.open(h.allocator, try files.join(h.allocator, h.root, "bounded-ledger.jsonl"));
    try t.expectEqual(@as(u64, 32 * 1024 * 1024), pinned.size);
    var expected_hash = std.crypto.hash.sha2.Sha256.init(.{});
    for (0..256) |_| expected_hash.update(record);
    var expected_digest: [32]u8 = undefined; expected_hash.final(&expected_digest);
    const actual_digest = try pinned.digest(std.crypto.hash.sha2.Sha256);
    try t.expectEqualSlices(u8, &expected_digest, &actual_digest); try pinned.close();
    // A separate genuinely blocked writer retains all eight queue slots.
    var pair = try Pair.create(h.allocator, &h.acl, "queue-bound", false, h.deadline);
    var writer: w.H = undefined;
    if (w.DuplicateHandle(w.GetCurrentProcess(), pair.client.?, w.GetCurrentProcess(), &writer, 0, 0, w.duplicate_same_access) == 0)
        return error.ControlPipeDuplicate;
    const blocked = try h.allocator.create(Queue); blocked.* = .{ .file = writer }; try blocked.start();
    for (0..8) |_| _ = try blocked.append(record);
    try t.expectError(error.PersistenceQueueFull, blocked.append("x\n"));
    try pair.closeServer(false); try pair.closeClient();
    if (w.WaitForSingleObject(blocked.thread.?, 2000) != w.wait_object) return error.ControlBoundedWriterNotRetired;
    try blocked.closeCompleted(); if (w.CloseHandle(writer) == 0) return error.ControlWriterClose; try h.finish();
}
test "native owner control15 invalid ACK rejects actual Node-role resume and valid ACK produces peer byte" {
    const h = try Host.create("control15-protocol-reject"); defer h.stop();
    // The genuine peer creates a suspended .node Launch, binds actual WMI,
    // attempts resume after wrong/reordered ACK rejection, and requires the
    // production UnacknowledgedResumeForbidden guard. A valid ACK then reaches
    // actual ResumeThread and the native child writes exactly one byte.
    try h.spawn("ack_pipeline", 1, 0, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(10))).exit_code);
    try h.drain(until(2)); try expectCapture(h, 1);
    try t.expectEqual(@as(u32, 2), (try h.job.snapshot()).accounting.basic.total_processes);
    try h.finish();
}
test "native owner control16 supervisor pulls actual remote event handle and rejects wrong PID" {
    const h = try Host.create("control16-wrong-remote-handle"); defer h.stop();
    try h.spawn("leaf", 0, 0, false);
    try t.expectError(error.PulledNodePidMismatch, process.pullNode(h.actor.info.process.?, @intFromPtr(h.ready), h.actor.info.pid, &h.job));
    try t.expect(w.WaitForSingleObject(h.actor.info.process.?, 0) == w.wait_timeout);
    try h.releaseDescendants(); try h.releaseActor(); _ = try h.waitActor(until(5)); try h.finish();
}
test "native owner control17 exited root with genuine grandchild output handle is not whole-job retirement" {
    const h = try Host.create("control17-retained-grandchild"); defer h.stop();
    try h.spawn("family_root_exit", 0, 2, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(10))).exit_code);
    const end = until(10);
    var snapshot = try h.job.snapshot();
    while (snapshot.accounting.basic.total_processes < 3) {
        if (w.GetTickCount64() >= end) return error.GrandchildNotCreated;
        try h.step(end); snapshot = try h.job.snapshot();
    }
    try t.expect(snapshot.accounting.basic.active_processes != 0 and !snapshot.zero());
    try t.expect(h.capture.state != .eof);
    try h.releaseDescendants(); try h.drain(until(5)); try h.finish();
}
test "native owner control18 kernel accounting remains authority without consuming advisory notices" {
    const h = try Host.create("control18-no-advisory-assumption"); defer h.stop();
    try h.spawn("family", 0, 2, false); try h.releaseDescendants(); try h.releaseActor();
    _ = try h.waitActor(until(10));
    // Deliberately never call job.notice: messages are not our identity/zero
    // authority. Real lifetime/member queries still include the genuine family.
    const snapshot = try h.job.snapshot();
    try t.expectEqual(@as(u32, 3), snapshot.accounting.basic.total_processes);
    try h.finish(); try t.expect(h.cleanup_proven);
}
test "native owner control19 exact eight four GiB sixty-four caps reject oversized real commit" {
    const h = try Host.create("control19-real-cap"); defer h.stop();
    const before = try h.job.snapshot();
    try t.expectEqual(@as(usize, 8 * 1024 * 1024 * 1024), before.limits.job_memory);
    try t.expectEqual(@as(usize, 4 * 1024 * 1024 * 1024), before.limits.process_memory);
    try t.expectEqual(@as(u32, 64), before.limits.basic.active_processes);
    try h.spawn("commit_pressure", 0, 0, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(5))).exit_code);
    var notices: [64]@import("../job.zig").Notice = undefined;
    var count: usize = 0;
    while (count < notices.len) { notices[count] = (try h.job.notice(0)) orelse break; count += 1; }
    try h.record(.{ .state = "actual_commit_denial", .advisory_notices = notices[0..count],
        .coverage = "observed_only", .no_complete_memory_denial_history_claim = true });
    try h.finish();
}
test "native owner control20 actual shared completion guards reject genuine late native signal" {
    const h = try Host.create("control20-deadline-boundaries"); defer h.stop();
    const whole = Deadline.start();
    try t.expectEqual(@as(u64, 900000), whole.hard_ms - whole.start_ms);
    try t.expectEqual(@as(u64, 890000), whole.cutoff_ms - whole.start_ms);
    try t.expectEqual(@as(u64, 650000), whole.worker_cutoff_ms - whole.start_ms);
    const early = w.GetTickCount64();
    try t.expectEqual(@min(early + 240000, whole.cutoff_ms), whole.finalStageEnd(early));
    const short = whole.regularUntil(w.GetTickCount64() + 20);
    try t.expectEqual(w.wait_timeout, w.WaitForSingleObject(h.hold, 25));
    // A real wait timeout does not establish that this same coarse clock has
    // crossed the fixed cutoff. Observe it, without moving either deadline.
    var cutoff_observations: u8 = 0;
    while (w.GetTickCount64() < short.cutoff_ms) : (cutoff_observations += 1) {
        if (cutoff_observations == 8) return error.ControlCutoffObservationBound;
        try t.expectEqual(w.wait_timeout, w.WaitForSingleObject(h.hold, 10));
    }

    try t.expectError(error.RetirementReserveReached, short.normal());
    try t.expect(short.retirementEnd() <= whole.hard_ms);
    // A real already-signaled owned event observed after its end stays late;
    // the controller's completion-side guards must not infer prompt completion.
    if (w.SetEvent(h.ready) == 0) return error.ControlEventFailed;
    try t.expect(w.GetTickCount64() >= short.cutoff_ms and w.WaitForSingleObject(h.ready, 0) == w.wait_object);
    try t.expectError(error.NodeLateCompletion, completion.requireBefore(.worker_node, short.cutoff_ms));
    try t.expectError(error.SupervisorNodeLateCompletion, completion.requireBefore(.supervisor_node, short.cutoff_ms));
    try t.expectError(error.WorkerLateCompletion, completion.requireBefore(.supervisor_worker, short.cutoff_ms));
    try t.expectError(error.PersistenceAckDeadline, completion.requireBefore(.persistence_poll, short.cutoff_ms));
    try t.expectError(error.PersistenceAckLateObservation, completion.requireBefore(.persistence_ack, short.cutoff_ms));
    // Shared-guard coverage plus independently reviewed production call-site
    // composition; no claim that deleting an entire caller would fail this unit.
    inline for (comptime std.meta.tags(completion.Site)) |site| try completion.requireBefore(site, whole.hard_ms);
    try h.finish();
}
test "native owner control21 actual exit recorded and retained handles released before required zero" {
    const h = try Host.create("control21-retained-exit-handles"); defer h.stop();
    try h.spawn("exit", 0, 0, false); try h.releaseActor();
    const exit = try h.waitActor(until(5)); try t.expectEqual(@as(u32, 0), exit.exit_code);
    try t.expect(h.actor.info.process != null and h.actor.info.thread != null);
    _ = try h.diagnosticSnapshot("single_actor_pre_retained_exit_snapshot");
    const retained = try h.job.snapshot();
    try h.record(.{ .state = "actual_snapshot_with_retained_exit_handles", .accounting = retained.accounting,
        .pids = retained.members.pids[0..retained.members.returned], .handles_still_retained = true });
    // Kernels may retire accounting at different observations; do not invent
    // a nonzero count. The API's ownership contract still requires release.
    try h.actor.releaseExited();
    try t.expect(h.actor.info.process == null and h.actor.info.thread == null); try h.finish();
}
fn setOwnEnvironment(h: *Host, comptime key: []const u8, value: ?[]const u8) !?[]const u8 {
    const name = std.unicode.utf8ToUtf16LeStringLiteral(key);
    var prior_wide: [32768]u16 = undefined;
    const count = GetEnvironmentVariableW(name, &prior_wide, prior_wide.len);
    if (count >= prior_wide.len) return error.ControlEnvironmentTooLarge;
    const prior: ?[]const u8 = if (count == 0) null else try std.unicode.utf16LeToUtf8Alloc(h.allocator, prior_wide[0..count]);
    const wide = if (value) |text| try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, text) else null;
    if (SetEnvironmentVariableW(name, if (wide) |text| text.ptr else null) == 0) return error.ControlEnvironmentSet;
    return prior;
}
fn restoreOwnEnvironment(h: *Host, comptime key: []const u8, prior: ?[]const u8) void { _ = setOwnEnvironment(h, key, prior) catch {}; }
fn jsonFile(h: *Host, name: []const u8, value: anytype) ![]const u8 {
    var buffer: [256 * 1024]u8 = undefined; var writer: std.Io.Writer = .fixed(&buffer);
    try std.json.Stringify.value(value, .{}, &writer);
    return put(h, name, writer.buffered(), false);
}
test "native owner control22 stale grant and actual live previous PID reject before any guest launch" {
    const h = try Host.create("control22-stale-grant"); defer h.stop();
    var negative = h.loaded.data; negative.authorized = false;
    const path = try jsonFile(h, "unauthorized-grant.json", negative);
    const sha = std.fmt.bytesToHex(try files.hash(h.allocator, path), .upper);
    const prior_path = try setOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT", path);
    defer restoreOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT", prior_path);
    const prior_sha = try setOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT_SHA256", &sha);
    defer restoreOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT_SHA256", prior_sha);
    try t.expectError(error.NativeFixtureGrantRequired, gate.load(h.allocator, false));
    negative = h.loaded.data; negative.released_owned_pids = &.{w.GetCurrentProcessId()};
    const live = try jsonFile(h, "live-previous-pid-grant.json", negative);
    const live_sha = std.fmt.bytesToHex(try files.hash(h.allocator, live), .upper);
    _ = try setOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT", live);
    _ = try setOwnEnvironment(h, "PI_ZIG_FIXTURE_GRANT_SHA256", &live_sha);
    try t.expectError(error.PreviousLeasePidPresent, gate.load(h.allocator, false));
    try t.expect(!h.actor.created_by_this_call);
    // Causal real-kernel coverage: a suspended owned actor is still live, then
    // the SAME retained process handle is signaled after its actual exit.
    try h.spawnSuspended("exit");
    const owned_birth = h.actor.kernel.?.creation_filetime_utc;
    const owned_pid = h.actor.info.pid;
    const owned_handle = h.actor.info.process.?;
    try t.expectError(error.PreviousLeasePidPresent, lease_policy.checkReleasedHandle(owned_handle, owned_pid, owned_birth));
    try t.expectError(error.PreviousLeasePidPresent, lease_policy.checkReleasedHandle(owned_handle, owned_pid, null));
    try h.actor.resumeVerified();
    try h.output_pair.closeClient();
    try t.expectEqual(w.wait_object, w.WaitForSingleObject(h.ready, 10000));
    try h.releaseActor();
    const actual_exit = try h.waitActor(until(5));
    try t.expect(h.actor.info.process != null);
    try t.expectEqual(lease_policy.ReleasedPresence.retired, try lease_policy.checkReleasedHandle(owned_handle, owned_pid, owned_birth));
    const actual_receipt = try jsonFile(h, "actual-retired-held-owner.json", actual_exit);
    const receipt_sha = std.fmt.bytesToHex(try files.hash(h.allocator, actual_receipt), .upper);
    const actual_records = .{.{ .pid = owned_pid, .receipt = actual_receipt, .sha256 = @as([]const u8, &receipt_sha) }};
    const actual_lease = try jsonFile(h, "actual-retired-held-lease.json", .{ .records = &actual_records });
    const lease_sha = std.fmt.bytesToHex(try files.hash(h.allocator, actual_lease), .upper);
    try lease_policy.verifyReleasedProcesses(h.allocator, actual_lease, &lease_sha, &.{owned_pid});
    // Pure predicate coverage only: the kernel cannot be told to allocate a
    // chosen reused PID. This is not claimed as an observed PID-reuse capture.
    try t.expectEqual(lease_policy.ReleasedPresence.pid_reused, try lease_policy.classifyReleasedIdentity(1, 2, w.wait_timeout));
    try t.expectError(error.PreviousLeasePidPresent, lease_policy.classifyReleasedIdentity(1, 1, w.wait_timeout));
    try t.expectError(error.PreviousLeasePidPresent, lease_policy.classifyReleasedIdentity(null, 2, w.wait_timeout));
    try t.expectError(error.PreviousLeaseIdentityUnverifiable, lease_policy.classifyReleasedIdentity(1, null, w.wait_timeout));
    try t.expectError(error.PreviousLeaseAbsenceUnverifiable, lease_policy.classifyReleasedIdentity(1, 2, w.wait_failed));
    // Independent actual .NET receipt example, including trimmed fractions and
    // equivalent explicit timezone. No coarse-CIM tolerance is introduced.
    try t.expectEqual(@as(u64, 134367342657372000), try lease_policy.receiptFileTime("2026-10-17T18:11:05.7372000Z"));
    try t.expectEqual(@as(u64, 134367342657372000), try lease_policy.receiptFileTime("2026-10-17T18:11:05.7372Z"));
    try t.expectEqual(@as(u64, 134367342657372000), try lease_policy.receiptFileTime("2026-10-17T19:11:05.7372000+01:00"));
    try t.expectError(error.PreviousLeaseIdentityUnverifiable, lease_policy.receiptFileTime("2025-02-29T18:11:05Z"));
    try h.record(.{ .state = "actual_live_owned_rejected_and_retired_held_handle_accepted", .identity = actual_exit,
        .receipt = actual_receipt, .lease = actual_lease, .genuine_pid_reuse_capture = false });
    try h.finish();
}
fn alias(h: *Host, name: []const u8) ![]const u8 {
    const directory = try files.join(h.allocator, h.root, ".zig-cache"); try common.freshDirectory(h.allocator, directory, h.root);
    const target = try files.join(h.allocator, directory, name);
    try files.contained(target, h.loaded.data.working_root);
    const from = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, h.loaded.data.actor_executable);
    const to = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, target);
    if (w.CopyFileW(from.ptr, to.ptr, 1) == 0) return error.ControlActorAliasCopy;
    try @import("../grant.zig").sameHash(h.loaded.data.actor_sha256, try files.hash(h.allocator, target));
    return target;
}
test "native owner control23 foreign owned main executable in cache blocks read-only admission" {
    const h = try Host.create("control23-native-census"); defer h.stop();
    const sentinel = try Host.create("control23-owned-sentinel"); defer sentinel.stop();
    try sentinel.spawnAt(try alias(sentinel, "main.exe"), "leaf", 0, 0, false);
    try t.expectError(error.OtherNativeJobPresent, admission.requireQuietNative(&h.identity, &h.job, h.nativeSink()));
    try t.expect(w.WaitForSingleObject(sentinel.actor.info.process.?, 0) == w.wait_timeout);
    try sentinel.releaseDescendants(); try sentinel.releaseActor(); _ = try sentinel.waitActor(until(5));
    try sentinel.finish(); try h.finish();
}
test "native owner control24 relevant owned test process with denied query metadata remains negative" {
    const h = try Host.create("control24-unverifiable-native"); defer h.stop();
    const sentinel = try Host.create("control24-protected-sentinel"); defer sentinel.stop();
    try sentinel.spawnAt(try alias(sentinel, "test.exe"), "leaf", 0, 0, false);
    var descriptor: ?*anyopaque = null;
    const sddl = std.unicode.utf8ToUtf16LeStringLiteral("D:P(D;;0x1000;;;WD)(A;;GA;;;SY)(A;;GA;;;OW)");
    if (w.ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, &descriptor, null) == 0) return error.ControlDaclCreate;
    defer _ = w.LocalFree(descriptor);
    var present: w.B = 0; var defaulted: w.B = 0; var dacl: ?*anyopaque = null;
    if (GetSecurityDescriptorDacl(descriptor.?, &present, &dacl, &defaulted) == 0 or present == 0) return error.ControlDaclRead;
    if (SetSecurityInfo(sentinel.actor.info.process.?, 6, 4, null, null, dacl, null) != 0) return error.ControlDaclApply;
    // Only this exact newly created actor's kernel object is changed. Existing
    // retained handles and the fresh job remain our cleanup authority.
    try t.expectError(error.NativeCandidateUnverifiable, admission.requireQuietNative(&h.identity, &h.job, h.nativeSink()));
    try t.expect(w.WaitForSingleObject(sentinel.actor.info.process.?, 0) == w.wait_timeout);
    try sentinel.releaseDescendants(); try sentinel.releaseActor(); _ = try sentinel.waitActor(until(5));
    try sentinel.finish(); try h.finish();
}
test "native owner control25 real actor does not inherit poisoned PATH or NODE_OPTIONS" {
    const h = try Host.create("control25-explicit-environment"); defer h.stop();
    const prior_path = try setOwnEnvironment(h, "PATH", "C:\\not-authorized-fixture-path");
    defer restoreOwnEnvironment(h, "PATH", prior_path);
    const prior_options = try setOwnEnvironment(h, "NODE_OPTIONS", "--require=not-authorized-fixture.js");
    defer restoreOwnEnvironment(h, "NODE_OPTIONS", prior_options);
    try h.spawn("clean_environment", 0, 0, false); try h.releaseActor();
    try t.expectEqual(@as(u32, 0), (try h.waitActor(until(5))).exit_code); try h.finish();
}
fn observed(raw: *anyopaque, row: manifest.Record) !void {
    const h: *Host = @ptrCast(@alignCast(raw));
    switch (row) {
        .file => |file| try h.record(.{ .state = "actual_file", .relative = file.relative,
            .sha256 = std.fmt.bytesToHex(file.sha256, .upper), .expected = file.expected }),
        .directory => |directory| try h.record(.{ .state = "actual_directory", .relative = directory.relative }),
        .reparse => |link| try h.record(.{ .state = "actual_reparse", .relative = link.relative, .tag = link.tag }),
        .missing => |missing| try h.record(.{ .state = "actual_missing", .relative = missing.relative }),
    }
}
fn treeSink(h: *Host) manifest.Sink { return .{ .context = h, .write_fn = observed }; }
fn expectTreeDrift(h: *Host, directory: []const u8, relative: []const u8) !void {
    try common.freshDirectory(h.allocator, directory, h.root);
    const full = try files.join(h.allocator, directory, relative);
    _ = try put(h, full[h.root.len + 1..], "original", false);
    var expected: manifest.Manifest = .{ .allocator = h.allocator }; defer expected.deinit();
    try expected.add(relative, &std.fmt.bytesToHex(try files.hash(h.allocator, full), .upper));
    try (try manifest.checkTree(h.allocator, directory, &expected, h.deadline, treeSink(h))).requireExact(0);
    _ = try put(h, full[h.root.len + 1..], "modified", true);
    const actual = try manifest.checkTree(h.allocator, directory, &expected, h.deadline, treeSink(h));
    try t.expectEqual(@as(usize, 1), actual.drift);
    try t.expectError(error.FullInventoryComparisonNegative, actual.requireExact(0));
}
fn cacheRecord(raw: *anyopaque, row: cache.Record) !void {
    const h: *Host = @ptrCast(@alignCast(raw));
    try h.record(.{ .state = "actual_sha512_pin", .package = row.package, .exact = row.exact,
        .actual = std.fmt.bytesToHex(row.actual, .upper), .expected = std.fmt.bytesToHex(row.expected, .upper) });
}
test "native owner control26 actual stage tool and SHA512 cache drift all reject" {
    const h = try Host.create("control26-full-file-drift"); defer h.stop();
    try expectTreeDrift(h, try files.join(h.allocator, h.root, "owned-stage-fixture"), "input.bin");
    try expectTreeDrift(h, try files.join(h.allocator, h.root, "owned-tool-fixture"), "tool.bin");
    const root = try files.join(h.allocator, h.root, "cache"); try common.freshDirectory(h.allocator, root, h.root);
    const leaf = try files.join(h.allocator, root, "pin.bin"); _ = try put(h, leaf[h.root.len + 1..], "pin0", false);
    const hash = try files.hash512(h.allocator, leaf);
    var encoded: [88]u8 = undefined; _ = std.base64.standard.Encoder.encode(&encoded, &hash);
    const integrity = try std.fmt.allocPrint(h.allocator, "sha512-{s}", .{encoded});
    const Pin = struct { package: []const u8, integrity: []const u8, required_original_installed: bool, cache_relative: []const u8 };
    const pins = try h.allocator.alloc(Pin, 365);
    for (pins, 0..) |*pin, index| pin.* = .{ .package = try std.fmt.allocPrint(h.allocator, "fixture-{d}", .{index}),
        .integrity = integrity, .required_original_installed = index < 281, .cache_relative = "pin.bin" };
    const path = try jsonFile(h, "fixture365pins.json", pins);
    try cache.checkPins(h.allocator, path, root, h.deadline, .{ .context = h, .write_fn = cacheRecord });
    _ = try put(h, leaf[h.root.len + 1..], "pin1", true);
    try t.expectError(error.RequiredOriginalCachePinNegative, cache.checkPins(h.allocator, path, root, h.deadline,
        .{ .context = h, .write_fn = cacheRecord }));
    try h.finish();
}
fn plans(h: *Host) ![]junctions.Plan {
    const rows = try h.allocator.alloc(junctions.Plan, 16);
    try common.freshDirectory(h.allocator, try files.join(h.allocator, h.root, "packages"), h.root);
    try common.freshDirectory(h.allocator, try files.join(h.allocator, h.root, "node_modules"), h.root);
    for (rows, 0..) |*row, index| {
        const target = try std.fmt.allocPrint(h.allocator, "{s}\\packages\\fixture-{d}", .{h.root, index});
        try common.freshDirectory(h.allocator, target, h.root);
        row.* = .{ .root = h.root, .path = try std.fmt.allocPrint(h.allocator, "{s}\\node_modules\\fixture-{d}", .{h.root, index}), .target = target };
        // Native test-only scope comes from the explicit fixture grant and
        // fresh Host directory, not a production-root admission shortcut.
        try junctions.create(h.allocator, .{ .path = h.root }, row.*);
    }
    try junctions.validatePlan(rows, h.root);
    return rows;
}
fn absenceAudit(h: *Host) ![]const u8 {
    const Pin = struct { path: []const u8, status: []const u8 };
    const Missing = struct { path: []const u8 };
    const pins = try h.allocator.alloc(Pin, 84);
    for (pins, 0..) |*pin, index| pin.* = .{ .path = try std.fmt.allocPrint(h.allocator, "absent-{d}", .{index}),
        .status = "platform_optional_absent" };
    // A []u8 serializes as a JSON string. The genuine absence checker expects
    // an array of path records, including when no mismatches are prepared.
    return jsonFile(h, "absence84.json", .{ .pins = pins, .mismatches = @as([]const Missing, &.{}) });
}
fn absenceRecord(raw: *anyopaque, relative: []const u8, resolved: []const u8, state: absence.State) !void {
    const h: *Host = @ptrCast(@alignCast(raw)); try h.record(.{ .state = "actual_absence", .relative = relative,
        .resolved = resolved, .observation = state });
}
fn renameOwnDirectory(h: *Host, source: []const u8, target: []const u8) !void {
    try files.contained(source, h.root); try files.contained(target, h.root);
    try files.requirePhysicalAncestors(h.allocator, source); try files.requirePhysicalAncestors(h.allocator, target);
    if (try absence.inspectPhysicalPath(h.allocator, target) != .absent) return error.FreshRenameTargetRequired;
    const from = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, source);
    const to = try std.unicode.utf8ToUtf16LeAllocZ(h.allocator, target);
    if (w.MoveFileExW(from.ptr, to.ptr, 0) == 0) return error.ControlOwnedRenameFailed;
}
test "native owner control27 output junction target and absence drift after positive checks reject" {
    const h = try Host.create("control27-post-comparison-drift"); defer h.stop();
    try expectTreeDrift(h, try files.join(h.allocator, h.root, "outputs"), "output.bin");
    const rows = try plans(h);
    for (rows) |row| try junctions.check(h.allocator, row);
    const audit = try absenceAudit(h);
    try absence.check(h.allocator, audit, h.root, rows, h.deadline, .{ .context = h, .write_fn = absenceRecord });
    _ = try put(h, "absent-7", "new physical file", false);
    try t.expectError(error.Original84AbsenceNegative, absence.check(h.allocator, audit, h.root, rows, h.deadline,
        .{ .context = h, .write_fn = absenceRecord }));
    try renameOwnDirectory(h, rows[0].target, try files.join(h.allocator, h.root, "moved-owned-target"));
    if (junctions.check(h.allocator, rows[0])) |_| return error.BrokenTargetAccepted else |_| {}
    try h.finish();
}
test "native owner control28 genuine broken junction leaf is present and ancestor is unverifiable" {
    const h = try Host.create("control28-broken-junction"); defer h.stop();
    const rows = try plans(h); try junctions.check(h.allocator, rows[0]);
    try renameOwnDirectory(h, rows[0].target, try files.join(h.allocator, h.root, "moved-target"));
    try t.expectEqual(absence.State.present, try absence.inspectPhysicalPath(h.allocator, rows[0].path));
    const child = try files.join(h.allocator, rows[0].path, "child");
    try t.expectError(error.UnapprovedReparsePoint, absence.inspectPhysicalPath(h.allocator, child));
    try h.finish();
}
test "native owner control29 emergency fresh job close causes actual containment retirement" {
    const h = try Host.create("control29-job-close"); defer h.stop();
    try h.spawn("leaf", 0, 0, false); try h.releaseActor();
    try t.expect(w.WaitForSingleObject(h.actor.info.process.?, 0) == w.wait_timeout);
    // Complete real accounting precedes sole-fresh-job close. We retain the
    // exact actor handle and do not invent a post-close job query or zero.
    const snapshot = try h.job.snapshot();
    try t.expect(snapshot.accounting.basic.active_processes != 0);
    try h.record(.{ .state = "before_own_job_close", .accounting = snapshot.accounting,
        .pids = snapshot.members.pids[0..snapshot.members.returned], .postclose_zero_claim = false });
    try h.job.close();
    if (w.WaitForSingleObject(h.actor.info.process.?, 2000) != w.wait_object) return error.KillOnCloseRetirementUnproven;
    const exit = try h.actor.exitRecord(); try h.record(.{ .state = "actual_exit_after_job_close", .identity = exit });
    try h.actor.releaseExited();
    // A newly created empty job permits the support's remaining I/O teardown;
    // its zero does not stand in for the closed workload job's unavailable zero.
    h.job = try @import("../job.zig").Job.create(@intFromPtr(h));
    h.job_generation = 2;
    try h.finish();
}
