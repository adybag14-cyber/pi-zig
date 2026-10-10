//! Owned native JSON-RPC messages and envelopes. Arbitrary extension values stay JSON data.
const std = @import("std");
pub const json = @import("../durable/backend/json.zig");
pub const Value = json.Value;
pub const max_id: u64 = 9_007_199_254_740_991;
pub const Kind = enum { request, notification, response };
pub fn field(v: Value, name: []const u8) !Value {
    return json.required(v, name);
}
pub fn text(v: Value, name: []const u8) ![]const u8 {
    return json.asString(try field(v, name));
}
pub fn validId(v: Value) bool {
    return switch (v) {
        .string, .integer => true,
        .float => |number| std.math.isFinite(number),
        else => false,
    };
}
pub fn kind(v: Value) !Kind {
    if (v != .object or !std.mem.eql(u8, try text(v, "jsonrpc"), "2.0")) return error.InvalidMcpMessage;
    const id = json.get(v, "id");
    if (json.get(v, "method")) |method| {
        if (method != .string) return error.InvalidMcpMessage;
        if (id) |value| {
            if (!validId(value)) return error.InvalidMcpMessage;
            return .request;
        }
        return .notification;
    }
    if (id == null or !validId(id.?)) return error.InvalidMcpMessage;
    const result = json.get(v, "result");
    const failure = json.get(v, "error");
    if ((result != null) == (failure != null)) return error.InvalidMcpMessage;
    if (failure) |value| {
        if (value != .object) return error.InvalidMcpMessage;
        const code = try field(value, "code");
        if (code != .integer and code != .float) return error.InvalidMcpMessage;
        _ = try text(value, "message");
    }
    return .response;
}
pub fn request(gpa: std.mem.Allocator, id: ?u64, method: []const u8, params: ?Value) !json.Owned {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "jsonrpc", .{ .string = "2.0" });
    if (id) |number| {
        if (number > max_id) return error.McpRequestIdExhausted;
        try value.object.put(a, "id", .{ .integer = @intCast(number) });
    }
    try value.object.put(a, "method", .{ .string = try a.dupe(u8, method) });
    if (params) |data| {
        if (data != .object) return error.InvalidMcpParams;
        try value.object.put(a, "params", try json.clone(a, data));
    }
    owned.value = value;
    return owned;
}
pub fn response(gpa: std.mem.Allocator, id: Value, result: Value, failure: bool) !json.Owned {
    if (!validId(id)) return error.InvalidMcpMessage;
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "jsonrpc", .{ .string = "2.0" });
    try value.object.put(a, "id", try json.clone(a, id));
    try value.object.put(a, if (failure) "error" else "result", try json.clone(a, result));
    owned.value = value;
    return owned;
}
pub fn rpcError(a: std.mem.Allocator, code: i64, message: []const u8) !Value {
    var value: Value = .{ .object = .empty };
    try value.object.put(a, "code", .{ .integer = code });
    try value.object.put(a, "message", .{ .string = try a.dupe(u8, message) });
    return value;
}
