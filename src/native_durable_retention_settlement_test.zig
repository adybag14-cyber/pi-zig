//! Keep the module root at src/ so actual Session/backend imports remain inside
//! the module while the focused test exercises the original implementation.
comptime {
    _ = @import("durable/session.zig");
}
