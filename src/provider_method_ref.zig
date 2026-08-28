const std = @import("std");

/// JSON field emitted by the V8 extension manifest codec for callable provider members.
pub const callback_id_field = "__pi_callback_id";
pub const callback_kind_field = "__pi_callback_kind";
pub const callback_path_field = "__pi_callback_path";
pub const callback_generation_field = "__pi_callback_generation";
pub const provider_method_kind = "provider_method";

pub const ProviderMethodRef = struct {
    callback_id: []const u8,
    path: []const u8,
    generation: u64,

    pub fn fromJson(value: std.json.Value) !ProviderMethodRef {
        const object = switch (value) {
            .object => |object| object,
            else => return error.InvalidProviderMethodRef,
        };
        const id_value = object.get(callback_id_field) orelse return error.InvalidProviderMethodRef;
        const kind_value = object.get(callback_kind_field) orelse return error.InvalidProviderMethodRef;
        const path_value = object.get(callback_path_field) orelse return error.InvalidProviderMethodRef;
        const generation_value = object.get(callback_generation_field) orelse return error.InvalidProviderMethodRef;
        const callback_id = switch (id_value) {
            .string => |string| string,
            else => return error.InvalidProviderMethodRef,
        };
        const kind = switch (kind_value) {
            .string => |string| string,
            else => return error.InvalidProviderMethodRef,
        };
        if (!std.mem.eql(u8, kind, provider_method_kind)) return error.InvalidProviderMethodRef;
        const path = switch (path_value) {
            .string => |string| string,
            else => return error.InvalidProviderMethodRef,
        };
        const generation: u64 = switch (generation_value) {
            .integer => |integer| if (integer > 0) @intCast(integer) else return error.InvalidProviderMethodRef,
            else => return error.InvalidProviderMethodRef,
        };
        if (callback_id.len == 0 or path.len == 0) return error.InvalidProviderMethodRef;
        return .{ .callback_id = callback_id, .path = path, .generation = generation };
    }
};

pub fn isProviderMethodRef(value: std.json.Value) bool {
    _ = ProviderMethodRef.fromJson(value) catch return false;
    return true;
}

test "provider method callback descriptor round-trips through JSON" {
    const source =
        \\{"__pi_callback_id":"provider:demo:oauth.refreshToken:4","__pi_callback_kind":"provider_method","__pi_callback_path":"oauth.refreshToken","__pi_callback_generation":7}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, source, .{});
    defer parsed.deinit();
    const ref = try ProviderMethodRef.fromJson(parsed.value);
    try std.testing.expectEqualStrings("provider:demo:oauth.refreshToken:4", ref.callback_id);
    try std.testing.expectEqualStrings("oauth.refreshToken", ref.path);
    try std.testing.expectEqual(@as(u64, 7), ref.generation);
    try std.testing.expect(isProviderMethodRef(parsed.value));
}

test "ordinary provider data is not mistaken for a callable descriptor" {
    const source =
        \\{"baseUrl":"https://example.invalid","api":"openai-completions"}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, source, .{});
    defer parsed.deinit();
    try std.testing.expect(!isProviderMethodRef(parsed.value));
    try std.testing.expectError(error.InvalidProviderMethodRef, ProviderMethodRef.fromJson(parsed.value));
}
