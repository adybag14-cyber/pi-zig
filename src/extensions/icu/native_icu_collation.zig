//! Direct ICU C ABI only. The project host and adapter remain native Zig.
//! Bootstrap pins the exact ICU78.2/Node24.14.0 common data before any collator.
//! This is a typed backend; JavaScript locale/options coercion is separate work.
const std = @import("std");
const builtin = @import("builtin");
const UCollator = opaque {};
extern fn udata_setCommonData_78(*align(16) const anyopaque, *i32) callconv(.c) void;
extern fn u_getVersion_78(*[4]u8) callconv(.c) void;
extern fn u_getUnicodeVersion_78(*[4]u8) callconv(.c) void;
extern fn ulocdata_getCLDRVersion_78(*[4]u8, *i32) callconv(.c) void;
extern fn ucol_open_78([*:0]const u8, *i32) callconv(.c) ?*UCollator;
extern fn ucol_close_78(*UCollator) callconv(.c) void;
extern fn ucol_setAttribute_78(*UCollator, i32, i32, *i32) callconv(.c) void;
extern fn ucol_strcoll_78(*const UCollator, [*]const u16, i32, [*]const u16, i32) callconv(.c) i32;
extern fn ucol_getVersion_78(*const UCollator, *[4]u8) callconv(.c) void;
extern fn ucol_getUCAVersion_78(*const UCollator, *[4]u8) callconv(.c) void;
extern fn ucol_getAttribute_78(*const UCollator, i32, *i32) callconv(.c) i32;
extern fn ucol_getLocaleByType_78(*const UCollator, i32, *i32) callconv(.c) ?[*:0]const u8;
const common_data align(16) = @embedFile("node-data/icudt78l.dat").*;
var bootstrap_mutex: std.atomic.Mutex = .unlocked;
var bootstrapped: std.atomic.Value(bool) = .init(false);
var bootstrap_attempts: std.atomic.Value(u32) = .init(0);
fn success(status: i32) !void {
    if (status == 7) return error.OutOfMemory;
    if (status > 0) return error.IcuOperationFailed;
}
pub fn initialize() !void {
    if (bootstrapped.load(.acquire)) return;
    while (!bootstrap_mutex.tryLock()) std.Thread.yield() catch std.atomic.spinLoopHint();
    defer bootstrap_mutex.unlock();
    if (bootstrapped.load(.monotonic)) return;
    // This lock covers only ICU's initial data and version validation. It never
    // enters JavaScript, allocates from the host allocator, or invokes callbacks.
    if (builtin.is_test) _ = bootstrap_attempts.fetchAdd(1, .monotonic);
    var status: i32 = 0;
    udata_setCommonData_78(&common_data, &status);
    try success(status);
    var version: [4]u8 = undefined;
    u_getVersion_78(&version);
    if (!std.mem.eql(u8, &version, &.{ 78, 2, 0, 0 })) return error.UnexpectedIcuRuntimeVersion;
    u_getUnicodeVersion_78(&version);
    if (!std.mem.eql(u8, &version, &.{ 17, 0, 0, 0 })) return error.UnexpectedIcuUnicodeVersion;
    status = 0;
    ulocdata_getCLDRVersion_78(&version, &status);
    try success(status);
    if (!std.mem.eql(u8, &version, &.{ 48, 0, 0, 0 })) return error.UnexpectedIcuCldrVersion;
    bootstrapped.store(true, .release);
}
pub fn initializationAttemptsForTest() u32 {
    if (!builtin.is_test) @compileError("Bootstrap diagnostics are test-only");
    return bootstrap_attempts.load(.acquire);
}
pub const Sensitivity = enum { base, accent, case, variant };
pub const CaseFirst = enum { off, lower, upper };
pub const Options = struct {
    sensitivity: ?Sensitivity = .variant,
    // Null retains the locale's ICU default, as Node/V8 does when omitted.
    numeric: ?bool = null,
    case_first: ?CaseFirst = null,
    ignore_punctuation: ?bool = null,
};
pub const Collator = struct {
    handle: *UCollator,
    pub fn open(locale: [:0]const u8, options: Options) !Collator {
        try initialize();
        var status: i32 = 0;
        const handle = ucol_open_78(locale, &status) orelse {
            try success(status);
            return error.IcuCollatorUnavailable;
        };
        errdefer ucol_close_78(handle);
        try success(status);
        var result: Collator = .{ .handle = handle };
        // Node's actual V8 Collator initialization always enables normalization.
        try result.attribute(4, 17);
        try result.setSensitivity(options.sensitivity);
        if (options.numeric) |value| try result.attribute(7, if (value) 17 else 16);
        if (options.case_first) |value| try result.attribute(2, switch (value) {
            .off => 16,
            .lower => 24,
            .upper => 25,
        });
        if (options.ignore_punctuation) |value| try result.attribute(1, if (value) 20 else 21);
        return result;
    }
    fn attribute(self: *Collator, name: i32, value: i32) !void {
        var status: i32 = 0;
        ucol_setAttribute_78(self.handle, name, value, &status);
        try success(status);
    }
    pub fn setSensitivity(self: *Collator, sensitivity: ?Sensitivity) !void {
        if (sensitivity) |value| {
            try self.attribute(5, switch (value) {
                .base, .case => 0,
                .accent => 1,
                .variant => 2,
            });
            if (value == .case) try self.attribute(3, 17);
        }
    }
    pub fn setIgnorePunctuation(self: *Collator, value: bool) !void {
        try self.attribute(1, if (value) 20 else 21);
    }
    pub fn deinit(self: *Collator) void {
        ucol_close_78(self.handle);
        self.* = undefined;
    }
    pub fn compare(self: *const Collator, left: []const u16, right: []const u16) !i32 {
        const left_len = std.math.cast(i32, left.len) orelse return error.StringTooLong;
        const right_len = std.math.cast(i32, right.len) orelse return error.StringTooLong;
        return ucol_strcoll_78(self.handle, left.ptr, left_len, right.ptr, right_len);
    }
    pub fn version(self: *const Collator) [4]u8 {
        var value: [4]u8 = undefined;
        ucol_getVersion_78(self.handle, &value);
        return value;
    }
    pub fn ucaVersion(self: *const Collator) [4]u8 {
        var value: [4]u8 = undefined;
        ucol_getUCAVersion_78(self.handle, &value);
        return value;
    }
    pub fn getAttribute(self: *const Collator, name: i32) !i32 {
        var status: i32 = 0;
        const value = ucol_getAttribute_78(self.handle, name, &status);
        try success(status);
        return value;
    }
    pub fn validLocaleId(self: *const Collator) ![:0]const u8 {
        var status: i32 = 0;
        const value = ucol_getLocaleByType_78(self.handle, 1, &status) orelse {
            try success(status);
            return error.IcuCollatorLocaleUnavailable;
        };
        try success(status);
        return std.mem.span(value);
    }
};
