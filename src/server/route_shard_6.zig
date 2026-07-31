//! Generated HTTP/RPC route surface shard 6.
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
    .{ .method = "POST", .path = "/ext/6/0", .name = "ext_6_0" },
    .{ .method = "POST", .path = "/ext/6/1", .name = "ext_6_1" },
    .{ .method = "POST", .path = "/ext/6/2", .name = "ext_6_2" },
    .{ .method = "POST", .path = "/ext/6/3", .name = "ext_6_3" },
    .{ .method = "POST", .path = "/ext/6/4", .name = "ext_6_4" },
    .{ .method = "POST", .path = "/ext/6/5", .name = "ext_6_5" },
    .{ .method = "POST", .path = "/ext/6/6", .name = "ext_6_6" },
    .{ .method = "POST", .path = "/ext/6/7", .name = "ext_6_7" },
    .{ .method = "POST", .path = "/ext/6/8", .name = "ext_6_8" },
    .{ .method = "POST", .path = "/ext/6/9", .name = "ext_6_9" },
    .{ .method = "POST", .path = "/ext/6/10", .name = "ext_6_10" },
    .{ .method = "POST", .path = "/ext/6/11", .name = "ext_6_11" },
    .{ .method = "POST", .path = "/ext/6/12", .name = "ext_6_12" },
    .{ .method = "POST", .path = "/ext/6/13", .name = "ext_6_13" },
    .{ .method = "POST", .path = "/ext/6/14", .name = "ext_6_14" },
    .{ .method = "POST", .path = "/ext/6/15", .name = "ext_6_15" },
    .{ .method = "POST", .path = "/ext/6/16", .name = "ext_6_16" },
    .{ .method = "POST", .path = "/ext/6/17", .name = "ext_6_17" },
    .{ .method = "POST", .path = "/ext/6/18", .name = "ext_6_18" },
    .{ .method = "POST", .path = "/ext/6/19", .name = "ext_6_19" },
    .{ .method = "POST", .path = "/ext/6/20", .name = "ext_6_20" },
    .{ .method = "POST", .path = "/ext/6/21", .name = "ext_6_21" },
    .{ .method = "POST", .path = "/ext/6/22", .name = "ext_6_22" },
    .{ .method = "POST", .path = "/ext/6/23", .name = "ext_6_23" },
    .{ .method = "POST", .path = "/ext/6/24", .name = "ext_6_24" },
    .{ .method = "POST", .path = "/ext/6/25", .name = "ext_6_25" },
    .{ .method = "POST", .path = "/ext/6/26", .name = "ext_6_26" },
    .{ .method = "POST", .path = "/ext/6/27", .name = "ext_6_27" },
    .{ .method = "POST", .path = "/ext/6/28", .name = "ext_6_28" },
    .{ .method = "POST", .path = "/ext/6/29", .name = "ext_6_29" },
    .{ .method = "POST", .path = "/ext/6/30", .name = "ext_6_30" },
    .{ .method = "POST", .path = "/ext/6/31", .name = "ext_6_31" },
    .{ .method = "POST", .path = "/ext/6/32", .name = "ext_6_32" },
    .{ .method = "POST", .path = "/ext/6/33", .name = "ext_6_33" },
    .{ .method = "POST", .path = "/ext/6/34", .name = "ext_6_34" },
    .{ .method = "POST", .path = "/ext/6/35", .name = "ext_6_35" },
    .{ .method = "POST", .path = "/ext/6/36", .name = "ext_6_36" },
    .{ .method = "POST", .path = "/ext/6/37", .name = "ext_6_37" },
    .{ .method = "POST", .path = "/ext/6/38", .name = "ext_6_38" },
    .{ .method = "POST", .path = "/ext/6/39", .name = "ext_6_39" },
    .{ .method = "POST", .path = "/ext/6/40", .name = "ext_6_40" },
    .{ .method = "POST", .path = "/ext/6/41", .name = "ext_6_41" },
    .{ .method = "POST", .path = "/ext/6/42", .name = "ext_6_42" },
    .{ .method = "POST", .path = "/ext/6/43", .name = "ext_6_43" },
    .{ .method = "POST", .path = "/ext/6/44", .name = "ext_6_44" },
    .{ .method = "POST", .path = "/ext/6/45", .name = "ext_6_45" },
    .{ .method = "POST", .path = "/ext/6/46", .name = "ext_6_46" },
    .{ .method = "POST", .path = "/ext/6/47", .name = "ext_6_47" },
    .{ .method = "POST", .path = "/ext/6/48", .name = "ext_6_48" },
    .{ .method = "POST", .path = "/ext/6/49", .name = "ext_6_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_6_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_0() []const u8 { return "application/json"; }

pub fn handle_ext_6_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_1() []const u8 { return "application/json"; }

pub fn handle_ext_6_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_2() []const u8 { return "application/json"; }

pub fn handle_ext_6_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_3() []const u8 { return "application/json"; }

pub fn handle_ext_6_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_4() []const u8 { return "application/json"; }

pub fn handle_ext_6_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_5() []const u8 { return "application/json"; }

pub fn handle_ext_6_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_6() []const u8 { return "application/json"; }

pub fn handle_ext_6_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_7() []const u8 { return "application/json"; }

pub fn handle_ext_6_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_8() []const u8 { return "application/json"; }

pub fn handle_ext_6_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_9() []const u8 { return "application/json"; }

pub fn handle_ext_6_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_10() []const u8 { return "application/json"; }

pub fn handle_ext_6_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_11() []const u8 { return "application/json"; }

pub fn handle_ext_6_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_12() []const u8 { return "application/json"; }

pub fn handle_ext_6_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_13() []const u8 { return "application/json"; }

pub fn handle_ext_6_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_14() []const u8 { return "application/json"; }

pub fn handle_ext_6_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_15() []const u8 { return "application/json"; }

pub fn handle_ext_6_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_16() []const u8 { return "application/json"; }

pub fn handle_ext_6_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_17() []const u8 { return "application/json"; }

pub fn handle_ext_6_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_18() []const u8 { return "application/json"; }

pub fn handle_ext_6_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_19() []const u8 { return "application/json"; }

pub fn handle_ext_6_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_20() []const u8 { return "application/json"; }

pub fn handle_ext_6_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_21() []const u8 { return "application/json"; }

pub fn handle_ext_6_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_22() []const u8 { return "application/json"; }

pub fn handle_ext_6_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_23() []const u8 { return "application/json"; }

pub fn handle_ext_6_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_24() []const u8 { return "application/json"; }

pub fn handle_ext_6_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_25() []const u8 { return "application/json"; }

pub fn handle_ext_6_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_26() []const u8 { return "application/json"; }

pub fn handle_ext_6_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_27() []const u8 { return "application/json"; }

pub fn handle_ext_6_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_28() []const u8 { return "application/json"; }

pub fn handle_ext_6_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_29() []const u8 { return "application/json"; }

pub fn handle_ext_6_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_30() []const u8 { return "application/json"; }

pub fn handle_ext_6_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_31() []const u8 { return "application/json"; }

pub fn handle_ext_6_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_32() []const u8 { return "application/json"; }

pub fn handle_ext_6_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_33() []const u8 { return "application/json"; }

pub fn handle_ext_6_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_34() []const u8 { return "application/json"; }

pub fn handle_ext_6_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_35() []const u8 { return "application/json"; }

pub fn handle_ext_6_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_36() []const u8 { return "application/json"; }

pub fn handle_ext_6_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_37() []const u8 { return "application/json"; }

pub fn handle_ext_6_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_38() []const u8 { return "application/json"; }

pub fn handle_ext_6_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_39() []const u8 { return "application/json"; }

pub fn handle_ext_6_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_40() []const u8 { return "application/json"; }

pub fn handle_ext_6_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_41() []const u8 { return "application/json"; }

pub fn handle_ext_6_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_42() []const u8 { return "application/json"; }

pub fn handle_ext_6_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_43() []const u8 { return "application/json"; }

pub fn handle_ext_6_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_44() []const u8 { return "application/json"; }

pub fn handle_ext_6_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_45() []const u8 { return "application/json"; }

pub fn handle_ext_6_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_46() []const u8 { return "application/json"; }

pub fn handle_ext_6_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_47() []const u8 { return "application/json"; }

pub fn handle_ext_6_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_48() []const u8 { return "application/json"; }

pub fn handle_ext_6_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_6_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_6_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_6_49() []const u8 { return "application/json"; }

test "server routes shard 6" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/6/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_6_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

