//! Shared native settings-selector transactions and clean process validation.
const std = @import("std");
const pty = @import("pty.zig");

pub fn choose(session: *pty.Session, query: []const u8, label: []const u8) !void {
    var start = session.output.items.len;
    try session.send(query);
    _ = try session.waitFor(label, start, 40_000);
    try session.send("\r");
    try session.io.sleep(.fromMilliseconds(120), .awake);
    start = session.output.items.len;
    try session.send("\x1b");
    _ = try session.waitFor("mouse wheel/click supported", start, 40_000);
}

pub fn cleanExit(scratch: *pty.Scratch, session: *pty.Session, stderr_path: []const u8) !void {
    const term = try session.wait(30_000);
    const errors = try scratch.dir.readFileAlloc(session.io, stderr_path, session.gpa, .limited(65536));
    defer session.gpa.free(errors);
    if (term != .exited or term.exited != 0 or errors.len != 0) {
        std.debug.print("Settings CLI failed: {any}, stderr={s}\n", .{ term, errors });
        return error.SettingsProcessFailed;
    }
}
