const std = @import("std");
comptime {
    std.testing.refAllDecls(@import("extensions/native_stream.zig"));
}
