//! Native transport capability. Callbacks receive borrowed JSON for their duration.
const protocol = @import("protocol.zig");
pub const Receiver = struct {
    context: ?*anyopaque,
    message: *const fn (?*anyopaque, protocol.Value) anyerror!void,
    failure: *const fn (?*anyopaque, anyerror) void,
    closed: *const fn (?*anyopaque) void,
};
pub const Transport = struct {
    context: *anyopaque,
    vtable: *const VTable,
    pub const VTable = struct {
        start: *const fn (*anyopaque, Receiver) anyerror!void,
        send: *const fn (*anyopaque, protocol.Value, ?*bool) anyerror!void,
        close: *const fn (*anyopaque) anyerror!void,
        protocol_version: ?*const fn (*anyopaque, []const u8) anyerror!void = null,
    };
    pub fn start(self: Transport, receiver: Receiver) !void {
        return self.vtable.start(self.context, receiver);
    }
    pub fn send(self: Transport, value: protocol.Value, abort_flag: ?*bool) !void {
        return self.vtable.send(self.context, value, abort_flag);
    }
    pub fn close(self: Transport) !void {
        return self.vtable.close(self.context);
    }
    pub fn setProtocolVersion(self: Transport, version: []const u8) !void {
        if (self.vtable.protocol_version) |callback| try callback(self.context, version);
    }
};
