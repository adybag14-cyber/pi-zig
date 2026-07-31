//! Generated HTTP/RPC route surface shard 12.
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
    .{ .method = "POST", .path = "/ext/12/0", .name = "ext_12_0" },
    .{ .method = "POST", .path = "/ext/12/1", .name = "ext_12_1" },
    .{ .method = "POST", .path = "/ext/12/2", .name = "ext_12_2" },
    .{ .method = "POST", .path = "/ext/12/3", .name = "ext_12_3" },
    .{ .method = "POST", .path = "/ext/12/4", .name = "ext_12_4" },
    .{ .method = "POST", .path = "/ext/12/5", .name = "ext_12_5" },
    .{ .method = "POST", .path = "/ext/12/6", .name = "ext_12_6" },
    .{ .method = "POST", .path = "/ext/12/7", .name = "ext_12_7" },
    .{ .method = "POST", .path = "/ext/12/8", .name = "ext_12_8" },
    .{ .method = "POST", .path = "/ext/12/9", .name = "ext_12_9" },
    .{ .method = "POST", .path = "/ext/12/10", .name = "ext_12_10" },
    .{ .method = "POST", .path = "/ext/12/11", .name = "ext_12_11" },
    .{ .method = "POST", .path = "/ext/12/12", .name = "ext_12_12" },
    .{ .method = "POST", .path = "/ext/12/13", .name = "ext_12_13" },
    .{ .method = "POST", .path = "/ext/12/14", .name = "ext_12_14" },
    .{ .method = "POST", .path = "/ext/12/15", .name = "ext_12_15" },
    .{ .method = "POST", .path = "/ext/12/16", .name = "ext_12_16" },
    .{ .method = "POST", .path = "/ext/12/17", .name = "ext_12_17" },
    .{ .method = "POST", .path = "/ext/12/18", .name = "ext_12_18" },
    .{ .method = "POST", .path = "/ext/12/19", .name = "ext_12_19" },
    .{ .method = "POST", .path = "/ext/12/20", .name = "ext_12_20" },
    .{ .method = "POST", .path = "/ext/12/21", .name = "ext_12_21" },
    .{ .method = "POST", .path = "/ext/12/22", .name = "ext_12_22" },
    .{ .method = "POST", .path = "/ext/12/23", .name = "ext_12_23" },
    .{ .method = "POST", .path = "/ext/12/24", .name = "ext_12_24" },
    .{ .method = "POST", .path = "/ext/12/25", .name = "ext_12_25" },
    .{ .method = "POST", .path = "/ext/12/26", .name = "ext_12_26" },
    .{ .method = "POST", .path = "/ext/12/27", .name = "ext_12_27" },
    .{ .method = "POST", .path = "/ext/12/28", .name = "ext_12_28" },
    .{ .method = "POST", .path = "/ext/12/29", .name = "ext_12_29" },
    .{ .method = "POST", .path = "/ext/12/30", .name = "ext_12_30" },
    .{ .method = "POST", .path = "/ext/12/31", .name = "ext_12_31" },
    .{ .method = "POST", .path = "/ext/12/32", .name = "ext_12_32" },
    .{ .method = "POST", .path = "/ext/12/33", .name = "ext_12_33" },
    .{ .method = "POST", .path = "/ext/12/34", .name = "ext_12_34" },
    .{ .method = "POST", .path = "/ext/12/35", .name = "ext_12_35" },
    .{ .method = "POST", .path = "/ext/12/36", .name = "ext_12_36" },
    .{ .method = "POST", .path = "/ext/12/37", .name = "ext_12_37" },
    .{ .method = "POST", .path = "/ext/12/38", .name = "ext_12_38" },
    .{ .method = "POST", .path = "/ext/12/39", .name = "ext_12_39" },
    .{ .method = "POST", .path = "/ext/12/40", .name = "ext_12_40" },
    .{ .method = "POST", .path = "/ext/12/41", .name = "ext_12_41" },
    .{ .method = "POST", .path = "/ext/12/42", .name = "ext_12_42" },
    .{ .method = "POST", .path = "/ext/12/43", .name = "ext_12_43" },
    .{ .method = "POST", .path = "/ext/12/44", .name = "ext_12_44" },
    .{ .method = "POST", .path = "/ext/12/45", .name = "ext_12_45" },
    .{ .method = "POST", .path = "/ext/12/46", .name = "ext_12_46" },
    .{ .method = "POST", .path = "/ext/12/47", .name = "ext_12_47" },
    .{ .method = "POST", .path = "/ext/12/48", .name = "ext_12_48" },
    .{ .method = "POST", .path = "/ext/12/49", .name = "ext_12_49" },
};

pub fn matchRoute(method: []const u8, path: []const u8) ?Route {
    for (routes) |r| {
        if (std.mem.eql(u8, r.method, method) and std.mem.eql(u8, r.path, path)) return r;
    }
    return null;
}

pub fn handle_ext_12_0(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_0\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_0(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_0() []const u8 { return "application/json"; }

pub fn handle_ext_12_1(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_1\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_1(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_1() []const u8 { return "application/json"; }

pub fn handle_ext_12_2(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_2\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_2(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_2() []const u8 { return "application/json"; }

pub fn handle_ext_12_3(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_3\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_3(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_3() []const u8 { return "application/json"; }

pub fn handle_ext_12_4(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_4\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_4(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_4() []const u8 { return "application/json"; }

pub fn handle_ext_12_5(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_5\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_5(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_5() []const u8 { return "application/json"; }

pub fn handle_ext_12_6(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_6\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_6(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_6() []const u8 { return "application/json"; }

pub fn handle_ext_12_7(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_7\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_7(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_7() []const u8 { return "application/json"; }

pub fn handle_ext_12_8(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_8\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_8(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_8() []const u8 { return "application/json"; }

pub fn handle_ext_12_9(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_9\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_9(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_9() []const u8 { return "application/json"; }

pub fn handle_ext_12_10(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_10\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_10(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_10() []const u8 { return "application/json"; }

pub fn handle_ext_12_11(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_11\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_11(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_11() []const u8 { return "application/json"; }

pub fn handle_ext_12_12(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_12\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_12(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_12() []const u8 { return "application/json"; }

pub fn handle_ext_12_13(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_13\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_13(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_13() []const u8 { return "application/json"; }

pub fn handle_ext_12_14(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_14\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_14(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_14() []const u8 { return "application/json"; }

pub fn handle_ext_12_15(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_15\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_15(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_15() []const u8 { return "application/json"; }

pub fn handle_ext_12_16(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_16\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_16(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_16() []const u8 { return "application/json"; }

pub fn handle_ext_12_17(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_17\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_17(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_17() []const u8 { return "application/json"; }

pub fn handle_ext_12_18(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_18\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_18(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_18() []const u8 { return "application/json"; }

pub fn handle_ext_12_19(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_19\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_19(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_19() []const u8 { return "application/json"; }

pub fn handle_ext_12_20(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_20\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_20(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_20() []const u8 { return "application/json"; }

pub fn handle_ext_12_21(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_21\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_21(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_21() []const u8 { return "application/json"; }

pub fn handle_ext_12_22(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_22\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_22(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_22() []const u8 { return "application/json"; }

pub fn handle_ext_12_23(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_23\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_23(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_23() []const u8 { return "application/json"; }

pub fn handle_ext_12_24(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_24\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_24(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_24() []const u8 { return "application/json"; }

pub fn handle_ext_12_25(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_25\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_25(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_25() []const u8 { return "application/json"; }

pub fn handle_ext_12_26(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_26\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_26(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_26() []const u8 { return "application/json"; }

pub fn handle_ext_12_27(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_27\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_27(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_27() []const u8 { return "application/json"; }

pub fn handle_ext_12_28(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_28\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_28(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_28() []const u8 { return "application/json"; }

pub fn handle_ext_12_29(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_29\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_29(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_29() []const u8 { return "application/json"; }

pub fn handle_ext_12_30(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_30\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_30(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_30() []const u8 { return "application/json"; }

pub fn handle_ext_12_31(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_31\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_31(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_31() []const u8 { return "application/json"; }

pub fn handle_ext_12_32(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_32\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_32(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_32() []const u8 { return "application/json"; }

pub fn handle_ext_12_33(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_33\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_33(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_33() []const u8 { return "application/json"; }

pub fn handle_ext_12_34(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_34\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_34(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_34() []const u8 { return "application/json"; }

pub fn handle_ext_12_35(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_35\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_35(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_35() []const u8 { return "application/json"; }

pub fn handle_ext_12_36(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_36\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_36(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_36() []const u8 { return "application/json"; }

pub fn handle_ext_12_37(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_37\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_37(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_37() []const u8 { return "application/json"; }

pub fn handle_ext_12_38(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_38\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_38(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_38() []const u8 { return "application/json"; }

pub fn handle_ext_12_39(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_39\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_39(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_39() []const u8 { return "application/json"; }

pub fn handle_ext_12_40(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_40\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_40(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_40() []const u8 { return "application/json"; }

pub fn handle_ext_12_41(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_41\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_41(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_41() []const u8 { return "application/json"; }

pub fn handle_ext_12_42(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_42\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_42(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_42() []const u8 { return "application/json"; }

pub fn handle_ext_12_43(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_43\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_43(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_43() []const u8 { return "application/json"; }

pub fn handle_ext_12_44(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_44\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_44(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_44() []const u8 { return "application/json"; }

pub fn handle_ext_12_45(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_45\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_45(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_45() []const u8 { return "application/json"; }

pub fn handle_ext_12_46(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_46\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_46(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_46() []const u8 { return "application/json"; }

pub fn handle_ext_12_47(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_47\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_47(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_47() []const u8 { return "application/json"; }

pub fn handle_ext_12_48(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_48\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_48(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_48() []const u8 { return "application/json"; }

pub fn handle_ext_12_49(gpa: std.mem.Allocator, body: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{{\"route\":\"ext_12_49\",\"bytes\":{d}}}", .{body.len});
}
pub fn status_for_ext_12_49(ok: bool) u16 { return if (ok) 200 else 400; }
pub fn content_type_ext_12_49() []const u8 { return "application/json"; }

test "server routes shard 12" {
    try std.testing.expect(matchRoute("GET", "/health") != null);
    try std.testing.expect(matchRoute("POST", "/ext/12/0") != null);
    const gpa = std.testing.allocator;
    const out = try handle_ext_12_0(gpa, "{}");
    defer gpa.free(out);
    try std.testing.expect(out.len > 0);
}

