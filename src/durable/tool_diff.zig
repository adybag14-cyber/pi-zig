//! Native line diffs. Myers paths retain upstream alignment with a bounded node budget.
const std = @import("std");
const values = @import("tool_types.zig");
const Kind = enum { same, remove, add };
const Op = struct { kind: Kind, line: []const u8 };
fn lines(gpa: std.mem.Allocator, input: []const u8) ![][]const u8 {
    var output: std.ArrayList([]const u8) = .empty;
    defer output.deinit(gpa);
    var from: usize = 0;
    while (from < input.len) {
        const end = if (std.mem.indexOfScalarPos(u8, input, from, '\n')) |at| at + 1 else input.len;
        try output.append(gpa, input[from..end]);
        from = end;
    }
    return output.toOwnedSlice(gpa);
}
// Native port of jsdiff 8.0.4's Myers path selection. BSD-3-Clause;
// see JSDIFF_LICENSE.txt and API_INVENTORY.md for immutable source integrity.
const Component = struct { kind: Kind, count: usize, previous: ?usize };
const Path = struct { old_pos: i64 = -1, last: ?usize = null };
const alignment_budget = 1024 * 1024;
fn component(gpa: std.mem.Allocator, nodes: *std.ArrayList(Component), path: *Path, kind: Kind, count: usize) !void {
    if (count == 0) return;
    if (nodes.items.len >= alignment_budget) return error.DiffBudgetExceeded;
    var item: Component = .{ .kind = kind, .count = count, .previous = path.last };
    if (path.last) |last| if (nodes.items[last].kind == kind) {
        item.count += nodes.items[last].count;
        item.previous = nodes.items[last].previous;
    };
    try nodes.append(gpa, item);
    path.last = nodes.items.len - 1;
}
fn common(gpa: std.mem.Allocator, nodes: *std.ArrayList(Component), path: *Path, diagonal: i64, old: [][]const u8, new: [][]const u8) !i64 {
    var new_pos = path.old_pos - diagonal;
    var count: usize = 0;
    while (path.old_pos + 1 < old.len and new_pos + 1 < new.len and std.mem.eql(u8, old[@intCast(path.old_pos + 1)], new[@intCast(new_pos + 1)])) {
        path.old_pos += 1;
        new_pos += 1;
        count += 1;
    }
    try component(gpa, nodes, path, .same, count);
    return new_pos;
}
fn operations(gpa: std.mem.Allocator, old: [][]const u8, new: [][]const u8) ![]Op {
    var nodes: std.ArrayList(Component) = .empty;
    defer nodes.deinit(gpa);
    var initial: Path = .{};
    const first_new = try common(gpa, &nodes, &initial, 0, old, new);
    var final: ?Path = if (initial.old_pos + 1 >= old.len and first_new + 1 >= new.len) initial else null;
    if (final == null) {
        const maximum = std.math.add(usize, old.len, new.len) catch return error.DiffBudgetExceeded;
        if (maximum > alignment_budget) return error.DiffBudgetExceeded;
        const best = try gpa.alloc(?Path, maximum * 2 + 3);
        defer gpa.free(best);
        @memset(best, null);
        const center: i64 = @intCast(maximum + 1);
        best[@intCast(center)] = initial;
        var min_diagonal: i64 = -@as(i64, @intCast(maximum));
        var max_diagonal: i64 = @intCast(maximum);
        outer: for (1..maximum + 1) |distance| {
            const d: i64 = @intCast(distance);
            var diagonal = @max(min_diagonal, -d);
            while (diagonal <= @min(max_diagonal, d)) : (diagonal += 2) {
                const index: usize = @intCast(center + diagonal);
                const remove_path = best[index - 1];
                const add_path = best[index + 1];
                if (remove_path != null) best[index - 1] = null;
                const can_add = if (add_path) |path| path.old_pos - diagonal >= 0 and path.old_pos - diagonal < new.len else false;
                const can_remove = if (remove_path) |path| path.old_pos + 1 < old.len else false;
                if (!can_add and !can_remove) {
                    best[index] = null;
                    continue;
                }
                var base = if (!can_remove or (can_add and remove_path.?.old_pos < add_path.?.old_pos)) add_path.? else remove_path.?;
                const kind: Kind = if (!can_remove or (can_add and remove_path.?.old_pos < add_path.?.old_pos)) .add else .remove;
                try component(gpa, &nodes, &base, kind, 1);
                if (kind == .remove) base.old_pos += 1;
                const new_pos = try common(gpa, &nodes, &base, diagonal, old, new);
                if (base.old_pos + 1 >= old.len and new_pos + 1 >= new.len) {
                    final = base;
                    break :outer;
                }
                best[index] = base;
                if (base.old_pos + 1 >= old.len) max_diagonal = @min(max_diagonal, diagonal - 1);
                if (new_pos + 1 >= new.len) min_diagonal = @max(min_diagonal, diagonal + 1);
            }
        }
    }
    const path = final orelse return error.DiffBudgetExceeded;
    var parts: std.ArrayList(Component) = .empty;
    defer parts.deinit(gpa);
    var last = path.last;
    while (last) |index| {
        try parts.append(gpa, nodes.items[index]);
        last = nodes.items[index].previous;
    }
    std.mem.reverse(Component, parts.items);
    var output: std.ArrayList(Op) = .empty;
    defer output.deinit(gpa);
    var old_pos: usize = 0;
    var new_pos: usize = 0;
    for (parts.items) |part| {
        const tokens = if (part.kind == .remove) old[old_pos..][0..part.count] else new[new_pos..][0..part.count];
        for (tokens) |line| try output.append(gpa, .{ .kind = part.kind, .line = line });
        if (part.kind != .remove) new_pos += part.count;
        if (part.kind != .add) old_pos += part.count;
    }
    var from: usize = 0;
    while (from < output.items.len) {
        if (output.items[from].kind == .same) {
            from += 1;
            continue;
        }
        var end = from;
        while (end < output.items.len and output.items[end].kind != .same) : (end += 1) {}
        var position = from;
        for (from..end) |at| if (output.items[at].kind == .remove) {
            const removed = output.items[at];
            std.mem.copyBackwards(Op, output.items[position + 1 .. at + 1], output.items[position..at]);
            output.items[position] = removed;
            position += 1;
        };
        from = end;
    }
    return output.toOwnedSlice(gpa);
}
fn noEnding(line: []const u8) []const u8 {
    return if (std.mem.endsWith(u8, line, "\n")) line[0 .. line.len - 1] else line;
}
fn appendDisplay(gpa: std.mem.Allocator, output: *std.ArrayList(u8), marker: u8, number: usize, width: usize, line: []const u8) !void {
    if (output.items.len != 0) try output.append(gpa, '\n');
    try output.append(gpa, marker);
    var buffer: [32]u8 = undefined;
    const digits = try std.fmt.bufPrint(&buffer, "{d}", .{number});
    try output.appendNTimes(gpa, ' ', width - digits.len);
    try output.appendSlice(gpa, digits);
    try output.append(gpa, ' ');
    try output.appendSlice(gpa, noEnding(line));
}
fn ellipsis(gpa: std.mem.Allocator, output: *std.ArrayList(u8), width: usize) !void {
    if (output.items.len != 0) try output.append(gpa, '\n');
    try output.appendNTimes(gpa, ' ', width + 1);
    try output.appendSlice(gpa, " ...");
}
pub fn generate(gpa: std.mem.Allocator, path: []const u8, original: []const u8, changed: []const u8) !values.EditDetails {
    const old = try lines(gpa, original);
    defer gpa.free(old);
    const new = try lines(gpa, changed);
    defer gpa.free(new);
    const ops = try operations(gpa, old, new);
    defer gpa.free(ops);
    var diff: std.ArrayList(u8) = .empty;
    defer diff.deinit(gpa);
    var patch: std.ArrayList(u8) = .empty;
    defer patch.deinit(gpa);
    const header = try std.fmt.allocPrint(gpa, "--- {s}\n+++ {s}\n", .{ path, path });
    defer gpa.free(header);
    try patch.appendSlice(gpa, header);
    var width: usize = 1;
    var max = @max(std.mem.count(u8, original, "\n") + 1, std.mem.count(u8, changed, "\n") + 1);
    while (max >= 10) : (max /= 10) width += 1;
    var old_number: usize = 1;
    var new_number: usize = 1;
    var first: ?u64 = null;
    var from: usize = 0;
    while (from < ops.len) {
        if (ops[from].kind != .same) {
            if (first == null) first = new_number;
            const op = ops[from];
            try appendDisplay(gpa, &diff, if (op.kind == .remove) '-' else '+', if (op.kind == .remove) old_number else new_number, width, op.line);
            if (op.kind == .remove) old_number += 1 else new_number += 1;
            from += 1;
            continue;
        }
        var end = from;
        while (end < ops.len and ops[end].kind == .same) : (end += 1) {}
        const leading = from > 0;
        const trailing = end < ops.len;
        const count = end - from;
        if (leading or trailing) {
            const leading_count = if (leading) @min(count, 4) else 0;
            const trailing_from = if (trailing) @max(leading_count, count -| 4) else count;
            for (0..leading_count) |index| try appendDisplay(gpa, &diff, ' ', old_number + index, width, ops[from + index].line);
            if (trailing_from > leading_count) try ellipsis(gpa, &diff, width);
            for (trailing_from..count) |index| try appendDisplay(gpa, &diff, ' ', old_number + index, width, ops[from + index].line);
        }
        old_number += count;
        new_number += count;
        from = end;
    }
    from = 0;
    old_number = 1;
    new_number = 1;
    while (from < ops.len) {
        var change = from;
        while (change < ops.len and ops[change].kind == .same) : (change += 1) {}
        if (change == ops.len) break;
        const start = @max(from, change -| 4);
        for (ops[from..start]) |op| {
            if (op.kind != .add) old_number += 1;
            if (op.kind != .remove) new_number += 1;
        }
        var end = change + 1;
        var context: usize = 0;
        while (end < ops.len) : (end += 1) {
            if (ops[end].kind != .same) {
                context = 0;
                continue;
            }
            context += 1;
            if (context > 8) {
                end = end + 1 - (context - 4);
                break;
            }
        }
        if (end == ops.len and context > 4) end -= context - 4;
        var old_count: usize = 0;
        var new_count: usize = 0;
        for (ops[start..end]) |op| {
            old_count += @intFromBool(op.kind != .add);
            new_count += @intFromBool(op.kind != .remove);
        }
        const hunk = try std.fmt.allocPrint(gpa, "@@ -{d},{d} +{d},{d} @@\n", .{ if (old_count == 0) old_number - 1 else old_number, old_count, if (new_count == 0) new_number - 1 else new_number, new_count });
        defer gpa.free(hunk);
        try patch.appendSlice(gpa, hunk);
        for (ops[start..end]) |op| {
            try patch.append(gpa, switch (op.kind) {
                .same => ' ',
                .remove => '-',
                .add => '+',
            });
            try patch.appendSlice(gpa, op.line);
            if (!std.mem.endsWith(u8, op.line, "\n")) try patch.appendSlice(gpa, "\n\\ No newline at end of file\n");
        }
        old_number += old_count;
        new_number += new_count;
        from = end;
    }
    const owned_diff = try diff.toOwnedSlice(gpa);
    errdefer gpa.free(owned_diff);
    return .{ .diff = owned_diff, .patch = try patch.toOwnedSlice(gpa), .firstChangedLine = first };
}
