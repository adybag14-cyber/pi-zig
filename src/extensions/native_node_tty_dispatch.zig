//! Actual Node24 StreamBase Buffer/String dispatch accounting. Native owner
//! calls BEFORE entering the console output lock; no VM work under that lock.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const h = @import("native_node_tty_values.zig");
pub const Kind = enum { buffer, native_utf8, native_ascii, native_latin1, native_ucs2 };
pub const Plan = struct {
    kind: Kind,
    encoded_bytes: usize,
    utf16_units: usize = 0,
    storage_bytes: usize = 0,
    small_string_fastpath: bool = false,
    too_large: bool = false,
    /// Actual StreamBase counter is not a native delivered-byte certificate.
    /// Buffer/large String increments total BEFORE DoTryWrite; small String
    /// increments synchronously_written, which stays0 on a negative UV result.
    pub fn dispatchedBytes(self: Plan, native_failed: bool) usize {
        if (self.too_large) return 0; // Source UV_ENOBUFS before native dispatch.
        if (native_failed and self.small_string_fastpath) return 0;
        return self.encoded_bytes;
    }
};
fn nativeKind(encoding: []const u8) Kind {
    if (std.mem.eql(u8, encoding, "utf8") or std.mem.eql(u8, encoding, "utf-8")) return .native_utf8;
    if (std.mem.eql(u8, encoding, "ascii")) return .native_ascii;
    if (std.mem.eql(u8, encoding, "latin1") or std.mem.eql(u8, encoding, "binary")) return .native_latin1;
    if (std.mem.eql(u8, encoding, "ucs2") or std.mem.eql(u8, encoding, "ucs-2") or std.mem.eql(u8, encoding, "utf16le") or std.mem.eql(u8, encoding, "utf-16le")) return .native_ucs2;
    // Source default genuinely performs live Buffer.from and writeBuffer.
    // Uppercase aliases also take that branch; do not lowercase the switch.
    return .buffer;
}
/// source/encoding are the genuine borrowed _write inputs preserved by the
/// canonical Socket hook; bytes is the already intrinsic/fallback encoded span.
/// This helper performs no Buffer.from call and retains no borrowed guest value.
pub fn plan(engine: *v.em.Engine, source: c.JSValue, encoding: c.JSValue, encoded_bytes: usize) !Plan {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    try h.pending(engine);
    if (!c.JS_IsString(source) or !c.JS_IsString(encoding)) return .{ .kind = .buffer, .encoded_bytes = encoded_bytes };
    const label = try engine.toString(encoding); defer engine.gpa.free(label);
    try h.pending(engine);
    const kind = nativeKind(label);
    if (kind == .buffer) return .{ .kind = .buffer, .encoded_bytes = encoded_bytes };
    const text = try engine.toString(source); defer engine.gpa.free(text);
    try h.pending(engine);
    var iterator = (try std.unicode.Wtf8View.init(text)).iterator();
    var units: usize = 0;
    while (iterator.nextCodepoint()) |point| units += if (point > 0xffff) @as(usize, 2) else 1;
    const storage = switch (kind) {
        .native_utf8 => if (units > 65535) encoded_bytes else std.math.mul(usize, units, 3) catch return error.NativeTtyStringStorageOverflow,
        .native_ascii, .native_latin1 => units,
        .native_ucs2 => std.math.mul(usize, units, 2) catch return error.NativeTtyStringStorageOverflow,
        .buffer => unreachable,
    };
    return .{ .kind = kind, .encoded_bytes = encoded_bytes, .utf16_units = units, .storage_bytes = storage,
        .small_string_fastpath = storage <= 16384, .too_large = storage > std.math.maxInt(i32) };
}
