//! Auto-aggregator for generated evals surface shards.
const std = @import("std");

pub const case_shard_0 = @import("case_shard_0.zig");
pub const case_shard_1 = @import("case_shard_1.zig");
pub const case_shard_2 = @import("case_shard_2.zig");
pub const case_shard_3 = @import("case_shard_3.zig");
pub const case_shard_4 = @import("case_shard_4.zig");
pub const case_shard_5 = @import("case_shard_5.zig");
pub const case_shard_6 = @import("case_shard_6.zig");
pub const case_shard_7 = @import("case_shard_7.zig");
pub const case_shard_8 = @import("case_shard_8.zig");
pub const case_shard_9 = @import("case_shard_9.zig");
pub const case_shard_10 = @import("case_shard_10.zig");
pub const case_shard_11 = @import("case_shard_11.zig");

test { std.testing.refAllDecls(@This()); }
