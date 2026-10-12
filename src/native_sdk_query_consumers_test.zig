const std = @import("std");
comptime {
    std.testing.refAllDecls(@import("extensions/native_sdk_builtin_execution.zig"));
    std.testing.refAllDecls(@import("extensions/native_sdk_agent_tool.zig"));
}
