//! Product themes surface: palettes across ALL palette_shard_*.
const std = @import("std");
const g = @import("generated_root.zig");
const theme = @import("theme.zig");

pub fn paletteShardCount() usize { return 12; }

pub fn listPalettes(gpa: std.mem.Allocator) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    {
        const p = g.palette_shard_0.palette_0_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_0.palette_0_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_1.palette_1_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_2.palette_2_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_3.palette_3_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_4.palette_4_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_5.palette_5_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_6.palette_6_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_7.palette_7_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_8.palette_8_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_9.palette_9_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_10.palette_10_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_0();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_1();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_2();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_3();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_4();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_5();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_6();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_7();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_8();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_9();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_10();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_11();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_12();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_13();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_14();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_15();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_16();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_17();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_18();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_19();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_20();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_21();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_22();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_23();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_24();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_25();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_26();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_27();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_28();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_29();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_30();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_31();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_32();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_33();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_34();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_35();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_36();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_37();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_38();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_39();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_40();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_41();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_42();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_43();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_44();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_45();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_46();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_47();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_48();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    {
        const p = g.palette_shard_11.palette_11_49();
        try aw.writer.print("{s}\t{s}\t{s}\n", .{ p.name, p.accent, p.bg });
    }
    return try aw.toOwnedSlice();
}

pub fn wrapAllAccents(gpa: std.mem.Allocator, text: []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(gpa);
    errdefer aw.deinit();
    {
        const w = try g.palette_shard_0.palette_0_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_1.palette_1_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_2.palette_2_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_3.palette_3_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_4.palette_4_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_5.palette_5_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_6.palette_6_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_7.palette_7_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_8.palette_8_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_9.palette_9_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_10.palette_10_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    {
        const w = try g.palette_shard_11.palette_11_0_wrap(gpa, text);
        defer gpa.free(w);
        try aw.writer.writeAll(w);
        try aw.writer.writeAll("\n");
    }
    return try aw.toOwnedSlice();
}

pub fn paletteCount() usize { return 12 * 50; }

test "themes product all palette shards" {
    const gpa = std.testing.allocator;
    const list = try listPalettes(gpa);
    defer gpa.free(list);
    try std.testing.expect(std.mem.indexOf(u8, list, "theme_0_0") != null);
    try std.testing.expect(std.mem.indexOf(u8, list, "theme_11_49") != null);
    try std.testing.expectEqual(@as(usize, 600), paletteCount());
}
