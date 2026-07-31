//! Generated HTTP/RPC route surface shard 0.
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
    .{ .method = "POST", .path = "/ext/0/0", .name = "ext_0_0" },
    .{ .method = "POST", .path = "/ext/0/1", .name = "ext_0_1" },
    .{ .method = "POST", .path = "/ext/0/2", .name = "ext_0_2" },
    .{ .method = "POST", .path = "/ext/0/3", .name = "ext_0_3" },
    .{ .method = "POST", .path = "/ext/0/4", .name = "ext_0_4" },
    .{ .method = "POST", .path = "/ext/0/5", .name = "ext_0_5" },
    .{ .method = "POST", .path = "/ext/0/6", .name = "ext_0_6" },
    .{ .method = "POST", .path = "/ext/0/7", .name = "ext_0_7" },
    .{ .method = "POST", .path = "/ext/0/8", .name = "ext_0_8" },
    .{ .method = "POST", .path = "/ext/0/9", .name = "ext_0_9" },
    .{ .method = "POST", .path = "/ext/0/10", .name = "ext_0_10" },
    .{ .method = "POST", .path = "/ext/0/11", .name = "ext_0_11" },
    .{ .method = "POST", .path = "/ext/0/12", .name = "ext_0_12" },
    .{ .method = "POST", .path = "/ext/0/13", .name = "ext_0_13" },
    .{ .method = "POST", .path = "/ext/0/14", .name = "ext_0_14" },
    .{ .method = "POST", .path = "/ext/0/15", .name = "ext_0_15" },
    .{ .method = "POST", .path = "/ext/0/16", .name = "ext_0_16" },
    .{ .method = "POST", .path = "/ext/0/17", .name = "ext_0_17" },
    .{ .method = "POST", .path = "/ext/0/18", .name = "ext_0_18" },
    .{ .method = "POST", .path = "/ext/0/19", .name = "ext_0_19" },
    .{ .method = "POST", .path = "/ext/0/20", .name = "ext_0_20" },
    .{ .method = "POST", .path = "/ext/0/21", .name = "ext_0_21" },
    .{ .method = "POST", .path = "/ext/0/22", .name = "ext_0_22" },
    .{ .method = "POST", .path = "/ext/0/23", .name = "ext_0_23" },
    .{ .method = "POST", .path = "/ext/0/24", .name = "ext_0_24" },
    .{ .method = "POST", .path = "/ext/0/25", .name = "ext_0_25" },
    .{ .method = "POST", .path = "/ext/0/26", .name = "ext_0_26" },
    .{ .method = "POST", .path = "/ext/0/27", .name = "ext_0_27" },
    .{ .method = "POST", .path = "/ext/0/28", .name = "ext_0_28" },
    .{ .method = "POST", .path = "/ext/0/29", .name = "ext_0_29" },
    .{ .method = "POST", .path = "/ext/0/30", .name = "ext_0_30" },
    .{ .method = "POST", .path = "/ext/0/31", .name = "ext_0_31" },
    .{ .method = "POST", .path = "/ext/0/32", .name = "ext_0_32" },
    .{ .method = "POST", .path = "/ext/0/33", .name = "ext_0_33" },
    .{ .method = "POST", .path = "/ext/0/34", .name = "ext_0_34" },
    .{ .method = "POST", .path = "/ext/0/35", .name = "ext_0_35" },
    .{ .method = "POST", .path = "/ext/0/36", .name = "ext_0_36" },
    .{ .method = "POST", .path = "/ext/0/37", .name = "ext_0_37" },
    .{ .method = "POST", .path = "/ext/0/38", .name = "ext_0_38" },
    .{ .method = "POST", .path = "/ext/0/39", .name = "ext_0_39" },
    .{ .method = "POST", .path = "/ext/0/40", .name = "ext_0_40" },
    .{ .method = "POST", .path = "/ext/0/41", .name = "ext_0_41" },
    .{ .method = "POST", .path = "/ext/0/42", .name = "ext_0_42" },
    .{ .method = "POST", .path = "/ext/0/43", .name = "ext_0_43" },
    .{ .method = "POST", .path = "/ext/0/44", .name = "ext_0_44" },
    .{ .method = "POST", .path = "/ext/0/45", .name = "ext_0_45" },
    .{ .method = "POST", .path = "/ext/0/46", .name = "ext_0_46" },
    .{ .method = "POST", .path = "/ext/0/47", .name = "ext_0_47" },
    .{ .method = "POST", .path = "/ext/0/48", .name = "ext_0_48" },
    .{ .method = "POST", .path = "/ext/0/49", .name = "ext_0_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_0_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_0() []const u8 { return "application/json"; }

pub fn handle_ext_0_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_1() []const u8 { return "application/json"; }

pub fn handle_ext_0_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_2() []const u8 { return "application/json"; }

pub fn handle_ext_0_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_3() []const u8 { return "application/json"; }

pub fn handle_ext_0_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_4() []const u8 { return "application/json"; }

pub fn handle_ext_0_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_5() []const u8 { return "application/json"; }

pub fn handle_ext_0_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_6() []const u8 { return "application/json"; }

pub fn handle_ext_0_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_7() []const u8 { return "application/json"; }

pub fn handle_ext_0_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_8() []const u8 { return "application/json"; }

pub fn handle_ext_0_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_9() []const u8 { return "application/json"; }

pub fn handle_ext_0_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_10() []const u8 { return "application/json"; }

pub fn handle_ext_0_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_11() []const u8 { return "application/json"; }

pub fn handle_ext_0_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_12() []const u8 { return "application/json"; }

pub fn handle_ext_0_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_13() []const u8 { return "application/json"; }

pub fn handle_ext_0_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_14() []const u8 { return "application/json"; }

pub fn handle_ext_0_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_15() []const u8 { return "application/json"; }

pub fn handle_ext_0_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_16() []const u8 { return "application/json"; }

pub fn handle_ext_0_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_17() []const u8 { return "application/json"; }

pub fn handle_ext_0_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_18() []const u8 { return "application/json"; }

pub fn handle_ext_0_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_19() []const u8 { return "application/json"; }

pub fn handle_ext_0_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_20() []const u8 { return "application/json"; }

pub fn handle_ext_0_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_21() []const u8 { return "application/json"; }

pub fn handle_ext_0_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_22() []const u8 { return "application/json"; }

pub fn handle_ext_0_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_23() []const u8 { return "application/json"; }

pub fn handle_ext_0_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_24() []const u8 { return "application/json"; }

pub fn handle_ext_0_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_25() []const u8 { return "application/json"; }

pub fn handle_ext_0_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_26() []const u8 { return "application/json"; }

pub fn handle_ext_0_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_27() []const u8 { return "application/json"; }

pub fn handle_ext_0_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_28() []const u8 { return "application/json"; }

pub fn handle_ext_0_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_29() []const u8 { return "application/json"; }

pub fn handle_ext_0_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_30() []const u8 { return "application/json"; }

pub fn handle_ext_0_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_31() []const u8 { return "application/json"; }

pub fn handle_ext_0_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_32() []const u8 { return "application/json"; }

pub fn handle_ext_0_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_33() []const u8 { return "application/json"; }

pub fn handle_ext_0_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_34() []const u8 { return "application/json"; }

pub fn handle_ext_0_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_35() []const u8 { return "application/json"; }

pub fn handle_ext_0_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_36() []const u8 { return "application/json"; }

pub fn handle_ext_0_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_37() []const u8 { return "application/json"; }

pub fn handle_ext_0_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_38() []const u8 { return "application/json"; }

pub fn handle_ext_0_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_39() []const u8 { return "application/json"; }

pub fn handle_ext_0_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_40() []const u8 { return "application/json"; }

pub fn handle_ext_0_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_41() []const u8 { return "application/json"; }

pub fn handle_ext_0_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_42() []const u8 { return "application/json"; }

pub fn handle_ext_0_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_43() []const u8 { return "application/json"; }

pub fn handle_ext_0_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_44() []const u8 { return "application/json"; }

pub fn handle_ext_0_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_45() []const u8 { return "application/json"; }

pub fn handle_ext_0_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_46() []const u8 { return "application/json"; }

pub fn handle_ext_0_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_47() []const u8 { return "application/json"; }

pub fn handle_ext_0_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_48() []const u8 { return "application/json"; }

pub fn handle_ext_0_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_0_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_0_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_0_49() []const u8 { return "application/json"; }

test "server routes shard 0" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/0/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_0_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

