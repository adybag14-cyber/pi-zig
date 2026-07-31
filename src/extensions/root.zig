//! Extensions package root: host + generated hook registry.
const std = @import("std");

pub const host = @import("host.zig");
pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

pub const Host = host.Host;
pub const ExtensionManifest = host.ExtensionManifest;

test {
    std.testing.refAllDecls(@This());
}
