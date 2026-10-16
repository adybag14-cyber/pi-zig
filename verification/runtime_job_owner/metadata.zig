//! Local WMI identity probe on a dedicated thread. Never controls the job.
//! The caller retains Request and thread state if a COM/RPC call does not return.
const std = @import("std");
const w = @import("win32.zig");
const kernel_process = @import("process.zig");
const Guid = extern struct { a: u32, b: u16, c: u16, d: [8]u8 };
const Object = extern struct { vtable: [*]const *const anyopaque };
const Variant = extern struct { kind: u16, reserved: [3]u16, data: [16]u8 align(8) };
comptime { if (@sizeOf(Guid) != 16 or @sizeOf(Variant) != 24) @compileError("COM ABI layout mismatch"); }
const locator_class: Guid = .{ .a = 0x4590f811, .b = 0x1d3a, .c = 0x11d0, .d = .{ 0x89, 0x1f, 0x00, 0xaa, 0x00, 0x4b, 0x2e, 0x24 } };
const locator_interface: Guid = .{ .a = 0xdc12a687, .b = 0x737f, .c = 0x11cf, .d = .{ 0x88, 0x4d, 0x00, 0xaa, 0x00, 0x4b, 0x2e, 0x24 } };
extern "ole32" fn CoInitializeEx(?*anyopaque, u32) callconv(.winapi) i32;
extern "ole32" fn CoUninitialize() callconv(.winapi) void;
extern "ole32" fn CoInitializeSecurity(?*anyopaque, i32, ?*anyopaque, ?*anyopaque, u32, u32, ?*anyopaque, u32, ?*anyopaque) callconv(.winapi) i32;
extern "ole32" fn CoCreateInstance(*const Guid, ?*anyopaque, u32, *const Guid, *?*Object) callconv(.winapi) i32;
extern "ole32" fn CoSetProxyBlanket(*Object, u32, u32, ?[*:0]u16, u32, u32, ?*anyopaque, u32) callconv(.winapi) i32;
extern "oleaut32" fn SysAllocString([*:0]const u16) callconv(.winapi) ?[*:0]u16;
extern "oleaut32" fn SysFreeString(?[*:0]u16) callconv(.winapi) void;
extern "oleaut32" fn SysStringLen([*:0]const u16) callconv(.winapi) u32;
extern "oleaut32" fn VariantClear(*Variant) callconv(.winapi) i32;
fn method(comptime F: type, object: *Object, index: usize) F {
    return @ptrCast(object.vtable[index]);
}
fn release(object: *Object) void {
    _ = method(*const fn (*Object) callconv(.winapi) u32, object, 2)(object);
}
fn bstr(comptime text: []const u8) ![*:0]u16 {
    const wide = std.unicode.utf8ToUtf16LeStringLiteral(text);
    return SysAllocString(wide) orelse error.MetadataAllocationFailed;
}

pub const Result = struct {
    pid: u32 = 0,
    parent_pid: u32 = 0,
    creation_filetime_utc: u64 = 0,
    image: [32768]u16 = undefined,
    image_units: usize = 0,
    command: [32768]u16 = undefined,
    command_units: usize = 0,
};
pub const Request = struct {
    pid: u32,
    result: Result = .{},
    first_error: ?anyerror = null,
    completed: std.atomic.Value(bool) = .init(false),
    thread: ?w.H = null,
    started_ms: u64 = 0,
    completed_ms: u64 = 0,
    attempted: bool = false,

    pub fn start(self: *Request) !void {
        if (self.pid == 0 or self.thread != null or self.attempted) return error.InvalidMetadataRequest;
        self.attempted = true; // one shot, including a failed CreateThread
        self.started_ms = w.GetTickCount64();
        self.thread = w.CreateThread(null, 1024 * 1024, run, self, 0, null) orelse return error.MetadataThreadFailed;
    }
    pub fn poll(self: *const Request) union(enum) { pending, ready, timeout } {
        if (self.completed.load(.acquire)) {
            if (self.completed_ms - self.started_ms >= 2000) return .timeout;
            return .ready;
        }
        if (w.GetTickCount64() - self.started_ms >= 2000) return .timeout;
        return .pending;
    }
    /// No unbounded join, cancellation assumption or TerminateThread.
    pub fn closeCompleted(self: *Request) !void {
        if (!self.completed.load(.acquire)) return error.MetadataStateMustRemainAlive;
        if (self.thread) |thread| {
            if (w.WaitForSingleObject(thread, 0) != w.wait_object) return error.MetadataThreadNotExited;
            if (w.CloseHandle(thread) == 0) return error.MetadataThreadCloseFailed;
            self.thread = null;
        }
    }
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Request = @ptrCast(@alignCast(raw.?));
        probe(self.pid, &self.result) catch |err| { self.first_error = err; };
        self.completed_ms = w.GetTickCount64();
        self.completed.store(true, .release);
        return 0;
    }
};

fn get(object: *Object, comptime property: []const u8, result: *Variant) !void {
    result.* = std.mem.zeroes(Variant);
    const name = std.unicode.utf8ToUtf16LeStringLiteral(property);
    if (method(*const fn (*Object, [*:0]const u16, i32, *Variant, ?*i32, ?*i32) callconv(.winapi) i32,
        object, 4)(object, name, 0, result, null, null) < 0) return error.MetadataPropertyFailed;
}
fn getNumber(object: *Object, comptime property: []const u8) !u32 {
    var value: Variant = undefined;
    try get(object, property, &value);
    defer _ = VariantClear(&value);
    if (value.kind != 3 and value.kind != 19) return error.MetadataNumberTypeMismatch;
    return std.mem.readInt(u32, value.data[0..4], .little);
}
fn getText(object: *Object, comptime property: []const u8, output: []u16) !usize {
    var value: Variant = undefined;
    try get(object, property, &value);
    defer _ = VariantClear(&value);
    if (value.kind != 8) return error.MetadataStringTypeMismatch;
    const ptr: ?[*:0]u16 = @as(*const ?[*:0]u16, @ptrCast(&value.data)).*;
    const text = ptr orelse return error.MetadataStringUnavailable;
    const length = SysStringLen(text);
    if (length == 0 or length > output.len) return error.MetadataStringLimit;
    if (std.mem.indexOfScalar(u16, text[0..length], 0) != null) return error.MetadataEmbeddedNul;
    @memcpy(output[0..length], text[0..length]);
    return length;
}

fn probe(pid: u32, output: *Result) !void {
    if (CoInitializeEx(null, 0) < 0) return error.MetadataComInitFailed;
    defer CoUninitialize();
    const security = CoInitializeSecurity(null, -1, null, null, 0, 3, null, 0, null);
    // RPC_E_TOO_LATE means this process already installed COM security. The
    // owner initializes once before probes; no weaker retry is performed here.
    if (security < 0 and security != @as(i32, @bitCast(@as(u32, 0x80010119)))) return error.MetadataComSecurityFailed;
    var locator_optional: ?*Object = null;
    if (CoCreateInstance(&locator_class, null, 1, &locator_interface, &locator_optional) < 0)
        return error.MetadataLocatorFailed;
    const locator = locator_optional orelse return error.MetadataLocatorFailed;
    defer release(locator);
    const namespace = try bstr("ROOT\\CIMV2");
    defer SysFreeString(namespace);
    var service_optional: ?*Object = null;
    if (method(*const fn (*Object, [*:0]u16, ?[*:0]u16, ?[*:0]u16, ?[*:0]u16, i32, ?[*:0]u16, ?*Object, *?*Object) callconv(.winapi) i32,
        locator, 3)(locator, namespace, null, null, null, 0x80, null, null, &service_optional) < 0)
        return error.MetadataConnectionFailed;
    const service = service_optional orelse return error.MetadataConnectionFailed;
    defer release(service);
    if (CoSetProxyBlanket(service, 10, 0, null, 3, 3, null, 0) < 0) return error.MetadataProxySecurityFailed;
    var query_buffer: [160]u8 = undefined;
    const query_utf8 = try std.fmt.bufPrint(&query_buffer,
        "SELECT ProcessId,ParentProcessId,CreationDate,ExecutablePath,CommandLine FROM Win32_Process WHERE ProcessId={d}", .{pid});
    var query_units: [160]u16 = undefined;
    const query_length = try std.unicode.utf8ToUtf16Le(&query_units, query_utf8);
    query_units[query_length] = 0;
    const query = SysAllocString(@ptrCast(&query_units)) orelse return error.MetadataAllocationFailed;
    defer SysFreeString(query);
    const language = try bstr("WQL");
    defer SysFreeString(language);
    var enumerator_optional: ?*Object = null;
    if (method(*const fn (*Object, [*:0]u16, [*:0]u16, i32, ?*Object, *?*Object) callconv(.winapi) i32,
        service, 20)(service, language, query, 0x10 | 0x20, null, &enumerator_optional) < 0)
        return error.MetadataQueryFailed;
    const enumerator = enumerator_optional orelse return error.MetadataQueryFailed;
    defer release(enumerator);
    var item_optional: ?*Object = null;
    var count: u32 = 0;
    const status = method(*const fn (*Object, i32, u32, *?*Object, *u32) callconv(.winapi) i32,
        enumerator, 4)(enumerator, 1000, 1, &item_optional, &count);
    if (status < 0 or count != 1) return error.MetadataInstanceUnavailable;
    const item = item_optional orelse return error.MetadataInstanceUnavailable;
    defer release(item);
    output.pid = try getNumber(item, "ProcessId");
    output.parent_pid = try getNumber(item, "ParentProcessId");
    output.image_units = try getText(item, "ExecutablePath", &output.image);
    output.command_units = try getText(item, "CommandLine", &output.command);
    var creation: [32]u16 = undefined;
    const units = try getText(item, "CreationDate", &creation);
    output.creation_filetime_utc = try parseCreation(creation[0..units]);
    if (output.pid != pid) return error.MetadataPidMismatch;
}

pub fn requireMatch(result: *const Result, kernel: *const kernel_process.KernelIdentity,
    parent: u32, expected_image: []const u16, expected_command: []const u16) !void
{
    if (result.pid != kernel.pid or result.parent_pid != parent) return error.MetadataParentOrPidMismatch;
    // WMI's DMTF timestamp has microsecond precision; kernel FILETIME has 100ns.
    // Equality after truncation to microseconds is the only accepted precision loss.
    if (result.creation_filetime_utc / 10 != kernel.creation_filetime_utc / 10) return error.MetadataCreationMismatch;
    if (!samePath(result.image[0..result.image_units], expected_image) or !samePath(kernel.path(), expected_image))
        return error.MetadataImageMismatch;
    if (!std.mem.eql(u16, result.command[0..result.command_units], expected_command)) return error.MetadataCommandMismatch;
}
fn samePath(a: []const u16, b: []const u16) bool {
    if (a.len > std.math.maxInt(i32) or b.len > std.math.maxInt(i32)) return false;
    return w.CompareStringOrdinal(a.ptr, @intCast(a.len), b.ptr, @intCast(b.len), 1) == 2;
}
fn number(text: []const u16) !u64 {
    var value: u64 = 0;
    for (text) |unit| {
        if (unit < '0' or unit > '9') return error.InvalidDmtfTimestamp;
        value = value * 10 + unit - '0';
    }
    return value;
}
fn leap(year: u64) bool { return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0); }
pub fn parseCreation(text: []const u16) !u64 {
    if (text.len != 25 or text[14] != '.' or (text[21] != '+' and text[21] != '-'))
        return error.InvalidDmtfTimestamp;
    const year = try number(text[0..4]);
    const month = try number(text[4..6]);
    const day = try number(text[6..8]);
    const hour = try number(text[8..10]);
    const minute = try number(text[10..12]);
    const second = try number(text[12..14]);
    const fraction = try number(text[15..21]);
    const offset = try number(text[22..25]);
    if (year < 1601 or year > 9999 or month < 1 or month > 12 or hour > 23 or minute > 59 or second > 59 or offset > 999)
        return error.InvalidDmtfTimestamp;
    const months = [_]u64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
    const max_day = months[month - 1] + @as(u64, @intFromBool(month == 2 and leap(year)));
    if (day < 1 or day > max_day) return error.InvalidDmtfTimestamp;
    const before = year - 1;
    var days: u64 = (year - 1601) * 365 + (before / 4 - before / 100 + before / 400) - (1600 / 4 - 1600 / 100 + 1600 / 400);
    for (months[0..month - 1], 0..) |length, index| {
        days += length + @as(u64, @intFromBool(index == 1 and leap(year)));
    }
    days += day - 1;
    var seconds: i64 = @intCast(days * 86400 + hour * 3600 + minute * 60 + second);
    const offset_seconds: i64 = @intCast(offset * 60);
    seconds += if (text[21] == '+') -offset_seconds else offset_seconds;
    if (seconds < 0) return error.InvalidDmtfTimestamp;
    return @as(u64, @intCast(seconds)) * 10_000_000 + fraction * 10;
}
