//! Generated HTTP/RPC route surface shard 8.
const std = @import("std");

pub const Route = struct { method: []const u8, path: []const u8, name: []const u8 };

pub const routes = [_]Route{
    .{ .method = "GET", .path = "/health", .name = "health" },
    .{ .method = "GET", .path = "/version", .name = "version" },
    .{ .method = "POST", .path = "/rpc", .name = "rpc" },
    .{ .method = "POST", .path = "/v1/chat/completions", .name = "openai_compat" },
    .{ .method = "GET", .path = "/sessions", .name = "list_sessions" },
    .{ .method = "POST", .path = "/sessions", .name = "create_session" },
    .{ .method = "GET", .path = "/models", .name = "list_models" },
    .{ .method = "POST", .path = "/ext/8/0", .name = "ext_8_0" },
    .{ .method = "POST", .path = "/ext/8/1", .name = "ext_8_1" },
    .{ .method = "POST", .path = "/ext/8/2", .name = "ext_8_2" },
    .{ .method = "POST", .path = "/ext/8/3", .name = "ext_8_3" },
    .{ .method = "POST", .path = "/ext/8/4", .name = "ext_8_4" },
    .{ .method = "POST", .path = "/ext/8/5", .name = "ext_8_5" },
    .{ .method = "POST", .path = "/ext/8/6", .name = "ext_8_6" },
    .{ .method = "POST", .path = "/ext/8/7", .name = "ext_8_7" },
    .{ .method = "POST", .path = "/ext/8/8", .name = "ext_8_8" },
    .{ .method = "POST", .path = "/ext/8/9", .name = "ext_8_9" },
    .{ .method = "POST", .path = "/ext/8/10", .name = "ext_8_10" },
    .{ .method = "POST", .path = "/ext/8/11", .name = "ext_8_11" },
    .{ .method = "POST", .path = "/ext/8/12", .name = "ext_8_12" },
    .{ .method = "POST", .path = "/ext/8/13", .name = "ext_8_13" },
    .{ .method = "POST", .path = "/ext/8/14", .name = "ext_8_14" },
    .{ .method = "POST", .path = "/ext/8/15", .name = "ext_8_15" },
    .{ .method = "POST", .path = "/ext/8/16", .name = "ext_8_16" },
    .{ .method = "POST", .path = "/ext/8/17", .name = "ext_8_17" },
    .{ .method = "POST", .path = "/ext/8/18", .name = "ext_8_18" },
    .{ .method = "POST", .path = "/ext/8/19", .name = "ext_8_19" },
    .{ .method = "POST", .path = "/ext/8/20", .name = "ext_8_20" },
    .{ .method = "POST", .path = "/ext/8/21", .name = "ext_8_21" },
    .{ .method = "POST", .path = "/ext/8/22", .name = "ext_8_22" },
    .{ .method = "POST", .path = "/ext/8/23", .name = "ext_8_23" },
    .{ .method = "POST", .path = "/ext/8/24", .name = "ext_8_24" },
    .{ .method = "POST", .path = "/ext/8/25", .name = "ext_8_25" },
    .{ .method = "POST", .path = "/ext/8/26", .name = "ext_8_26" },
    .{ .method = "POST", .path = "/ext/8/27", .name = "ext_8_27" },
    .{ .method = "POST", .path = "/ext/8/28", .name = "ext_8_28" },
    .{ .method = "POST", .path = "/ext/8/29", .name = "ext_8_29" },
    .{ .method = "POST", .path = "/ext/8/30", .name = "ext_8_30" },
    .{ .method = "POST", .path = "/ext/8/31", .name = "ext_8_31" },
    .{ .method = "POST", .path = "/ext/8/32", .name = "ext_8_32" },
    .{ .method = "POST", .path = "/ext/8/33", .name = "ext_8_33" },
    .{ .method = "POST", .path = "/ext/8/34", .name = "ext_8_34" },
    .{ .method = "POST", .path = "/ext/8/35", .name = "ext_8_35" },
    .{ .method = "POST", .path = "/ext/8/36", .name = "ext_8_36" },
    .{ .method = "POST", .path = "/ext/8/37", .name = "ext_8_37" },
    .{ .method = "POST", .path = "/ext/8/38", .name = "ext_8_38" },
    .{ .method = "POST", .path = "/ext/8/39", .name = "ext_8_39" },
    .{ .method = "POST", .path = "/ext/8/40", .name = "ext_8_40" },
    .{ .method = "POST", .path = "/ext/8/41", .name = "ext_8_41" },
    .{ .method = "POST", .path = "/ext/8/42", .name = "ext_8_42" },
    .{ .method = "POST", .path = "/ext/8/43", .name = "ext_8_43" },
    .{ .method = "POST", .path = "/ext/8/44", .name = "ext_8_44" },
    .{ .method = "POST", .path = "/ext/8/45", .name = "ext_8_45" },
    .{ .method = "POST", .path = "/ext/8/46", .name = "ext_8_46" },
    .{ .method = "POST", .path = "/ext/8/47", .name = "ext_8_47" },
    .{ .method = "POST", .path = "/ext/8/48", .name = "ext_8_48" },
    .{ .method = "POST", .path = "/ext/8/49", .name = "ext_8_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_8_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_0() []const u8 { return "application/json"; }

pub fn handle_ext_8_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_1() []const u8 { return "application/json"; }

pub fn handle_ext_8_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_2() []const u8 { return "application/json"; }

pub fn handle_ext_8_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_3() []const u8 { return "application/json"; }

pub fn handle_ext_8_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_4() []const u8 { return "application/json"; }

pub fn handle_ext_8_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_5() []const u8 { return "application/json"; }

pub fn handle_ext_8_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_6() []const u8 { return "application/json"; }

pub fn handle_ext_8_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_7() []const u8 { return "application/json"; }

pub fn handle_ext_8_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_8() []const u8 { return "application/json"; }

pub fn handle_ext_8_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_9() []const u8 { return "application/json"; }

pub fn handle_ext_8_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_10() []const u8 { return "application/json"; }

pub fn handle_ext_8_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_11() []const u8 { return "application/json"; }

pub fn handle_ext_8_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_12() []const u8 { return "application/json"; }

pub fn handle_ext_8_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_13() []const u8 { return "application/json"; }

pub fn handle_ext_8_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_14() []const u8 { return "application/json"; }

pub fn handle_ext_8_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_15() []const u8 { return "application/json"; }

pub fn handle_ext_8_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_16() []const u8 { return "application/json"; }

pub fn handle_ext_8_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_17() []const u8 { return "application/json"; }

pub fn handle_ext_8_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_18() []const u8 { return "application/json"; }

pub fn handle_ext_8_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_19() []const u8 { return "application/json"; }

pub fn handle_ext_8_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_20() []const u8 { return "application/json"; }

pub fn handle_ext_8_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_21() []const u8 { return "application/json"; }

pub fn handle_ext_8_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_22() []const u8 { return "application/json"; }

pub fn handle_ext_8_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_23() []const u8 { return "application/json"; }

pub fn handle_ext_8_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_24() []const u8 { return "application/json"; }

pub fn handle_ext_8_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_25() []const u8 { return "application/json"; }

pub fn handle_ext_8_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_26() []const u8 { return "application/json"; }

pub fn handle_ext_8_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_27() []const u8 { return "application/json"; }

pub fn handle_ext_8_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_28() []const u8 { return "application/json"; }

pub fn handle_ext_8_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_29() []const u8 { return "application/json"; }

pub fn handle_ext_8_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_30() []const u8 { return "application/json"; }

pub fn handle_ext_8_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_31() []const u8 { return "application/json"; }

pub fn handle_ext_8_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_32() []const u8 { return "application/json"; }

pub fn handle_ext_8_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_33() []const u8 { return "application/json"; }

pub fn handle_ext_8_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_34() []const u8 { return "application/json"; }

pub fn handle_ext_8_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_35() []const u8 { return "application/json"; }

pub fn handle_ext_8_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_36() []const u8 { return "application/json"; }

pub fn handle_ext_8_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_37() []const u8 { return "application/json"; }

pub fn handle_ext_8_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_38() []const u8 { return "application/json"; }

pub fn handle_ext_8_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_39() []const u8 { return "application/json"; }

pub fn handle_ext_8_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_40() []const u8 { return "application/json"; }

pub fn handle_ext_8_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_41() []const u8 { return "application/json"; }

pub fn handle_ext_8_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_42() []const u8 { return "application/json"; }

pub fn handle_ext_8_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_43() []const u8 { return "application/json"; }

pub fn handle_ext_8_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_44() []const u8 { return "application/json"; }

pub fn handle_ext_8_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_45() []const u8 { return "application/json"; }

pub fn handle_ext_8_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_46() []const u8 { return "application/json"; }

pub fn handle_ext_8_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_47() []const u8 { return "application/json"; }

pub fn handle_ext_8_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_48() []const u8 { return "application/json"; }

pub fn handle_ext_8_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_8_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_8_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_8_49() []const u8 { return "application/json"; }

test "server routes shard 8" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/8/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_8_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

