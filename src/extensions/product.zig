//! Product extensions surface: emit across ALL hook_shard_*.
const std = @import("std");
const g = @import("generated_root.zig");
const host_mod = @import("host.zig");

pub fn extensionShardCount() usize { return 15; }

pub fn emitAll(gpa: std.mem.Allocator, hook: []const u8, payload: []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    if (g.hook_shard_0.ext_0_0_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_1_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_2_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_3_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_4_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_5_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_6_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_7_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_8_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_9_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_10_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_11_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_12_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_13_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_14_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_15_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_16_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_17_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_18_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_19_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_20_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_21_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_22_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_23_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_24_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_25_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_26_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_27_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_28_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_29_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_30_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_31_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_32_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_33_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_34_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_35_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_36_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_37_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_38_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_0.ext_0_39_matches(hook)) {
        const o = try g.hook_shard_0.ext_0_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_0_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_1_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_2_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_3_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_4_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_5_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_6_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_7_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_8_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_9_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_10_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_11_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_12_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_13_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_14_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_15_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_16_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_17_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_18_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_19_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_20_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_21_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_22_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_23_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_24_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_25_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_26_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_27_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_28_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_29_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_30_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_31_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_32_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_33_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_34_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_35_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_36_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_37_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_38_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_1.ext_1_39_matches(hook)) {
        const o = try g.hook_shard_1.ext_1_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_0_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_1_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_2_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_3_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_4_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_5_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_6_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_7_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_8_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_9_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_10_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_11_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_12_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_13_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_14_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_15_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_16_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_17_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_18_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_19_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_20_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_21_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_22_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_23_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_24_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_25_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_26_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_27_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_28_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_29_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_30_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_31_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_32_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_33_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_34_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_35_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_36_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_37_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_38_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_2.ext_2_39_matches(hook)) {
        const o = try g.hook_shard_2.ext_2_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_0_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_1_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_2_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_3_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_4_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_5_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_6_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_7_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_8_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_9_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_10_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_11_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_12_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_13_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_14_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_15_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_16_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_17_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_18_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_19_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_20_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_21_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_22_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_23_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_24_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_25_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_26_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_27_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_28_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_29_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_30_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_31_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_32_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_33_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_34_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_35_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_36_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_37_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_38_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_3.ext_3_39_matches(hook)) {
        const o = try g.hook_shard_3.ext_3_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_0_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_1_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_2_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_3_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_4_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_5_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_6_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_7_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_8_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_9_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_10_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_11_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_12_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_13_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_14_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_15_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_16_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_17_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_18_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_19_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_20_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_21_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_22_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_23_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_24_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_25_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_26_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_27_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_28_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_29_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_30_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_31_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_32_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_33_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_34_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_35_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_36_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_37_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_38_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_4.ext_4_39_matches(hook)) {
        const o = try g.hook_shard_4.ext_4_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_0_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_1_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_2_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_3_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_4_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_5_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_6_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_7_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_8_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_9_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_10_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_11_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_12_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_13_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_14_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_15_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_16_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_17_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_18_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_19_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_20_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_21_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_22_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_23_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_24_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_25_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_26_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_27_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_28_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_29_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_30_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_31_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_32_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_33_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_34_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_35_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_36_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_37_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_38_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_5.ext_5_39_matches(hook)) {
        const o = try g.hook_shard_5.ext_5_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_0_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_1_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_2_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_3_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_4_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_5_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_6_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_7_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_8_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_9_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_10_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_11_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_12_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_13_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_14_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_15_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_16_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_17_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_18_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_19_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_20_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_21_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_22_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_23_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_24_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_25_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_26_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_27_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_28_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_29_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_30_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_31_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_32_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_33_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_34_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_35_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_36_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_37_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_38_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_6.ext_6_39_matches(hook)) {
        const o = try g.hook_shard_6.ext_6_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_0_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_1_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_2_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_3_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_4_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_5_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_6_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_7_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_8_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_9_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_10_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_11_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_12_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_13_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_14_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_15_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_16_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_17_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_18_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_19_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_20_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_21_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_22_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_23_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_24_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_25_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_26_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_27_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_28_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_29_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_30_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_31_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_32_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_33_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_34_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_35_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_36_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_37_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_38_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_7.ext_7_39_matches(hook)) {
        const o = try g.hook_shard_7.ext_7_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_0_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_1_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_2_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_3_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_4_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_5_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_6_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_7_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_8_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_9_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_10_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_11_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_12_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_13_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_14_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_15_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_16_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_17_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_18_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_19_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_20_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_21_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_22_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_23_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_24_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_25_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_26_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_27_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_28_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_29_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_30_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_31_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_32_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_33_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_34_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_35_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_36_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_37_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_38_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_8.ext_8_39_matches(hook)) {
        const o = try g.hook_shard_8.ext_8_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_0_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_1_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_2_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_3_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_4_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_5_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_6_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_7_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_8_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_9_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_10_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_11_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_12_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_13_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_14_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_15_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_16_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_17_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_18_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_19_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_20_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_21_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_22_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_23_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_24_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_25_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_26_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_27_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_28_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_29_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_30_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_31_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_32_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_33_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_34_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_35_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_36_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_37_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_38_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_9.ext_9_39_matches(hook)) {
        const o = try g.hook_shard_9.ext_9_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_0_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_1_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_2_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_3_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_4_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_5_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_6_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_7_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_8_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_9_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_10_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_11_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_12_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_13_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_14_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_15_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_16_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_17_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_18_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_19_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_20_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_21_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_22_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_23_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_24_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_25_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_26_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_27_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_28_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_29_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_30_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_31_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_32_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_33_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_34_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_35_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_36_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_37_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_38_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_10.ext_10_39_matches(hook)) {
        const o = try g.hook_shard_10.ext_10_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_0_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_1_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_2_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_3_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_4_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_5_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_6_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_7_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_8_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_9_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_10_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_11_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_12_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_13_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_14_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_15_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_16_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_17_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_18_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_19_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_20_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_21_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_22_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_23_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_24_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_25_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_26_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_27_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_28_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_29_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_30_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_31_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_32_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_33_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_34_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_35_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_36_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_37_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_38_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_11.ext_11_39_matches(hook)) {
        const o = try g.hook_shard_11.ext_11_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_0_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_1_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_2_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_3_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_4_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_5_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_6_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_7_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_8_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_9_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_10_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_11_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_12_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_13_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_14_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_15_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_16_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_17_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_18_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_19_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_20_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_21_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_22_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_23_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_24_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_25_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_26_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_27_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_28_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_29_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_30_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_31_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_32_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_33_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_34_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_35_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_36_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_37_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_38_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_12.ext_12_39_matches(hook)) {
        const o = try g.hook_shard_12.ext_12_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_0_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_1_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_2_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_3_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_4_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_5_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_6_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_7_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_8_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_9_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_10_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_11_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_12_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_13_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_14_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_15_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_16_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_17_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_18_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_19_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_20_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_21_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_22_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_23_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_24_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_25_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_26_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_27_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_28_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_29_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_30_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_31_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_32_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_33_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_34_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_35_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_36_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_37_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_38_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_13.ext_13_39_matches(hook)) {
        const o = try g.hook_shard_13.ext_13_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_0_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_0_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_1_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_1_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_2_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_2_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_3_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_3_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_4_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_4_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_5_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_5_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_6_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_6_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_7_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_7_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_8_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_8_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_9_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_9_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_10_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_10_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_11_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_11_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_12_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_12_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_13_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_13_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_14_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_14_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_15_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_15_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_16_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_16_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_17_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_17_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_18_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_18_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_19_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_19_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_20_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_20_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_21_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_21_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_22_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_22_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_23_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_23_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_24_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_24_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_25_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_25_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_26_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_26_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_27_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_27_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_28_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_28_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_29_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_29_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_30_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_30_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_31_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_31_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_32_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_32_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_33_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_33_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_34_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_34_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_35_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_35_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_36_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_36_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_37_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_37_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_38_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_38_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    if (g.hook_shard_14.ext_14_39_matches(hook)) {
        const o = try g.hook_shard_14.ext_14_39_emit(gpa, hook, payload);
        defer gpa.free(o);
        try aw.writer.writeAll(o);
        try aw.writer.writeAll("\n");
    }
    return try aw.toOwnedSlice();
}

pub fn listExtensionNames(gpa: std.mem.Allocator) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_0_name(), g.hook_shard_0.ext_0_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_1_name(), g.hook_shard_0.ext_0_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_2_name(), g.hook_shard_0.ext_0_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_3_name(), g.hook_shard_0.ext_0_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_4_name(), g.hook_shard_0.ext_0_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_5_name(), g.hook_shard_0.ext_0_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_6_name(), g.hook_shard_0.ext_0_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_7_name(), g.hook_shard_0.ext_0_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_8_name(), g.hook_shard_0.ext_0_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_9_name(), g.hook_shard_0.ext_0_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_10_name(), g.hook_shard_0.ext_0_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_11_name(), g.hook_shard_0.ext_0_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_12_name(), g.hook_shard_0.ext_0_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_13_name(), g.hook_shard_0.ext_0_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_14_name(), g.hook_shard_0.ext_0_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_15_name(), g.hook_shard_0.ext_0_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_16_name(), g.hook_shard_0.ext_0_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_17_name(), g.hook_shard_0.ext_0_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_18_name(), g.hook_shard_0.ext_0_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_19_name(), g.hook_shard_0.ext_0_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_20_name(), g.hook_shard_0.ext_0_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_21_name(), g.hook_shard_0.ext_0_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_22_name(), g.hook_shard_0.ext_0_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_23_name(), g.hook_shard_0.ext_0_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_24_name(), g.hook_shard_0.ext_0_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_25_name(), g.hook_shard_0.ext_0_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_26_name(), g.hook_shard_0.ext_0_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_27_name(), g.hook_shard_0.ext_0_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_28_name(), g.hook_shard_0.ext_0_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_29_name(), g.hook_shard_0.ext_0_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_30_name(), g.hook_shard_0.ext_0_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_31_name(), g.hook_shard_0.ext_0_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_32_name(), g.hook_shard_0.ext_0_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_33_name(), g.hook_shard_0.ext_0_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_34_name(), g.hook_shard_0.ext_0_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_35_name(), g.hook_shard_0.ext_0_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_36_name(), g.hook_shard_0.ext_0_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_37_name(), g.hook_shard_0.ext_0_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_38_name(), g.hook_shard_0.ext_0_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_0.ext_0_39_name(), g.hook_shard_0.ext_0_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_0_name(), g.hook_shard_1.ext_1_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_1_name(), g.hook_shard_1.ext_1_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_2_name(), g.hook_shard_1.ext_1_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_3_name(), g.hook_shard_1.ext_1_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_4_name(), g.hook_shard_1.ext_1_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_5_name(), g.hook_shard_1.ext_1_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_6_name(), g.hook_shard_1.ext_1_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_7_name(), g.hook_shard_1.ext_1_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_8_name(), g.hook_shard_1.ext_1_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_9_name(), g.hook_shard_1.ext_1_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_10_name(), g.hook_shard_1.ext_1_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_11_name(), g.hook_shard_1.ext_1_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_12_name(), g.hook_shard_1.ext_1_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_13_name(), g.hook_shard_1.ext_1_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_14_name(), g.hook_shard_1.ext_1_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_15_name(), g.hook_shard_1.ext_1_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_16_name(), g.hook_shard_1.ext_1_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_17_name(), g.hook_shard_1.ext_1_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_18_name(), g.hook_shard_1.ext_1_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_19_name(), g.hook_shard_1.ext_1_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_20_name(), g.hook_shard_1.ext_1_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_21_name(), g.hook_shard_1.ext_1_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_22_name(), g.hook_shard_1.ext_1_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_23_name(), g.hook_shard_1.ext_1_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_24_name(), g.hook_shard_1.ext_1_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_25_name(), g.hook_shard_1.ext_1_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_26_name(), g.hook_shard_1.ext_1_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_27_name(), g.hook_shard_1.ext_1_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_28_name(), g.hook_shard_1.ext_1_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_29_name(), g.hook_shard_1.ext_1_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_30_name(), g.hook_shard_1.ext_1_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_31_name(), g.hook_shard_1.ext_1_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_32_name(), g.hook_shard_1.ext_1_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_33_name(), g.hook_shard_1.ext_1_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_34_name(), g.hook_shard_1.ext_1_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_35_name(), g.hook_shard_1.ext_1_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_36_name(), g.hook_shard_1.ext_1_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_37_name(), g.hook_shard_1.ext_1_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_38_name(), g.hook_shard_1.ext_1_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_1.ext_1_39_name(), g.hook_shard_1.ext_1_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_0_name(), g.hook_shard_2.ext_2_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_1_name(), g.hook_shard_2.ext_2_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_2_name(), g.hook_shard_2.ext_2_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_3_name(), g.hook_shard_2.ext_2_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_4_name(), g.hook_shard_2.ext_2_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_5_name(), g.hook_shard_2.ext_2_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_6_name(), g.hook_shard_2.ext_2_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_7_name(), g.hook_shard_2.ext_2_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_8_name(), g.hook_shard_2.ext_2_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_9_name(), g.hook_shard_2.ext_2_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_10_name(), g.hook_shard_2.ext_2_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_11_name(), g.hook_shard_2.ext_2_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_12_name(), g.hook_shard_2.ext_2_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_13_name(), g.hook_shard_2.ext_2_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_14_name(), g.hook_shard_2.ext_2_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_15_name(), g.hook_shard_2.ext_2_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_16_name(), g.hook_shard_2.ext_2_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_17_name(), g.hook_shard_2.ext_2_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_18_name(), g.hook_shard_2.ext_2_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_19_name(), g.hook_shard_2.ext_2_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_20_name(), g.hook_shard_2.ext_2_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_21_name(), g.hook_shard_2.ext_2_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_22_name(), g.hook_shard_2.ext_2_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_23_name(), g.hook_shard_2.ext_2_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_24_name(), g.hook_shard_2.ext_2_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_25_name(), g.hook_shard_2.ext_2_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_26_name(), g.hook_shard_2.ext_2_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_27_name(), g.hook_shard_2.ext_2_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_28_name(), g.hook_shard_2.ext_2_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_29_name(), g.hook_shard_2.ext_2_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_30_name(), g.hook_shard_2.ext_2_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_31_name(), g.hook_shard_2.ext_2_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_32_name(), g.hook_shard_2.ext_2_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_33_name(), g.hook_shard_2.ext_2_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_34_name(), g.hook_shard_2.ext_2_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_35_name(), g.hook_shard_2.ext_2_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_36_name(), g.hook_shard_2.ext_2_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_37_name(), g.hook_shard_2.ext_2_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_38_name(), g.hook_shard_2.ext_2_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_2.ext_2_39_name(), g.hook_shard_2.ext_2_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_0_name(), g.hook_shard_3.ext_3_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_1_name(), g.hook_shard_3.ext_3_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_2_name(), g.hook_shard_3.ext_3_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_3_name(), g.hook_shard_3.ext_3_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_4_name(), g.hook_shard_3.ext_3_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_5_name(), g.hook_shard_3.ext_3_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_6_name(), g.hook_shard_3.ext_3_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_7_name(), g.hook_shard_3.ext_3_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_8_name(), g.hook_shard_3.ext_3_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_9_name(), g.hook_shard_3.ext_3_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_10_name(), g.hook_shard_3.ext_3_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_11_name(), g.hook_shard_3.ext_3_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_12_name(), g.hook_shard_3.ext_3_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_13_name(), g.hook_shard_3.ext_3_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_14_name(), g.hook_shard_3.ext_3_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_15_name(), g.hook_shard_3.ext_3_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_16_name(), g.hook_shard_3.ext_3_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_17_name(), g.hook_shard_3.ext_3_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_18_name(), g.hook_shard_3.ext_3_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_19_name(), g.hook_shard_3.ext_3_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_20_name(), g.hook_shard_3.ext_3_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_21_name(), g.hook_shard_3.ext_3_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_22_name(), g.hook_shard_3.ext_3_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_23_name(), g.hook_shard_3.ext_3_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_24_name(), g.hook_shard_3.ext_3_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_25_name(), g.hook_shard_3.ext_3_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_26_name(), g.hook_shard_3.ext_3_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_27_name(), g.hook_shard_3.ext_3_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_28_name(), g.hook_shard_3.ext_3_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_29_name(), g.hook_shard_3.ext_3_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_30_name(), g.hook_shard_3.ext_3_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_31_name(), g.hook_shard_3.ext_3_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_32_name(), g.hook_shard_3.ext_3_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_33_name(), g.hook_shard_3.ext_3_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_34_name(), g.hook_shard_3.ext_3_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_35_name(), g.hook_shard_3.ext_3_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_36_name(), g.hook_shard_3.ext_3_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_37_name(), g.hook_shard_3.ext_3_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_38_name(), g.hook_shard_3.ext_3_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_3.ext_3_39_name(), g.hook_shard_3.ext_3_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_0_name(), g.hook_shard_4.ext_4_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_1_name(), g.hook_shard_4.ext_4_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_2_name(), g.hook_shard_4.ext_4_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_3_name(), g.hook_shard_4.ext_4_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_4_name(), g.hook_shard_4.ext_4_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_5_name(), g.hook_shard_4.ext_4_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_6_name(), g.hook_shard_4.ext_4_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_7_name(), g.hook_shard_4.ext_4_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_8_name(), g.hook_shard_4.ext_4_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_9_name(), g.hook_shard_4.ext_4_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_10_name(), g.hook_shard_4.ext_4_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_11_name(), g.hook_shard_4.ext_4_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_12_name(), g.hook_shard_4.ext_4_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_13_name(), g.hook_shard_4.ext_4_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_14_name(), g.hook_shard_4.ext_4_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_15_name(), g.hook_shard_4.ext_4_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_16_name(), g.hook_shard_4.ext_4_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_17_name(), g.hook_shard_4.ext_4_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_18_name(), g.hook_shard_4.ext_4_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_19_name(), g.hook_shard_4.ext_4_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_20_name(), g.hook_shard_4.ext_4_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_21_name(), g.hook_shard_4.ext_4_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_22_name(), g.hook_shard_4.ext_4_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_23_name(), g.hook_shard_4.ext_4_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_24_name(), g.hook_shard_4.ext_4_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_25_name(), g.hook_shard_4.ext_4_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_26_name(), g.hook_shard_4.ext_4_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_27_name(), g.hook_shard_4.ext_4_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_28_name(), g.hook_shard_4.ext_4_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_29_name(), g.hook_shard_4.ext_4_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_30_name(), g.hook_shard_4.ext_4_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_31_name(), g.hook_shard_4.ext_4_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_32_name(), g.hook_shard_4.ext_4_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_33_name(), g.hook_shard_4.ext_4_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_34_name(), g.hook_shard_4.ext_4_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_35_name(), g.hook_shard_4.ext_4_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_36_name(), g.hook_shard_4.ext_4_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_37_name(), g.hook_shard_4.ext_4_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_38_name(), g.hook_shard_4.ext_4_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_4.ext_4_39_name(), g.hook_shard_4.ext_4_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_0_name(), g.hook_shard_5.ext_5_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_1_name(), g.hook_shard_5.ext_5_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_2_name(), g.hook_shard_5.ext_5_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_3_name(), g.hook_shard_5.ext_5_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_4_name(), g.hook_shard_5.ext_5_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_5_name(), g.hook_shard_5.ext_5_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_6_name(), g.hook_shard_5.ext_5_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_7_name(), g.hook_shard_5.ext_5_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_8_name(), g.hook_shard_5.ext_5_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_9_name(), g.hook_shard_5.ext_5_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_10_name(), g.hook_shard_5.ext_5_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_11_name(), g.hook_shard_5.ext_5_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_12_name(), g.hook_shard_5.ext_5_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_13_name(), g.hook_shard_5.ext_5_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_14_name(), g.hook_shard_5.ext_5_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_15_name(), g.hook_shard_5.ext_5_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_16_name(), g.hook_shard_5.ext_5_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_17_name(), g.hook_shard_5.ext_5_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_18_name(), g.hook_shard_5.ext_5_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_19_name(), g.hook_shard_5.ext_5_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_20_name(), g.hook_shard_5.ext_5_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_21_name(), g.hook_shard_5.ext_5_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_22_name(), g.hook_shard_5.ext_5_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_23_name(), g.hook_shard_5.ext_5_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_24_name(), g.hook_shard_5.ext_5_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_25_name(), g.hook_shard_5.ext_5_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_26_name(), g.hook_shard_5.ext_5_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_27_name(), g.hook_shard_5.ext_5_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_28_name(), g.hook_shard_5.ext_5_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_29_name(), g.hook_shard_5.ext_5_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_30_name(), g.hook_shard_5.ext_5_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_31_name(), g.hook_shard_5.ext_5_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_32_name(), g.hook_shard_5.ext_5_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_33_name(), g.hook_shard_5.ext_5_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_34_name(), g.hook_shard_5.ext_5_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_35_name(), g.hook_shard_5.ext_5_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_36_name(), g.hook_shard_5.ext_5_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_37_name(), g.hook_shard_5.ext_5_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_38_name(), g.hook_shard_5.ext_5_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_5.ext_5_39_name(), g.hook_shard_5.ext_5_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_0_name(), g.hook_shard_6.ext_6_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_1_name(), g.hook_shard_6.ext_6_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_2_name(), g.hook_shard_6.ext_6_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_3_name(), g.hook_shard_6.ext_6_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_4_name(), g.hook_shard_6.ext_6_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_5_name(), g.hook_shard_6.ext_6_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_6_name(), g.hook_shard_6.ext_6_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_7_name(), g.hook_shard_6.ext_6_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_8_name(), g.hook_shard_6.ext_6_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_9_name(), g.hook_shard_6.ext_6_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_10_name(), g.hook_shard_6.ext_6_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_11_name(), g.hook_shard_6.ext_6_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_12_name(), g.hook_shard_6.ext_6_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_13_name(), g.hook_shard_6.ext_6_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_14_name(), g.hook_shard_6.ext_6_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_15_name(), g.hook_shard_6.ext_6_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_16_name(), g.hook_shard_6.ext_6_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_17_name(), g.hook_shard_6.ext_6_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_18_name(), g.hook_shard_6.ext_6_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_19_name(), g.hook_shard_6.ext_6_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_20_name(), g.hook_shard_6.ext_6_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_21_name(), g.hook_shard_6.ext_6_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_22_name(), g.hook_shard_6.ext_6_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_23_name(), g.hook_shard_6.ext_6_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_24_name(), g.hook_shard_6.ext_6_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_25_name(), g.hook_shard_6.ext_6_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_26_name(), g.hook_shard_6.ext_6_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_27_name(), g.hook_shard_6.ext_6_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_28_name(), g.hook_shard_6.ext_6_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_29_name(), g.hook_shard_6.ext_6_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_30_name(), g.hook_shard_6.ext_6_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_31_name(), g.hook_shard_6.ext_6_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_32_name(), g.hook_shard_6.ext_6_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_33_name(), g.hook_shard_6.ext_6_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_34_name(), g.hook_shard_6.ext_6_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_35_name(), g.hook_shard_6.ext_6_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_36_name(), g.hook_shard_6.ext_6_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_37_name(), g.hook_shard_6.ext_6_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_38_name(), g.hook_shard_6.ext_6_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_6.ext_6_39_name(), g.hook_shard_6.ext_6_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_0_name(), g.hook_shard_7.ext_7_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_1_name(), g.hook_shard_7.ext_7_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_2_name(), g.hook_shard_7.ext_7_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_3_name(), g.hook_shard_7.ext_7_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_4_name(), g.hook_shard_7.ext_7_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_5_name(), g.hook_shard_7.ext_7_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_6_name(), g.hook_shard_7.ext_7_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_7_name(), g.hook_shard_7.ext_7_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_8_name(), g.hook_shard_7.ext_7_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_9_name(), g.hook_shard_7.ext_7_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_10_name(), g.hook_shard_7.ext_7_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_11_name(), g.hook_shard_7.ext_7_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_12_name(), g.hook_shard_7.ext_7_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_13_name(), g.hook_shard_7.ext_7_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_14_name(), g.hook_shard_7.ext_7_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_15_name(), g.hook_shard_7.ext_7_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_16_name(), g.hook_shard_7.ext_7_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_17_name(), g.hook_shard_7.ext_7_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_18_name(), g.hook_shard_7.ext_7_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_19_name(), g.hook_shard_7.ext_7_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_20_name(), g.hook_shard_7.ext_7_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_21_name(), g.hook_shard_7.ext_7_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_22_name(), g.hook_shard_7.ext_7_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_23_name(), g.hook_shard_7.ext_7_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_24_name(), g.hook_shard_7.ext_7_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_25_name(), g.hook_shard_7.ext_7_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_26_name(), g.hook_shard_7.ext_7_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_27_name(), g.hook_shard_7.ext_7_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_28_name(), g.hook_shard_7.ext_7_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_29_name(), g.hook_shard_7.ext_7_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_30_name(), g.hook_shard_7.ext_7_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_31_name(), g.hook_shard_7.ext_7_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_32_name(), g.hook_shard_7.ext_7_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_33_name(), g.hook_shard_7.ext_7_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_34_name(), g.hook_shard_7.ext_7_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_35_name(), g.hook_shard_7.ext_7_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_36_name(), g.hook_shard_7.ext_7_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_37_name(), g.hook_shard_7.ext_7_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_38_name(), g.hook_shard_7.ext_7_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_7.ext_7_39_name(), g.hook_shard_7.ext_7_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_0_name(), g.hook_shard_8.ext_8_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_1_name(), g.hook_shard_8.ext_8_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_2_name(), g.hook_shard_8.ext_8_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_3_name(), g.hook_shard_8.ext_8_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_4_name(), g.hook_shard_8.ext_8_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_5_name(), g.hook_shard_8.ext_8_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_6_name(), g.hook_shard_8.ext_8_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_7_name(), g.hook_shard_8.ext_8_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_8_name(), g.hook_shard_8.ext_8_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_9_name(), g.hook_shard_8.ext_8_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_10_name(), g.hook_shard_8.ext_8_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_11_name(), g.hook_shard_8.ext_8_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_12_name(), g.hook_shard_8.ext_8_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_13_name(), g.hook_shard_8.ext_8_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_14_name(), g.hook_shard_8.ext_8_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_15_name(), g.hook_shard_8.ext_8_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_16_name(), g.hook_shard_8.ext_8_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_17_name(), g.hook_shard_8.ext_8_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_18_name(), g.hook_shard_8.ext_8_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_19_name(), g.hook_shard_8.ext_8_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_20_name(), g.hook_shard_8.ext_8_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_21_name(), g.hook_shard_8.ext_8_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_22_name(), g.hook_shard_8.ext_8_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_23_name(), g.hook_shard_8.ext_8_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_24_name(), g.hook_shard_8.ext_8_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_25_name(), g.hook_shard_8.ext_8_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_26_name(), g.hook_shard_8.ext_8_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_27_name(), g.hook_shard_8.ext_8_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_28_name(), g.hook_shard_8.ext_8_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_29_name(), g.hook_shard_8.ext_8_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_30_name(), g.hook_shard_8.ext_8_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_31_name(), g.hook_shard_8.ext_8_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_32_name(), g.hook_shard_8.ext_8_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_33_name(), g.hook_shard_8.ext_8_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_34_name(), g.hook_shard_8.ext_8_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_35_name(), g.hook_shard_8.ext_8_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_36_name(), g.hook_shard_8.ext_8_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_37_name(), g.hook_shard_8.ext_8_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_38_name(), g.hook_shard_8.ext_8_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_8.ext_8_39_name(), g.hook_shard_8.ext_8_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_0_name(), g.hook_shard_9.ext_9_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_1_name(), g.hook_shard_9.ext_9_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_2_name(), g.hook_shard_9.ext_9_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_3_name(), g.hook_shard_9.ext_9_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_4_name(), g.hook_shard_9.ext_9_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_5_name(), g.hook_shard_9.ext_9_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_6_name(), g.hook_shard_9.ext_9_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_7_name(), g.hook_shard_9.ext_9_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_8_name(), g.hook_shard_9.ext_9_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_9_name(), g.hook_shard_9.ext_9_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_10_name(), g.hook_shard_9.ext_9_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_11_name(), g.hook_shard_9.ext_9_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_12_name(), g.hook_shard_9.ext_9_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_13_name(), g.hook_shard_9.ext_9_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_14_name(), g.hook_shard_9.ext_9_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_15_name(), g.hook_shard_9.ext_9_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_16_name(), g.hook_shard_9.ext_9_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_17_name(), g.hook_shard_9.ext_9_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_18_name(), g.hook_shard_9.ext_9_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_19_name(), g.hook_shard_9.ext_9_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_20_name(), g.hook_shard_9.ext_9_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_21_name(), g.hook_shard_9.ext_9_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_22_name(), g.hook_shard_9.ext_9_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_23_name(), g.hook_shard_9.ext_9_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_24_name(), g.hook_shard_9.ext_9_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_25_name(), g.hook_shard_9.ext_9_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_26_name(), g.hook_shard_9.ext_9_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_27_name(), g.hook_shard_9.ext_9_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_28_name(), g.hook_shard_9.ext_9_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_29_name(), g.hook_shard_9.ext_9_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_30_name(), g.hook_shard_9.ext_9_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_31_name(), g.hook_shard_9.ext_9_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_32_name(), g.hook_shard_9.ext_9_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_33_name(), g.hook_shard_9.ext_9_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_34_name(), g.hook_shard_9.ext_9_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_35_name(), g.hook_shard_9.ext_9_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_36_name(), g.hook_shard_9.ext_9_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_37_name(), g.hook_shard_9.ext_9_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_38_name(), g.hook_shard_9.ext_9_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_9.ext_9_39_name(), g.hook_shard_9.ext_9_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_0_name(), g.hook_shard_10.ext_10_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_1_name(), g.hook_shard_10.ext_10_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_2_name(), g.hook_shard_10.ext_10_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_3_name(), g.hook_shard_10.ext_10_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_4_name(), g.hook_shard_10.ext_10_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_5_name(), g.hook_shard_10.ext_10_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_6_name(), g.hook_shard_10.ext_10_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_7_name(), g.hook_shard_10.ext_10_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_8_name(), g.hook_shard_10.ext_10_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_9_name(), g.hook_shard_10.ext_10_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_10_name(), g.hook_shard_10.ext_10_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_11_name(), g.hook_shard_10.ext_10_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_12_name(), g.hook_shard_10.ext_10_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_13_name(), g.hook_shard_10.ext_10_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_14_name(), g.hook_shard_10.ext_10_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_15_name(), g.hook_shard_10.ext_10_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_16_name(), g.hook_shard_10.ext_10_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_17_name(), g.hook_shard_10.ext_10_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_18_name(), g.hook_shard_10.ext_10_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_19_name(), g.hook_shard_10.ext_10_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_20_name(), g.hook_shard_10.ext_10_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_21_name(), g.hook_shard_10.ext_10_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_22_name(), g.hook_shard_10.ext_10_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_23_name(), g.hook_shard_10.ext_10_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_24_name(), g.hook_shard_10.ext_10_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_25_name(), g.hook_shard_10.ext_10_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_26_name(), g.hook_shard_10.ext_10_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_27_name(), g.hook_shard_10.ext_10_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_28_name(), g.hook_shard_10.ext_10_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_29_name(), g.hook_shard_10.ext_10_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_30_name(), g.hook_shard_10.ext_10_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_31_name(), g.hook_shard_10.ext_10_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_32_name(), g.hook_shard_10.ext_10_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_33_name(), g.hook_shard_10.ext_10_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_34_name(), g.hook_shard_10.ext_10_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_35_name(), g.hook_shard_10.ext_10_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_36_name(), g.hook_shard_10.ext_10_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_37_name(), g.hook_shard_10.ext_10_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_38_name(), g.hook_shard_10.ext_10_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_10.ext_10_39_name(), g.hook_shard_10.ext_10_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_0_name(), g.hook_shard_11.ext_11_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_1_name(), g.hook_shard_11.ext_11_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_2_name(), g.hook_shard_11.ext_11_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_3_name(), g.hook_shard_11.ext_11_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_4_name(), g.hook_shard_11.ext_11_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_5_name(), g.hook_shard_11.ext_11_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_6_name(), g.hook_shard_11.ext_11_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_7_name(), g.hook_shard_11.ext_11_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_8_name(), g.hook_shard_11.ext_11_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_9_name(), g.hook_shard_11.ext_11_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_10_name(), g.hook_shard_11.ext_11_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_11_name(), g.hook_shard_11.ext_11_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_12_name(), g.hook_shard_11.ext_11_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_13_name(), g.hook_shard_11.ext_11_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_14_name(), g.hook_shard_11.ext_11_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_15_name(), g.hook_shard_11.ext_11_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_16_name(), g.hook_shard_11.ext_11_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_17_name(), g.hook_shard_11.ext_11_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_18_name(), g.hook_shard_11.ext_11_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_19_name(), g.hook_shard_11.ext_11_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_20_name(), g.hook_shard_11.ext_11_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_21_name(), g.hook_shard_11.ext_11_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_22_name(), g.hook_shard_11.ext_11_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_23_name(), g.hook_shard_11.ext_11_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_24_name(), g.hook_shard_11.ext_11_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_25_name(), g.hook_shard_11.ext_11_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_26_name(), g.hook_shard_11.ext_11_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_27_name(), g.hook_shard_11.ext_11_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_28_name(), g.hook_shard_11.ext_11_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_29_name(), g.hook_shard_11.ext_11_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_30_name(), g.hook_shard_11.ext_11_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_31_name(), g.hook_shard_11.ext_11_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_32_name(), g.hook_shard_11.ext_11_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_33_name(), g.hook_shard_11.ext_11_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_34_name(), g.hook_shard_11.ext_11_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_35_name(), g.hook_shard_11.ext_11_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_36_name(), g.hook_shard_11.ext_11_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_37_name(), g.hook_shard_11.ext_11_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_38_name(), g.hook_shard_11.ext_11_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_11.ext_11_39_name(), g.hook_shard_11.ext_11_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_0_name(), g.hook_shard_12.ext_12_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_1_name(), g.hook_shard_12.ext_12_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_2_name(), g.hook_shard_12.ext_12_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_3_name(), g.hook_shard_12.ext_12_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_4_name(), g.hook_shard_12.ext_12_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_5_name(), g.hook_shard_12.ext_12_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_6_name(), g.hook_shard_12.ext_12_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_7_name(), g.hook_shard_12.ext_12_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_8_name(), g.hook_shard_12.ext_12_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_9_name(), g.hook_shard_12.ext_12_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_10_name(), g.hook_shard_12.ext_12_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_11_name(), g.hook_shard_12.ext_12_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_12_name(), g.hook_shard_12.ext_12_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_13_name(), g.hook_shard_12.ext_12_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_14_name(), g.hook_shard_12.ext_12_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_15_name(), g.hook_shard_12.ext_12_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_16_name(), g.hook_shard_12.ext_12_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_17_name(), g.hook_shard_12.ext_12_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_18_name(), g.hook_shard_12.ext_12_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_19_name(), g.hook_shard_12.ext_12_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_20_name(), g.hook_shard_12.ext_12_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_21_name(), g.hook_shard_12.ext_12_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_22_name(), g.hook_shard_12.ext_12_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_23_name(), g.hook_shard_12.ext_12_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_24_name(), g.hook_shard_12.ext_12_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_25_name(), g.hook_shard_12.ext_12_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_26_name(), g.hook_shard_12.ext_12_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_27_name(), g.hook_shard_12.ext_12_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_28_name(), g.hook_shard_12.ext_12_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_29_name(), g.hook_shard_12.ext_12_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_30_name(), g.hook_shard_12.ext_12_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_31_name(), g.hook_shard_12.ext_12_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_32_name(), g.hook_shard_12.ext_12_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_33_name(), g.hook_shard_12.ext_12_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_34_name(), g.hook_shard_12.ext_12_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_35_name(), g.hook_shard_12.ext_12_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_36_name(), g.hook_shard_12.ext_12_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_37_name(), g.hook_shard_12.ext_12_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_38_name(), g.hook_shard_12.ext_12_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_12.ext_12_39_name(), g.hook_shard_12.ext_12_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_0_name(), g.hook_shard_13.ext_13_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_1_name(), g.hook_shard_13.ext_13_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_2_name(), g.hook_shard_13.ext_13_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_3_name(), g.hook_shard_13.ext_13_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_4_name(), g.hook_shard_13.ext_13_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_5_name(), g.hook_shard_13.ext_13_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_6_name(), g.hook_shard_13.ext_13_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_7_name(), g.hook_shard_13.ext_13_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_8_name(), g.hook_shard_13.ext_13_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_9_name(), g.hook_shard_13.ext_13_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_10_name(), g.hook_shard_13.ext_13_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_11_name(), g.hook_shard_13.ext_13_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_12_name(), g.hook_shard_13.ext_13_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_13_name(), g.hook_shard_13.ext_13_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_14_name(), g.hook_shard_13.ext_13_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_15_name(), g.hook_shard_13.ext_13_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_16_name(), g.hook_shard_13.ext_13_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_17_name(), g.hook_shard_13.ext_13_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_18_name(), g.hook_shard_13.ext_13_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_19_name(), g.hook_shard_13.ext_13_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_20_name(), g.hook_shard_13.ext_13_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_21_name(), g.hook_shard_13.ext_13_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_22_name(), g.hook_shard_13.ext_13_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_23_name(), g.hook_shard_13.ext_13_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_24_name(), g.hook_shard_13.ext_13_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_25_name(), g.hook_shard_13.ext_13_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_26_name(), g.hook_shard_13.ext_13_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_27_name(), g.hook_shard_13.ext_13_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_28_name(), g.hook_shard_13.ext_13_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_29_name(), g.hook_shard_13.ext_13_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_30_name(), g.hook_shard_13.ext_13_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_31_name(), g.hook_shard_13.ext_13_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_32_name(), g.hook_shard_13.ext_13_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_33_name(), g.hook_shard_13.ext_13_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_34_name(), g.hook_shard_13.ext_13_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_35_name(), g.hook_shard_13.ext_13_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_36_name(), g.hook_shard_13.ext_13_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_37_name(), g.hook_shard_13.ext_13_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_38_name(), g.hook_shard_13.ext_13_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_13.ext_13_39_name(), g.hook_shard_13.ext_13_39_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_0_name(), g.hook_shard_14.ext_14_0_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_1_name(), g.hook_shard_14.ext_14_1_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_2_name(), g.hook_shard_14.ext_14_2_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_3_name(), g.hook_shard_14.ext_14_3_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_4_name(), g.hook_shard_14.ext_14_4_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_5_name(), g.hook_shard_14.ext_14_5_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_6_name(), g.hook_shard_14.ext_14_6_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_7_name(), g.hook_shard_14.ext_14_7_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_8_name(), g.hook_shard_14.ext_14_8_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_9_name(), g.hook_shard_14.ext_14_9_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_10_name(), g.hook_shard_14.ext_14_10_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_11_name(), g.hook_shard_14.ext_14_11_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_12_name(), g.hook_shard_14.ext_14_12_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_13_name(), g.hook_shard_14.ext_14_13_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_14_name(), g.hook_shard_14.ext_14_14_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_15_name(), g.hook_shard_14.ext_14_15_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_16_name(), g.hook_shard_14.ext_14_16_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_17_name(), g.hook_shard_14.ext_14_17_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_18_name(), g.hook_shard_14.ext_14_18_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_19_name(), g.hook_shard_14.ext_14_19_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_20_name(), g.hook_shard_14.ext_14_20_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_21_name(), g.hook_shard_14.ext_14_21_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_22_name(), g.hook_shard_14.ext_14_22_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_23_name(), g.hook_shard_14.ext_14_23_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_24_name(), g.hook_shard_14.ext_14_24_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_25_name(), g.hook_shard_14.ext_14_25_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_26_name(), g.hook_shard_14.ext_14_26_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_27_name(), g.hook_shard_14.ext_14_27_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_28_name(), g.hook_shard_14.ext_14_28_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_29_name(), g.hook_shard_14.ext_14_29_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_30_name(), g.hook_shard_14.ext_14_30_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_31_name(), g.hook_shard_14.ext_14_31_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_32_name(), g.hook_shard_14.ext_14_32_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_33_name(), g.hook_shard_14.ext_14_33_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_34_name(), g.hook_shard_14.ext_14_34_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_35_name(), g.hook_shard_14.ext_14_35_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_36_name(), g.hook_shard_14.ext_14_36_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_37_name(), g.hook_shard_14.ext_14_37_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_38_name(), g.hook_shard_14.ext_14_38_version()});
    try aw.writer.print("{s}@{s}\n", .{g.hook_shard_14.ext_14_39_name(), g.hook_shard_14.ext_14_39_version()});
    return try aw.toOwnedSlice();
}

pub fn extensionCount() usize { return 15 * 40; }

test "extensions product all hook shards" {
    const gpa = std.testing.allocator;
    const names = try listExtensionNames(gpa);
    defer gpa.free(names);
    try std.testing.expect(std.mem.indexOf(u8, names, "ext_0_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, names, "ext_14_39") != null);
    const emitted = try emitAll(gpa, "before_prompt", "{}");
    defer gpa.free(emitted);
    try std.testing.expect(emitted.len > 0);
}
