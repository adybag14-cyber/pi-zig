//! Focused catalog validation without compiling the application or C runtimes.
const std = @import("std");
pub const catalog = @import("ai/catalog.zig");
pub const providers = @import("ai/providers.zig");
pub const projection = @import("ai/catalog_projection_test.zig");

test {
    std.testing.refAllDecls(@This());
}
