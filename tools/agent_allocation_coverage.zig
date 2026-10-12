//! Validate actual per-range Agent runtime markers before aggregate CI receipts.
const std = @import("std");
pub const graphs = [_][]const u8{ "agent-complete-metadata", "agent-complete-runtime", "agent-loop-changes", "agent-loop-tools", "agent-loop-owned-stream" };
pub const Row = struct { graph: []const u8, range: usize, start: usize, end: usize, total: usize, complete: bool = true };

fn number(bytes: []const u8) !usize {
    return std.fmt.parseInt(usize, bytes, 10) catch error.InvalidAllocationMarker;
}
fn graphIndex(labels: []const []const u8, label: []const u8) !usize {
    for (labels, 0..) |graph, index| if (std.mem.eql(u8, graph, label)) return index;
    return error.UnknownAllocationGraph;
}
fn clean(gpa: std.mem.Allocator, raw: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(gpa);
    var index: usize = 0;
    while (index < raw.len) {
        if (raw[index] == 0x1b and index + 1 < raw.len and raw[index + 1] == '[') {
            index += 2;
            while (index < raw.len and !(raw[index] >= 0x40 and raw[index] <= 0x7e)) : (index += 1) {}
            if (index < raw.len) index += 1;
        } else {
            try output.append(gpa, raw[index]);
            index += 1;
        }
    }
    return output.toOwnedSlice(gpa);
}

pub const State = StateFor(&graphs, "SDK_ALLOCATION", 28, false);

pub fn StateFor(comptime labels: []const []const u8, comptime marker: []const u8, comptime inventory: ?usize, comptime require_baseline: bool) type {
    return struct {
        const Self = @This();
        shards: usize,
        first: usize,
        end: usize,
        next: usize,
        totals: [labels.len]?usize = @splat(null),

        pub fn init(shards: usize, group: usize, groups: usize) !Self {
            if (shards == 0 or shards > 4096 or groups == 0 or groups > shards or group >= groups) return error.InvalidAllocationGroup;
            const first = shards * group / groups;
            return .{ .shards = shards, .first = first, .next = first, .end = shards * (group + 1) / groups };
        }

        pub fn ingest(self: *Self, gpa: std.mem.Allocator, raw: []const u8, range: usize) ![labels.len]Row {
            if (range != self.next or range >= self.end) return error.IncorrectAllocationRangeOrder;
            const log = try clean(gpa, raw);
            defer gpa.free(log);
            if (inventory) |count| {
                const expected = try std.fmt.allocPrint(gpa, "{d}/{d} tests passed", .{ count, count });
                defer gpa.free(expected);
                if (std.mem.indexOf(u8, log, expected) == null) return error.IncompleteAgentTestInventory;
            }
            var rows: [labels.len]?Row = @splat(null);
            var lines = std.mem.splitScalar(u8, log, '\n');
            while (lines.next()) |line| {
                const prefix = marker ++ "_COMPLETE ";
                const position = std.mem.indexOf(u8, line, prefix) orelse continue;
                var fields = std.mem.tokenizeAny(u8, line[position + prefix.len ..], " \t\r");
                const graph = try graphIndex(labels, fields.next() orelse return error.InvalidAllocationMarker);
                if (rows[graph] != null) return error.DuplicateAllocationCompletion;
                const partition = fields.next() orelse return error.InvalidAllocationMarker;
                const slash = std.mem.indexOfScalar(u8, partition, '/') orelse return error.InvalidAllocationMarker;
                if (try number(partition[0..slash]) != range or try number(partition[slash + 1 ..]) != self.shards) return error.IncorrectAllocationPartition;
                const bounds = fields.next() orelse return error.InvalidAllocationMarker;
                if (!std.mem.startsWith(u8, bounds, "range=[") or !std.mem.endsWith(u8, bounds, ")")) return error.InvalidAllocationMarker;
                const comma = std.mem.indexOfScalar(u8, bounds, ',') orelse return error.InvalidAllocationMarker;
                const first = try number(bounds[7..comma]);
                const end = try number(bounds[comma + 1 .. bounds.len - 1]);
                const total_field = fields.next() orelse return error.InvalidAllocationMarker;
                if (!std.mem.startsWith(u8, total_field, "total=") or fields.next() != null) return error.InvalidAllocationMarker;
                const total = try number(total_field[6..]);
                if (total == 0 or total > std.math.maxInt(u32)) return error.InvalidAllocationUniverse;
                if (self.totals[graph]) |previous| if (previous != total) return error.AllocationUniverseChanged;
                if (first != total * range / self.shards or end != total * (range + 1) / self.shards) return error.IncorrectAllocationPartition;
                rows[graph] = .{ .graph = labels[graph], .range = range, .start = first, .end = end, .total = total };
            }
            for (rows) |row| if (row == null) return error.MissingAllocationCompletion;

            if (require_baseline) {
                var baselines: [labels.len]?usize = @splat(null);
                var headers: [labels.len]bool = @splat(false);
                lines = std.mem.splitScalar(u8, log, '\n');
                while (lines.next()) |line| {
                    const baseline_prefix = marker ++ "_BASELINE ";
                    if (std.mem.indexOf(u8, line, baseline_prefix)) |position| {
                        var fields = std.mem.tokenizeAny(u8, line[position + baseline_prefix.len ..], " \t\r");
                        const graph = try graphIndex(labels, fields.next() orelse return error.InvalidAllocationMarker);
                        if (baselines[graph] != null) return error.DuplicateAllocationBaseline;
                        const total = fields.next() orelse return error.InvalidAllocationMarker;
                        if (!std.mem.startsWith(u8, total, "total=") or fields.next() != null) return error.InvalidAllocationMarker;
                        baselines[graph] = try number(total[6..]);
                    }
                    const header_prefix = marker ++ "_RANGE ";
                    if (std.mem.indexOf(u8, line, header_prefix)) |position| {
                        const value = std.mem.trim(u8, line[position + header_prefix.len ..], " \t\r");
                        var fields = std.mem.tokenizeAny(u8, value, " \t\r");
                        const graph = try graphIndex(labels, fields.next() orelse return error.InvalidAllocationMarker);
                        if (headers[graph]) return error.DuplicateAllocationRangeHeader;
                        const row = rows[graph].?;
                        const expected = try std.fmt.allocPrint(gpa, "{s} {d}/{d} range=[{d},{d}) total={d}", .{ labels[graph], range, self.shards, row.start, row.end, row.total });
                        defer gpa.free(expected);
                        if (!std.mem.eql(u8, value, expected)) return error.IncorrectAllocationPartition;
                        headers[graph] = true;
                    }
                }
                for (rows, 0..) |row, graph| {
                    if (baselines[graph] == null or !headers[graph]) return error.MissingAllocationBaseline;
                    if (baselines[graph].? != row.?.total) return error.AllocationBaselineChanged;
                }
            }

            var begun: [labels.len]usize = @splat(0);
            var completed: [labels.len]usize = @splat(0);
            var pending: [labels.len]?usize = @splat(null);
            lines = std.mem.splitScalar(u8, log, '\n');
            while (lines.next()) |line| {
                const start_prefix = marker ++ "_INDEX_BEGIN ";
                const end_prefix = marker ++ "_INDEX_COMPLETE ";
                const beginning = std.mem.indexOf(u8, line, start_prefix);
                const finishing = std.mem.indexOf(u8, line, end_prefix);
                const position = beginning orelse finishing orelse continue;
                const prefix = if (beginning != null) start_prefix else end_prefix;
                var fields = std.mem.tokenizeAny(u8, line[position + prefix.len ..], " \t\r");
                const graph = try graphIndex(labels, fields.next() orelse return error.InvalidAllocationMarker);
                const index = try number(fields.next() orelse return error.InvalidAllocationMarker);
                if (fields.next() != null) return error.InvalidAllocationMarker;
                const row = rows[graph].?;
                if (beginning != null) {
                    if (pending[graph] != null or index != row.start + begun[graph] or index >= row.end) return error.IncorrectAllocationIndexOrder;
                    pending[graph] = index;
                    begun[graph] += 1;
                } else {
                    if (pending[graph] == null or pending[graph].? != index or index != row.start + completed[graph]) return error.IncorrectAllocationIndexOrder;
                    pending[graph] = null;
                    completed[graph] += 1;
                }
            }
            var result: [labels.len]Row = undefined;
            for (rows, 0..) |row, graph| {
                const value = row.?;
                if (pending[graph] != null or begun[graph] != value.end - value.start or completed[graph] != value.end - value.start) return error.MissingAllocationIndex;
                result[graph] = value;
            }
            // Each group establishes its universe from its own first observed
            // range. Nonzero macOS groups never execute global range zero.
            for (result, 0..) |row, graph| self.totals[graph] = row.total;
            self.next += 1;
            return result;
        }
    };
}

pub fn verifyDirectory(gpa: std.mem.Allocator, io: std.Io, directory: []const u8, shards: usize, group: usize, groups: usize) !void {
    return verifyDirectoryFor(State, gpa, io, directory, shards, group, groups, "agent-range", "allocation-coverage.json");
}

pub fn verifyDirectoryFor(comptime StateType: type, gpa: std.mem.Allocator, io: std.Io, directory: []const u8, shards: usize, group: usize, groups: usize, log_prefix: []const u8, output_name: []const u8) !void {
    var state = try StateType.init(shards, group, groups);
    var rows: std.ArrayList(Row) = .empty;
    defer rows.deinit(gpa);
    while (state.next < state.end) {
        const path = try std.fmt.allocPrint(gpa, "{s}/{s}-{d}.log", .{ directory, log_prefix, state.next });
        defer gpa.free(path);
        const log = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024 * 1024));
        defer gpa.free(log);
        const parsed = try state.ingest(gpa, log, state.next);
        try rows.appendSlice(gpa, &parsed);
    }
    const output = try std.json.Stringify.valueAlloc(gpa, rows.items, .{ .whitespace = .indent_2 });
    defer gpa.free(output);
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}", .{ directory, output_name });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = output });
}
