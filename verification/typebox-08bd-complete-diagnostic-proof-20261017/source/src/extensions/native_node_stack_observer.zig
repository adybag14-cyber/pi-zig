//! Test-only integer observations. Storage and reporting are owned by the host.
//! No JS dependency, allocator, formatting, IO, value ownership or guest call.
const std = @import("std");

pub const Event = enum(u8) { enter = 0, leave = 1, native_error = 2 };
pub const Record = struct {
    sequence: u64,
    callback: usize,
    // Existing native-function State allocation, one per native function.
    // An opaque correlation identity, never dereferenced by the observer.
    function_state: usize,
    frame_address: usize,
    depth: usize,
    event: u8,
};
pub const foreign_engine: u32 = 1;
pub const foreign_thread: u32 = 2;
pub const unbalanced: u32 = 4;
pub const counter_saturated: u32 = 8;
pub const suppression_unbalanced: u32 = 16;

pub const Observer = struct {
    owner_engine: usize,
    owner_thread: std.Thread.Id,
    records: []Record,
    used: usize = 0,
    depth: usize = 0,
    maximum_depth: usize = 0,
    attempted: u64 = 0,
    dropped: u64 = 0,
    native_errors: u64 = 0,
    capture_epoch: u64 = 0,
    // Only this atomic is touched when a foreign thread/engine is rejected.
    guard_flags: std.atomic.Value(u32) = .init(0),

    pub fn init(storage: []Record, engine: usize) Observer {
        return .{ .records = storage, .owner_engine = engine, .owner_thread = std.Thread.getCurrentId() };
    }
    fn accept(self: *Observer, engine: usize) bool {
        var flags: u32 = 0;
        if (engine != self.owner_engine) flags |= foreign_engine;
        if (std.Thread.getCurrentId() != self.owner_thread) flags |= foreign_thread;
        if (flags != 0) {
            _ = self.guard_flags.fetchOr(flags, .monotonic);
            return false;
        }
        return true;
    }
    fn append(self: *Observer, callback: usize, function_state: usize, frame: usize, event: Event) void {
        if (self.attempted == std.math.maxInt(u64)) {
            _ = self.guard_flags.fetchOr(counter_saturated, .monotonic);
        } else self.attempted += 1;
        if (self.used == self.records.len) {
            self.dropped +|= 1;
            return;
        }
        self.records[self.used] = .{ .sequence = self.attempted, .callback = callback, .function_state = function_state, .frame_address = frame, .depth = self.depth, .event = @intFromEnum(event) };
        self.used += 1;
    }
    pub fn enter(self: *Observer, engine: usize, callback: usize, function_state: usize, frame: usize) ?usize {
        if (!self.accept(engine)) return null;
        if (self.depth == std.math.maxInt(usize)) {
            _ = self.guard_flags.fetchOr(counter_saturated, .monotonic);
            return null;
        }
        self.depth += 1;
        self.maximum_depth = @max(self.maximum_depth, self.depth);
        self.append(callback, function_state, frame, .enter);
        return self.depth;
    }
    /// Engine.captureValue freshness only; no exception value/root is touched.
    pub fn captured(self: *Observer, engine: usize) void {
        if (!self.accept(engine)) return;
        if (self.capture_epoch == std.math.maxInt(u64)) {
            _ = self.guard_flags.fetchOr(counter_saturated, .monotonic);
            return;
        }
        self.capture_epoch += 1;
    }
    pub fn leave(self: *Observer, engine: usize, callback: usize, function_state: usize, frame: usize, entered_depth: usize, failed: bool) void {
        if (!self.accept(engine)) return;
        if (self.depth == 0 or entered_depth != self.depth) {
            _ = self.guard_flags.fetchOr(unbalanced, .monotonic);
            return;
        }
        if (failed) self.native_errors +|= 1;
        self.append(callback, function_state, frame, if (failed) .native_error else .leave);
        self.depth -= 1;
    }
    pub fn complete(self: *const Observer) bool {
        return self.depth == 0 and self.dropped == 0 and self.guard_flags.load(.monotonic) == 0;
    }
};
