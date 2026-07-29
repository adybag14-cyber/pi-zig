//! Export session to simple HTML transcript.
const std = @import("std");
const session_mod = @import("../agent/session.zig");

pub fn exportHtml(gpa: std.mem.Allocator, sess: *const session_mod.Session) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    try out.appendSlice(gpa,
        \\<!DOCTYPE html>
        \\<html><head><meta charset="utf-8"><title>pi session
    );
    try out.appendSlice(gpa, sess.id);
    try out.appendSlice(gpa,
        \\</title>
        \\<style>
        \\body{font-family:system-ui,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem;background:#0d1117;color:#e6edf3}
        \\.msg{border:1px solid #30363d;border-radius:8px;padding:1rem;margin:1rem 0}
        \\.role{font-weight:700;color:#58a6ff;margin-bottom:.5rem}
        \\.role.user{color:#3fb950}.role.assistant{color:#d2a8ff}.role.tool{color:#ffa657}.role.system{color:#8b949e}
        \\pre{white-space:pre-wrap;word-break:break-word;margin:0}
        \\h1{font-size:1.25rem}
        \\</style></head><body>
        \\<h1>pi session 
    );
    try appendEscaped(gpa, &out, sess.id);
    if (sess.name.len > 0) {
        try out.appendSlice(gpa, " — ");
        try appendEscaped(gpa, &out, sess.name);
    }
    try out.appendSlice(gpa, "</h1>\n");

    for (sess.entries.items) |e| {
        try out.appendSlice(gpa, "<div class=\"msg\"><div class=\"role ");
        try out.appendSlice(gpa, e.role);
        try out.appendSlice(gpa, "\">");
        try appendEscaped(gpa, &out, e.role);
        const small = try std.fmt.allocPrint(gpa, " <small>({s})</small></div><pre>", .{e.id});
        defer gpa.free(small);
        try out.appendSlice(gpa, small);
        try appendEscaped(gpa, &out, e.content);
        try out.appendSlice(gpa, "</pre></div>\n");
    }

    try out.appendSlice(gpa, "</body></html>\n");
    return try out.toOwnedSlice(gpa);
}

fn appendEscaped(gpa: std.mem.Allocator, out: *std.ArrayList(u8), s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '<' => try out.appendSlice(gpa, "&lt;"),
            '>' => try out.appendSlice(gpa, "&gt;"),
            '&' => try out.appendSlice(gpa, "&amp;"),
            '"' => try out.appendSlice(gpa, "&quot;"),
            else => try out.append(gpa, c),
        }
    }
}

test "export html contains messages" {
    const gpa = std.testing.allocator;
    var s = try session_mod.Session.init(gpa, "html-1", "/tmp");
    defer s.deinit();
    _ = try s.appendMessage(null, "user", "Hello <world>", null, null);
    const html = try exportHtml(gpa, &s);
    defer gpa.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "Hello") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "&lt;world&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "html-1") != null);
}
