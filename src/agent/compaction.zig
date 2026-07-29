//! Compact older messages into a single summary, keep recent N.
const std = @import("std");
const session_mod = @import("session.zig");

pub const CompactOptions = struct {
    /// Keep this many most recent messages on the active branch (default 6).
    keep_recent: usize = 6,
};

/// Heuristic compaction: replace older branch messages with one system summary message.
/// Mutates session in place.
pub fn compact(sess: *session_mod.Session, opts: CompactOptions) !void {
    if (sess.entries.items.len <= opts.keep_recent) return;

    const gpa = sess.gpa;
    const branch = try sess.branchEntries(gpa);
    defer gpa.free(branch);

    if (branch.len <= opts.keep_recent) return;

    const cut = branch.len - opts.keep_recent;
    var summary: std.ArrayList(u8) = .empty;
    defer summary.deinit(gpa);
    try summary.appendSlice(gpa, "[Compacted conversation summary]\n");
    for (branch[0..cut]) |e| {
        const line = try std.fmt.allocPrint(gpa, "- {s}: {s}\n", .{ e.role, truncate(e.content, 200) });
        defer gpa.free(line);
        try summary.appendSlice(gpa, line);
    }

    // Collect ids to keep (recent branch + anything not on branch? we keep only recent branch for simplicity)
    var keep_ids: std.ArrayList([]const u8) = .empty;
    defer keep_ids.deinit(gpa);
    for (branch[cut..]) |e| {
        try keep_ids.append(gpa, e.id);
    }

    // Build new entry list: summary as first, then kept
    var new_entries: std.ArrayList(session_mod.SessionEntry) = .empty;
    errdefer {
        for (new_entries.items) |*e| e.deinit(gpa);
        new_entries.deinit(gpa);
    }

    const summary_id = try std.fmt.allocPrint(gpa, "m{d}", .{sess.next_seq});
    sess.next_seq += 1;
    try new_entries.append(gpa, .{
        .id = summary_id,
        .parent_id = null,
        .role = try gpa.dupe(u8, "system"),
        .content = try summary.toOwnedSlice(gpa),
        .tool_call_id = null,
        .tool_calls_json = null,
    });

    // Re-parent first kept entry to summary
    var first_kept = true;
    for (sess.entries.items) |e| {
        var should_keep = false;
        for (keep_ids.items) |kid| {
            if (std.mem.eql(u8, kid, e.id)) {
                should_keep = true;
                break;
            }
        }
        if (!should_keep) {
            // free old entry fields by cloning only keepers
            continue;
        }
        const parent: ?[]const u8 = if (first_kept) summary_id else if (e.parent_id) |p| p else null;
        first_kept = false;
        try new_entries.append(gpa, .{
            .id = try gpa.dupe(u8, e.id),
            .parent_id = if (parent) |p| try gpa.dupe(u8, p) else null,
            .role = try gpa.dupe(u8, e.role),
            .content = try gpa.dupe(u8, e.content),
            .tool_call_id = if (e.tool_call_id) |t| try gpa.dupe(u8, t) else null,
            .tool_calls_json = if (e.tool_calls_json) |t| try gpa.dupe(u8, t) else null,
        });
    }

    // Free old entries
    for (sess.entries.items) |*e| e.deinit(gpa);
    sess.entries.deinit(gpa);
    sess.entries = new_entries;

    // Update tip to last new entry
    if (sess.tip_id) |t| gpa.free(t);
    if (sess.entries.items.len > 0) {
        const last = sess.entries.items[sess.entries.items.len - 1].id;
        sess.tip_id = try gpa.dupe(u8, last);
    } else {
        sess.tip_id = null;
    }
}

fn truncate(s: []const u8, max: usize) []const u8 {
    if (s.len <= max) return s;
    return s[0..max];
}

test "compact keeps recent messages" {
    const gpa = std.testing.allocator;
    var s = try session_mod.Session.init(gpa, "c1", "/tmp");
    defer s.deinit();

    var parent: ?[]const u8 = null;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const role = if (i % 2 == 0) "user" else "assistant";
        const content = try std.fmt.allocPrint(gpa, "msg-{d}", .{i});
        defer gpa.free(content);
        parent = try s.appendMessage(parent, role, content, null, null);
    }
    try std.testing.expectEqual(@as(usize, 10), s.entries.items.len);

    try compact(&s, .{ .keep_recent = 4 });
    // 1 summary + 4 recent
    try std.testing.expect(s.entries.items.len <= 5);
    try std.testing.expectEqualStrings("system", s.entries.items[0].role);
    try std.testing.expect(std.mem.indexOf(u8, s.entries.items[0].content, "Compacted") != null);
}
