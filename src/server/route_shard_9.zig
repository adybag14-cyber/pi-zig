//! Generated HTTP/RPC route surface shard 9.
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
    .{ .method = "POST", .path = "/ext/9/0", .name = "ext_9_0" },
    .{ .method = "POST", .path = "/ext/9/1", .name = "ext_9_1" },
    .{ .method = "POST", .path = "/ext/9/2", .name = "ext_9_2" },
    .{ .method = "POST", .path = "/ext/9/3", .name = "ext_9_3" },
    .{ .method = "POST", .path = "/ext/9/4", .name = "ext_9_4" },
    .{ .method = "POST", .path = "/ext/9/5", .name = "ext_9_5" },
    .{ .method = "POST", .path = "/ext/9/6", .name = "ext_9_6" },
    .{ .method = "POST", .path = "/ext/9/7", .name = "ext_9_7" },
    .{ .method = "POST", .path = "/ext/9/8", .name = "ext_9_8" },
    .{ .method = "POST", .path = "/ext/9/9", .name = "ext_9_9" },
    .{ .method = "POST", .path = "/ext/9/10", .name = "ext_9_10" },
    .{ .method = "POST", .path = "/ext/9/11", .name = "ext_9_11" },
    .{ .method = "POST", .path = "/ext/9/12", .name = "ext_9_12" },
    .{ .method = "POST", .path = "/ext/9/13", .name = "ext_9_13" },
    .{ .method = "POST", .path = "/ext/9/14", .name = "ext_9_14" },
    .{ .method = "POST", .path = "/ext/9/15", .name = "ext_9_15" },
    .{ .method = "POST", .path = "/ext/9/16", .name = "ext_9_16" },
    .{ .method = "POST", .path = "/ext/9/17", .name = "ext_9_17" },
    .{ .method = "POST", .path = "/ext/9/18", .name = "ext_9_18" },
    .{ .method = "POST", .path = "/ext/9/19", .name = "ext_9_19" },
    .{ .method = "POST", .path = "/ext/9/20", .name = "ext_9_20" },
    .{ .method = "POST", .path = "/ext/9/21", .name = "ext_9_21" },
    .{ .method = "POST", .path = "/ext/9/22", .name = "ext_9_22" },
    .{ .method = "POST", .path = "/ext/9/23", .name = "ext_9_23" },
    .{ .method = "POST", .path = "/ext/9/24", .name = "ext_9_24" },
    .{ .method = "POST", .path = "/ext/9/25", .name = "ext_9_25" },
    .{ .method = "POST", .path = "/ext/9/26", .name = "ext_9_26" },
    .{ .method = "POST", .path = "/ext/9/27", .name = "ext_9_27" },
    .{ .method = "POST", .path = "/ext/9/28", .name = "ext_9_28" },
    .{ .method = "POST", .path = "/ext/9/29", .name = "ext_9_29" },
    .{ .method = "POST", .path = "/ext/9/30", .name = "ext_9_30" },
    .{ .method = "POST", .path = "/ext/9/31", .name = "ext_9_31" },
    .{ .method = "POST", .path = "/ext/9/32", .name = "ext_9_32" },
    .{ .method = "POST", .path = "/ext/9/33", .name = "ext_9_33" },
    .{ .method = "POST", .path = "/ext/9/34", .name = "ext_9_34" },
    .{ .method = "POST", .path = "/ext/9/35", .name = "ext_9_35" },
    .{ .method = "POST", .path = "/ext/9/36", .name = "ext_9_36" },
    .{ .method = "POST", .path = "/ext/9/37", .name = "ext_9_37" },
    .{ .method = "POST", .path = "/ext/9/38", .name = "ext_9_38" },
    .{ .method = "POST", .path = "/ext/9/39", .name = "ext_9_39" },
    .{ .method = "POST", .path = "/ext/9/40", .name = "ext_9_40" },
    .{ .method = "POST", .path = "/ext/9/41", .name = "ext_9_41" },
    .{ .method = "POST", .path = "/ext/9/42", .name = "ext_9_42" },
    .{ .method = "POST", .path = "/ext/9/43", .name = "ext_9_43" },
    .{ .method = "POST", .path = "/ext/9/44", .name = "ext_9_44" },
    .{ .method = "POST", .path = "/ext/9/45", .name = "ext_9_45" },
    .{ .method = "POST", .path = "/ext/9/46", .name = "ext_9_46" },
    .{ .method = "POST", .path = "/ext/9/47", .name = "ext_9_47" },
    .{ .method = "POST", .path = "/ext/9/48", .name = "ext_9_48" },
    .{ .method = "POST", .path = "/ext/9/49", .name = "ext_9_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_9_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_0() []const u8 { return "application/json"; }

pub fn handle_ext_9_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_1() []const u8 { return "application/json"; }

pub fn handle_ext_9_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_2() []const u8 { return "application/json"; }

pub fn handle_ext_9_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_3() []const u8 { return "application/json"; }

pub fn handle_ext_9_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_4() []const u8 { return "application/json"; }

pub fn handle_ext_9_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_5() []const u8 { return "application/json"; }

pub fn handle_ext_9_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_6() []const u8 { return "application/json"; }

pub fn handle_ext_9_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_7() []const u8 { return "application/json"; }

pub fn handle_ext_9_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_8() []const u8 { return "application/json"; }

pub fn handle_ext_9_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_9() []const u8 { return "application/json"; }

pub fn handle_ext_9_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_10() []const u8 { return "application/json"; }

pub fn handle_ext_9_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_11() []const u8 { return "application/json"; }

pub fn handle_ext_9_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_12() []const u8 { return "application/json"; }

pub fn handle_ext_9_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_13() []const u8 { return "application/json"; }

pub fn handle_ext_9_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_14() []const u8 { return "application/json"; }

pub fn handle_ext_9_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_15() []const u8 { return "application/json"; }

pub fn handle_ext_9_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_16() []const u8 { return "application/json"; }

pub fn handle_ext_9_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_17() []const u8 { return "application/json"; }

pub fn handle_ext_9_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_18() []const u8 { return "application/json"; }

pub fn handle_ext_9_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_19() []const u8 { return "application/json"; }

pub fn handle_ext_9_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_20() []const u8 { return "application/json"; }

pub fn handle_ext_9_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_21() []const u8 { return "application/json"; }

pub fn handle_ext_9_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_22() []const u8 { return "application/json"; }

pub fn handle_ext_9_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_23() []const u8 { return "application/json"; }

pub fn handle_ext_9_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_24() []const u8 { return "application/json"; }

pub fn handle_ext_9_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_25() []const u8 { return "application/json"; }

pub fn handle_ext_9_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_26() []const u8 { return "application/json"; }

pub fn handle_ext_9_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_27() []const u8 { return "application/json"; }

pub fn handle_ext_9_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_28() []const u8 { return "application/json"; }

pub fn handle_ext_9_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_29() []const u8 { return "application/json"; }

pub fn handle_ext_9_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_30() []const u8 { return "application/json"; }

pub fn handle_ext_9_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_31() []const u8 { return "application/json"; }

pub fn handle_ext_9_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_32() []const u8 { return "application/json"; }

pub fn handle_ext_9_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_33() []const u8 { return "application/json"; }

pub fn handle_ext_9_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_34() []const u8 { return "application/json"; }

pub fn handle_ext_9_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_35() []const u8 { return "application/json"; }

pub fn handle_ext_9_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_36() []const u8 { return "application/json"; }

pub fn handle_ext_9_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_37() []const u8 { return "application/json"; }

pub fn handle_ext_9_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_38() []const u8 { return "application/json"; }

pub fn handle_ext_9_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_39() []const u8 { return "application/json"; }

pub fn handle_ext_9_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_40() []const u8 { return "application/json"; }

pub fn handle_ext_9_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_41() []const u8 { return "application/json"; }

pub fn handle_ext_9_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_42() []const u8 { return "application/json"; }

pub fn handle_ext_9_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_43() []const u8 { return "application/json"; }

pub fn handle_ext_9_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_44() []const u8 { return "application/json"; }

pub fn handle_ext_9_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_45() []const u8 { return "application/json"; }

pub fn handle_ext_9_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_46() []const u8 { return "application/json"; }

pub fn handle_ext_9_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_47() []const u8 { return "application/json"; }

pub fn handle_ext_9_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_48() []const u8 { return "application/json"; }

pub fn handle_ext_9_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_9_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_9_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_9_49() []const u8 { return "application/json"; }

test "server routes shard 9" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/9/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_9_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

