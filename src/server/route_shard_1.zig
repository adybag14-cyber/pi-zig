//! Generated HTTP/RPC route surface shard 1.
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
    .{ .method = "POST", .path = "/ext/1/0", .name = "ext_1_0" },
    .{ .method = "POST", .path = "/ext/1/1", .name = "ext_1_1" },
    .{ .method = "POST", .path = "/ext/1/2", .name = "ext_1_2" },
    .{ .method = "POST", .path = "/ext/1/3", .name = "ext_1_3" },
    .{ .method = "POST", .path = "/ext/1/4", .name = "ext_1_4" },
    .{ .method = "POST", .path = "/ext/1/5", .name = "ext_1_5" },
    .{ .method = "POST", .path = "/ext/1/6", .name = "ext_1_6" },
    .{ .method = "POST", .path = "/ext/1/7", .name = "ext_1_7" },
    .{ .method = "POST", .path = "/ext/1/8", .name = "ext_1_8" },
    .{ .method = "POST", .path = "/ext/1/9", .name = "ext_1_9" },
    .{ .method = "POST", .path = "/ext/1/10", .name = "ext_1_10" },
    .{ .method = "POST", .path = "/ext/1/11", .name = "ext_1_11" },
    .{ .method = "POST", .path = "/ext/1/12", .name = "ext_1_12" },
    .{ .method = "POST", .path = "/ext/1/13", .name = "ext_1_13" },
    .{ .method = "POST", .path = "/ext/1/14", .name = "ext_1_14" },
    .{ .method = "POST", .path = "/ext/1/15", .name = "ext_1_15" },
    .{ .method = "POST", .path = "/ext/1/16", .name = "ext_1_16" },
    .{ .method = "POST", .path = "/ext/1/17", .name = "ext_1_17" },
    .{ .method = "POST", .path = "/ext/1/18", .name = "ext_1_18" },
    .{ .method = "POST", .path = "/ext/1/19", .name = "ext_1_19" },
    .{ .method = "POST", .path = "/ext/1/20", .name = "ext_1_20" },
    .{ .method = "POST", .path = "/ext/1/21", .name = "ext_1_21" },
    .{ .method = "POST", .path = "/ext/1/22", .name = "ext_1_22" },
    .{ .method = "POST", .path = "/ext/1/23", .name = "ext_1_23" },
    .{ .method = "POST", .path = "/ext/1/24", .name = "ext_1_24" },
    .{ .method = "POST", .path = "/ext/1/25", .name = "ext_1_25" },
    .{ .method = "POST", .path = "/ext/1/26", .name = "ext_1_26" },
    .{ .method = "POST", .path = "/ext/1/27", .name = "ext_1_27" },
    .{ .method = "POST", .path = "/ext/1/28", .name = "ext_1_28" },
    .{ .method = "POST", .path = "/ext/1/29", .name = "ext_1_29" },
    .{ .method = "POST", .path = "/ext/1/30", .name = "ext_1_30" },
    .{ .method = "POST", .path = "/ext/1/31", .name = "ext_1_31" },
    .{ .method = "POST", .path = "/ext/1/32", .name = "ext_1_32" },
    .{ .method = "POST", .path = "/ext/1/33", .name = "ext_1_33" },
    .{ .method = "POST", .path = "/ext/1/34", .name = "ext_1_34" },
    .{ .method = "POST", .path = "/ext/1/35", .name = "ext_1_35" },
    .{ .method = "POST", .path = "/ext/1/36", .name = "ext_1_36" },
    .{ .method = "POST", .path = "/ext/1/37", .name = "ext_1_37" },
    .{ .method = "POST", .path = "/ext/1/38", .name = "ext_1_38" },
    .{ .method = "POST", .path = "/ext/1/39", .name = "ext_1_39" },
    .{ .method = "POST", .path = "/ext/1/40", .name = "ext_1_40" },
    .{ .method = "POST", .path = "/ext/1/41", .name = "ext_1_41" },
    .{ .method = "POST", .path = "/ext/1/42", .name = "ext_1_42" },
    .{ .method = "POST", .path = "/ext/1/43", .name = "ext_1_43" },
    .{ .method = "POST", .path = "/ext/1/44", .name = "ext_1_44" },
    .{ .method = "POST", .path = "/ext/1/45", .name = "ext_1_45" },
    .{ .method = "POST", .path = "/ext/1/46", .name = "ext_1_46" },
    .{ .method = "POST", .path = "/ext/1/47", .name = "ext_1_47" },
    .{ .method = "POST", .path = "/ext/1/48", .name = "ext_1_48" },
    .{ .method = "POST", .path = "/ext/1/49", .name = "ext_1_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_1_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_0() []const u8 { return "application/json"; }

pub fn handle_ext_1_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_1() []const u8 { return "application/json"; }

pub fn handle_ext_1_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_2() []const u8 { return "application/json"; }

pub fn handle_ext_1_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_3() []const u8 { return "application/json"; }

pub fn handle_ext_1_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_4() []const u8 { return "application/json"; }

pub fn handle_ext_1_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_5() []const u8 { return "application/json"; }

pub fn handle_ext_1_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_6() []const u8 { return "application/json"; }

pub fn handle_ext_1_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_7() []const u8 { return "application/json"; }

pub fn handle_ext_1_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_8() []const u8 { return "application/json"; }

pub fn handle_ext_1_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_9() []const u8 { return "application/json"; }

pub fn handle_ext_1_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_10() []const u8 { return "application/json"; }

pub fn handle_ext_1_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_11() []const u8 { return "application/json"; }

pub fn handle_ext_1_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_12() []const u8 { return "application/json"; }

pub fn handle_ext_1_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_13() []const u8 { return "application/json"; }

pub fn handle_ext_1_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_14() []const u8 { return "application/json"; }

pub fn handle_ext_1_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_15() []const u8 { return "application/json"; }

pub fn handle_ext_1_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_16() []const u8 { return "application/json"; }

pub fn handle_ext_1_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_17() []const u8 { return "application/json"; }

pub fn handle_ext_1_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_18() []const u8 { return "application/json"; }

pub fn handle_ext_1_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_19() []const u8 { return "application/json"; }

pub fn handle_ext_1_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_20() []const u8 { return "application/json"; }

pub fn handle_ext_1_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_21() []const u8 { return "application/json"; }

pub fn handle_ext_1_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_22() []const u8 { return "application/json"; }

pub fn handle_ext_1_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_23() []const u8 { return "application/json"; }

pub fn handle_ext_1_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_24() []const u8 { return "application/json"; }

pub fn handle_ext_1_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_25() []const u8 { return "application/json"; }

pub fn handle_ext_1_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_26() []const u8 { return "application/json"; }

pub fn handle_ext_1_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_27() []const u8 { return "application/json"; }

pub fn handle_ext_1_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_28() []const u8 { return "application/json"; }

pub fn handle_ext_1_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_29() []const u8 { return "application/json"; }

pub fn handle_ext_1_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_30() []const u8 { return "application/json"; }

pub fn handle_ext_1_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_31() []const u8 { return "application/json"; }

pub fn handle_ext_1_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_32() []const u8 { return "application/json"; }

pub fn handle_ext_1_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_33() []const u8 { return "application/json"; }

pub fn handle_ext_1_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_34() []const u8 { return "application/json"; }

pub fn handle_ext_1_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_35() []const u8 { return "application/json"; }

pub fn handle_ext_1_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_36() []const u8 { return "application/json"; }

pub fn handle_ext_1_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_37() []const u8 { return "application/json"; }

pub fn handle_ext_1_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_38() []const u8 { return "application/json"; }

pub fn handle_ext_1_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_39() []const u8 { return "application/json"; }

pub fn handle_ext_1_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_40() []const u8 { return "application/json"; }

pub fn handle_ext_1_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_41() []const u8 { return "application/json"; }

pub fn handle_ext_1_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_42() []const u8 { return "application/json"; }

pub fn handle_ext_1_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_43() []const u8 { return "application/json"; }

pub fn handle_ext_1_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_44() []const u8 { return "application/json"; }

pub fn handle_ext_1_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_45() []const u8 { return "application/json"; }

pub fn handle_ext_1_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_46() []const u8 { return "application/json"; }

pub fn handle_ext_1_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_47() []const u8 { return "application/json"; }

pub fn handle_ext_1_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_48() []const u8 { return "application/json"; }

pub fn handle_ext_1_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_1_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_1_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_1_49() []const u8 { return "application/json"; }

test "server routes shard 1" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/1/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_1_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

