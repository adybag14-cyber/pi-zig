//! Native parent callbacks for the process-wide terminal. No callback executes
//! guest code, and no extension or SDK session token grants this global lease.
const protocol = @import("process_stream_protocol.zig");
pub const Sink = struct {
    context: ?*anyopaque,
    lease: protocol.Lease,
    input_fn: *const fn (?*anyopaque, protocol.Lease, []const u8) anyerror!void,
    resize_fn: *const fn (?*anyopaque, protocol.Lease, u32, u32) anyerror!void,
    end_fn: *const fn (?*anyopaque, protocol.Lease) anyerror!void,
    pub fn matches(self: Sink, other: Sink) bool {
        return self.context == other.context and self.lease.matches(other.lease);
    }
    pub fn input(self: Sink, bytes: []const u8) !void {
        return self.input_fn(self.context, self.lease, bytes);
    }
    pub fn resize(self: Sink, columns: u32, rows: u32) !void {
        return self.resize_fn(self.context, self.lease, columns, rows);
    }
    pub fn end(self: Sink) !void {
        return self.end_fn(self.context, self.lease);
    }
};
pub const Bridge = struct {
    context: ?*anyopaque,
    guard_fn: *const fn (?*anyopaque) anyerror!void,
    metadata_fn: *const fn (?*anyopaque) anyerror!protocol.Metadata,
    control_fn: *const fn (?*anyopaque, protocol.Control) anyerror!void,
    write_fn: *const fn (?*anyopaque, protocol.Output, []const u8) anyerror!void,
    /// Attach and detach are paired before worker factories and before Runtime
    /// teardown. Detach must return only after every delivery using this sink
    /// has completed, and must prevent new deliveries to its borrowed context.
    attach_fn: ?*const fn (?*anyopaque, Sink) anyerror!void = null,
    detach_fn: ?*const fn (?*anyopaque, Sink) void = null,
    is_shift_pressed_fn: ?*const fn (?*anyopaque) anyerror!bool = null,
    enable_vt_input_fn: ?*const fn (?*anyopaque) anyerror!bool = null,
};
