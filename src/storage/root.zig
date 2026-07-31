//! Storage package root: session index + generated schema surface.
const std = @import("std");

pub const session_index = @import("session_index.zig");
pub const generated = @import("generated_root.zig");
pub const product = @import("product.zig");

pub const SessionIndex = session_index.SessionIndex;
pub const IndexEntry = session_index.IndexEntry;

test {
    std.testing.refAllDecls(@This());
}
