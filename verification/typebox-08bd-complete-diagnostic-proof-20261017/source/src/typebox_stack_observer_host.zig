//! Source396 host-only setup/reporting. Never imported by a production entry.
const std = @import("std");
const em = @import("extensions/engine.zig");
const probe = @import("extensions/native_node_stack_observer.zig");

pub const capacity: usize = 1048576;
pub const output_variable = "PI_TYPEBOX_STACK_OBSERVER_FILE";

/// Deliberately accepts only an ordinary Windows leaf inside this workspace's
/// evidence directory. Parent directories must already exist; no mkdir here.
pub fn validateReportPath(path: []const u8) !void {
    const prefix = "C:\\Users\\adyba\\pi-zig\\evidence\\";
    if (path.len <= prefix.len or !std.ascii.eqlIgnoreCase(path[0..prefix.len], prefix)) return error.ObserverReportOutsideEvidence;
    if (!std.ascii.endsWithIgnoreCase(path, ".json")) return error.ObserverReportInvalidLeaf;
    var parts = std.mem.splitScalar(u8, path[3..], '\\');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..") or part[part.len - 1] == '.') return error.ObserverReportInvalidLeaf;
        for (part) |char| if (!(std.ascii.isAlphanumeric(char) or char == '-' or char == '_' or char == '.')) return error.ObserverReportInvalidLeaf;
        const stem = part[0 .. std.mem.indexOfScalar(u8, part, '.') orelse part.len];
        for ([_][]const u8{ "CON", "PRN", "AUX", "NUL" }) |reserved| if (std.ascii.eqlIgnoreCase(stem, reserved)) return error.ObserverReportInvalidLeaf;
        if (stem.len == 4 and (std.ascii.eqlIgnoreCase(stem[0..3], "COM") or std.ascii.eqlIgnoreCase(stem[0..3], "LPT")) and stem[3] >= '1' and stem[3] <= '9') return error.ObserverReportInvalidLeaf;
    }
}

fn createFreshReport(io: std.Io, path: []const u8) !std.Io.File {
    try validateReportPath(path);
    var directory = try std.Io.Dir.openDirAbsolute(io, "C:\\", .{ .follow_symlinks = false });
    defer directory.close(io);
    if ((try directory.stat(io)).kind != .directory) return error.ObserverReportReparseOrNonDirectory;
    var parts = std.mem.splitScalar(u8, path[3..], '\\');
    var part = parts.next().?;
    while (parts.next()) |next| {
        const stat = try directory.statFile(io, part, .{ .follow_symlinks = false });
        if (stat.kind != .directory) return error.ObserverReportReparseOrNonDirectory;
        const child = try directory.openDir(io, part, .{ .follow_symlinks = false });
        // A Windows nofollow open can return a reparse handle successfully.
        // Inspect that actual retained handle, not only the pre-open name.
        const opened_stat = child.stat(io) catch |err| {
            child.close(io);
            return err;
        };
        if (opened_stat.kind != .directory) {
            child.close(io);
            return error.ObserverReportReparseOrNonDirectory;
        }
        directory.close(io);
        directory = child;
        part = next;
    }
    // Existing files, including links, must fail. Root must supply a fresh leaf.
    return directory.createFile(io, part, .{ .exclusive = true, .truncate = false });
}

/// Host-only observation boundary. The retained exception slot is untouched.
pub const Boundary = struct {
    engine: *em.Engine,
    observer: *probe.Observer,
    active: bool = false,
    started: bool = false,
    prior_suppression: usize = 0,
    epoch_at_start: u64 = 0,
    restoration_valid: bool = true,
    recapture_status: []const u8 = "not_requested",

    pub fn init(engine: *em.Engine, observer: *probe.Observer) Boundary {
        return .{ .engine = engine, .observer = observer };
    }
    pub fn start(self: *Boundary) !void {
        if (self.started or self.engine.native_node_stack_observer != null) return error.ObserverAlreadyAttached;
        if (self.observer.owner_thread != std.Thread.getCurrentId()) return error.ObserverWrongThread;
        if (self.observer.owner_engine != @intFromPtr(self.engine)) return error.ObserverWrongEngine;
        if (self.engine.native_exception_diagnostics_suppressed == std.math.maxInt(usize)) {
            _ = self.observer.guard_flags.fetchOr(probe.counter_saturated, .monotonic);
            return error.ObserverSuppressionSaturated;
        }
        self.prior_suppression = self.engine.native_exception_diagnostics_suppressed;
        self.epoch_at_start = self.observer.capture_epoch;
        self.engine.native_exception_diagnostics_suppressed = self.prior_suppression + 1;
        self.engine.native_node_stack_observer = self.observer;
        self.active = true;
        self.started = true;
    }
    pub fn detach(self: *Boundary) void {
        if (!self.active) return;
        // Detach before restoring the formatting policy or inspecting reasons.
        if (self.engine.native_node_stack_observer == self.observer) {
            self.engine.native_node_stack_observer = null;
        } else {
            _ = self.observer.guard_flags.fetchOr(probe.foreign_engine, .monotonic);
        }
        if (self.engine.native_exception_diagnostics_suppressed != self.prior_suppression + 1) {
            self.restoration_valid = false;
            _ = self.observer.guard_flags.fetchOr(probe.suppression_unbalanced, .monotonic);
        }
        self.engine.native_exception_diagnostics_suppressed = self.prior_suppression;
        self.active = false;
    }
    /// Preserve the caller's original error. Recapture is solely for existing
    /// host diagnostic text, only after unwind/detach and with actual freshness.
    pub fn afterFailure(self: *Boundary, original_error: anyerror) void {
        self.detach();
        if (!self.started or !std.mem.eql(u8, self.recapture_status, "not_requested")) return;
        if (!self.restoration_valid) {
            self.recapture_status = "suppression_mismatch_original_error_preserved";
            return;
        }
        if (original_error != error.JavaScriptException) {
            self.recapture_status = if (original_error == error.OutOfMemory) "host_out_of_memory_untouched" else "non_JS_error_untouched";
            return;
        }
        const c = em.c;
        const pending = c.JS_HasException(self.engine.context);
        const epoch_fresh = self.observer.capture_epoch != self.epoch_at_start and (self.observer.guard_flags.load(.monotonic) & probe.counter_saturated) == 0;
        if (!pending and (!epoch_fresh or self.engine.captured_exception == null)) {
            self.recapture_status = "no_fresh_reason_no_recapture";
            return;
        }
        const reason = if (pending) c.JS_GetException(self.engine.context) else c.JS_DupValue(self.engine.context, self.engine.captured_exception.?);
        defer self.engine.freeValue(reason);
        // These checks do not clear uncatchability, retag an allocation, or
        // modify native_allocation_generation. Restore a pending fatal reason.
        if (c.JS_IsUncatchableError(reason) or c.pi_js_native_allocation_error_generation(reason) != 0 or self.prior_suppression != 0) {
            if (pending) _ = c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason));
            self.recapture_status = if (c.JS_IsUncatchableError(reason)) "uncatchable_reason_untouched" else if (c.pi_js_native_allocation_error_generation(reason) != 0) "private_allocation_reason_untouched" else "outer_suppression_untouched";
            return;
        }
        _ = self.engine.checked(c.JS_Throw(self.engine.context, c.JS_DupValue(self.engine.context, reason))) catch |recapture_error| {
            self.recapture_status = if (recapture_error == error.JavaScriptException and self.engine.last_error != null) "fresh_reason_diagnostic_recaptured" else "diagnostic_recapture_failed_original_error_preserved";
            return;
        };
        self.recapture_status = "diagnostic_recapture_unexpected_original_error_preserved";
    }
};

pub const Session = struct {
    const State = struct {
        gpa: std.mem.Allocator,
        io: std.Io,
        engine: *em.Engine,
        file: std.Io.File,
        observer: probe.Observer,
        boundary: Boundary,
        started: bool = false,
        finished: bool = false,
    };
    state: ?*State = null,

    pub fn prepare(engine: *em.Engine, gpa: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !Session {
        if (!@import("builtin").is_test) @compileError("TypeBox observer host is test-only");
        var environment = try std.process.Environ.createMap(environ, gpa);
        defer environment.deinit();
        const path = environment.get(output_variable) orelse return .{};
        if (engine.native_node_stack_observer != null) return error.ObserverAlreadyAttached;
        const storage = try gpa.alloc(probe.Record, capacity);
        errdefer gpa.free(storage);
        const state = try gpa.create(State);
        errdefer gpa.destroy(state);
        const file = try createFreshReport(io, path);
        state.* = .{ .gpa = gpa, .io = io, .engine = engine, .file = file, .observer = .init(storage, @intFromPtr(engine)), .boundary = undefined };
        state.boundary = .init(engine, &state.observer);
        return .{ .state = state };
    }
    pub fn start(self: *Session) !void {
        const state = self.state orelse return;
        if (state.finished) return error.ObserverAlreadyAttached;
        try state.boundary.start();
        state.started = true;
    }
    pub fn detach(self: *Session) void {
        const state = self.state orelse return;
        state.boundary.detach();
    }
    pub fn afterFailure(self: *Session, original_error: anyerror) void {
        const state = self.state orelse return;
        state.boundary.afterFailure(original_error);
    }
    /// Only called by the host after the guest replay returned/unwound. Failure
    /// records mean native error propagation, not an inferred stack-overflow.
    pub fn finish(self: *Session, host_replay_error: bool) !void {
        const state = self.state orelse return;
        self.detach();
        if (state.finished) return;
        state.finished = true;
        const observer = &state.observer;
        const json = try std.json.Stringify.valueAlloc(state.gpa, .{
            .format_version = @as(u32, 1),
            .diagnostic_instrumented_candidate = true,
            .production_stack_peak_measured = false,
            .host_replay_error = host_replay_error,
            .observed_replay_started = state.started,
            .event_legend = .{ .enter = @as(u8, 0), .leave = @as(u8, 1), .native_error = @as(u8, 2) },
            .native_error_classification = "Native callback returned an error; not every exception is stack overflow",
            .function_identity_kind = "Existing native-function State address; opaque only, never dereferenced by observer",
            // Correlate this actual load with its own uniquely matched PDB
            // symbol/RVA. This header is assembled only after detachment.
            .load_anchor_symbol = "native_node_function.createArrow",
            .load_anchor_address = @intFromPtr(&@import("extensions/native_node_function.zig").createArrow),
            .owner_engine = observer.owner_engine,
            .owner_thread = observer.owner_thread,
            .capacity = observer.records.len,
            .used = observer.used,
            .attempted = observer.attempted,
            .dropped = observer.dropped,
            .remaining_depth = observer.depth,
            .maximum_callback_depth = observer.maximum_depth,
            .native_errors = observer.native_errors,
            .capture_epoch = observer.capture_epoch,
            .epoch_at_observation_start = state.boundary.epoch_at_start,
            .diagnostic_suppression_restoration_valid = state.boundary.restoration_valid,
            .prior_diagnostic_suppression = state.boundary.prior_suppression,
            .diagnostic_recapture_status = state.boundary.recapture_status,
            .guard_flags = observer.guard_flags.load(.monotonic),
            .complete = observer.complete(),
            .events = observer.records[0..observer.used],
        }, .{});
        defer state.gpa.free(json);
        try state.file.writeStreamingAll(state.io, json);
        // Written only to the fresh report file, never protocol stdout/stderr.
        try state.file.writeStreamingAll(state.io, "\n");
    }
    pub fn deinit(self: *Session) void {
        const state = self.state orelse return;
        self.detach();
        state.file.close(state.io);
        state.gpa.free(state.observer.records);
        const gpa = state.gpa;
        gpa.destroy(state);
        self.state = null;
    }
};
