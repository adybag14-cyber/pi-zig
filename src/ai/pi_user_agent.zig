//! Pi's provider-neutral HTTP User-Agent.
const std = @import("std");
const builtin = @import("builtin");

pub const value = std.fmt.comptimePrint("pi ({s}; {s})", .{
    @tagName(builtin.os.tag),
    @tagName(builtin.cpu.arch),
});

test "Pi user agent identifies the runtime without credentials" {
    try std.testing.expect(std.mem.startsWith(u8, value, "pi ("));
    try std.testing.expect(std.mem.indexOf(u8, value, @tagName(builtin.os.tag)) != null);
}
