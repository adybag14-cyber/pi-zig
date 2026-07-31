//! Product protocol surface: MessageKind across agent+protocol msg shards.
const std = @import("std");
const ag = @import("../agent/generated_root.zig");
const pg = @import("generated_root.zig");

pub fn parseAnyKind(s: []const u8) bool {
    if (ag.protocol_shard_0.parseKind(s) != null) return true;
    if (ag.protocol_shard_1.parseKind(s) != null) return true;
    if (ag.protocol_shard_2.parseKind(s) != null) return true;
    if (ag.protocol_shard_3.parseKind(s) != null) return true;
    if (ag.protocol_shard_4.parseKind(s) != null) return true;
    if (ag.protocol_shard_5.parseKind(s) != null) return true;
    if (ag.protocol_shard_6.parseKind(s) != null) return true;
    if (ag.protocol_shard_7.parseKind(s) != null) return true;
    if (ag.protocol_shard_8.parseKind(s) != null) return true;
    if (ag.protocol_shard_9.parseKind(s) != null) return true;
    if (ag.protocol_shard_10.parseKind(s) != null) return true;
    if (ag.protocol_shard_11.parseKind(s) != null) return true;
    if (ag.protocol_shard_12.parseKind(s) != null) return true;
    if (ag.protocol_shard_13.parseKind(s) != null) return true;
    if (ag.protocol_shard_14.parseKind(s) != null) return true;
    if (ag.protocol_shard_15.parseKind(s) != null) return true;
    if (ag.protocol_shard_16.parseKind(s) != null) return true;
    if (ag.protocol_shard_17.parseKind(s) != null) return true;
    if (ag.protocol_shard_18.parseKind(s) != null) return true;
    if (ag.protocol_shard_19.parseKind(s) != null) return true;
    if (pg.msg_shard_0.parseKind(s) != null) return true;
    if (pg.msg_shard_1.parseKind(s) != null) return true;
    if (pg.msg_shard_2.parseKind(s) != null) return true;
    if (pg.msg_shard_3.parseKind(s) != null) return true;
    if (pg.msg_shard_4.parseKind(s) != null) return true;
    if (pg.msg_shard_5.parseKind(s) != null) return true;
    if (pg.msg_shard_6.parseKind(s) != null) return true;
    if (pg.msg_shard_7.parseKind(s) != null) return true;
    if (pg.msg_shard_8.parseKind(s) != null) return true;
    if (pg.msg_shard_9.parseKind(s) != null) return true;
    if (pg.msg_shard_10.parseKind(s) != null) return true;
    if (pg.msg_shard_11.parseKind(s) != null) return true;
    if (pg.msg_shard_12.parseKind(s) != null) return true;
    if (pg.msg_shard_13.parseKind(s) != null) return true;
    if (pg.msg_shard_14.parseKind(s) != null) return true;
    return false;
}

pub fn dispatchAny(gpa: std.mem.Allocator, name: []const u8, payload: []const u8) !?[]u8 {
    if (try ag.protocol_shard_0.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_1.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_2.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_3.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_4.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_5.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_6.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_7.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_8.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_9.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_10.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_11.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_12.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_13.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_14.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_15.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_16.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_17.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_18.dispatchByName(gpa, name, payload)) |o| return o;
    if (try ag.protocol_shard_19.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_0.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_1.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_2.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_3.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_4.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_5.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_6.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_7.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_8.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_9.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_10.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_11.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_12.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_13.dispatchByName(gpa, name, payload)) |o| return o;
    if (try pg.msg_shard_14.dispatchByName(gpa, name, payload)) |o| return o;
    return null;
}

pub fn encodePing(gpa: std.mem.Allocator) ![]u8 {
    return try ag.protocol_shard_0.encodeEnvelope(gpa, "p1", .ping, "{}");
}

test "protocol product agent+protocol shards" {
    try std.testing.expect(parseAnyKind("prompt"));
    try std.testing.expect(parseAnyKind("ext_msg_0_0"));
    try std.testing.expect(parseAnyKind("ext_msg_100_0"));
    try std.testing.expect(parseAnyKind("ext_msg_114_49"));
    const gpa = std.testing.allocator;
    const out = try dispatchAny(gpa, "ext_msg_0_0", "x");
    try std.testing.expect(out != null);
    defer gpa.free(out.?);
    try std.testing.expect(std.mem.indexOf(u8, out.?, "\"ok\":true") != null);
    const out2 = try dispatchAny(gpa, "ext_msg_114_0", "y");
    try std.testing.expect(out2 != null);
    defer gpa.free(out2.?);
}
