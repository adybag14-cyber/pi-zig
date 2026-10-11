//! Use the actual Session and settlement channel with src/ as module root.
comptime {
    _ = @import("durable/owner_settlement.zig");
}
