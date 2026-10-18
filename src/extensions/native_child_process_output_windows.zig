//! Engine-independent, bounded overlapped output-read ownership. A pending kernel
//! request retains its stable slot until actual completion, including teardown.
const std = @import("std");
const w = std.os.windows;
const capacity = 32;
pub const chunk_size = 64 * 1024;
const Overlapped = extern struct {
    internal: usize = 0,
    internal_high: usize = 0,
    offset: u32 = 0,
    offset_high: u32 = 0,
    event: ?w.HANDLE = null,
};
pub const Slot = struct {
    // reserved/quarantined/generation are protected by registry.lock. All other
    // members have exactly one owner: pump, then watcher after quarantine.
    reserved: bool = false,
    quarantined: bool = false,
    generation: u64 = 0,
    endpoint: ?w.HANDLE = null,
    event: ?w.HANDLE = null,
    operation: Overlapped = .{},
    pending: bool = false,
    operation_kind: enum { connect, read } = .connect,
    chunk: [chunk_size]u8 = undefined,

    fn prepare(self: *Slot) !void {
        std.debug.assert(!self.pending);
        if (api.ResetEvent(self.event.?) == 0) return error.NativeChildOutputEventFailed;
        self.operation = .{ .event = self.event };
    }
    /// null means the exact operation is still pending. A connect's returned
    /// byte count is undefined and the caller deliberately ignores it.
    pub fn completion(self: *Slot) !?usize {
        if (!self.pending) return error.NativeChildOutputNoPendingOperation;
        var transferred: u32 = 0;
        if (api.GetOverlappedResult(self.endpoint.?, &self.operation, &transferred, 0) != 0) {
            self.pending = false;
            if (self.operation_kind == .read and transferred > chunk_size) return error.NativeChildOutputReadProgressInvalid;
            return transferred;
        }
        const code = lastError();
        if (code == 996) return null; // ERROR_IO_INCOMPLETE
        // A metadata/API error is not permission to free a request which the
        // kernel still marks STATUS_PENDING. Preserve it for bounded retirement.
        const internal: *volatile usize = &self.operation.internal;
        if (internal.* == 0x103) return null;
        self.pending = false; // the operation has completed with an error
        return self.operationError(code);
    }
    fn operationError(self: *Slot, code: u32) anyerror {
        return switch (code) {
            109 => if (self.operation_kind == .read) error.EndOfStream else error.NativeChildOutputConnectFailed,
            995 => error.NativeChildOutputOperationAborted,
            232 => error.NativeChildOutputPipeClosing,
            233 => error.NativeChildOutputNotConnected,
            else => error.NativeChildOutputReadFailed,
        };
    }
    /// One bounded overlapped read. Zero successful bytes are no progress, not
    /// EOF: a zero-length producer write can complete a pipe read that way.
    pub fn beginRead(self: *Slot) !?usize {
        std.debug.assert(!self.pending);
        self.operation_kind = .read;
        try self.prepare();
        // Overlapped ReadFile's optional count is not an async progress source,
        // even when it returns TRUE. Observe the actual operation in both cases.
        const immediate = api.ReadFile(self.endpoint.?, &self.chunk, chunk_size, null, &self.operation) != 0;
        const code = if (immediate) @as(u32, 0) else lastError();
        if (immediate or code == 997) {
            self.pending = true;
            return self.completion();
        }
        const internal: *volatile usize = &self.operation.internal;
        if (internal.* == 0x103) { self.pending = true; return error.NativeChildOutputCompletionUnconfirmed; }
        return self.operationError(code);
    }
    pub fn bytes(self: *Slot, count: usize) []const u8 {
        std.debug.assert(!self.pending and count <= chunk_size);
        return self.chunk[0..count];
    }
    /// Owner-thread adapters use these nonblocking primitives instead of the
    /// synchronous retire loop. The caller must retain this slot until completion
    /// or transfer it exactly once to quarantine, then forget the pointer.
    pub fn requestCancellation(self: *Slot) void {
        if (self.pending) _ = api.CancelIoEx(self.endpoint.?, &self.operation);
    }
    pub fn quarantine(self: *Slot) void {
        std.debug.assert(self.pending);
        api.AcquireSRWLockExclusive(&registry.lock);
        defer api.ReleaseSRWLockExclusive(&registry.lock);
        self.quarantined = true;
        if (api.SetEvent(registry.wake.?) == 0) registry.watcher_failed = true;
    }
    /// true means all resources retired; false transfers ownership to the
    /// process-lifetime watcher. The caller must forget this pointer either way.
    pub fn retire(self: *Slot) bool {
        if (self.pending) {
            self.requestCancellation();
            const started = api.GetTickCount64();
            while (self.pending) {
                _ = self.completion() catch null;
                if (!self.pending) break;
                const elapsed = api.GetTickCount64() -| started;
                if (elapsed >= 250 or api.WaitForSingleObject(self.event.?, 0) == 0) {
                    _ = self.completion() catch null;
                    if (!self.pending) break;
                    self.quarantine();
                    return false;
                }
                _ = api.WaitForSingleObject(self.event.?, @intCast(@min(@as(u64, 5), 250 - elapsed)));
            }
        }
        release(self);
        return true;
    }
};
const Registry = struct {
    lock: w.SRWLOCK = .{},
    slots: [capacity]Slot = .{.{}} ** capacity,
    wake: ?w.HANDLE = null,
    initialized: bool = false,
    watcher_failed: bool = false,
};
// Static storage and OS SRW lock deliberately outlive every Engine. No Engine
// allocator, std.Io mutex/cancel scope, JS value or callback reaches the watcher.
var registry: Registry = .{};
pub fn monotonicMilliseconds() u64 { return api.GetTickCount64(); }
pub const Snapshot = struct { reserved: usize = 0, quarantined: usize = 0, watcher_initialized: bool = false, watcher_failed: bool = false };
/// Native owner diagnostics only: no bytes, pipe name, SID, guest value or PID.
pub fn snapshot() Snapshot {
    api.AcquireSRWLockExclusive(&registry.lock);
    defer api.ReleaseSRWLockExclusive(&registry.lock);
    var result: Snapshot = .{ .watcher_initialized = registry.initialized, .watcher_failed = registry.watcher_failed };
    for (&registry.slots) |*slot| { result.reserved += @intFromBool(slot.reserved); result.quarantined += @intFromBool(slot.quarantined); }
    return result;
}
fn lastError() u32 { return @intFromEnum(w.GetLastError()); }
fn release(slot: *Slot) void {
    if (slot.endpoint) |handle| w.CloseHandle(handle);
    slot.endpoint = null;
    std.crypto.secureZero(u8, &slot.chunk);
    api.AcquireSRWLockExclusive(&registry.lock);
    defer api.ReleaseSRWLockExclusive(&registry.lock);
    slot.quarantined = false;
    slot.reserved = false;
}
fn watch() void {
    while (true) {
        var handles: [capacity + 1]w.HANDLE = undefined;
        var slots: [capacity]*Slot = undefined;
        var generations: [capacity]u64 = undefined;
        var count: usize = 1;
        api.AcquireSRWLockExclusive(&registry.lock);
        handles[0] = registry.wake.?;
        if (api.ResetEvent(handles[0]) == 0) {
            registry.watcher_failed = true;
            api.ReleaseSRWLockExclusive(&registry.lock);
            return;
        }
        for (&registry.slots) |*slot| if (slot.quarantined) {
            handles[count] = slot.event.?;
            slots[count - 1] = slot;
            generations[count - 1] = slot.generation;
            count += 1;
        };
        api.ReleaseSRWLockExclusive(&registry.lock);
        const selected = api.WaitForMultipleObjects(@intCast(count), &handles, 0, 0xffffffff);
        if (selected == 0xffffffff) {
            api.AcquireSRWLockExclusive(&registry.lock);
            registry.watcher_failed = true;
            api.ReleaseSRWLockExclusive(&registry.lock);
            return; // retain pending storage; reject new admission
        }
        if (selected == 0 or selected >= count) continue;
        const slot = slots[selected - 1];
        api.AcquireSRWLockExclusive(&registry.lock);
        const owns = slot.quarantined and slot.generation == generations[selected - 1];
        api.ReleaseSRWLockExclusive(&registry.lock);
        if (!owns) continue;
        _ = slot.completion() catch null;
        if (!slot.pending) release(slot) else {
            // A signaled event with a still-pending operation violates the
            // completion invariant. Retain storage and degrade admission;
            // repeatedly waiting on this signaled event would busy-spin.
            api.AcquireSRWLockExclusive(&registry.lock);
            registry.watcher_failed = true;
            api.ReleaseSRWLockExclusive(&registry.lock);
            return;
        }
    }
}
/// Reserve the complete requested output set atomically before any connection
/// or process launch. Caller owns all returned slots until successful transfer.
pub fn reserveSet(requested: [2]bool) ![2]?*Slot {
    const needed: usize = @as(usize, @intFromBool(requested[0])) + @as(usize, @intFromBool(requested[1]));
    if (needed == 0) return .{ null, null };
    api.AcquireSRWLockExclusive(&registry.lock);
    defer api.ReleaseSRWLockExclusive(&registry.lock);
    if (!registry.initialized) {
        var made: usize = 0;
        errdefer {
            for (registry.slots[0..made]) |*slot| w.CloseHandle(slot.event.?);
            for (&registry.slots) |*slot| slot.event = null;
            if (registry.wake) |event| w.CloseHandle(event);
            registry.wake = null;
        }
        registry.wake = api.CreateEventW(null, 1, 0, null) orelse return error.NativeChildOutputEventFailed;
        for (&registry.slots) |*slot| {
            slot.event = api.CreateEventW(null, 1, 0, null) orelse return error.NativeChildOutputEventFailed;
            made += 1;
        }
        const watcher = try std.Thread.spawn(.{ .stack_size = 128 * 1024, .allocator = std.heap.page_allocator }, watch, .{});
        watcher.detach();
        registry.initialized = true;
    }
    if (registry.watcher_failed) return error.NativeChildOutputRetirementWatcherFailed;
    var available: usize = 0;
    for (&registry.slots) |*slot| if (!slot.reserved) { available += 1; };
    if (available < needed) return error.NativeChildOutputRetirementCapacity;
    var result: [2]?*Slot = .{ null, null };
    for (requested, 0..) |wanted, index| if (wanted) {
        for (&registry.slots) |*slot| if (!slot.reserved) {
            slot.reserved = true;
            slot.generation +%= 1;
            slot.pending = false;
            slot.quarantined = false;
            slot.operation_kind = .connect;
            slot.operation = .{ .event = slot.event };
            result[index] = slot;
            break;
        };
    };
    return result;
}
pub const Connected = struct { slot: *Slot, child: w.HANDLE };
const Descriptor = extern struct {
    revision: u8 = 0, sbz1: u8 = 0, control: u16 = 0,
    owner: ?*anyopaque = null, group: ?*anyopaque = null,
    sacl: ?*anyopaque = null, dacl: ?*anyopaque = null,
};
const TokenUser = extern struct { sid: *anyopaque, attributes: u32 };
/// All security metadata remains in this frame until the kernel copies it. A
/// process user token is used only when the thread has no impersonation token.
pub fn connect(slot: *Slot) !Connected {
    var thread_token: w.HANDLE = undefined;
    if (api.OpenThreadToken(api.GetCurrentThread(), 8, 1, &thread_token) != 0) {
        w.CloseHandle(thread_token);
        return error.NativeChildOutputThreadImpersonationUnsupported;
    }
    if (lastError() != 1008) return error.NativeChildOutputTokenFailed;
    var token: w.HANDLE = undefined;
    if (api.OpenProcessToken(api.GetCurrentProcess(), 8, &token) == 0) return error.NativeChildOutputTokenFailed;
    defer w.CloseHandle(token);
    var required: u32 = 0;
    _ = api.GetTokenInformation(token, 1, null, 0, &required);
    if (required < @sizeOf(TokenUser)) return error.NativeChildOutputTokenFailed;
    const token_words = try std.heap.page_allocator.alloc(usize, std.math.divCeil(usize, required, @sizeOf(usize)) catch return error.NativeChildOutputTokenFailed);
    defer std.heap.page_allocator.free(token_words);
    if (api.GetTokenInformation(token, 1, @ptrCast(token_words.ptr), required, &required) == 0) return error.NativeChildOutputTokenFailed;
    const user: *const TokenUser = @ptrCast(token_words.ptr);
    const sid_length = api.GetLengthSid(user.sid);
    if (sid_length == 0) return error.NativeChildOutputTokenFailed;
    const acl_size: u32 = 8 + 8 + sid_length;
    const acl_words = try std.heap.page_allocator.alloc(usize, std.math.divCeil(usize, acl_size, @sizeOf(usize)) catch return error.NativeChildOutputTokenFailed);
    defer std.heap.page_allocator.free(acl_words);
    const acl: *anyopaque = @ptrCast(acl_words.ptr);
    if (api.InitializeAcl(acl, acl_size, 2) == 0 or api.AddAccessAllowedAceEx(acl, 2, 0, 0x001f01ff, user.sid) == 0) return error.NativeChildOutputAclFailed;
    var descriptor: Descriptor = .{};
    if (api.InitializeSecurityDescriptor(&descriptor, 1) == 0 or api.SetSecurityDescriptorOwner(&descriptor, user.sid, 0) == 0 or api.SetSecurityDescriptorDacl(&descriptor, 1, acl, 0) == 0 or api.SetSecurityDescriptorControl(&descriptor, 0x1000, 0x1000) == 0) return error.NativeChildOutputAclFailed;
    var attributes: w.SECURITY_ATTRIBUTES = .{ .nLength = @sizeOf(w.SECURITY_ATTRIBUTES), .lpSecurityDescriptor = &descriptor, .bInheritHandle = .FALSE };
    var random: [32]u8 = undefined;
    if (api.BCryptGenRandom(null, &random, random.len, 2) < 0) return error.NativeChildOutputEntropyFailed;
    var name: [128:0]u16 = undefined;
    const prefix = std.unicode.utf8ToUtf16LeStringLiteral("\\\\.\\pipe\\pi-zig-output-");
    @memcpy(name[0..prefix.len], prefix);
    const digits = "0123456789abcdef";
    for (random, 0..) |byte, i| { name[prefix.len + i * 2] = digits[byte >> 4]; name[prefix.len + i * 2 + 1] = digits[byte & 15]; }
    name[prefix.len + random.len * 2] = 0;
    // The reserving spawn frame retains ownership on every error, including
    // security/entropy failure before a kernel endpoint has been created.
    return connectSlot(slot, &name, &attributes);
}
fn connectSlot(slot: *Slot, name: [*:0]const u16, attributes: *w.SECURITY_ATTRIBUTES) !Connected {
    const server = api.CreateNamedPipeW(name, 0x40080001, 0x00000008, 1, 0, chunk_size, 0, attributes);
    if (server == w.INVALID_HANDLE_VALUE) return error.NativeChildOutputPipeFailed;
    slot.endpoint = server;
    try slot.prepare();
    const started = api.GetTickCount64();
    if (api.ConnectNamedPipe(server, &slot.operation) == 0) switch (lastError()) {
        535 => {}, // ERROR_PIPE_CONNECTED: immediate completion, no byte count
        997 => slot.pending = true,
        else => return error.NativeChildOutputConnectFailed,
    };
    const child = api.CreateFileW(name, 0x40000000, 0, attributes, 3, 0x00110000, null);
    if (child == w.INVALID_HANDLE_VALUE) return if (api.GetTickCount64() -| started >= 1000) error.NativeChildOutputConnectTimedOut else error.NativeChildOutputConnectFailed;
    errdefer w.CloseHandle(child);
    if (api.GetTickCount64() -| started >= 1000) return error.NativeChildOutputConnectTimedOut;
    while (slot.pending) {
        _ = try slot.completion(); // connect count is deliberately ignored
        if (!slot.pending) break;
        if (api.WaitForSingleObject(slot.event.?, 0) == 0) {
            _ = try slot.completion();
            if (slot.pending) return error.NativeChildOutputConnectCompletionInconsistent;
            break;
        }
        const elapsed = api.GetTickCount64() -| started;
        if (elapsed >= 1000) return error.NativeChildOutputConnectTimedOut;
        _ = api.WaitForSingleObject(slot.event.?, @intCast(@min(@as(u64, 5), 1000 - elapsed)));
    }
    var client_pid: u32 = 0;
    if (api.GetNamedPipeClientProcessId(server, &client_pid) == 0 or client_pid != api.GetCurrentProcessId()) return error.NativeChildOutputUnexpectedClient;
    if (api.SetHandleInformation(child, 1, 1) == 0) return error.NativeChildOutputInheritanceFailed;
    return .{ .slot = slot, .child = child };
}
const api = struct {
    extern "kernel32" fn AcquireSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn ReleaseSRWLockExclusive(*w.SRWLOCK) callconv(.winapi) void;
    extern "kernel32" fn CreateEventW(?*w.SECURITY_ATTRIBUTES, i32, i32, ?[*:0]const u16) callconv(.winapi) ?w.HANDLE;
    extern "kernel32" fn ResetEvent(w.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn SetEvent(w.HANDLE) callconv(.winapi) i32;
    extern "kernel32" fn WaitForSingleObject(w.HANDLE, u32) callconv(.winapi) u32;
    extern "kernel32" fn WaitForMultipleObjects(u32, [*]const w.HANDLE, i32, u32) callconv(.winapi) u32;
    extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    extern "kernel32" fn GetCurrentProcess() callconv(.winapi) w.HANDLE;
    extern "kernel32" fn GetCurrentThread() callconv(.winapi) w.HANDLE;
    extern "kernel32" fn GetCurrentProcessId() callconv(.winapi) u32;
    extern "kernel32" fn CreateNamedPipeW([*:0]const u16, u32, u32, u32, u32, u32, u32, *w.SECURITY_ATTRIBUTES) callconv(.winapi) w.HANDLE;
    extern "kernel32" fn CreateFileW([*:0]const u16, u32, u32, *w.SECURITY_ATTRIBUTES, u32, u32, ?w.HANDLE) callconv(.winapi) w.HANDLE;
    extern "kernel32" fn ConnectNamedPipe(w.HANDLE, *Overlapped) callconv(.winapi) i32;
    extern "kernel32" fn GetNamedPipeClientProcessId(w.HANDLE, *u32) callconv(.winapi) i32;
    extern "kernel32" fn SetHandleInformation(w.HANDLE, u32, u32) callconv(.winapi) i32;
    extern "kernel32" fn ReadFile(w.HANDLE, *anyopaque, u32, ?*u32, *Overlapped) callconv(.winapi) i32;
    extern "kernel32" fn GetOverlappedResult(w.HANDLE, *Overlapped, *u32, i32) callconv(.winapi) i32;
    extern "kernel32" fn CancelIoEx(w.HANDLE, *Overlapped) callconv(.winapi) i32;
    extern "advapi32" fn OpenProcessToken(w.HANDLE, u32, *w.HANDLE) callconv(.winapi) i32;
    extern "advapi32" fn OpenThreadToken(w.HANDLE, u32, i32, *w.HANDLE) callconv(.winapi) i32;
    extern "advapi32" fn GetTokenInformation(w.HANDLE, u32, ?*anyopaque, u32, *u32) callconv(.winapi) i32;
    extern "advapi32" fn GetLengthSid(*anyopaque) callconv(.winapi) u32;
    extern "advapi32" fn InitializeAcl(*anyopaque, u32, u32) callconv(.winapi) i32;
    extern "advapi32" fn AddAccessAllowedAceEx(*anyopaque, u32, u32, u32, *anyopaque) callconv(.winapi) i32;
    extern "advapi32" fn InitializeSecurityDescriptor(*Descriptor, u32) callconv(.winapi) i32;
    extern "advapi32" fn SetSecurityDescriptorOwner(*Descriptor, *anyopaque, i32) callconv(.winapi) i32;
    extern "advapi32" fn SetSecurityDescriptorDacl(*Descriptor, i32, *anyopaque, i32) callconv(.winapi) i32;
    extern "advapi32" fn SetSecurityDescriptorControl(*Descriptor, u16, u16) callconv(.winapi) i32;
    extern "bcrypt" fn BCryptGenRandom(?*anyopaque, *[32]u8, u32, u32) callconv(.winapi) i32;
};
