//! Single-producer receipt queue. Synchronous flushes never run on the timer loop.
const std = @import("std");
const w = @import("win32.zig");
const max_record = 256 * 1024;
const slots = 8;
const max_ledger = 32 * 1024 * 1024;
const Item = struct {
    sequence: u64 = 0,
    kind: enum { append, flush_external, stop } = .append,
    length: usize = 0,
    external: ?w.H = null,
    bytes: [max_record]u8 = undefined,
};
pub const Queue = struct {
    file: w.H,
    wake: ?w.H = null,
    thread: ?w.H = null,
    items: [slots]Item = undefined,
    submitted: std.atomic.Value(u64) = .init(0),
    completed: std.atomic.Value(u64) = .init(0),
    progress_ms: std.atomic.Value(u64) = .init(0),
    failed: std.atomic.Value(bool) = .init(false),
    done: std.atomic.Value(bool) = .init(false),
    first_error: ?anyerror = null,
    bytes_submitted: usize = 0,
    stop_submitted: bool = false,
    pending_since_ms: u64 = 0,

    /// Initialize at a stable heap address. file is CREATE_NEW/non-overlapped,
    /// supervisor-owned and must remain open until this thread actually exits.
    pub fn start(self: *Queue) !void {
        if (self.thread != null or self.wake != null) return error.PersistenceAlreadyStarted;
        var flags: u32 = 0;
        if (w.GetHandleInformation(self.file, &flags) == 0 or flags & w.handle_flag_inherit != 0)
            return error.PersistenceFileInheritable;
        self.wake = w.CreateEventW(null, 0, 0, null) orelse return error.PersistenceWakeFailed;
        errdefer {
            _ = w.CloseHandle(self.wake.?);
            self.wake = null;
        }
        self.progress_ms.store(w.GetTickCount64(), .release);
        self.thread = w.CreateThread(null, 1024 * 1024, run, self, 0, null) orelse return error.PersistenceThreadFailed;
    }
    pub fn append(self: *Queue, record: []const u8) !u64 {
        if (record.len == 0 or record.len >= max_record or record[record.len - 1] != '\n')
            return error.PersistenceRecordInvalid;
        if (record.len > max_ledger - self.bytes_submitted) return error.PersistenceLedgerLimit;
        const slot = try self.reserve();
        slot.kind = .append;
        slot.external = null;
        slot.length = record.len;
        @memcpy(slot.bytes[0..record.len], record);
        self.bytes_submitted += record.len;
        return self.publish(slot);
    }
    /// Only supervisor-owned, pinned sink handles can be passed. Never accept a
    /// raw external HANDLE from worker protocol as a flush target.
    pub fn flushExternal(self: *Queue, handle: w.H) !u64 {
        const slot = try self.reserve();
        slot.kind = .flush_external;
        slot.external = handle;
        slot.length = 0;
        return self.publish(slot);
    }
    pub fn stop(self: *Queue) !u64 {
        const slot = try self.reserve();
        slot.kind = .stop;
        slot.external = null;
        slot.length = 0;
        self.stop_submitted = true;
        return self.publish(slot);
    }
    fn reserve(self: *Queue) !*Item {
        if (self.stop_submitted or self.failed.load(.acquire) or self.done.load(.acquire) or self.thread == null)
            return error.PersistenceNotAccepting;
        const produced = self.submitted.load(.monotonic);
        const consumed = self.completed.load(.acquire);
        if (produced - consumed >= slots) return error.PersistenceQueueFull;
        if (produced == consumed) self.pending_since_ms = w.GetTickCount64();
        const item = &self.items[produced % slots];
        item.sequence = produced + 1;
        return item;
    }
    fn publish(self: *Queue, item: *Item) !u64 {
        self.submitted.store(item.sequence, .release);
        if (w.SetEvent(self.wake orelse return error.PersistenceNotStarted) == 0) return error.PersistenceWakeFailed;
        return item.sequence;
    }
    pub fn acknowledged(self: *const Queue, sequence: u64) !bool {
        if (self.failed.load(.acquire)) return self.first_error orelse error.PersistenceFailed;
        return self.completed.load(.acquire) >= sequence;
    }
    pub fn requireResponsive(self: *const Queue) !void {
        if (self.failed.load(.acquire)) return self.first_error orelse error.PersistenceFailed;
        if (self.submitted.load(.acquire) != self.completed.load(.acquire) and
            w.GetTickCount64() - @max(self.progress_ms.load(.acquire), self.pending_since_ms) >= 2000)
            return error.PersistenceWatchdogExpired;
    }
    /// Never joins/disposes a blocked flush thread. State/sink survive until
    /// owner exit if this returns negative; the dedicated job is retired first.
    pub fn closeCompleted(self: *Queue) !void {
        if (!self.done.load(.acquire)) return error.PersistenceStateMustRemainAlive;
        if (self.thread) |thread| {
            if (w.WaitForSingleObject(thread, 0) != w.wait_object) return error.PersistenceThreadNotExited;
            if (w.CloseHandle(thread) == 0) return error.PersistenceThreadCloseFailed;
            self.thread = null;
        }
        if (self.wake) |wake| {
            if (w.CloseHandle(wake) == 0) return error.PersistenceWakeCloseFailed;
            self.wake = null;
        }
    }
    fn run(raw: ?*anyopaque) callconv(.winapi) u32 {
        const self: *Queue = @ptrCast(@alignCast(raw.?));
        self.consume() catch |err| {
            self.first_error = err;
            self.failed.store(true, .release);
        };
        self.done.store(true, .release);
        return 0;
    }
    fn consume(self: *Queue) !void {
        var next: u64 = 0;
        while (true) {
            while (next < self.submitted.load(.acquire)) {
                const item = &self.items[next % slots];
                if (item.sequence != next + 1) return error.PersistenceSequenceMismatch;
                self.progress_ms.store(w.GetTickCount64(), .release);
                switch (item.kind) {
                    .append => {
                        var offset: usize = 0;
                        while (offset < item.length) {
                            var count: u32 = 0;
                            const amount: u32 = @intCast(@min(item.length - offset, 65536));
                            if (w.WriteFile(self.file, item.bytes[offset..].ptr, amount, &count, null) == 0 or count == 0 or count > amount)
                                return error.PersistenceWriteFailed;
                            offset += count;
                            self.progress_ms.store(w.GetTickCount64(), .release);
                        }
                        if (w.FlushFileBuffers(self.file) == 0) return error.PersistenceFlushFailed;
                    },
                    .flush_external => {
                        if (w.FlushFileBuffers(item.external orelse return error.PersistenceFlushTargetMissing) == 0)
                            return error.OutputFlushFailed;
                    },
                    .stop => {
                        if (w.FlushFileBuffers(self.file) == 0) return error.PersistenceFinalFlushFailed;
                        self.completed.store(next + 1, .release);
                        return;
                    },
                }
                next += 1;
                self.progress_ms.store(w.GetTickCount64(), .release);
                self.completed.store(next, .release);
            }
            if (w.WaitForSingleObject(self.wake orelse return error.PersistenceWakeMissing, 250) == w.wait_failed)
                return error.PersistenceWaitFailed;
        }
    }
};
