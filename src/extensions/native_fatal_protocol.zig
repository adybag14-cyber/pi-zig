//! Private Main/worker fatal lease. Never put this lease into guest argv,
//! environment, a public manifest, or a guest-facing protocol capability.
const std = @import("std");
pub const version = 1;
pub const maximum_diagnostic_bytes = 4 * 1024 * 1024;
pub const Plan = enum {
    uncaught_crash,
    emergency_terminal_exit,
    already_shutting_down,
    handler_failure,

    pub fn exitCode(self: Plan) u8 {
        return switch (self) {
            .emergency_terminal_exit => 129,
            .handler_failure => 7,
            else => 1,
        };
    }
};
pub const Lease = struct {
    owner_generation: u64,
    secret: [32]u8,

    pub fn generate(io: std.Io, owner_generation: u64) !Lease {
        if (owner_generation == 0) return error.InvalidNativeFatalLease;
        var result: Lease = .{ .owner_generation = owner_generation, .secret = undefined };
        std.Io.random(io, &result.secret);
        return result;
    }
    pub fn matches(self: Lease, other: Lease) bool {
        const same_secret = std.crypto.timing_safe.eql([32]u8, self.secret, other.secret);
        return same_secret and self.owner_generation == other.owner_generation;
    }
};
pub const Record = struct {
    gpa: std.mem.Allocator,
    lease: Lease,
    sequence: u64,
    plan: Plan,
    diagnostic: ?[]u8,

    pub fn deinit(self: *Record) void {
        if (self.diagnostic) |bytes| self.gpa.free(bytes);
        self.diagnostic = null;
    }
};
pub const Release = enum { restored, terminal_dead, already_released };
pub const Ack = struct { lease: Lease, sequence: u64, release: Release };
pub const Diagnostic = struct {
    gpa: std.mem.Allocator,
    lease: Lease,
    sequence: u64,
    exit_code: u8,
    bytes: []u8,
    pub fn deinit(self: *Diagnostic) void {
        self.gpa.free(self.bytes);
    }
};

fn text(object: *const std.json.ObjectMap, name: []const u8) ![]const u8 {
    const value = object.get(name) orelse return error.InvalidNativeFatalRecord;
    return if (value == .string) value.string else error.InvalidNativeFatalRecord;
}
fn identifier(object: *const std.json.ObjectMap, name: []const u8) !u64 {
    const bytes = try text(object, name);
    if (bytes.len == 0 or bytes[0] == '0') return error.InvalidNativeFatalRecord;
    for (bytes) |byte| if (byte < '0' or byte > '9') return error.InvalidNativeFatalRecord;
    return std.fmt.parseInt(u64, bytes, 10) catch error.InvalidNativeFatalRecord;
}
fn incomingLease(object: *const std.json.ObjectMap) !Lease {
    const encoded = try text(object, "fatalLease");
    if (encoded.len != 64) return error.InvalidNativeFatalRecord;
    var secret: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&secret, encoded) catch return error.InvalidNativeFatalRecord;
    return .{ .owner_generation = try identifier(object, "ownerGeneration"), .secret = secret };
}
pub fn readStartup(object: *const std.json.ObjectMap, owner_generation: u64) !Lease {
    const lease = try incomingLease(object);
    try checkVersion(object);
    if (lease.owner_generation != owner_generation) return error.InvalidNativeFatalLease;
    return lease;
}
fn checkVersion(object: *const std.json.ObjectMap) !void {
    const value = object.get("version") orelse return error.InvalidNativeFatalRecord;
    if (value != .integer or value.integer != version) return error.InvalidNativeFatalRecord;
}
/// Reject an unauthenticated or retired producer before reading its payload.
/// A guest stdout string cannot turn an unrelated owner into a fatal producer.
pub fn readAuthenticated(gpa: std.mem.Allocator, object: *const std.json.ObjectMap, expected: Lease) !?Record {
    const lease = incomingLease(object) catch return null;
    if (!lease.matches(expected)) return null;
    try checkVersion(object);
    if (!std.mem.eql(u8, try text(object, "type"), "native_fatal")) return error.InvalidNativeFatalRecord;
    const sequence = try identifier(object, "sequence");
    // A fatal owner has one terminal outcome and cannot issue a replacement.
    if (sequence != 1) return error.InvalidNativeFatalRecord;
    const plan = std.meta.stringToEnum(Plan, try text(object, "plan")) orelse return error.InvalidNativeFatalRecord;
    const exit_code = object.get("exitCode") orelse return error.InvalidNativeFatalRecord;
    if (exit_code != .integer or exit_code.integer != plan.exitCode()) return error.InvalidNativeFatalRecord;
    const value = object.get("diagnostic") orelse return error.InvalidNativeFatalRecord;
    // Source formats the original reason only after UI stop. The initial
    // header must not contain a preformatted stack or invoke a guest getter.
    if (value != .null) return error.EarlyNativeFatalDiagnostic;
    return .{ .gpa = gpa, .lease = lease, .sequence = sequence, .plan = plan, .diagnostic = null };
}
pub fn readDiagnostic(gpa: std.mem.Allocator, object: *const std.json.ObjectMap, expected: Lease) !?Diagnostic {
    const lease = incomingLease(object) catch return null;
    if (!lease.matches(expected)) return null;
    try checkVersion(object);
    if (!std.mem.eql(u8, try text(object, "type"), "native_fatal_diagnostic")) return error.InvalidNativeFatalRecord;
    const sequence = try identifier(object, "sequence");
    if (sequence != 1) return error.InvalidNativeFatalRecord;
    const exit_code = object.get("exitCode") orelse return error.InvalidNativeFatalRecord;
    if (exit_code != .integer or (exit_code.integer != 1 and exit_code.integer != 7)) return error.InvalidNativeFatalRecord;
    const bytes = try text(object, "diagnostic");
    if (bytes.len > maximum_diagnostic_bytes) return error.NativeFatalDiagnosticLimit;
    return .{ .gpa = gpa, .lease = lease, .sequence = sequence, .exit_code = @intCast(exit_code.integer), .bytes = try gpa.dupe(u8, bytes) };
}
pub fn readAck(object: *const std.json.ObjectMap, expected: Lease) !?Ack {
    const lease = incomingLease(object) catch return null;
    if (!lease.matches(expected)) return null;
    try checkVersion(object);
    if (!std.mem.eql(u8, try text(object, "kind"), "native_fatal_restore_ack")) return error.InvalidNativeFatalRecord;
    const sequence = try identifier(object, "sequence");
    if (sequence != 1) return error.InvalidNativeFatalRecord;
    return .{ .lease = lease, .sequence = sequence, .release = std.meta.stringToEnum(Release, try text(object, "release")) orelse return error.InvalidNativeFatalRecord };
}
pub fn writeLease(writer: *std.Io.Writer, lease: Lease) !void {
    const encoded = std.fmt.bytesToHex(lease.secret, .lower);
    try writer.print("\"version\":{d},\"ownerGeneration\":\"{d}\",\"fatalLease\":\"{s}\"", .{ version, lease.owner_generation, encoded });
}
pub fn writeRecord(writer: *std.Io.Writer, record: Record) !void {
    if (record.diagnostic != null) return error.EarlyNativeFatalDiagnostic;
    try writer.writeAll("\x1e{\"type\":\"native_fatal\",");
    try writeLease(writer, record.lease);
    try writer.print(",\"sequence\":\"{d}\",\"plan\":\"{s}\",\"exitCode\":{d},\"diagnostic\":", .{ record.sequence, @tagName(record.plan), record.plan.exitCode() });
    try std.json.Stringify.value(record.diagnostic, .{}, writer);
    try writer.writeAll("}\n");
    try writer.flush();
}
pub fn writeDiagnostic(writer: *std.Io.Writer, diagnostic: Diagnostic) !void {
    if (diagnostic.bytes.len > maximum_diagnostic_bytes) return error.NativeFatalDiagnosticLimit;
    try writer.writeAll("\x1e{\"type\":\"native_fatal_diagnostic\",");
    try writeLease(writer, diagnostic.lease);
    try writer.print(",\"sequence\":\"{d}\",\"exitCode\":{d},\"diagnostic\":", .{ diagnostic.sequence, diagnostic.exit_code });
    try std.json.Stringify.value(diagnostic.bytes, .{}, writer);
    try writer.writeAll("}\n");
    try writer.flush();
}
pub fn writeAck(writer: *std.Io.Writer, ack: Ack) !void {
    try writer.writeAll("{\"kind\":\"native_fatal_restore_ack\",");
    try writeLease(writer, ack.lease);
    try writer.print(",\"sequence\":\"{d}\",\"release\":\"{s}\"}}\n", .{ ack.sequence, @tagName(ack.release) });
    try writer.flush();
}
/// Owned by the real Main read-session owner. The producer is accepted once;
/// Main must finish terminal release before an ACK is available to its writer.
pub const Latch = struct {
    lease: Lease,
    record: ?Record = null,
    released: ?Release = null,
    acknowledged: bool = false,
    diagnostic_received: bool = false,
    final_exit_code: ?u8 = null,

    pub fn accept(self: *Latch, record: Record) bool {
        if (!record.lease.matches(self.lease) or record.sequence != 1 or self.record != null or self.acknowledged) return false;
        self.record = record;
        return true;
    }
    pub fn completeRelease(self: *Latch, release: Release) !void {
        const record = self.record orelse return error.NoNativeFatalRecord;
        const expected: Release = switch (record.plan) {
            .emergency_terminal_exit => .terminal_dead,
            .already_shutting_down => .already_released,
            .uncaught_crash, .handler_failure => .restored,
        };
        if (release != expected or self.released != null) return error.InvalidNativeFatalRelease;
        self.released = release;
    }
    pub fn takeAck(self: *Latch) !Ack {
        const record = self.record orelse return error.NoNativeFatalRecord;
        const release = self.released orelse return error.NativeTerminalReleasePending;
        if (self.acknowledged) return error.NativeFatalAlreadyAcknowledged;
        self.acknowledged = true;
        return .{ .lease = self.lease, .sequence = record.sequence, .release = release };
    }
    pub fn acceptDiagnostic(self: *Latch, diagnostic: Diagnostic) bool {
        const record = if (self.record) |*value| value else return false;
        if (!self.acknowledged or self.diagnostic_received or
            !diagnostic.lease.matches(self.lease) or diagnostic.sequence != record.sequence or
            (record.plan != .uncaught_crash and record.plan != .handler_failure) or
            (diagnostic.exit_code != record.plan.exitCode() and diagnostic.exit_code != 7)) return false;
        // The initial header owns no heap payload. Transfer the diagnostic's
        // actual allocator together with its bytes rather than assuming that
        // the reader and Main retention allocator are the same instance.
        record.gpa = diagnostic.gpa;
        record.diagnostic = diagnostic.bytes;
        self.diagnostic_received = true;
        self.final_exit_code = diagnostic.exit_code;
        return true;
    }
    pub fn deinit(self: *Latch) void {
        if (self.record) |*record| record.deinit();
        self.record = null;
    }
};

test "native fatal protocol authenticates owner before payload and rejects old owners duplicate terminal records and early ACK" {
    const lease: Lease = .{ .owner_generation = 9007199254740993, .secret = .{0x4d} ** 32 };
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    var original: Record = .{ .gpa = std.testing.allocator, .lease = lease, .sequence = 1, .plan = .uncaught_crash, .diagnostic = null };
    defer original.deinit();
    try writeRecord(&output.writer, original);
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, std.mem.trim(u8, output.written()[1..], "\n"), .{});
    defer parsed.deinit();
    const decoded = (try readAuthenticated(std.testing.allocator, &parsed.value.object, lease)).?;
    var latch: Latch = .{ .lease = lease };
    defer latch.deinit();
    try std.testing.expect(latch.accept(decoded));
    try std.testing.expect(!latch.accept(decoded));
    const diagnostic: Diagnostic = .{ .gpa = std.testing.allocator, .lease = lease, .sequence = 1, .exit_code = 1, .bytes = try std.testing.allocator.dupe(u8, "Error: original Ω\n    at genuine (input.js:1:9)") };
    try std.testing.expect(!latch.acceptDiagnostic(diagnostic));
    try std.testing.expectError(error.NativeTerminalReleasePending, latch.takeAck());
    try std.testing.expectError(error.InvalidNativeFatalRelease, latch.completeRelease(.terminal_dead));
    try latch.completeRelease(.restored);
    const ack = try latch.takeAck();
    try std.testing.expect(ack.lease.matches(lease));
    try std.testing.expect(latch.acceptDiagnostic(diagnostic));
    try std.testing.expect(!latch.acceptDiagnostic(diagnostic));
    try std.testing.expectEqualStrings("Error: original Ω\n    at genuine (input.js:1:9)", latch.record.?.diagnostic.?);
    try std.testing.expectError(error.NativeFatalAlreadyAcknowledged, latch.takeAck());
    var retired = lease;
    retired.owner_generation += 1;
    try std.testing.expect((try readAuthenticated(std.testing.allocator, &parsed.value.object, retired)) == null);
    retired = lease;
    retired.secret[0] ^= 1;
    try std.testing.expect((try readAuthenticated(std.testing.allocator, &parsed.value.object, retired)) == null);
}

test "native fatal protocol dead terminal never carries diagnostic and ACK follows distinct terminal release" {
    const lease: Lease = .{ .owner_generation = 1, .secret = .{0xa1} ** 32 };
    var latch: Latch = .{ .lease = lease };
    defer latch.deinit();
    try std.testing.expect(latch.accept(.{ .gpa = std.testing.allocator, .lease = lease, .sequence = 1, .plan = .emergency_terminal_exit, .diagnostic = null }));
    try std.testing.expectError(error.InvalidNativeFatalRelease, latch.completeRelease(.restored));
    try latch.completeRelease(.terminal_dead);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try writeAck(&output.writer, try latch.takeAck());
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.written(), .{});
    defer parsed.deinit();
    try std.testing.expectEqual(Release.terminal_dead, (try readAck(&parsed.value.object, lease)).?.release);
}
