//! Generated HTTP/RPC route surface shard 7.
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
    .{ .method = "POST", .path = "/ext/7/0", .name = "ext_7_0" },
    .{ .method = "POST", .path = "/ext/7/1", .name = "ext_7_1" },
    .{ .method = "POST", .path = "/ext/7/2", .name = "ext_7_2" },
    .{ .method = "POST", .path = "/ext/7/3", .name = "ext_7_3" },
    .{ .method = "POST", .path = "/ext/7/4", .name = "ext_7_4" },
    .{ .method = "POST", .path = "/ext/7/5", .name = "ext_7_5" },
    .{ .method = "POST", .path = "/ext/7/6", .name = "ext_7_6" },
    .{ .method = "POST", .path = "/ext/7/7", .name = "ext_7_7" },
    .{ .method = "POST", .path = "/ext/7/8", .name = "ext_7_8" },
    .{ .method = "POST", .path = "/ext/7/9", .name = "ext_7_9" },
    .{ .method = "POST", .path = "/ext/7/10", .name = "ext_7_10" },
    .{ .method = "POST", .path = "/ext/7/11", .name = "ext_7_11" },
    .{ .method = "POST", .path = "/ext/7/12", .name = "ext_7_12" },
    .{ .method = "POST", .path = "/ext/7/13", .name = "ext_7_13" },
    .{ .method = "POST", .path = "/ext/7/14", .name = "ext_7_14" },
    .{ .method = "POST", .path = "/ext/7/15", .name = "ext_7_15" },
    .{ .method = "POST", .path = "/ext/7/16", .name = "ext_7_16" },
    .{ .method = "POST", .path = "/ext/7/17", .name = "ext_7_17" },
    .{ .method = "POST", .path = "/ext/7/18", .name = "ext_7_18" },
    .{ .method = "POST", .path = "/ext/7/19", .name = "ext_7_19" },
    .{ .method = "POST", .path = "/ext/7/20", .name = "ext_7_20" },
    .{ .method = "POST", .path = "/ext/7/21", .name = "ext_7_21" },
    .{ .method = "POST", .path = "/ext/7/22", .name = "ext_7_22" },
    .{ .method = "POST", .path = "/ext/7/23", .name = "ext_7_23" },
    .{ .method = "POST", .path = "/ext/7/24", .name = "ext_7_24" },
    .{ .method = "POST", .path = "/ext/7/25", .name = "ext_7_25" },
    .{ .method = "POST", .path = "/ext/7/26", .name = "ext_7_26" },
    .{ .method = "POST", .path = "/ext/7/27", .name = "ext_7_27" },
    .{ .method = "POST", .path = "/ext/7/28", .name = "ext_7_28" },
    .{ .method = "POST", .path = "/ext/7/29", .name = "ext_7_29" },
    .{ .method = "POST", .path = "/ext/7/30", .name = "ext_7_30" },
    .{ .method = "POST", .path = "/ext/7/31", .name = "ext_7_31" },
    .{ .method = "POST", .path = "/ext/7/32", .name = "ext_7_32" },
    .{ .method = "POST", .path = "/ext/7/33", .name = "ext_7_33" },
    .{ .method = "POST", .path = "/ext/7/34", .name = "ext_7_34" },
    .{ .method = "POST", .path = "/ext/7/35", .name = "ext_7_35" },
    .{ .method = "POST", .path = "/ext/7/36", .name = "ext_7_36" },
    .{ .method = "POST", .path = "/ext/7/37", .name = "ext_7_37" },
    .{ .method = "POST", .path = "/ext/7/38", .name = "ext_7_38" },
    .{ .method = "POST", .path = "/ext/7/39", .name = "ext_7_39" },
    .{ .method = "POST", .path = "/ext/7/40", .name = "ext_7_40" },
    .{ .method = "POST", .path = "/ext/7/41", .name = "ext_7_41" },
    .{ .method = "POST", .path = "/ext/7/42", .name = "ext_7_42" },
    .{ .method = "POST", .path = "/ext/7/43", .name = "ext_7_43" },
    .{ .method = "POST", .path = "/ext/7/44", .name = "ext_7_44" },
    .{ .method = "POST", .path = "/ext/7/45", .name = "ext_7_45" },
    .{ .method = "POST", .path = "/ext/7/46", .name = "ext_7_46" },
    .{ .method = "POST", .path = "/ext/7/47", .name = "ext_7_47" },
    .{ .method = "POST", .path = "/ext/7/48", .name = "ext_7_48" },
    .{ .method = "POST", .path = "/ext/7/49", .name = "ext_7_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_7_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_0() []const u8 { return "application/json"; }

pub fn handle_ext_7_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_1() []const u8 { return "application/json"; }

pub fn handle_ext_7_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_2() []const u8 { return "application/json"; }

pub fn handle_ext_7_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_3() []const u8 { return "application/json"; }

pub fn handle_ext_7_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_4() []const u8 { return "application/json"; }

pub fn handle_ext_7_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_5() []const u8 { return "application/json"; }

pub fn handle_ext_7_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_6() []const u8 { return "application/json"; }

pub fn handle_ext_7_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_7() []const u8 { return "application/json"; }

pub fn handle_ext_7_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_8() []const u8 { return "application/json"; }

pub fn handle_ext_7_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_9() []const u8 { return "application/json"; }

pub fn handle_ext_7_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_10() []const u8 { return "application/json"; }

pub fn handle_ext_7_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_11() []const u8 { return "application/json"; }

pub fn handle_ext_7_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_12() []const u8 { return "application/json"; }

pub fn handle_ext_7_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_13() []const u8 { return "application/json"; }

pub fn handle_ext_7_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_14() []const u8 { return "application/json"; }

pub fn handle_ext_7_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_15() []const u8 { return "application/json"; }

pub fn handle_ext_7_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_16() []const u8 { return "application/json"; }

pub fn handle_ext_7_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_17() []const u8 { return "application/json"; }

pub fn handle_ext_7_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_18() []const u8 { return "application/json"; }

pub fn handle_ext_7_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_19() []const u8 { return "application/json"; }

pub fn handle_ext_7_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_20() []const u8 { return "application/json"; }

pub fn handle_ext_7_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_21() []const u8 { return "application/json"; }

pub fn handle_ext_7_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_22() []const u8 { return "application/json"; }

pub fn handle_ext_7_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_23() []const u8 { return "application/json"; }

pub fn handle_ext_7_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_24() []const u8 { return "application/json"; }

pub fn handle_ext_7_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_25() []const u8 { return "application/json"; }

pub fn handle_ext_7_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_26() []const u8 { return "application/json"; }

pub fn handle_ext_7_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_27() []const u8 { return "application/json"; }

pub fn handle_ext_7_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_28() []const u8 { return "application/json"; }

pub fn handle_ext_7_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_29() []const u8 { return "application/json"; }

pub fn handle_ext_7_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_30() []const u8 { return "application/json"; }

pub fn handle_ext_7_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_31() []const u8 { return "application/json"; }

pub fn handle_ext_7_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_32() []const u8 { return "application/json"; }

pub fn handle_ext_7_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_33() []const u8 { return "application/json"; }

pub fn handle_ext_7_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_34() []const u8 { return "application/json"; }

pub fn handle_ext_7_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_35() []const u8 { return "application/json"; }

pub fn handle_ext_7_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_36() []const u8 { return "application/json"; }

pub fn handle_ext_7_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_37() []const u8 { return "application/json"; }

pub fn handle_ext_7_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_38() []const u8 { return "application/json"; }

pub fn handle_ext_7_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_39() []const u8 { return "application/json"; }

pub fn handle_ext_7_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_40() []const u8 { return "application/json"; }

pub fn handle_ext_7_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_41() []const u8 { return "application/json"; }

pub fn handle_ext_7_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_42() []const u8 { return "application/json"; }

pub fn handle_ext_7_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_43() []const u8 { return "application/json"; }

pub fn handle_ext_7_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_44() []const u8 { return "application/json"; }

pub fn handle_ext_7_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_45() []const u8 { return "application/json"; }

pub fn handle_ext_7_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_46() []const u8 { return "application/json"; }

pub fn handle_ext_7_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_47() []const u8 { return "application/json"; }

pub fn handle_ext_7_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_48() []const u8 { return "application/json"; }

pub fn handle_ext_7_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_7_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_7_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_7_49() []const u8 { return "application/json"; }

test "server routes shard 7" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/7/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_7_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

