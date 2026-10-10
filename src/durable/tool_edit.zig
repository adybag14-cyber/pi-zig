//! Original-content edit matching and line-preserving fuzzy replacements.
const std = @import("std");
const text = @import("text.zig");
pub const Edit = struct { oldText: []const u8, newText: []const u8 };
pub const Applied = struct {
    baseContent: []u8,
    newContent: []u8,
    pub fn deinit(self: *Applied, gpa: std.mem.Allocator) void {
        gpa.free(self.baseContent);
        gpa.free(self.newContent);
    }
};
pub const Result = union(enum) { value: Applied, failure: []u8 };
const Replacement = struct { index: usize, length: usize, newText: []const u8, editIndex: usize };
fn occurrences(content: []const u8, old: []const u8) usize {
    if (old.len == 0) {
        var iterator = (std.unicode.Utf8View.init(content) catch unreachable).iterator();
        var units: usize = 0;
        while (iterator.nextCodepoint()) |point| units += if (point > 0xffff) @as(usize, 2) else 1;
        return units -| 1;
    }
    var count: usize = 0;
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, content, from, old)) |at| {
        count += 1;
        from = at + old.len;
    }
    return count;
}
fn before(_: void, a: Replacement, b: Replacement) bool {
    return a.index < b.index;
}
fn replace(gpa: std.mem.Allocator, base: []const u8, replacements: []const Replacement, offset: usize) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var from: usize = 0;
    for (replacements) |replacement| {
        const at = replacement.index - offset;
        try output.appendSlice(gpa, base[from..at]);
        try output.appendSlice(gpa, replacement.newText);
        from = at + replacement.length;
    }
    try output.appendSlice(gpa, base[from..]);
    return output.toOwnedSlice(gpa);
}
const Span = struct { start: usize, end: usize };
fn spans(gpa: std.mem.Allocator, input: []const u8) ![]Span {
    var lines: std.ArrayList(Span) = .empty;
    defer lines.deinit(gpa);
    var from: usize = 0;
    while (from < input.len) {
        const end = if (std.mem.indexOfScalarPos(u8, input, from, '\n')) |at| at + 1 else input.len;
        try lines.append(gpa, .{ .start = from, .end = end });
        from = end;
    }
    return lines.toOwnedSlice(gpa);
}
fn preserving(gpa: std.mem.Allocator, original: []const u8, base: []const u8, replacements: []const Replacement) ![]u8 {
    const original_lines = try spans(gpa, original);
    defer gpa.free(original_lines);
    const base_lines = try spans(gpa, base);
    defer gpa.free(base_lines);
    if (original_lines.len != base_lines.len) return error.NormalizationChangedLineCount;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    var old_from: usize = 0;
    var index: usize = 0;
    while (index < replacements.len) {
        const first = replacements[index];
        var start_line: usize = 0;
        while (start_line < base_lines.len and base_lines[start_line].end <= first.index) : (start_line += 1) {}
        if (start_line == base_lines.len) return error.ReplacementOutsideBase;
        var end_line = start_line;
        while (base_lines[end_line].end < first.index + first.length) : (end_line += 1) {
            if (end_line + 1 >= base_lines.len) return error.ReplacementOutsideBase;
        }
        var next = index + 1;
        while (next < replacements.len and replacements[next].index < base_lines[end_line].end) : (next += 1) {
            while (base_lines[end_line].end < replacements[next].index + replacements[next].length) : (end_line += 1) {
                if (end_line + 1 >= base_lines.len) return error.ReplacementOutsideBase;
            }
        }
        try output.appendSlice(gpa, original[old_from..original_lines[start_line].start]);
        const changed = try replace(gpa, base[base_lines[start_line].start..base_lines[end_line].end], replacements[index..next], base_lines[start_line].start);
        defer gpa.free(changed);
        try output.appendSlice(gpa, changed);
        old_from = original_lines[end_line].end;
        index = next;
    }
    try output.appendSlice(gpa, original[old_from..]);
    return output.toOwnedSlice(gpa);
}
pub fn apply(gpa: std.mem.Allocator, original: []const u8, edits: []const Edit, path: []const u8) !Result {
    if (edits.len == 0) return .{ .failure = try std.fmt.allocPrint(gpa, "No changes made to {s}. The replacements produced identical content.", .{path}) };
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const temporary = arena.allocator();
    const base = try text.lf(temporary, original);
    const normalized_edits = try temporary.alloc(Edit, edits.len);
    var used_fuzzy = false;
    const fuzzy_base = try text.fuzzy(temporary, base);
    for (edits, normalized_edits, 0..) |edit, *normalized, index| {
        normalized.* = .{ .oldText = try text.lf(temporary, edit.oldText), .newText = try text.lf(temporary, edit.newText) };
        if (normalized.oldText.len == 0) return .{ .failure = if (edits.len == 1) try std.fmt.allocPrint(gpa, "oldText must not be empty in {s}.", .{path}) else try std.fmt.allocPrint(gpa, "edits[{d}].oldText must not be empty in {s}.", .{ index, path }) };
        if (std.mem.indexOf(u8, base, normalized.oldText) == null) {
            const fuzzy_old = try text.fuzzy(temporary, normalized.oldText);
            if (std.mem.indexOf(u8, fuzzy_base, fuzzy_old) != null) used_fuzzy = true;
        }
    }
    const replacement_base = if (used_fuzzy) fuzzy_base else base;
    const replacements = try temporary.alloc(Replacement, edits.len);
    for (normalized_edits, replacements, 0..) |edit, *replacement, index| {
        const fuzzy_old = try text.fuzzy(temporary, edit.oldText);
        const exact_index = std.mem.indexOf(u8, replacement_base, edit.oldText);
        const fuzzy_index = if (exact_index == null) std.mem.indexOf(u8, try text.fuzzy(temporary, replacement_base), fuzzy_old) else null;
        const at = exact_index orelse fuzzy_index orelse return .{ .failure = if (edits.len == 1) try std.fmt.allocPrint(gpa, "Could not find the exact text in {s}. The old text must match exactly including all whitespace and newlines.", .{path}) else try std.fmt.allocPrint(gpa, "Could not find edits[{d}] in {s}. The oldText must match exactly including all whitespace and newlines.", .{ index, path }) };
        const count = occurrences(try text.fuzzy(temporary, replacement_base), fuzzy_old);
        if (count > 1) return .{ .failure = if (edits.len == 1) try std.fmt.allocPrint(gpa, "Found {d} occurrences of the text in {s}. The text must be unique. Please provide more context to make it unique.", .{ count, path }) else try std.fmt.allocPrint(gpa, "Found {d} occurrences of edits[{d}] in {s}. Each oldText must be unique. Please provide more context to make it unique.", .{ count, index, path }) };
        replacement.* = .{ .index = at, .length = if (exact_index != null) edit.oldText.len else fuzzy_old.len, .newText = edit.newText, .editIndex = index };
    }
    std.mem.sort(Replacement, replacements, {}, before);
    for (replacements[1..], replacements[0 .. replacements.len - 1]) |current, previous| {
        if (previous.index + previous.length > current.index) return .{ .failure = try std.fmt.allocPrint(gpa, "edits[{d}] and edits[{d}] overlap in {s}. Merge them into one edit or target disjoint regions.", .{ previous.editIndex, current.editIndex, path }) };
    }
    const changed = if (used_fuzzy) try preserving(gpa, base, replacement_base, replacements) else try replace(gpa, replacement_base, replacements, 0);
    var transferred = false;
    defer if (!transferred) gpa.free(changed);
    if (std.mem.eql(u8, base, changed)) {
        return .{ .failure = if (edits.len == 1) try std.fmt.allocPrint(gpa, "No changes made to {s}. The replacement produced identical content. This might indicate an issue with special characters or the text not existing as expected.", .{path}) else try std.fmt.allocPrint(gpa, "No changes made to {s}. The replacements produced identical content.", .{path}) };
    }
    const owned_base = try gpa.dupe(u8, base);
    transferred = true;
    return .{ .value = .{ .baseContent = owned_base, .newContent = changed } };
}
pub fn restore(gpa: std.mem.Allocator, changed: []const u8, original: []const u8) ![]u8 {
    const crlf = std.mem.indexOf(u8, original, "\r\n");
    const first_lf = std.mem.indexOfScalar(u8, original, '\n');
    const use_crlf = crlf != null and first_lf != null and crlf.? < first_lf.?;
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(gpa);
    if (std.mem.startsWith(u8, original, "\xef\xbb\xbf")) try output.appendSlice(gpa, "\xef\xbb\xbf");
    for (changed) |byte| {
        if (byte == '\n' and use_crlf) try output.append(gpa, '\r');
        try output.append(gpa, byte);
    }
    return output.toOwnedSlice(gpa);
}
