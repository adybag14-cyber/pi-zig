//! Shared native clipboard transport for the application consumer.
//!
//! The Win32 worker owns its copied input, output and 1 MiB thread-stack
//! reservation under a real PiMemoryOwner. No JavaScript runtime is created.
//! A read returns only after the C worker has joined and its owned result has
//! been copied. The C job and initial owner reference are then retired before
//! any caller invokes an image codec.
//!
//! Returned buffers and temporary UTF8/UTF16 conversions belong to gpa. They
//! are separate from the native-owner budget, not a process-wide aggregate.
const std = @import("std");
const builtin = @import("builtin");
const abi = @import("../extensions/native_tui_win32_platform_abi.zig");

pub const default_memory_limit: usize = 64 * 1024 * 1024;

/// Empty contents must not trigger fallback to another clipboard owner.
pub const Read = union(enum) {
    unavailable,
    empty,
    value: []u8,
};

/// Injected backends return caller-owned buffers and preserve actual OOM.
/// The default implements the linked Win32 helper; other hosts are unavailable.
pub const Backend = struct {
    context: ?*anyopaque = null,
    get_text_fn: *const fn (?*anyopaque, std.mem.Allocator, usize) anyerror!Read = getTextNative,
    get_image_fn: *const fn (?*anyopaque, std.mem.Allocator, usize) anyerror!Read = getImageNative,
    set_text_fn: *const fn (?*anyopaque, std.mem.Allocator, []const u8, usize) anyerror!bool = setTextNative,

    pub fn getText(self: Backend, gpa: std.mem.Allocator, memory_limit: usize) !Read {
        return self.get_text_fn(self.context, gpa, memory_limit);
    }
    pub fn getImage(self: Backend, gpa: std.mem.Allocator, memory_limit: usize) !Read {
        return self.get_image_fn(self.context, gpa, memory_limit);
    }
    pub fn setText(self: Backend, gpa: std.mem.Allocator, text: []const u8, memory_limit: usize) !bool {
        return self.set_text_fn(self.context, gpa, text, memory_limit);
    }
};

/// A deterministic unavailable backend for routing tests and explicit callers.
pub const unavailable: Backend = .{
    .get_text_fn = unavailableRead,
    .get_image_fn = unavailableRead,
    .set_text_fn = unavailableWrite,
};

fn unavailableRead(_: ?*anyopaque, _: std.mem.Allocator, _: usize) !Read {
    return .unavailable;
}
fn unavailableWrite(_: ?*anyopaque, _: std.mem.Allocator, _: []const u8, _: usize) !bool {
    return false;
}

extern fn pi_js_new_memory_owner(memory_limit: usize) ?*anyopaque;
extern fn pi_js_release_memory_owner(memory_owner: *anyopaque) void;

const CompletedJob = struct {
    owner: *anyopaque,
    raw: *abi.Job,

    fn init(operation: abi.Operation, input: ?[]const u16, memory_limit: usize) !CompletedJob {
        const owner = pi_js_new_memory_owner(memory_limit) orelse return error.OutOfMemory;
        errdefer pi_js_release_memory_owner(owner);
        var failure: c_int = @intFromEnum(abi.CreateFailure.none);
        const raw = abi.pi_tui_win32_clipboard_create(owner, @intFromEnum(operation),
            if (input) |text| text.ptr else null,
            if (input) |text| text.len else 0, &failure) orelse {
            if (failure == @intFromEnum(abi.CreateFailure.native_budget)) return error.OutOfMemory;
            return error.NativeClipboardUnavailable;
        };
        errdefer abi.pi_tui_win32_clipboard_destroy(raw);
        const start_status = abi.pi_tui_win32_clipboard_start(raw);
        if (start_status < 0) return error.OutOfMemory;
        if (start_status != 0) return error.NativeClipboardQueueFailed;
        // True join owns the complete worker lifetime. No timeout releases data
        // or the budget while a thread can still access them.
        abi.pi_tui_win32_clipboard_join(raw);
        if (abi.pi_tui_win32_clipboard_allocation_failed(raw) != 0) return error.OutOfMemory;
        // C records OS transfer failures separately from genuine budget failure.
        // Diagnostic text, including "Out of memory", is never an OOM authority.
        if (abi.pi_tui_win32_clipboard_error(raw) != null) return error.NativeClipboardFailed;
        return .{ .owner = owner, .raw = raw };
    }

    fn deinit(self: CompletedJob) void {
        abi.pi_tui_win32_clipboard_destroy(self.raw);
        pi_js_release_memory_owner(self.owner);
    }
};

fn getTextNative(_: ?*anyopaque, gpa: std.mem.Allocator, memory_limit: usize) !Read {
    if (comptime builtin.os.tag != .windows) return .unavailable;
    const job = try CompletedJob.init(.text, null, memory_limit);
    defer job.deinit();
    const format = abi.pi_tui_win32_clipboard_format(job.raw);
    if (format == @intFromEnum(abi.Format.unavailable)) return .unavailable;
    if (format == @intFromEnum(abi.Format.empty)) return .empty;
    const length = abi.pi_tui_win32_clipboard_length(job.raw);
    if (length == 0) return .empty;
    const pointer = abi.pi_tui_win32_clipboard_data(job.raw) orelse return error.InvalidNativeClipboardResult;
    const bytes = switch (format) {
        @intFromEnum(abi.Format.utf16) => blk: {
            const units: [*]const u16 = @ptrCast(@alignCast(pointer));
            break :blk try utf16ToUtf8Alloc(gpa, units[0..length]);
        },
        @intFromEnum(abi.Format.utf8) => blk: {
            const input: [*]const u8 = @ptrCast(pointer);
            break :blk try decodeUtf8Alloc(gpa, input[0..length]);
        },
        @intFromEnum(abi.Format.latin1) => blk: {
            const input: [*]const u8 = @ptrCast(pointer);
            break :blk try latin1ToUtf8Alloc(gpa, input[0..length]);
        },
        else => return error.InvalidNativeClipboardResult,
    };
    return .{ .value = bytes };
}

fn getImageNative(_: ?*anyopaque, gpa: std.mem.Allocator, memory_limit: usize) !Read {
    if (comptime builtin.os.tag != .windows) return .unavailable;
    const job = try CompletedJob.init(.image, null, memory_limit);
    defer job.deinit();
    const format = abi.pi_tui_win32_clipboard_format(job.raw);
    if (format == @intFromEnum(abi.Format.unavailable)) return .unavailable;
    if (format == @intFromEnum(abi.Format.empty)) return .empty;
    if (format != @intFromEnum(abi.Format.buffer)) return error.InvalidNativeClipboardResult;
    const length = abi.pi_tui_win32_clipboard_length(job.raw);
    if (length == 0) return .empty;
    const pointer = abi.pi_tui_win32_clipboard_data(job.raw) orelse return error.InvalidNativeClipboardResult;
    const bytes: [*]const u8 = @ptrCast(pointer);
    return .{ .value = try gpa.dupe(u8, bytes[0..length]) };
}

fn setTextNative(_: ?*anyopaque, gpa: std.mem.Allocator, text: []const u8, memory_limit: usize) !bool {
    if (comptime builtin.os.tag != .windows) return false;
    // The application applies its existing 50 MiB text-input bound. UTF16 uses
    // at most two bytes per input byte; the exact-sized temporary is host-owned.
    const units = try utf8ToUtf16Alloc(gpa, text);
    defer gpa.free(units);
    const job = try CompletedJob.init(.write, units, memory_limit);
    defer job.deinit();
    return true;
}

const Scalar = struct { value: u21, consumed: usize };

/// UTF8 replacement follows maximal subparts, including an incomplete valid
/// prefix at EOF. Embedded NUL is an ordinary scalar and remains in the result.
fn nextUtf8(input: []const u8, index: usize) Scalar {
    const first = input[index];
    if (first < 0x80) return .{ .value = first, .consumed = 1 };
    const length: usize = if (first >= 0xc2 and first <= 0xdf) 2
        else if (first >= 0xe0 and first <= 0xef) 3
        else if (first >= 0xf0 and first <= 0xf4) 4
        else return .{ .value = 0xfffd, .consumed = 1 };
    var value: u21 = switch (length) {
        2 => first & 0x1f,
        3 => first & 0x0f,
        4 => first & 0x07,
        else => unreachable,
    };
    var consumed: usize = 1;
    while (consumed < length) : (consumed += 1) {
        if (consumed >= input.len - index) return .{ .value = 0xfffd, .consumed = consumed };
        const byte = input[index + consumed];
        const lower: u8 = if (consumed == 1 and first == 0xe0) 0xa0
            else if (consumed == 1 and first == 0xf0) 0x90 else 0x80;
        const upper: u8 = if (consumed == 1 and first == 0xed) 0x9f
            else if (consumed == 1 and first == 0xf4) 0x8f else 0xbf;
        if (byte < lower or byte > upper) return .{ .value = 0xfffd, .consumed = consumed };
        value = (value << 6) | @as(u21, byte & 0x3f);
    }
    return .{ .value = value, .consumed = length };
}

fn nextUtf16(input: []const u16, index: usize) Scalar {
    const first = input[index];
    if (first >= 0xd800 and first <= 0xdbff) {
        if (index + 1 < input.len) {
            const second = input[index + 1];
            if (second >= 0xdc00 and second <= 0xdfff)
                return .{ .value = 0x10000 + ((@as(u21, first) - 0xd800) << 10) + (@as(u21, second) - 0xdc00), .consumed = 2 };
        }
        return .{ .value = 0xfffd, .consumed = 1 };
    }
    if (first >= 0xdc00 and first <= 0xdfff) return .{ .value = 0xfffd, .consumed = 1 };
    return .{ .value = first, .consumed = 1 };
}

fn utf8Length(value: u21) usize {
    return if (value < 0x80) 1 else if (value < 0x800) 2 else if (value < 0x10000) 3 else 4;
}

fn putUtf8(output: []u8, index: *usize, value: u21) void {
    const length = utf8Length(value);
    switch (length) {
        1 => output[index.*] = @intCast(value),
        2 => {
            output[index.*] = 0xc0 | @as(u8, @intCast(value >> 6));
            output[index.* + 1] = 0x80 | @as(u8, @intCast(value & 0x3f));
        },
        3 => {
            output[index.*] = 0xe0 | @as(u8, @intCast(value >> 12));
            output[index.* + 1] = 0x80 | @as(u8, @intCast((value >> 6) & 0x3f));
            output[index.* + 2] = 0x80 | @as(u8, @intCast(value & 0x3f));
        },
        4 => {
            output[index.*] = 0xf0 | @as(u8, @intCast(value >> 18));
            output[index.* + 1] = 0x80 | @as(u8, @intCast((value >> 12) & 0x3f));
            output[index.* + 2] = 0x80 | @as(u8, @intCast((value >> 6) & 0x3f));
            output[index.* + 3] = 0x80 | @as(u8, @intCast(value & 0x3f));
        },
        else => unreachable,
    }
    index.* += length;
}

/// Buffer.toString("utf8") compatible replacement; caller owns the result.
pub fn decodeUtf8Alloc(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var size: usize = 0;
    var index: usize = 0;
    while (index < input.len) {
        const scalar = nextUtf8(input, index);
        size = std.math.add(usize, size, utf8Length(scalar.value)) catch return error.OutOfMemory;
        index += scalar.consumed;
    }
    const output = try gpa.alloc(u8, size);
    var written: usize = 0;
    index = 0;
    while (index < input.len) {
        const scalar = nextUtf8(input, index);
        putUtf8(output, &written, scalar.value);
        index += scalar.consumed;
    }
    return output;
}

pub fn utf16ToUtf8Alloc(gpa: std.mem.Allocator, input: []const u16) ![]u8 {
    var size: usize = 0;
    var index: usize = 0;
    while (index < input.len) {
        const scalar = nextUtf16(input, index);
        size = std.math.add(usize, size, utf8Length(scalar.value)) catch return error.OutOfMemory;
        index += scalar.consumed;
    }
    const output = try gpa.alloc(u8, size);
    var written: usize = 0;
    index = 0;
    while (index < input.len) {
        const scalar = nextUtf16(input, index);
        putUtf8(output, &written, scalar.value);
        index += scalar.consumed;
    }
    return output;
}

pub fn utf8ToUtf16Alloc(gpa: std.mem.Allocator, input: []const u8) ![]u16 {
    var size: usize = 0;
    var index: usize = 0;
    while (index < input.len) {
        const scalar = nextUtf8(input, index);
        size = std.math.add(usize, size, if (scalar.value < 0x10000) @as(usize, 1) else 2) catch return error.OutOfMemory;
        index += scalar.consumed;
    }
    const output = try gpa.alloc(u16, size);
    var written: usize = 0;
    index = 0;
    while (index < input.len) {
        const scalar = nextUtf8(input, index);
        if (scalar.value < 0x10000) {
            output[written] = @intCast(scalar.value);
            written += 1;
        } else {
            const pair = scalar.value - 0x10000;
            output[written] = @intCast(0xd800 + (pair >> 10));
            output[written + 1] = @intCast(0xdc00 + (pair & 0x3ff));
            written += 2;
        }
        index += scalar.consumed;
    }
    return output;
}

fn latin1ToUtf8Alloc(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    var size: usize = input.len;
    for (input) |byte| if (byte >= 0x80) {
        size = std.math.add(usize, size, 1) catch return error.OutOfMemory;
    };
    const output = try gpa.alloc(u8, size);
    var written: usize = 0;
    for (input) |byte| putUtf8(output, &written, byte);
    return output;
}
