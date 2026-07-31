//! Generated HTTP/RPC route surface shard 14.
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
    .{ .method = "POST", .path = "/ext/14/0", .name = "ext_14_0" },
    .{ .method = "POST", .path = "/ext/14/1", .name = "ext_14_1" },
    .{ .method = "POST", .path = "/ext/14/2", .name = "ext_14_2" },
    .{ .method = "POST", .path = "/ext/14/3", .name = "ext_14_3" },
    .{ .method = "POST", .path = "/ext/14/4", .name = "ext_14_4" },
    .{ .method = "POST", .path = "/ext/14/5", .name = "ext_14_5" },
    .{ .method = "POST", .path = "/ext/14/6", .name = "ext_14_6" },
    .{ .method = "POST", .path = "/ext/14/7", .name = "ext_14_7" },
    .{ .method = "POST", .path = "/ext/14/8", .name = "ext_14_8" },
    .{ .method = "POST", .path = "/ext/14/9", .name = "ext_14_9" },
    .{ .method = "POST", .path = "/ext/14/10", .name = "ext_14_10" },
    .{ .method = "POST", .path = "/ext/14/11", .name = "ext_14_11" },
    .{ .method = "POST", .path = "/ext/14/12", .name = "ext_14_12" },
    .{ .method = "POST", .path = "/ext/14/13", .name = "ext_14_13" },
    .{ .method = "POST", .path = "/ext/14/14", .name = "ext_14_14" },
    .{ .method = "POST", .path = "/ext/14/15", .name = "ext_14_15" },
    .{ .method = "POST", .path = "/ext/14/16", .name = "ext_14_16" },
    .{ .method = "POST", .path = "/ext/14/17", .name = "ext_14_17" },
    .{ .method = "POST", .path = "/ext/14/18", .name = "ext_14_18" },
    .{ .method = "POST", .path = "/ext/14/19", .name = "ext_14_19" },
    .{ .method = "POST", .path = "/ext/14/20", .name = "ext_14_20" },
    .{ .method = "POST", .path = "/ext/14/21", .name = "ext_14_21" },
    .{ .method = "POST", .path = "/ext/14/22", .name = "ext_14_22" },
    .{ .method = "POST", .path = "/ext/14/23", .name = "ext_14_23" },
    .{ .method = "POST", .path = "/ext/14/24", .name = "ext_14_24" },
    .{ .method = "POST", .path = "/ext/14/25", .name = "ext_14_25" },
    .{ .method = "POST", .path = "/ext/14/26", .name = "ext_14_26" },
    .{ .method = "POST", .path = "/ext/14/27", .name = "ext_14_27" },
    .{ .method = "POST", .path = "/ext/14/28", .name = "ext_14_28" },
    .{ .method = "POST", .path = "/ext/14/29", .name = "ext_14_29" },
    .{ .method = "POST", .path = "/ext/14/30", .name = "ext_14_30" },
    .{ .method = "POST", .path = "/ext/14/31", .name = "ext_14_31" },
    .{ .method = "POST", .path = "/ext/14/32", .name = "ext_14_32" },
    .{ .method = "POST", .path = "/ext/14/33", .name = "ext_14_33" },
    .{ .method = "POST", .path = "/ext/14/34", .name = "ext_14_34" },
    .{ .method = "POST", .path = "/ext/14/35", .name = "ext_14_35" },
    .{ .method = "POST", .path = "/ext/14/36", .name = "ext_14_36" },
    .{ .method = "POST", .path = "/ext/14/37", .name = "ext_14_37" },
    .{ .method = "POST", .path = "/ext/14/38", .name = "ext_14_38" },
    .{ .method = "POST", .path = "/ext/14/39", .name = "ext_14_39" },
    .{ .method = "POST", .path = "/ext/14/40", .name = "ext_14_40" },
    .{ .method = "POST", .path = "/ext/14/41", .name = "ext_14_41" },
    .{ .method = "POST", .path = "/ext/14/42", .name = "ext_14_42" },
    .{ .method = "POST", .path = "/ext/14/43", .name = "ext_14_43" },
    .{ .method = "POST", .path = "/ext/14/44", .name = "ext_14_44" },
    .{ .method = "POST", .path = "/ext/14/45", .name = "ext_14_45" },
    .{ .method = "POST", .path = "/ext/14/46", .name = "ext_14_46" },
    .{ .method = "POST", .path = "/ext/14/47", .name = "ext_14_47" },
    .{ .method = "POST", .path = "/ext/14/48", .name = "ext_14_48" },
    .{ .method = "POST", .path = "/ext/14/49", .name = "ext_14_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_14_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_0() []const u8 { return "application/json"; }

pub fn handle_ext_14_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_1() []const u8 { return "application/json"; }

pub fn handle_ext_14_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_2() []const u8 { return "application/json"; }

pub fn handle_ext_14_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_3() []const u8 { return "application/json"; }

pub fn handle_ext_14_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_4() []const u8 { return "application/json"; }

pub fn handle_ext_14_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_5() []const u8 { return "application/json"; }

pub fn handle_ext_14_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_6() []const u8 { return "application/json"; }

pub fn handle_ext_14_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_7() []const u8 { return "application/json"; }

pub fn handle_ext_14_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_8() []const u8 { return "application/json"; }

pub fn handle_ext_14_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_9() []const u8 { return "application/json"; }

pub fn handle_ext_14_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_10() []const u8 { return "application/json"; }

pub fn handle_ext_14_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_11() []const u8 { return "application/json"; }

pub fn handle_ext_14_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_12() []const u8 { return "application/json"; }

pub fn handle_ext_14_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_13() []const u8 { return "application/json"; }

pub fn handle_ext_14_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_14() []const u8 { return "application/json"; }

pub fn handle_ext_14_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_15() []const u8 { return "application/json"; }

pub fn handle_ext_14_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_16() []const u8 { return "application/json"; }

pub fn handle_ext_14_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_17() []const u8 { return "application/json"; }

pub fn handle_ext_14_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_18() []const u8 { return "application/json"; }

pub fn handle_ext_14_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_19() []const u8 { return "application/json"; }

pub fn handle_ext_14_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_20() []const u8 { return "application/json"; }

pub fn handle_ext_14_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_21() []const u8 { return "application/json"; }

pub fn handle_ext_14_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_22() []const u8 { return "application/json"; }

pub fn handle_ext_14_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_23() []const u8 { return "application/json"; }

pub fn handle_ext_14_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_24() []const u8 { return "application/json"; }

pub fn handle_ext_14_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_25() []const u8 { return "application/json"; }

pub fn handle_ext_14_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_26() []const u8 { return "application/json"; }

pub fn handle_ext_14_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_27() []const u8 { return "application/json"; }

pub fn handle_ext_14_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_28() []const u8 { return "application/json"; }

pub fn handle_ext_14_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_29() []const u8 { return "application/json"; }

pub fn handle_ext_14_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_30() []const u8 { return "application/json"; }

pub fn handle_ext_14_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_31() []const u8 { return "application/json"; }

pub fn handle_ext_14_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_32() []const u8 { return "application/json"; }

pub fn handle_ext_14_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_33() []const u8 { return "application/json"; }

pub fn handle_ext_14_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_34() []const u8 { return "application/json"; }

pub fn handle_ext_14_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_35() []const u8 { return "application/json"; }

pub fn handle_ext_14_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_36() []const u8 { return "application/json"; }

pub fn handle_ext_14_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_37() []const u8 { return "application/json"; }

pub fn handle_ext_14_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_38() []const u8 { return "application/json"; }

pub fn handle_ext_14_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_39() []const u8 { return "application/json"; }

pub fn handle_ext_14_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_40() []const u8 { return "application/json"; }

pub fn handle_ext_14_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_41() []const u8 { return "application/json"; }

pub fn handle_ext_14_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_42() []const u8 { return "application/json"; }

pub fn handle_ext_14_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_43() []const u8 { return "application/json"; }

pub fn handle_ext_14_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_44() []const u8 { return "application/json"; }

pub fn handle_ext_14_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_45() []const u8 { return "application/json"; }

pub fn handle_ext_14_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_46() []const u8 { return "application/json"; }

pub fn handle_ext_14_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_47() []const u8 { return "application/json"; }

pub fn handle_ext_14_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_48() []const u8 { return "application/json"; }

pub fn handle_ext_14_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_14_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_14_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_14_49() []const u8 { return "application/json"; }

test "server routes shard 14" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/14/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_14_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

