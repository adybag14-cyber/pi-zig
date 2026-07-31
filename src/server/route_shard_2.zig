//! Generated HTTP/RPC route surface shard 2.
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
    .{ .method = "POST", .path = "/ext/2/0", .name = "ext_2_0" },
    .{ .method = "POST", .path = "/ext/2/1", .name = "ext_2_1" },
    .{ .method = "POST", .path = "/ext/2/2", .name = "ext_2_2" },
    .{ .method = "POST", .path = "/ext/2/3", .name = "ext_2_3" },
    .{ .method = "POST", .path = "/ext/2/4", .name = "ext_2_4" },
    .{ .method = "POST", .path = "/ext/2/5", .name = "ext_2_5" },
    .{ .method = "POST", .path = "/ext/2/6", .name = "ext_2_6" },
    .{ .method = "POST", .path = "/ext/2/7", .name = "ext_2_7" },
    .{ .method = "POST", .path = "/ext/2/8", .name = "ext_2_8" },
    .{ .method = "POST", .path = "/ext/2/9", .name = "ext_2_9" },
    .{ .method = "POST", .path = "/ext/2/10", .name = "ext_2_10" },
    .{ .method = "POST", .path = "/ext/2/11", .name = "ext_2_11" },
    .{ .method = "POST", .path = "/ext/2/12", .name = "ext_2_12" },
    .{ .method = "POST", .path = "/ext/2/13", .name = "ext_2_13" },
    .{ .method = "POST", .path = "/ext/2/14", .name = "ext_2_14" },
    .{ .method = "POST", .path = "/ext/2/15", .name = "ext_2_15" },
    .{ .method = "POST", .path = "/ext/2/16", .name = "ext_2_16" },
    .{ .method = "POST", .path = "/ext/2/17", .name = "ext_2_17" },
    .{ .method = "POST", .path = "/ext/2/18", .name = "ext_2_18" },
    .{ .method = "POST", .path = "/ext/2/19", .name = "ext_2_19" },
    .{ .method = "POST", .path = "/ext/2/20", .name = "ext_2_20" },
    .{ .method = "POST", .path = "/ext/2/21", .name = "ext_2_21" },
    .{ .method = "POST", .path = "/ext/2/22", .name = "ext_2_22" },
    .{ .method = "POST", .path = "/ext/2/23", .name = "ext_2_23" },
    .{ .method = "POST", .path = "/ext/2/24", .name = "ext_2_24" },
    .{ .method = "POST", .path = "/ext/2/25", .name = "ext_2_25" },
    .{ .method = "POST", .path = "/ext/2/26", .name = "ext_2_26" },
    .{ .method = "POST", .path = "/ext/2/27", .name = "ext_2_27" },
    .{ .method = "POST", .path = "/ext/2/28", .name = "ext_2_28" },
    .{ .method = "POST", .path = "/ext/2/29", .name = "ext_2_29" },
    .{ .method = "POST", .path = "/ext/2/30", .name = "ext_2_30" },
    .{ .method = "POST", .path = "/ext/2/31", .name = "ext_2_31" },
    .{ .method = "POST", .path = "/ext/2/32", .name = "ext_2_32" },
    .{ .method = "POST", .path = "/ext/2/33", .name = "ext_2_33" },
    .{ .method = "POST", .path = "/ext/2/34", .name = "ext_2_34" },
    .{ .method = "POST", .path = "/ext/2/35", .name = "ext_2_35" },
    .{ .method = "POST", .path = "/ext/2/36", .name = "ext_2_36" },
    .{ .method = "POST", .path = "/ext/2/37", .name = "ext_2_37" },
    .{ .method = "POST", .path = "/ext/2/38", .name = "ext_2_38" },
    .{ .method = "POST", .path = "/ext/2/39", .name = "ext_2_39" },
    .{ .method = "POST", .path = "/ext/2/40", .name = "ext_2_40" },
    .{ .method = "POST", .path = "/ext/2/41", .name = "ext_2_41" },
    .{ .method = "POST", .path = "/ext/2/42", .name = "ext_2_42" },
    .{ .method = "POST", .path = "/ext/2/43", .name = "ext_2_43" },
    .{ .method = "POST", .path = "/ext/2/44", .name = "ext_2_44" },
    .{ .method = "POST", .path = "/ext/2/45", .name = "ext_2_45" },
    .{ .method = "POST", .path = "/ext/2/46", .name = "ext_2_46" },
    .{ .method = "POST", .path = "/ext/2/47", .name = "ext_2_47" },
    .{ .method = "POST", .path = "/ext/2/48", .name = "ext_2_48" },
    .{ .method = "POST", .path = "/ext/2/49", .name = "ext_2_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_2_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_0() []const u8 { return "application/json"; }

pub fn handle_ext_2_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_1() []const u8 { return "application/json"; }

pub fn handle_ext_2_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_2() []const u8 { return "application/json"; }

pub fn handle_ext_2_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_3() []const u8 { return "application/json"; }

pub fn handle_ext_2_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_4() []const u8 { return "application/json"; }

pub fn handle_ext_2_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_5() []const u8 { return "application/json"; }

pub fn handle_ext_2_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_6() []const u8 { return "application/json"; }

pub fn handle_ext_2_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_7() []const u8 { return "application/json"; }

pub fn handle_ext_2_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_8() []const u8 { return "application/json"; }

pub fn handle_ext_2_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_9() []const u8 { return "application/json"; }

pub fn handle_ext_2_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_10() []const u8 { return "application/json"; }

pub fn handle_ext_2_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_11() []const u8 { return "application/json"; }

pub fn handle_ext_2_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_12() []const u8 { return "application/json"; }

pub fn handle_ext_2_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_13() []const u8 { return "application/json"; }

pub fn handle_ext_2_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_14() []const u8 { return "application/json"; }

pub fn handle_ext_2_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_15() []const u8 { return "application/json"; }

pub fn handle_ext_2_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_16() []const u8 { return "application/json"; }

pub fn handle_ext_2_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_17() []const u8 { return "application/json"; }

pub fn handle_ext_2_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_18() []const u8 { return "application/json"; }

pub fn handle_ext_2_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_19() []const u8 { return "application/json"; }

pub fn handle_ext_2_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_20() []const u8 { return "application/json"; }

pub fn handle_ext_2_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_21() []const u8 { return "application/json"; }

pub fn handle_ext_2_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_22() []const u8 { return "application/json"; }

pub fn handle_ext_2_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_23() []const u8 { return "application/json"; }

pub fn handle_ext_2_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_24() []const u8 { return "application/json"; }

pub fn handle_ext_2_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_25() []const u8 { return "application/json"; }

pub fn handle_ext_2_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_26() []const u8 { return "application/json"; }

pub fn handle_ext_2_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_27() []const u8 { return "application/json"; }

pub fn handle_ext_2_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_28() []const u8 { return "application/json"; }

pub fn handle_ext_2_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_29() []const u8 { return "application/json"; }

pub fn handle_ext_2_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_30() []const u8 { return "application/json"; }

pub fn handle_ext_2_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_31() []const u8 { return "application/json"; }

pub fn handle_ext_2_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_32() []const u8 { return "application/json"; }

pub fn handle_ext_2_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_33() []const u8 { return "application/json"; }

pub fn handle_ext_2_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_34() []const u8 { return "application/json"; }

pub fn handle_ext_2_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_35() []const u8 { return "application/json"; }

pub fn handle_ext_2_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_36() []const u8 { return "application/json"; }

pub fn handle_ext_2_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_37() []const u8 { return "application/json"; }

pub fn handle_ext_2_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_38() []const u8 { return "application/json"; }

pub fn handle_ext_2_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_39() []const u8 { return "application/json"; }

pub fn handle_ext_2_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_40() []const u8 { return "application/json"; }

pub fn handle_ext_2_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_41() []const u8 { return "application/json"; }

pub fn handle_ext_2_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_42() []const u8 { return "application/json"; }

pub fn handle_ext_2_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_43() []const u8 { return "application/json"; }

pub fn handle_ext_2_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_44() []const u8 { return "application/json"; }

pub fn handle_ext_2_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_45() []const u8 { return "application/json"; }

pub fn handle_ext_2_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_46() []const u8 { return "application/json"; }

pub fn handle_ext_2_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_47() []const u8 { return "application/json"; }

pub fn handle_ext_2_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_48() []const u8 { return "application/json"; }

pub fn handle_ext_2_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_2_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_2_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_2_49() []const u8 { return "application/json"; }

test "server routes shard 2" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/2/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_2_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

