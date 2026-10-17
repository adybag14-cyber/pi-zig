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
    image_authority: enum { unavailable, owned_kernel_handle } = .unavailable,
    kernel_pid: u32 = 0,
    kernel_creation_filetime_utc: u64 = 0,
    wmi_image: [32768]u16 = undefined,
    wmi_image_units: usize = 0,
    wmi_image_available: bool = false,
    wmi_image_property: PropertyDiagnostic = .{},
};
pub const PropertyDiagnostic = struct {
    property: ?[]const u8 = null,
    hresult: ?i32 = null,
    variant_kind: ?u16 = null,
    cim_type: ?i32 = null,
};
pub const Request = struct {
    pid: u32,
    result: Result = .{},
    first_error: ?anyerror = null,
    property_diagnostic: PropertyDiagnostic = .{},
    // One noninheritable limited-query duplicate. Only the probe worker closes
    // it after actual probe return; timeout/owner cleanup cannot retire it early.
    query_handle: std.atomic.Value(usize) = .init(0),
    query_handle_duplicated: bool = false,
    query_handle_close_succeeded: bool = false,
    query_handle_close_error: ?u32 = null,
    completed: std.atomic.Value(bool) = .init(false),
    thread: ?w.H = null,
    started_ms: u64 = 0,
    completed_ms: u64 = 0,
    attempted: bool = false,

    pub fn start(self: *Request) !void {
        if (self.pid == 0 or self.thread != null or self.attempted) return error.InvalidMetadataRequest;
        if (self.pid != w.GetCurrentProcessId()) return error.MetadataOwnedProcessHandleRequired;
        return self.startBound(w.GetCurrentProcess());
    }
    /// The caller retains its actual created/pulled process handle while this
    /// synchronous duplication occurs. No PID lookup or intended metadata input.
    pub fn startBound(self: *Request, process: w.H) !void {
        if (self.pid == 0 or self.thread != null or self.attempted) return error.InvalidMetadataRequest;
        self.attempted = true; // one shot, including duplicate/CreateThread failure
        self.started_ms = w.GetTickCount64();
        const current = w.GetCurrentProcess();
        var duplicate: w.H = undefined;
        if (w.DuplicateHandle(current, process, current, &duplicate,
            w.process_query_limited | w.process_synchronize, 0, 0) == 0) return error.MetadataProcessDuplicateFailed;
        self.query_handle.store(@intFromPtr(duplicate), .release);
        self.query_handle_duplicated = true;
        self.thread = w.CreateThread(null, 1024 * 1024, run, self, 0, null) orelse {
            self.closeQueryHandle();
            if (self.query_handle_close_error != null) return error.MetadataQueryHandleCloseRetained;
            return error.MetadataThreadFailed;
        };
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
        if (!self.retired()) return error.MetadataQueryHandleCloseRetained;
    }
    pub fn retired(self: *const Request) bool {
        return self.thread == null and self.query_handle.load(.acquire) == 0 and self.query_handle_close_error == null;
    }
    fn closeQueryHandle(self: *Request) void {
        // Disarm before CloseHandle: failure is retained uncertainty, never a
        // reason to retry a possibly recycled numeric handle during cleanup.
        const raw_handle = self.query_handle.swap(0, .acq_rel);
        if (raw_handle == 0) return;
        if (w.CloseHandle(@ptrFromInt(raw_handle)) == 0) {
            self.query_handle_close_error = w.GetLastError();
            if (self.first_error == null) self.first_error = error.MetadataQueryHandleCloseRetained;
        } else self.query_handle_close_succeeded = true;
    }
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Request = @ptrCast(@alignCast(raw.?));
        const raw_handle = self.query_handle.load(.acquire);
        if (raw_handle == 0) self.first_error = error.MetadataOwnedProcessHandleRequired else
            probe(self.pid, @ptrFromInt(raw_handle), &self.result, &self.property_diagnostic) catch |err| { self.first_error = err; };
        self.closeQueryHandle();
        self.completed_ms = w.GetTickCount64();
        self.completed.store(true, .release);
        return 0;
    }
};

fn get(object: *Object, comptime property: []const u8, result: *Variant, diagnostic: *PropertyDiagnostic) !void {
    result.* = std.mem.zeroes(Variant);
    diagnostic.* = .{ .property = property };
    const name = std.unicode.utf8ToUtf16LeStringLiteral(property);
    var cim_type: i32 = 0;
    const status = method(*const fn (*Object, [*:0]const u16, i32, *Variant, ?*i32, ?*i32) callconv(.winapi) i32,
        object, 4)(object, name, 0, result, &cim_type, null);
    diagnostic.hresult = status;
    if (status < 0) return error.MetadataPropertyFailed;
    diagnostic.variant_kind = result.kind;
    diagnostic.cim_type = cim_type;
}
fn getNumber(object: *Object, comptime property: []const u8, diagnostic: *PropertyDiagnostic) !u32 {
    var value: Variant = undefined;
    try get(object, property, &value, diagnostic);
    defer _ = VariantClear(&value);
    if (value.kind != 3 and value.kind != 19) return error.MetadataNumberTypeMismatch;
    return std.mem.readInt(u32, value.data[0..4], .little);
}
fn getText(object: *Object, comptime property: []const u8, output: []u16, diagnostic: *PropertyDiagnostic) !usize {
    var value: Variant = undefined;
    try get(object, property, &value, diagnostic);
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

fn probe(pid: u32, process: w.H, output: *Result, diagnostic: *PropertyDiagnostic) !void {
    const kernel = try kernel_process.identity(process);
    if (kernel.pid != pid) return error.MetadataHandlePidMismatch;
    output.kernel_pid = kernel.pid;
    output.kernel_creation_filetime_utc = kernel.creation_filetime_utc;
    @memcpy(output.image[0..kernel.image_units], kernel.path());
    output.image_units = kernel.image_units;
    output.image_authority = .owned_kernel_handle;
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
    output.pid = try getNumber(item, "ProcessId", diagnostic);
    output.parent_pid = try getNumber(item, "ParentProcessId", diagnostic);
    const wmi_image_units: ?usize = getText(item, "ExecutablePath", &output.wmi_image, diagnostic) catch |err| missing: {
        output.wmi_image_property = diagnostic.*;
        // Actual provider NULL is unavailable WMI data. The independently
        // queried retained kernel handle remains the primary image authority.
        if (err == error.MetadataStringTypeMismatch and diagnostic.variant_kind == 1 and
            diagnostic.cim_type == 8 and diagnostic.hresult == 0) break :missing null;
        return err;
    };
    output.wmi_image_property = diagnostic.*;
    if (wmi_image_units) |wmi_units| {
        output.wmi_image_units = wmi_units;
        output.wmi_image_available = true;
        try requireImageAgreement(output.wmi_image[0..wmi_units], output.image[0..output.image_units]);
    }
    output.command_units = try getText(item, "CommandLine", &output.command, diagnostic);
    var creation: [32]u16 = undefined;
    const units = try getText(item, "CreationDate", &creation, diagnostic);
    output.creation_filetime_utc = try parseCreation(creation[0..units]);
    if (output.pid != pid) return error.MetadataPidMismatch;
}

pub fn requireMatch(result: *const Result, kernel: *const kernel_process.KernelIdentity,
    parent: u32, expected_image: []const u16, expected_command: []const u16) !void
{
    if (result.image_authority != .owned_kernel_handle or result.kernel_pid != kernel.pid or
        result.kernel_creation_filetime_utc != kernel.creation_filetime_utc) return error.MetadataKernelBindingMismatch;
    if (result.pid != kernel.pid or result.parent_pid != parent) return error.MetadataParentOrPidMismatch;
    // WMI's DMTF timestamp has microsecond precision; kernel FILETIME has 100ns.
    // Equality after truncation to microseconds is the only accepted precision loss.
    if (result.creation_filetime_utc / 10 != kernel.creation_filetime_utc / 10) return error.MetadataCreationMismatch;
    if (!samePath(result.image[0..result.image_units], expected_image) or !samePath(kernel.path(), expected_image))
        return error.MetadataImageMismatch;
    if (!std.mem.eql(u16, result.command[0..result.command_units], expected_command)) return error.MetadataCommandMismatch;
}
pub fn requireImageAgreement(wmi_image: []const u16, kernel_image: []const u16) !void {
    if (!samePath(wmi_image, kernel_image)) return error.MetadataWmiImageMismatch;
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
