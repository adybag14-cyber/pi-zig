//! Server package root: HTTP RPC + generated route surface.
const std = @import("std");

pub const http_rpc = @import("http_rpc.zig");
pub const generated = @import("generated_root.zig");
pub const routes_all = @import("routes_all.zig");

pub const Server = http_rpc.Server;
pub const ServerConfig = http_rpc.ServerConfig;

test {
    std.testing.refAllDecls(@This());
}
