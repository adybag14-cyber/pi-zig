//! Cross-platform file-permission values for Zig 0.16.
//!
//! Final Zig 0.16 represents Windows permissions as file attributes and does
//! not expose the POSIX-only `fromMode` constructor. Keep security-sensitive
//! POSIX modes while using the native Windows defaults.
const std = @import("std");
const builtin = @import("builtin");

pub fn privateFile() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) {
        return std.Io.File.Permissions.fromMode(0o600);
    }
    return .default_file;
}

pub fn ownerExecutable() std.Io.File.Permissions {
    if (@hasDecl(std.Io.File.Permissions, "fromMode")) {
        return std.Io.File.Permissions.fromMode(0o700);
    }
    return .executable_file;
}

pub fn setOwnerExecutable(dir: std.Io.Dir, io: std.Io, path: []const u8) !void {
    if (builtin.os.tag == .windows) return;
    try dir.setFilePermissions(io, path, ownerExecutable(), .{});
}
