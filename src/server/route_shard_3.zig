//! Generated HTTP/RPC route surface shard 3.
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
    .{ .method = "POST", .path = "/ext/3/0", .name = "ext_3_0" },
    .{ .method = "POST", .path = "/ext/3/1", .name = "ext_3_1" },
    .{ .method = "POST", .path = "/ext/3/2", .name = "ext_3_2" },
    .{ .method = "POST", .path = "/ext/3/3", .name = "ext_3_3" },
    .{ .method = "POST", .path = "/ext/3/4", .name = "ext_3_4" },
    .{ .method = "POST", .path = "/ext/3/5", .name = "ext_3_5" },
    .{ .method = "POST", .path = "/ext/3/6", .name = "ext_3_6" },
    .{ .method = "POST", .path = "/ext/3/7", .name = "ext_3_7" },
    .{ .method = "POST", .path = "/ext/3/8", .name = "ext_3_8" },
    .{ .method = "POST", .path = "/ext/3/9", .name = "ext_3_9" },
    .{ .method = "POST", .path = "/ext/3/10", .name = "ext_3_10" },
    .{ .method = "POST", .path = "/ext/3/11", .name = "ext_3_11" },
    .{ .method = "POST", .path = "/ext/3/12", .name = "ext_3_12" },
    .{ .method = "POST", .path = "/ext/3/13", .name = "ext_3_13" },
    .{ .method = "POST", .path = "/ext/3/14", .name = "ext_3_14" },
    .{ .method = "POST", .path = "/ext/3/15", .name = "ext_3_15" },
    .{ .method = "POST", .path = "/ext/3/16", .name = "ext_3_16" },
    .{ .method = "POST", .path = "/ext/3/17", .name = "ext_3_17" },
    .{ .method = "POST", .path = "/ext/3/18", .name = "ext_3_18" },
    .{ .method = "POST", .path = "/ext/3/19", .name = "ext_3_19" },
    .{ .method = "POST", .path = "/ext/3/20", .name = "ext_3_20" },
    .{ .method = "POST", .path = "/ext/3/21", .name = "ext_3_21" },
    .{ .method = "POST", .path = "/ext/3/22", .name = "ext_3_22" },
    .{ .method = "POST", .path = "/ext/3/23", .name = "ext_3_23" },
    .{ .method = "POST", .path = "/ext/3/24", .name = "ext_3_24" },
    .{ .method = "POST", .path = "/ext/3/25", .name = "ext_3_25" },
    .{ .method = "POST", .path = "/ext/3/26", .name = "ext_3_26" },
    .{ .method = "POST", .path = "/ext/3/27", .name = "ext_3_27" },
    .{ .method = "POST", .path = "/ext/3/28", .name = "ext_3_28" },
    .{ .method = "POST", .path = "/ext/3/29", .name = "ext_3_29" },
    .{ .method = "POST", .path = "/ext/3/30", .name = "ext_3_30" },
    .{ .method = "POST", .path = "/ext/3/31", .name = "ext_3_31" },
    .{ .method = "POST", .path = "/ext/3/32", .name = "ext_3_32" },
    .{ .method = "POST", .path = "/ext/3/33", .name = "ext_3_33" },
    .{ .method = "POST", .path = "/ext/3/34", .name = "ext_3_34" },
    .{ .method = "POST", .path = "/ext/3/35", .name = "ext_3_35" },
    .{ .method = "POST", .path = "/ext/3/36", .name = "ext_3_36" },
    .{ .method = "POST", .path = "/ext/3/37", .name = "ext_3_37" },
    .{ .method = "POST", .path = "/ext/3/38", .name = "ext_3_38" },
    .{ .method = "POST", .path = "/ext/3/39", .name = "ext_3_39" },
    .{ .method = "POST", .path = "/ext/3/40", .name = "ext_3_40" },
    .{ .method = "POST", .path = "/ext/3/41", .name = "ext_3_41" },
    .{ .method = "POST", .path = "/ext/3/42", .name = "ext_3_42" },
    .{ .method = "POST", .path = "/ext/3/43", .name = "ext_3_43" },
    .{ .method = "POST", .path = "/ext/3/44", .name = "ext_3_44" },
    .{ .method = "POST", .path = "/ext/3/45", .name = "ext_3_45" },
    .{ .method = "POST", .path = "/ext/3/46", .name = "ext_3_46" },
    .{ .method = "POST", .path = "/ext/3/47", .name = "ext_3_47" },
    .{ .method = "POST", .path = "/ext/3/48", .name = "ext_3_48" },
    .{ .method = "POST", .path = "/ext/3/49", .name = "ext_3_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_3_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_0() []const u8 { return "application/json"; }

pub fn handle_ext_3_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_1() []const u8 { return "application/json"; }

pub fn handle_ext_3_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_2() []const u8 { return "application/json"; }

pub fn handle_ext_3_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_3() []const u8 { return "application/json"; }

pub fn handle_ext_3_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_4() []const u8 { return "application/json"; }

pub fn handle_ext_3_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_5() []const u8 { return "application/json"; }

pub fn handle_ext_3_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_6() []const u8 { return "application/json"; }

pub fn handle_ext_3_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_7() []const u8 { return "application/json"; }

pub fn handle_ext_3_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_8() []const u8 { return "application/json"; }

pub fn handle_ext_3_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_9() []const u8 { return "application/json"; }

pub fn handle_ext_3_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_10() []const u8 { return "application/json"; }

pub fn handle_ext_3_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_11() []const u8 { return "application/json"; }

pub fn handle_ext_3_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_12() []const u8 { return "application/json"; }

pub fn handle_ext_3_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_13() []const u8 { return "application/json"; }

pub fn handle_ext_3_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_14() []const u8 { return "application/json"; }

pub fn handle_ext_3_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_15() []const u8 { return "application/json"; }

pub fn handle_ext_3_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_16() []const u8 { return "application/json"; }

pub fn handle_ext_3_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_17() []const u8 { return "application/json"; }

pub fn handle_ext_3_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_18() []const u8 { return "application/json"; }

pub fn handle_ext_3_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_19() []const u8 { return "application/json"; }

pub fn handle_ext_3_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_20() []const u8 { return "application/json"; }

pub fn handle_ext_3_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_21() []const u8 { return "application/json"; }

pub fn handle_ext_3_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_22() []const u8 { return "application/json"; }

pub fn handle_ext_3_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_23() []const u8 { return "application/json"; }

pub fn handle_ext_3_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_24() []const u8 { return "application/json"; }

pub fn handle_ext_3_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_25() []const u8 { return "application/json"; }

pub fn handle_ext_3_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_26() []const u8 { return "application/json"; }

pub fn handle_ext_3_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_27() []const u8 { return "application/json"; }

pub fn handle_ext_3_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_28() []const u8 { return "application/json"; }

pub fn handle_ext_3_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_29() []const u8 { return "application/json"; }

pub fn handle_ext_3_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_30() []const u8 { return "application/json"; }

pub fn handle_ext_3_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_31() []const u8 { return "application/json"; }

pub fn handle_ext_3_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_32() []const u8 { return "application/json"; }

pub fn handle_ext_3_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_33() []const u8 { return "application/json"; }

pub fn handle_ext_3_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_34() []const u8 { return "application/json"; }

pub fn handle_ext_3_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_35() []const u8 { return "application/json"; }

pub fn handle_ext_3_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_36() []const u8 { return "application/json"; }

pub fn handle_ext_3_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_37() []const u8 { return "application/json"; }

pub fn handle_ext_3_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_38() []const u8 { return "application/json"; }

pub fn handle_ext_3_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_39() []const u8 { return "application/json"; }

pub fn handle_ext_3_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_40() []const u8 { return "application/json"; }

pub fn handle_ext_3_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_41() []const u8 { return "application/json"; }

pub fn handle_ext_3_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_42() []const u8 { return "application/json"; }

pub fn handle_ext_3_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_43() []const u8 { return "application/json"; }

pub fn handle_ext_3_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_44() []const u8 { return "application/json"; }

pub fn handle_ext_3_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_45() []const u8 { return "application/json"; }

pub fn handle_ext_3_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_46() []const u8 { return "application/json"; }

pub fn handle_ext_3_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_47() []const u8 { return "application/json"; }

pub fn handle_ext_3_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_48() []const u8 { return "application/json"; }

pub fn handle_ext_3_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_3_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_3_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_3_49() []const u8 { return "application/json"; }

test "server routes shard 3" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/3/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_3_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

