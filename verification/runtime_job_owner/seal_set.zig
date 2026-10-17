//! Independent source/tool/cache/output assertions; no workload launch or mutation.
const std = @import("std");
const w = @import("win32.zig");
const files = @import("files.zig");
const manifest = @import("manifest.zig");
const inputs = @import("inputs.zig");
const grant = @import("grant.zig");
const tools = @import("tools.zig");
const cache = @import("cache.zig");
const absence = @import("absence.zig");
const junctions = @import("junctions.zig");
const receipts = @import("receipts.zig");
const Storage = @import("storage.zig").Storage;
const Deadline = @import("deadline.zig").Deadline;
pub const Check = enum { controls, union_inputs, protected_stage, original1774, additional1838,
    prospective_tools, cache_pins, cache_inventory, phase_files, links_absences, ancestor_bins };
pub const Result = struct { attempted: bool = false, complete: bool = false, exact: bool = false,
    error_name: ?[]const u8 = null, evidence_error: ?[]const u8 = null };
pub const Outcome = struct {
    results: [11]Result = @splat(.{}),
    completed_ms: u64 = 0,
    pub fn exact(self: *const Outcome) bool {
        for (self.results) |result| if (!result.complete or !result.exact) return false;
        return true;
    }
};
pub const Set = struct {
    storage: *Storage,
    cfg: inputs.Config,
    granted: grant.Data,
    deadline: Deadline,
    evidence: []const u8,
    quota: *receipts.Quota,
    final: bool,
    outcome: Outcome = .{},

    pub fn run(self: *Set) void {
        inline for (comptime std.meta.tags(Check)) |check| {
            const result = &self.outcome.results[@intFromEnum(check)];
            if (w.GetTickCount64() >= self.deadline.cutoff_ms) {
                result.error_name = "FinalSealDeadline";
            } else {
                result.attempted = true;
                if (self.one(check)) |_| {
                    result.complete = true;
                    result.exact = true;
                } else |err| {
                    if (result.error_name == null) result.error_name = @errorName(err);
                    result.complete = result.evidence_error == null and comparisonNegative(err);
                }
            }
        }
        self.outcome.completed_ms = w.GetTickCount64();
    }
    fn one(self: *Set, comptime check: Check) !void {
        const allocator = try self.storage.leaseScratch();
        defer self.storage.releaseScratch() catch {};
        const label = @tagName(check);
        var summary = try self.newWriter(allocator, label, "summary.json");
        defer summary.closePartial() catch {};
        const result = self.evaluate(allocator, check);
        if (result) |_| {} else |err| { self.outcome.results[@intFromEnum(check)].error_name = @errorName(err); }
        summary.json(.{ .check = label, .final = self.final,
            .exact = if (result) |_| true else |_| false,
            .error_name = if (result) |_| @as(?[]const u8, null) else |err| @errorName(err),
            .deadline_ms = self.deadline.cutoff_ms }) catch |err| {
                self.outcome.results[@intFromEnum(check)].evidence_error = @errorName(err);
                return err;
            };
        _ = summary.finish() catch |err| {
            self.outcome.results[@intFromEnum(check)].evidence_error = @errorName(err);
            return err;
        };
        try result;
    }
    fn evaluate(self: *Set, allocator: std.mem.Allocator, comptime check: Check) !void {
        switch (check) {
            .controls => {
                try grant.verifyControls(allocator, self.granted);
                try grant.sameHash(self.granted.phase_inputs_sha256, try files.hash(allocator, self.granted.phase_inputs_path));
            },
            .union_inputs => try self.checkUnion(allocator),
            .protected_stage => try self.tree(allocator, "stage", self.cfg.protected_stage, self.cfg.protected30555_jsonl, 30555, true, 0, .none),
            .original1774 => {
                var sinks = try self.newInventory(allocator, "tools1774");
                defer sinks.closePartial();
                _ = try tools.checkOriginal1774(allocator, self.cfg.tools1774, self.deadline, sinks.sink());
                try sinks.finish();
            },
            .additional1838 => {
                var sinks = try self.newInventory(allocator, "tools1838");
                defer sinks.closePartial();
                _ = try tools.checkAdditionalOriginal1838(allocator, self.cfg.tools1838, self.deadline, sinks.sink());
                try sinks.finish();
            },
            .prospective_tools => {
                var sinks = try self.newInventory(allocator, "prospective");
                defer sinks.closePartial();
                const prospective = try tools.checkProspective(allocator, self.cfg.prospective_tools,
                    self.granted.prospective_tool_closure_sha256, self.deadline, sinks.sink());
                defer tools.releaseProspective(allocator, prospective);
                try sinks.finish();
            },
            .cache_pins => {
                var writer = try self.newWriter(allocator, "cache-pins", "jsonl");
                defer writer.closePartial() catch {};
                try cache.checkPins(allocator, self.cfg.cache_pins365, self.cfg.cache, self.deadline,
                    .{ .context = &writer, .write_fn = cachePin });
                _ = try writer.finish();
            },
            .cache_inventory => try self.cacheInventory(allocator),
            .phase_files => try self.phaseFiles(allocator),
            .links_absences => try self.linksAbsences(allocator),
            .ancestor_bins => {
                var writer = try self.newWriter(allocator, "ancestor-bins", "jsonl");
                defer writer.closePartial() catch {};
                const cwds = try buildCwds(allocator, self.cfg.reproduction);
                try tools.checkAncestorBins(allocator, self.cfg.reproduction, cwds, self.deadline,
                    .{ .context = &writer, .write_fn = ancestor });
                _ = try writer.finish();
            },
        }
    }
    fn newWriter(self: *Set, allocator: std.mem.Allocator, label: []const u8, suffix: []const u8) !receipts.Writer {
        const relative = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ label, suffix });
        const path = try files.join(allocator, self.evidence, relative);
        return receipts.Writer.create(allocator, self.evidence, path, self.quota, self.deadline);
    }
    const Inventory = struct {
        files_writer: receipts.Writer,
        namespace_writer: receipts.Writer,
        diffs_writer: receipts.Writer,
        adapter: receipts.InventorySink = undefined,
        fn sink(self: *Inventory) manifest.Sink {
            self.adapter = .{ .observed_files = &self.files_writer, .namespace = &self.namespace_writer, .differences = &self.diffs_writer };
            return self.adapter.sink();
        }
        fn finish(self: *Inventory) !void {
            _ = try self.files_writer.finish();
            _ = try self.namespace_writer.finish();
            _ = try self.diffs_writer.finish();
        }
        fn closePartial(self: *Inventory) void {
            self.files_writer.closePartial() catch {};
            self.namespace_writer.closePartial() catch {};
            self.diffs_writer.closePartial() catch {};
        }
    };
    fn newInventory(self: *Set, allocator: std.mem.Allocator, label: []const u8) !Inventory {
        var a = try self.newWriter(allocator, label, "files.jsonl");
        errdefer a.closePartial() catch {};
        var b = try self.newWriter(allocator, label, "namespace.jsonl");
        errdefer b.closePartial() catch {};
        const c = try self.newWriter(allocator, label, "differences.jsonl");
        return .{ .files_writer = a, .namespace_writer = b, .diffs_writer = c };
    }
    const Projection = enum { none, without_hidden, without_hydrated };
    fn tree(self: *Set, allocator: std.mem.Allocator, label: []const u8, root: []const u8,
        authority: []const u8, count: usize, jsonl: bool, links: usize, projection: Projection) !void
    {
        var expected = if (jsonl) try manifest.Manifest.loadJsonl(allocator, authority, count)
            else try manifest.Manifest.loadAbsolute(allocator, authority, inputs.original_prefix, count);
        defer expected.deinit();
        if (projection == .without_hidden) try expected.remove(inputs.hidden_relative);
        if (projection == .without_hydrated) {
            var hydrated = try manifest.Manifest.loadAbsolute(allocator, self.cfg.hydrated43, inputs.original_prefix, 43);
            defer hydrated.deinit();
            var iterator = hydrated.entries.keyIterator();
            while (iterator.next()) |key| try expected.remove(key.*);
        }
        var sinks = try self.newInventory(allocator, label);
        defer sinks.closePartial();
        const report = try manifest.checkTree(allocator, root, &expected, self.deadline, sinks.sink());
        try sinks.finish();
        try report.requireExact(links);
    }
    fn phaseFiles(self: *Set, allocator: std.mem.Allocator) !void {
        var first: ?anyerror = null;
        if (self.granted.phase == .npm_ci_offline) {
            if (self.final) {
                self.tree(allocator, "ci-output", self.cfg.metadata, self.cfg.prebuild28293, 28293, false, 16, .without_hydrated)
                    catch |err| { first = err; };
                self.tree(allocator, "repro-prebuild", self.cfg.reproduction, self.cfg.prebuild28293, 28293, false, 0, .none)
                    catch |err| { first = first orelse err; };
                self.checkHidden(allocator) catch |err| { first = first orelse err; };
            } else {
                self.tree(allocator, "ci-source", self.cfg.metadata, self.cfg.source1898, 1898, false, 0, .none)
                    catch |err| { first = err; };
                const install = try files.join(allocator, self.cfg.metadata, "node_modules");
                if (try absence.inspectPhysicalPath(allocator, install) != .absent) return error.FreshCiInstallRequired;
                self.tree(allocator, "repro-known-prebuild", self.cfg.reproduction, self.cfg.prebuild28293, 28293, false, 0, .without_hidden)
                    catch |err| { first = first orelse err; };
            }
        } else {
            self.tree(allocator, "repro", self.cfg.reproduction,
                if (self.final) self.cfg.runtime31064 else self.cfg.prebuild28293,
                if (self.final) 31064 else 28293, false, 16, .none) catch |err| { first = err; };
            self.tree(allocator, "protected-ci", self.cfg.metadata, self.cfg.prebuild28293, 28293, false, 16, .without_hydrated)
                catch |err| { first = first orelse err; };
        }
        if (first) |err| return err;
    }
    fn checkHidden(self: *Set, allocator: std.mem.Allocator) !void {
        const hidden = try files.join(allocator, self.cfg.metadata, inputs.hidden_relative);
        defer allocator.free(hidden);
        try grant.sameHash(inputs.hidden_sha, try files.hash(allocator, hidden));
    }
    fn linksAbsences(self: *Set, allocator: std.mem.Allocator) !void {
        if (!self.final and self.granted.phase == .npm_ci_offline) return; // actual source tree0links asserted separately
        var first: ?anyerror = null;
        self.linksAbsencesRoot(allocator, self.cfg.metadata, "metadata") catch |err| { first = err; };
        if (self.granted.phase == .build_offline)
            self.linksAbsencesRoot(allocator, self.cfg.reproduction, "reproduction") catch |err| { first = first orelse err; };
        if (first) |err| return err;
    }
    fn linksAbsencesRoot(self: *Set, allocator: std.mem.Allocator, root: []const u8, label: []const u8) !void {
        const rows = try inputs.links(allocator, self.cfg, root);
        defer inputs.releaseLinks(allocator, rows);
        const links_label = try std.fmt.allocPrint(allocator, "links-{s}", .{label});
        defer allocator.free(links_label);
        var writer = try self.newWriter(allocator, links_label, "jsonl");
        defer writer.closePartial() catch {};
        var failed: bool = false;
        for (rows) |row| {
            const result = junctions.check(allocator, row);
            try writer.json(.{ .path = row.path, .target = row.target,
                .exact = if (result) |_| true else |_| false,
                .error_name = if (result) |_| @as(?[]const u8, null) else |err| @errorName(err) });
            if (result) |_| {} else |_| { failed = true; }
        }
        _ = try writer.finish();
        const absent_label = try std.fmt.allocPrint(allocator, "absence84-{s}", .{label});
        defer allocator.free(absent_label);
        var absent = try self.newWriter(allocator, absent_label, "jsonl");
        defer absent.closePartial() catch {};
        var absence_error: ?anyerror = null;
        absence.check(allocator, self.cfg.absence84, root, rows, self.deadline,
            .{ .context = &absent, .write_fn = absentRecord }) catch |err| { absence_error = err; };
        if (absence_error) |err| try absent.json(.{ .kind = "absence_check_error", .error_name = @errorName(err), .complete = false });
        _ = try absent.finish();
        if (absence_error) |err| return err;
        if (failed) return error.FinalLinksOrAbsenceNegative;
    }
    fn checkUnion(self: *Set, allocator: std.mem.Allocator) !void {
        var pre = try manifest.Manifest.loadAbsolute(allocator, self.cfg.prebuild28293, inputs.original_prefix, 28293);
        defer pre.deinit();
        var generated = try manifest.Manifest.loadAbsolute(allocator, self.cfg.generated2771, inputs.original_prefix, 2771);
        defer generated.deinit();
        var full = try manifest.Manifest.loadAbsolute(allocator, self.cfg.runtime31064, inputs.original_prefix, 31064);
        defer full.deinit();
        var iterator = pre.entries.iterator();
        while (iterator.next()) |entry| {
            if (generated.entries.contains(entry.key_ptr.*)) return error.OriginalInputOutputOverlap;
            const final = full.entries.get(entry.key_ptr.*) orelse return error.OriginalUnionMissing;
            if (!std.mem.eql(u8, &final.sha256, &entry.value_ptr.sha256)) return error.OriginalUnionHashMismatch;
        }
        var outputs = generated.entries.iterator();
        while (outputs.next()) |entry| {
            const final = full.entries.get(entry.key_ptr.*) orelse return error.OriginalUnionMissing;
            if (!std.mem.eql(u8, &final.sha256, &entry.value_ptr.sha256)) return error.OriginalUnionHashMismatch;
        }
    }
    fn cacheInventory(self: *Set, allocator: std.mem.Allocator) !void {
        if (!self.final and self.granted.phase == .npm_ci_offline) {
            var sinks = try self.newInventory(allocator, "cache-initial");
            defer sinks.closePartial();
            _ = try cache.checkInitial(allocator, self.cfg.initial_cache558_jsonl, self.cfg.cache, self.deadline, sinks.sink());
            try sinks.finish();
            return;
        }
        // This full comparison records every mutable change against the frozen
        // initial/prior authority. Changes are allowed cache evidence, not file
        // equality assertions; required SHA512 contents are checked independently.
        const baseline_path = if (self.granted.phase == .build_offline) self.cfg.prior_cache_snapshot.? else self.cfg.initial_cache558_jsonl;
        var baseline = try manifest.Manifest.loadJsonlAny(allocator, baseline_path, 65536);
        defer baseline.deinit();
        var sinks = try self.newInventory(allocator, "cache-mutable");
        defer sinks.closePartial();
        const report = try manifest.checkTree(allocator, self.cfg.cache, &baseline, self.deadline, sinks.sink());
        try sinks.finish();
        if (!report.inventory_complete or report.reparse_points != 0) return error.MutableCacheInventoryIncomplete;
        // Observed before/after ceiling, not an NTFS kernel disk quota or a claim
        // about unobserved transient cache growth during the workload.
        if (report.actual_file_bytes > 1024 * 1024 * 1024) return error.ObservedCacheSizeLimit;
        if (!self.final and (report.drift != 0 or report.missing != 0 or report.extras != 0)) return error.ReviewedPriorCacheDrift;
    }
};
fn comparisonNegative(err: anyerror) bool {
    return err == error.FullInventoryComparisonNegative or
        err == error.RequiredOriginalCachePinNegative or err == error.Original84AbsenceNegative or
        err == error.UnsealedAncestorBinPresent or err == error.ReviewedPriorCacheDrift or err == error.ObservedCacheSizeLimit;
}
fn cachePin(raw: *anyopaque, row: cache.Record) !void {
    const writer: *receipts.Writer = @ptrCast(@alignCast(raw));
    const expected = std.fmt.bytesToHex(row.expected, .upper);
    const actual = std.fmt.bytesToHex(row.actual, .upper);
    try writer.json(.{ .package = row.package, .cache_relative = row.cache_relative,
        .expected_sha512 = @as([]const u8, &expected), .actual_sha512 = @as([]const u8, &actual), .exact = row.exact });
}
fn ancestor(raw: *anyopaque, row: tools.AncestorBin) !void {
    const writer: *receipts.Writer = @ptrCast(@alignCast(raw));
    try writer.json(row);
}
fn absentRecord(raw: *anyopaque, relative: []const u8, resolved: []const u8, state: absence.State) !void {
    const writer: *receipts.Writer = @ptrCast(@alignCast(raw));
    try writer.json(.{ .relative = relative, .resolved_relative = resolved, .state = state });
}
pub fn buildCwds(allocator: std.mem.Allocator, root: []const u8) ![]const []const u8 {
    const names = [_][]const u8{ "chord", "tui", "telemetry", "codemode", "mcp", "ai", "durable", "env", "agent", "coding-agent" };
    const result = try allocator.alloc([]const u8, names.len + 1);
    result[0] = root;
    for (names, 0..) |name, index| result[index + 1] = try std.fmt.allocPrint(allocator, "{s}\\packages\\{s}", .{ root, name });
    return result;
}
