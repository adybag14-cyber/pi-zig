//! Native durable environment foundations; consumers supply explicit I/O.
const std = @import("std");
pub const decode = @import("decode.zig");
pub const line_scan = @import("line_scan.zig");
pub const types = @import("types.zig");
pub const filesystem = @import("filesystem.zig");
pub const output_window = @import("output_window.zig");
pub const startup = @import("startup.zig");
pub const shell = @import("shell.zig");
pub const watch = @import("watch.zig");
pub const read = @import("read.zig");
pub const execution_env = @import("execution_env.zig");
pub const ExecutionEnv = execution_env.ExecutionEnv;
pub const tools = @import("tools.zig");
pub const tool_bash = @import("tool_bash.zig");
pub const tool_powershell = @import("tool_powershell.zig");
pub const truncate = @import("truncate.zig");
pub const LineScanner = line_scan.LineScanner;
pub const LineScan = line_scan.LineScan;
test {
    std.testing.refAllDecls(@This());
    _ = @import("oracle_tests.zig");
}
