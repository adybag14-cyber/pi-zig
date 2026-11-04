//! An owned clipboard task. The worker touches native data and Win32 only.
const std = @import("std");
const js = @import("native_js_values.zig");
const c = js.c;
const abi = @import("native_tui_win32_platform_abi.zig");
pub const Worker = struct {
    allocator: std.mem.Allocator,
    memory_owner: *anyopaque,
    job: *abi.Job,
    operation: abi.Operation,
    started: bool = false,

    /// The task is initially unstarted. The Promise and completion root must
    /// exist before start publishes any clipboard side effect.
    pub fn create(engine: *js.Engine, operation: abi.Operation, input: ?[]const u16) !*Worker {
        if (c.pi_js_native_memory_reserve(engine.native_memory_owner, @sizeOf(Worker)) == 0) return error.OutOfMemory;
        errdefer c.pi_js_native_memory_release(engine.native_memory_owner, @sizeOf(Worker));
        const self = try engine.gpa.create(Worker);
        errdefer engine.gpa.destroy(self);
        var failure: c_int = @intFromEnum(abi.CreateFailure.none);
        const job = abi.pi_tui_win32_clipboard_create(engine.native_memory_owner, @intFromEnum(operation),
            if (input) |units| units.ptr else null, if (input) |units| units.len else 0, &failure) orelse return switch (failure) {
            @intFromEnum(abi.CreateFailure.native_budget) => error.OutOfMemory,
            @intFromEnum(abi.CreateFailure.os_job) => error.NativeClipboardJobAllocation,
            @intFromEnum(abi.CreateFailure.os_text) => error.NativeClipboardTextCopy,
            else => error.InvalidNativeClipboardOperation,
        };
        self.* = .{ .allocator = engine.gpa, .memory_owner = engine.native_memory_owner, .job = job, .operation = operation };
        return self;
    }
    pub fn start(self: *Worker) !void {
        std.debug.assert(!self.started);
        const start_status = abi.pi_tui_win32_clipboard_start(self.job);
        if (start_status == -1) return error.OutOfMemory;
        if (start_status != 0) return error.NativeClipboardQueueUnavailable;
        self.started = true;
    }
    pub fn isDone(self: *Worker) bool {
        return self.started and abi.pi_tui_win32_clipboard_done(self.job) != 0;
    }
    pub fn join(self: *Worker) void {
        abi.pi_tui_win32_clipboard_join(self.job);
    }
    pub fn allocationFailed(self: *Worker) bool {
        return abi.pi_tui_win32_clipboard_allocation_failed(self.job) != 0;
    }
    pub fn message(self: *Worker) ?[*:0]const u8 {
        return abi.pi_tui_win32_clipboard_error(self.job);
    }
    /// Only the owner thread calls this, after its acquire observation and join.
    /// Buffer construction uses the actual same-context Node Buffer owner.
    pub fn result(self: *Worker, engine: *js.Engine) !c.JSValue {
        self.join();
        if (self.allocationFailed()) return error.OutOfMemory;
        if (self.operation == .write) return c.pi_js_undefined();
        const length = abi.pi_tui_win32_clipboard_length(self.job);
        const data = abi.pi_tui_win32_clipboard_data(self.job);
        return switch (@as(abi.Format, @enumFromInt(abi.pi_tui_win32_clipboard_format(self.job)))) {
            .unavailable => c.pi_js_undefined(),
            .empty => c.pi_js_null(),
            .utf16 => @import("native_tui_win32_value.zig").fromUtf16(engine,
                @as([*]const u16, @ptrCast(@alignCast(data orelse return error.InvalidNativeClipboardData)))[0..length]),
            .buffer => @import("native_tui_win32_value.zig").fromBytes(engine,
                @as([*]const u8, @ptrCast(data orelse return error.InvalidNativeClipboardData))[0..length]),
            // The selected complete Win32 source produces only the four
            // cases above. Other platform result formats are not fabricated.
            else => error.InvalidWin32ClipboardFormat,
        };
    }
    pub fn deinit(self: *Worker) void {
        self.join();
        const allocator = self.allocator;
        const memory_owner = self.memory_owner;
        // The C job's retained memory owner remains live through release.
        c.pi_js_native_memory_release(memory_owner, @sizeOf(Worker));
        abi.pi_tui_win32_clipboard_destroy(self.job);
        allocator.destroy(self);
    }
};
