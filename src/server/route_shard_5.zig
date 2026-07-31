//! Generated HTTP/RPC route surface shard 5.
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
    .{ .method = "POST", .path = "/ext/5/0", .name = "ext_5_0" },
    .{ .method = "POST", .path = "/ext/5/1", .name = "ext_5_1" },
    .{ .method = "POST", .path = "/ext/5/2", .name = "ext_5_2" },
    .{ .method = "POST", .path = "/ext/5/3", .name = "ext_5_3" },
    .{ .method = "POST", .path = "/ext/5/4", .name = "ext_5_4" },
    .{ .method = "POST", .path = "/ext/5/5", .name = "ext_5_5" },
    .{ .method = "POST", .path = "/ext/5/6", .name = "ext_5_6" },
    .{ .method = "POST", .path = "/ext/5/7", .name = "ext_5_7" },
    .{ .method = "POST", .path = "/ext/5/8", .name = "ext_5_8" },
    .{ .method = "POST", .path = "/ext/5/9", .name = "ext_5_9" },
    .{ .method = "POST", .path = "/ext/5/10", .name = "ext_5_10" },
    .{ .method = "POST", .path = "/ext/5/11", .name = "ext_5_11" },
    .{ .method = "POST", .path = "/ext/5/12", .name = "ext_5_12" },
    .{ .method = "POST", .path = "/ext/5/13", .name = "ext_5_13" },
    .{ .method = "POST", .path = "/ext/5/14", .name = "ext_5_14" },
    .{ .method = "POST", .path = "/ext/5/15", .name = "ext_5_15" },
    .{ .method = "POST", .path = "/ext/5/16", .name = "ext_5_16" },
    .{ .method = "POST", .path = "/ext/5/17", .name = "ext_5_17" },
    .{ .method = "POST", .path = "/ext/5/18", .name = "ext_5_18" },
    .{ .method = "POST", .path = "/ext/5/19", .name = "ext_5_19" },
    .{ .method = "POST", .path = "/ext/5/20", .name = "ext_5_20" },
    .{ .method = "POST", .path = "/ext/5/21", .name = "ext_5_21" },
    .{ .method = "POST", .path = "/ext/5/22", .name = "ext_5_22" },
    .{ .method = "POST", .path = "/ext/5/23", .name = "ext_5_23" },
    .{ .method = "POST", .path = "/ext/5/24", .name = "ext_5_24" },
    .{ .method = "POST", .path = "/ext/5/25", .name = "ext_5_25" },
    .{ .method = "POST", .path = "/ext/5/26", .name = "ext_5_26" },
    .{ .method = "POST", .path = "/ext/5/27", .name = "ext_5_27" },
    .{ .method = "POST", .path = "/ext/5/28", .name = "ext_5_28" },
    .{ .method = "POST", .path = "/ext/5/29", .name = "ext_5_29" },
    .{ .method = "POST", .path = "/ext/5/30", .name = "ext_5_30" },
    .{ .method = "POST", .path = "/ext/5/31", .name = "ext_5_31" },
    .{ .method = "POST", .path = "/ext/5/32", .name = "ext_5_32" },
    .{ .method = "POST", .path = "/ext/5/33", .name = "ext_5_33" },
    .{ .method = "POST", .path = "/ext/5/34", .name = "ext_5_34" },
    .{ .method = "POST", .path = "/ext/5/35", .name = "ext_5_35" },
    .{ .method = "POST", .path = "/ext/5/36", .name = "ext_5_36" },
    .{ .method = "POST", .path = "/ext/5/37", .name = "ext_5_37" },
    .{ .method = "POST", .path = "/ext/5/38", .name = "ext_5_38" },
    .{ .method = "POST", .path = "/ext/5/39", .name = "ext_5_39" },
    .{ .method = "POST", .path = "/ext/5/40", .name = "ext_5_40" },
    .{ .method = "POST", .path = "/ext/5/41", .name = "ext_5_41" },
    .{ .method = "POST", .path = "/ext/5/42", .name = "ext_5_42" },
    .{ .method = "POST", .path = "/ext/5/43", .name = "ext_5_43" },
    .{ .method = "POST", .path = "/ext/5/44", .name = "ext_5_44" },
    .{ .method = "POST", .path = "/ext/5/45", .name = "ext_5_45" },
    .{ .method = "POST", .path = "/ext/5/46", .name = "ext_5_46" },
    .{ .method = "POST", .path = "/ext/5/47", .name = "ext_5_47" },
    .{ .method = "POST", .path = "/ext/5/48", .name = "ext_5_48" },
    .{ .method = "POST", .path = "/ext/5/49", .name = "ext_5_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_5_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_0() []const u8 { return "application/json"; }

pub fn handle_ext_5_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_1() []const u8 { return "application/json"; }

pub fn handle_ext_5_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_2() []const u8 { return "application/json"; }

pub fn handle_ext_5_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_3() []const u8 { return "application/json"; }

pub fn handle_ext_5_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_4() []const u8 { return "application/json"; }

pub fn handle_ext_5_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_5() []const u8 { return "application/json"; }

pub fn handle_ext_5_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_6() []const u8 { return "application/json"; }

pub fn handle_ext_5_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_7() []const u8 { return "application/json"; }

pub fn handle_ext_5_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_8() []const u8 { return "application/json"; }

pub fn handle_ext_5_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_9() []const u8 { return "application/json"; }

pub fn handle_ext_5_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_10() []const u8 { return "application/json"; }

pub fn handle_ext_5_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_11() []const u8 { return "application/json"; }

pub fn handle_ext_5_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_12() []const u8 { return "application/json"; }

pub fn handle_ext_5_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_13() []const u8 { return "application/json"; }

pub fn handle_ext_5_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_14() []const u8 { return "application/json"; }

pub fn handle_ext_5_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_15() []const u8 { return "application/json"; }

pub fn handle_ext_5_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_16() []const u8 { return "application/json"; }

pub fn handle_ext_5_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_17() []const u8 { return "application/json"; }

pub fn handle_ext_5_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_18() []const u8 { return "application/json"; }

pub fn handle_ext_5_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_19() []const u8 { return "application/json"; }

pub fn handle_ext_5_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_20() []const u8 { return "application/json"; }

pub fn handle_ext_5_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_21() []const u8 { return "application/json"; }

pub fn handle_ext_5_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_22() []const u8 { return "application/json"; }

pub fn handle_ext_5_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_23() []const u8 { return "application/json"; }

pub fn handle_ext_5_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_24() []const u8 { return "application/json"; }

pub fn handle_ext_5_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_25() []const u8 { return "application/json"; }

pub fn handle_ext_5_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_26() []const u8 { return "application/json"; }

pub fn handle_ext_5_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_27() []const u8 { return "application/json"; }

pub fn handle_ext_5_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_28() []const u8 { return "application/json"; }

pub fn handle_ext_5_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_29() []const u8 { return "application/json"; }

pub fn handle_ext_5_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_30() []const u8 { return "application/json"; }

pub fn handle_ext_5_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_31() []const u8 { return "application/json"; }

pub fn handle_ext_5_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_32() []const u8 { return "application/json"; }

pub fn handle_ext_5_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_33() []const u8 { return "application/json"; }

pub fn handle_ext_5_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_34() []const u8 { return "application/json"; }

pub fn handle_ext_5_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_35() []const u8 { return "application/json"; }

pub fn handle_ext_5_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_36() []const u8 { return "application/json"; }

pub fn handle_ext_5_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_37() []const u8 { return "application/json"; }

pub fn handle_ext_5_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_38() []const u8 { return "application/json"; }

pub fn handle_ext_5_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_39() []const u8 { return "application/json"; }

pub fn handle_ext_5_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_40() []const u8 { return "application/json"; }

pub fn handle_ext_5_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_41() []const u8 { return "application/json"; }

pub fn handle_ext_5_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_42() []const u8 { return "application/json"; }

pub fn handle_ext_5_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_43() []const u8 { return "application/json"; }

pub fn handle_ext_5_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_44() []const u8 { return "application/json"; }

pub fn handle_ext_5_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_45() []const u8 { return "application/json"; }

pub fn handle_ext_5_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_46() []const u8 { return "application/json"; }

pub fn handle_ext_5_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_47() []const u8 { return "application/json"; }

pub fn handle_ext_5_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_48() []const u8 { return "application/json"; }

pub fn handle_ext_5_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_5_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_5_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_5_49() []const u8 { return "application/json"; }

test "server routes shard 5" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/5/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_5_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

