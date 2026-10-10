//! Private native Main UI service identities. Public context JSON is not admission.
const std = @import("std");
const identifiers = @import("component_protocol.zig");
pub const version: u32 = 1;
pub const maximum_pending: usize = 64;
pub const maximum_request_bytes: usize = 1024 * 1024;
pub const Lease = struct {
    owner_generation: u64,
    service_id: u64,
    service_generation: u64,
    extension_id: u64,
    pub fn eql(a: Lease, b: Lease) bool {
        return a.owner_generation == b.owner_generation and a.service_id == b.service_id and a.service_generation == b.service_generation and a.extension_id == b.extension_id;
    }
    pub fn read(object: std.json.ObjectMap) !Lease {
        const v = object.get("version") orelse return error.InvalidNativeUiServiceVersion;
        if (v != .integer or v.integer != version) return error.InvalidNativeUiServiceVersion;
        return .{ .owner_generation = try positive(object, "ownerGeneration"), .service_id = try positive(object, "serviceId"), .service_generation = try positive(object, "serviceGeneration"), .extension_id = try positive(object, "extensionId") };
    }
    pub fn writeFields(self: Lease, writer: *std.Io.Writer) !void {
        try writer.print("\"version\":1,\"ownerGeneration\":\"{d}\",\"serviceId\":\"{d}\",\"serviceGeneration\":\"{d}\",\"extensionId\":\"{d}\"", .{ self.owner_generation, self.service_id, self.service_generation, self.extension_id });
    }
};
pub const Header = struct {
    lease: Lease,
    request_id: u64,
    pub fn read(object: std.json.ObjectMap) !Header {
        return .{ .lease = try Lease.read(object), .request_id = try positive(object, "requestId") };
    }
    pub fn matches(a: Header, b: Header) bool {
        return a.lease.eql(b.lease) and a.request_id == b.request_id;
    }
    pub fn writeFields(self: Header, writer: *std.Io.Writer) !void {
        try writer.print("\"version\":1,\"ownerGeneration\":\"{d}\",\"serviceId\":\"{d}\",\"serviceGeneration\":\"{d}\",\"extensionId\":\"{d}\",\"requestId\":\"{d}\"", .{ self.lease.owner_generation, self.lease.service_id, self.lease.service_generation, self.lease.extension_id, self.request_id });
    }
};
fn positive(object: std.json.ObjectMap, key: []const u8) !u64 {
    const value = try identifiers.identifier(object.get(key) orelse return error.InvalidNativeUiServiceIdentity);
    if (value == 0) return error.InvalidNativeUiServiceIdentity;
    return value;
}
pub fn readRequest(object: std.json.ObjectMap) !struct { header: Header, method: []const u8, args: std.json.ObjectMap } {
    const header = try Header.read(object);
    const method = object.get("method") orelse return error.InvalidNativeUiServiceRequest;
    const args = object.get("args") orelse return error.InvalidNativeUiServiceRequest;
    if (method != .string or args != .object) return error.InvalidNativeUiServiceRequest;
    const allowed = std.mem.eql(u8, method.string, "select") or std.mem.eql(u8, method.string, "confirm") or std.mem.eql(u8, method.string, "input") or std.mem.eql(u8, method.string, "editor") or std.mem.eql(u8, method.string, "custom_native");
    if (!allowed) return error.InvalidNativeUiServiceMethod;
    return .{ .header = header, .method = method.string, .args = args.object };
}
test "native UI service identities reject foreign owners generations request ids and public shapes" {
    const raw = "{\"version\":1,\"ownerGeneration\":\"9\",\"serviceId\":\"11\",\"serviceGeneration\":\"2\",\"extensionId\":\"3\",\"requestId\":\"17\",\"method\":\"input\",\"args\":{\"title\":\"retained\"}}";
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
    defer parsed.deinit();
    const request = try readRequest(parsed.value.object);
    try std.testing.expectEqual(@as(u64, 17), request.header.request_id);
    var foreign = request.header;
    foreign.lease.owner_generation += 1;
    try std.testing.expect(!request.header.matches(foreign));
    foreign = request.header;
    foreign.lease.service_id += 1;
    try std.testing.expect(!request.header.matches(foreign));
    foreign = request.header;
    foreign.lease.service_generation += 1;
    try std.testing.expect(!request.header.matches(foreign));
    foreign = request.header;
    foreign.lease.extension_id += 1;
    try std.testing.expect(!request.header.matches(foreign));
    foreign = request.header;
    foreign.request_id += 1;
    try std.testing.expect(!request.header.matches(foreign));
    _ = parsed.value.object.swapRemove("serviceGeneration");
    try std.testing.expectError(error.InvalidNativeUiServiceIdentity, Header.read(parsed.value.object));
}
