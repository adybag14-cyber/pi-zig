//! Generated HTTP/RPC route surface shard 13.
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
    .{ .method = "POST", .path = "/ext/13/0", .name = "ext_13_0" },
    .{ .method = "POST", .path = "/ext/13/1", .name = "ext_13_1" },
    .{ .method = "POST", .path = "/ext/13/2", .name = "ext_13_2" },
    .{ .method = "POST", .path = "/ext/13/3", .name = "ext_13_3" },
    .{ .method = "POST", .path = "/ext/13/4", .name = "ext_13_4" },
    .{ .method = "POST", .path = "/ext/13/5", .name = "ext_13_5" },
    .{ .method = "POST", .path = "/ext/13/6", .name = "ext_13_6" },
    .{ .method = "POST", .path = "/ext/13/7", .name = "ext_13_7" },
    .{ .method = "POST", .path = "/ext/13/8", .name = "ext_13_8" },
    .{ .method = "POST", .path = "/ext/13/9", .name = "ext_13_9" },
    .{ .method = "POST", .path = "/ext/13/10", .name = "ext_13_10" },
    .{ .method = "POST", .path = "/ext/13/11", .name = "ext_13_11" },
    .{ .method = "POST", .path = "/ext/13/12", .name = "ext_13_12" },
    .{ .method = "POST", .path = "/ext/13/13", .name = "ext_13_13" },
    .{ .method = "POST", .path = "/ext/13/14", .name = "ext_13_14" },
    .{ .method = "POST", .path = "/ext/13/15", .name = "ext_13_15" },
    .{ .method = "POST", .path = "/ext/13/16", .name = "ext_13_16" },
    .{ .method = "POST", .path = "/ext/13/17", .name = "ext_13_17" },
    .{ .method = "POST", .path = "/ext/13/18", .name = "ext_13_18" },
    .{ .method = "POST", .path = "/ext/13/19", .name = "ext_13_19" },
    .{ .method = "POST", .path = "/ext/13/20", .name = "ext_13_20" },
    .{ .method = "POST", .path = "/ext/13/21", .name = "ext_13_21" },
    .{ .method = "POST", .path = "/ext/13/22", .name = "ext_13_22" },
    .{ .method = "POST", .path = "/ext/13/23", .name = "ext_13_23" },
    .{ .method = "POST", .path = "/ext/13/24", .name = "ext_13_24" },
    .{ .method = "POST", .path = "/ext/13/25", .name = "ext_13_25" },
    .{ .method = "POST", .path = "/ext/13/26", .name = "ext_13_26" },
    .{ .method = "POST", .path = "/ext/13/27", .name = "ext_13_27" },
    .{ .method = "POST", .path = "/ext/13/28", .name = "ext_13_28" },
    .{ .method = "POST", .path = "/ext/13/29", .name = "ext_13_29" },
    .{ .method = "POST", .path = "/ext/13/30", .name = "ext_13_30" },
    .{ .method = "POST", .path = "/ext/13/31", .name = "ext_13_31" },
    .{ .method = "POST", .path = "/ext/13/32", .name = "ext_13_32" },
    .{ .method = "POST", .path = "/ext/13/33", .name = "ext_13_33" },
    .{ .method = "POST", .path = "/ext/13/34", .name = "ext_13_34" },
    .{ .method = "POST", .path = "/ext/13/35", .name = "ext_13_35" },
    .{ .method = "POST", .path = "/ext/13/36", .name = "ext_13_36" },
    .{ .method = "POST", .path = "/ext/13/37", .name = "ext_13_37" },
    .{ .method = "POST", .path = "/ext/13/38", .name = "ext_13_38" },
    .{ .method = "POST", .path = "/ext/13/39", .name = "ext_13_39" },
    .{ .method = "POST", .path = "/ext/13/40", .name = "ext_13_40" },
    .{ .method = "POST", .path = "/ext/13/41", .name = "ext_13_41" },
    .{ .method = "POST", .path = "/ext/13/42", .name = "ext_13_42" },
    .{ .method = "POST", .path = "/ext/13/43", .name = "ext_13_43" },
    .{ .method = "POST", .path = "/ext/13/44", .name = "ext_13_44" },
    .{ .method = "POST", .path = "/ext/13/45", .name = "ext_13_45" },
    .{ .method = "POST", .path = "/ext/13/46", .name = "ext_13_46" },
    .{ .method = "POST", .path = "/ext/13/47", .name = "ext_13_47" },
    .{ .method = "POST", .path = "/ext/13/48", .name = "ext_13_48" },
    .{ .method = "POST", .path = "/ext/13/49", .name = "ext_13_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_13_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_0() []const u8 { return "application/json"; }

pub fn handle_ext_13_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_1() []const u8 { return "application/json"; }

pub fn handle_ext_13_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_2() []const u8 { return "application/json"; }

pub fn handle_ext_13_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_3() []const u8 { return "application/json"; }

pub fn handle_ext_13_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_4() []const u8 { return "application/json"; }

pub fn handle_ext_13_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_5() []const u8 { return "application/json"; }

pub fn handle_ext_13_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_6() []const u8 { return "application/json"; }

pub fn handle_ext_13_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_7() []const u8 { return "application/json"; }

pub fn handle_ext_13_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_8() []const u8 { return "application/json"; }

pub fn handle_ext_13_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_9() []const u8 { return "application/json"; }

pub fn handle_ext_13_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_10() []const u8 { return "application/json"; }

pub fn handle_ext_13_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_11() []const u8 { return "application/json"; }

pub fn handle_ext_13_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_12() []const u8 { return "application/json"; }

pub fn handle_ext_13_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_13() []const u8 { return "application/json"; }

pub fn handle_ext_13_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_14() []const u8 { return "application/json"; }

pub fn handle_ext_13_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_15() []const u8 { return "application/json"; }

pub fn handle_ext_13_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_16() []const u8 { return "application/json"; }

pub fn handle_ext_13_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_17() []const u8 { return "application/json"; }

pub fn handle_ext_13_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_18() []const u8 { return "application/json"; }

pub fn handle_ext_13_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_19() []const u8 { return "application/json"; }

pub fn handle_ext_13_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_20() []const u8 { return "application/json"; }

pub fn handle_ext_13_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_21() []const u8 { return "application/json"; }

pub fn handle_ext_13_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_22() []const u8 { return "application/json"; }

pub fn handle_ext_13_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_23() []const u8 { return "application/json"; }

pub fn handle_ext_13_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_24() []const u8 { return "application/json"; }

pub fn handle_ext_13_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_25() []const u8 { return "application/json"; }

pub fn handle_ext_13_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_26() []const u8 { return "application/json"; }

pub fn handle_ext_13_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_27() []const u8 { return "application/json"; }

pub fn handle_ext_13_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_28() []const u8 { return "application/json"; }

pub fn handle_ext_13_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_29() []const u8 { return "application/json"; }

pub fn handle_ext_13_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_30() []const u8 { return "application/json"; }

pub fn handle_ext_13_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_31() []const u8 { return "application/json"; }

pub fn handle_ext_13_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_32() []const u8 { return "application/json"; }

pub fn handle_ext_13_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_33() []const u8 { return "application/json"; }

pub fn handle_ext_13_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_34() []const u8 { return "application/json"; }

pub fn handle_ext_13_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_35() []const u8 { return "application/json"; }

pub fn handle_ext_13_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_36() []const u8 { return "application/json"; }

pub fn handle_ext_13_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_37() []const u8 { return "application/json"; }

pub fn handle_ext_13_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_38() []const u8 { return "application/json"; }

pub fn handle_ext_13_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_39() []const u8 { return "application/json"; }

pub fn handle_ext_13_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_40() []const u8 { return "application/json"; }

pub fn handle_ext_13_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_41() []const u8 { return "application/json"; }

pub fn handle_ext_13_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_42() []const u8 { return "application/json"; }

pub fn handle_ext_13_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_43() []const u8 { return "application/json"; }

pub fn handle_ext_13_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_44() []const u8 { return "application/json"; }

pub fn handle_ext_13_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_45() []const u8 { return "application/json"; }

pub fn handle_ext_13_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_46() []const u8 { return "application/json"; }

pub fn handle_ext_13_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_47() []const u8 { return "application/json"; }

pub fn handle_ext_13_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_48() []const u8 { return "application/json"; }

pub fn handle_ext_13_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_13_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_13_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_13_49() []const u8 { return "application/json"; }

test "server routes shard 13" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/13/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_13_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

