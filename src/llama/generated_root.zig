//! Auto-aggregator for generated llama surface shards.
const std = @import("std");

pub const runtime_shard_0 = @import("runtime_shard_0.zig");
pub const runtime_shard_1 = @import("runtime_shard_1.zig");
pub const runtime_shard_2 = @import("runtime_shard_2.zig");
pub const runtime_shard_3 = @import("runtime_shard_3.zig");
pub const runtime_shard_4 = @import("runtime_shard_4.zig");
pub const runtime_shard_5 = @import("runtime_shard_5.zig");
pub const runtime_shard_6 = @import("runtime_shard_6.zig");
pub const runtime_shard_7 = @import("runtime_shard_7.zig");
pub const runtime_shard_8 = @import("runtime_shard_8.zig");
pub const runtime_shard_9 = @import("runtime_shard_9.zig");
pub const runtime_shard_10 = @import("runtime_shard_10.zig");
pub const runtime_shard_11 = @import("runtime_shard_11.zig");

test { std.testing.refAllDecls(@This()); }
