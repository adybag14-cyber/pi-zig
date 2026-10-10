//! Private process-wide terminal records. These leases identify the worker and
//! physical frontend, independently of every extension and SDK session lease.
const std = @import("std");
pub const version = 1;
pub const maximum_chunk_bytes = 64 * 1024;
pub const maximum_encoding_bytes = 128;
pub const Output = enum { stdout, stderr };
pub const Control = union(enum) { raw_mode: bool, @"resume", pause, encoding: []const u8 };
pub const Metadata = struct {
    stdin_tty: bool,
    stdin_raw: bool,
    stdout_tty: bool,
    stderr_tty: bool,
    columns: ?u32,
    rows: ?u32,
    has_shift_helper: bool = false,
    has_vt_input_helper: bool = false,
};
pub const Lease = struct {
    owner_generation: u64,
    process_generation: u64,
    pub fn matches(self: Lease, other: Lease) bool {
        return self.owner_generation == other.owner_generation and self.process_generation == other.process_generation;
    }
};
pub const Header = struct {
    lease: Lease,
    request_id: u64,
    pub fn matches(self: Header, other: Header) bool {
        return self.lease.matches(other.lease) and self.request_id == other.request_id;
    }
};
pub const Operation = union(enum) {
    control: Control,
    write: struct { output: Output, base64: []const u8 },
    is_shift_pressed,
    enable_vt_input,
};
pub const Request = struct { header: Header, operation: Operation };
fn value(object: *const std.json.ObjectMap, name: []const u8) !std.json.Value {
    return object.get(name) orelse error.InvalidProcessStreamRecord;
}
fn boolean(object: *const std.json.ObjectMap, name: []const u8) !bool {
    const item = try value(object, name);
    return if (item == .bool) item.bool else error.InvalidProcessStreamRecord;
}
fn string(object: *const std.json.ObjectMap, name: []const u8) ![]const u8 {
    const item = try value(object, name);
    return if (item == .string) item.string else error.InvalidProcessStreamRecord;
}
fn identifier(object: *const std.json.ObjectMap, name: []const u8) !u64 {
    const raw = try string(object, name);
    if (raw.len == 0 or raw[0] == '0') return error.InvalidProcessStreamRecord;
    for (raw) |byte| if (byte < '0' or byte > '9') return error.InvalidProcessStreamRecord;
    return std.fmt.parseInt(u64, raw, 10) catch error.InvalidProcessStreamRecord;
}
fn optionalDimension(object: *const std.json.ObjectMap, name: []const u8) !?u32 {
    const item = try value(object, name);
    if (item == .null) return null;
    if (item != .integer or item.integer < 0 or item.integer > std.math.maxInt(u32)) return error.InvalidProcessStreamRecord;
    return @intCast(item.integer);
}
pub fn readMetadata(object: *const std.json.ObjectMap) !Metadata {
    return .{ .stdin_tty = try boolean(object, "stdinTTY"), .stdin_raw = try boolean(object, "stdinRaw"), .stdout_tty = try boolean(object, "stdoutTTY"), .stderr_tty = try boolean(object, "stderrTTY"), .columns = try optionalDimension(object, "columns"), .rows = try optionalDimension(object, "rows"), .has_shift_helper = if (object.contains("hasShiftHelper")) try boolean(object, "hasShiftHelper") else false, .has_vt_input_helper = if (object.contains("hasVTInputHelper")) try boolean(object, "hasVTInputHelper") else false };
}
pub fn readLease(object: *const std.json.ObjectMap) !Lease {
    const incoming = try value(object, "version");
    if (incoming != .integer or incoming.integer != version) return error.InvalidProcessStreamRecord;
    return .{ .owner_generation = try identifier(object, "ownerGeneration"), .process_generation = try identifier(object, "processGeneration") };
}
pub fn readHeader(object: *const std.json.ObjectMap) !Header {
    return .{ .lease = try readLease(object), .request_id = try identifier(object, "requestId") };
}
pub fn readRequest(object: *const std.json.ObjectMap) !Request {
    const header = try readHeader(object);
    const method = try string(object, "method");
    const operation: Operation = if (std.mem.eql(u8, method, "write")) blk: {
        const output = std.meta.stringToEnum(Output, try string(object, "output")) orelse return error.InvalidProcessStreamRecord;
        const encoded = try string(object, "bytesBase64");
        const count = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return error.InvalidProcessStreamRecord;
        if (count > maximum_chunk_bytes) return error.ProcessStreamChunkLimit;
        break :blk .{ .write = .{ .output = output, .base64 = encoded } };
    } else if (std.mem.eql(u8, method, "raw_mode")) .{ .control = .{ .raw_mode = try boolean(object, "enabled") } } else if (std.mem.eql(u8, method, "resume")) .{ .control = .@"resume" } else if (std.mem.eql(u8, method, "pause")) .{ .control = .pause } else if (std.mem.eql(u8, method, "encoding")) blk: {
        const encoding = try string(object, "encoding");
        if (encoding.len == 0 or encoding.len > maximum_encoding_bytes) return error.InvalidProcessStreamRecord;
        break :blk .{ .control = .{ .encoding = encoding } };
    } else if (std.mem.eql(u8, method, "is_shift_pressed")) .is_shift_pressed else if (std.mem.eql(u8, method, "enable_vt_input")) .enable_vt_input else return error.InvalidProcessStreamRecord;
    return .{ .header = header, .operation = operation };
}
pub fn writeLease(writer: *std.Io.Writer, lease: Lease) !void {
    try writer.print("\"version\":{d},\"ownerGeneration\":\"{d}\",\"processGeneration\":\"{d}\"", .{ version, lease.owner_generation, lease.process_generation });
}
pub fn writeHeader(writer: *std.Io.Writer, header: Header) !void {
    try writeLease(writer, header.lease);
    try writer.print(",\"requestId\":\"{d}\"", .{header.request_id});
}
pub fn writeMetadata(writer: *std.Io.Writer, metadata: Metadata) !void {
    try writer.print("\"stdinTTY\":{s},\"stdinRaw\":{s},\"stdoutTTY\":{s},\"stderrTTY\":{s},\"columns\":", .{ if (metadata.stdin_tty) "true" else "false", if (metadata.stdin_raw) "true" else "false", if (metadata.stdout_tty) "true" else "false", if (metadata.stderr_tty) "true" else "false" });
    try std.json.Stringify.value(metadata.columns, .{}, writer);
    try writer.writeAll(",\"rows\":");
    try std.json.Stringify.value(metadata.rows, .{}, writer);
    try writer.print(",\"hasShiftHelper\":{s},\"hasVTInputHelper\":{s}", .{ if (metadata.has_shift_helper) "true" else "false", if (metadata.has_vt_input_helper) "true" else "false" });
}
test "process stream protocol preserves full generation fences raw bytes and nullable pipe metadata" {
    const allocator = std.testing.allocator;
    var request = try std.json.parseFromSlice(std.json.Value, allocator, "{\"version\":1,\"ownerGeneration\":\"9007199254740993\",\"processGeneration\":\"18446744073709551615\",\"requestId\":\"4\",\"method\":\"write\",\"output\":\"stdout\",\"bytesBase64\":\"/wA=\"}", .{});
    defer request.deinit();
    const decoded = try readRequest(&request.value.object);
    try std.testing.expectEqual(@as(u64, 9007199254740993), decoded.header.lease.owner_generation);
    try std.testing.expectEqual(std.math.maxInt(u64), decoded.header.lease.process_generation);
    var bytes: [2]u8 = undefined;
    try std.base64.standard.Decoder.decode(&bytes, decoded.operation.write.base64);
    try std.testing.expectEqualSlices(u8, &.{ 0xff, 0 }, &bytes);
    try std.testing.expect(!decoded.header.matches(.{ .lease = decoded.header.lease, .request_id = 3 }));
    var metadata = try std.json.parseFromSlice(std.json.Value, allocator, "{\"stdinTTY\":false,\"stdinRaw\":false,\"stdoutTTY\":false,\"stderrTTY\":true,\"columns\":null,\"rows\":0}", .{});
    defer metadata.deinit();
    const pipe = try readMetadata(&metadata.value.object);
    try std.testing.expect(pipe.columns == null and pipe.rows.? == 0 and pipe.stderr_tty);
    try request.value.object.put(request.arena.allocator(), "requestId", .{ .string = "04" });
    try std.testing.expectError(error.InvalidProcessStreamRecord, readHeader(&request.value.object));
}
