//! Native fixture program for observing actual pseudoconsole capabilities.
const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;
extern "kernel32" fn GetConsoleMode(w.HANDLE, *u32) callconv(.winapi) w.BOOL;
extern "kernel32" fn SetConsoleMode(w.HANDLE, u32) callconv(.winapi) w.BOOL;
extern "kernel32" fn SetConsoleCP(u32) callconv(.winapi) w.BOOL;
extern "kernel32" fn SetConsoleOutputCP(u32) callconv(.winapi) w.BOOL;
pub fn main(init: std.process.Init) !void {
    if (comptime builtin.os.tag != .windows) return error.UnsupportedProbe;
    var input_mode: u32 = 0;
    var output_mode: u32 = 0;
    if (!GetConsoleMode(std.Io.File.stdin().handle, &input_mode).toBool()) return error.ProbeInputIsNotConsole;
    if (!GetConsoleMode(std.Io.File.stdout().handle, &output_mode).toBool()) return error.ProbeOutputIsNotConsole;
    if (!SetConsoleMode(std.Io.File.stdin().handle, (input_mode & ~@as(u32, 7)) | 0x200).toBool()) return error.ProbeRawFailed;
    defer _ = SetConsoleMode(std.Io.File.stdin().handle, input_mode);
    if (!SetConsoleMode(std.Io.File.stdout().handle, output_mode | 4).toBool()) return error.ProbeOutputFailed;
    defer _ = SetConsoleMode(std.Io.File.stdout().handle, output_mode);
    _ = SetConsoleCP(65001);
    _ = SetConsoleOutputCP(65001);
    try std.Io.File.stderr().writeStreamingAll(init.io, "native-conpty-stderr\n");
    try std.Io.File.stdout().writeStreamingAll(init.io, "\x1b[?1049h\x1b[2J\x1b[Hnative-conpty-ready\r\n");
    var buffer: [256]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const line = try reader.interface.takeDelimiterInclusive('\r');
    if (std.mem.eql(u8, line, "burst\r")) {
        const burst = [_]u8{'B'} ** 65536;
        for (0..8) |_| try std.Io.File.stdout().writeStreamingAll(init.io, &burst);
    }
    try std.Io.File.stdout().writeStreamingAll(init.io, line);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\r\nnative-conpty-done\x1b[?1049l");
}
