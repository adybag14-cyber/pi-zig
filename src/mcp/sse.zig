//! Native streaming decoder for the MCP Streamable HTTP SSE contract.
const std = @import("std");
const utf8 = @import("../durable/decode.zig");
pub const Event = struct { event: ?[]const u8 = null, data: []const u8, id: ?[]const u8 = null };
pub const Options = struct {
    max_event_bytes: usize = 16 * 1024 * 1024,
    context: ?*anyopaque = null,
    on_event: *const fn (?*anyopaque, Event) anyerror!void,
    on_id: ?*const fn (?*anyopaque, []const u8) anyerror!void = null,
    on_retry: ?*const fn (?*anyopaque, f64) anyerror!void = null,
};
pub const Parser = struct {
    gpa: std.mem.Allocator,
    options: Options,
    decoder: utf8.Decoder = .{ .drop_initial_bom = true },
    line: std.ArrayList(u8) = .empty,
    data: std.ArrayList(u8) = .empty,
    data_lines: usize = 0,
    event_name: ?[]u8 = null,
    event_id: ?[]u8 = null,
    sealed: bool = false,
    failed: ?anyerror = null,
    pub fn init(gpa: std.mem.Allocator, options: Options) Parser {
        return .{ .gpa = gpa, .options = options };
    }
    pub fn deinit(self: *Parser) void {
        self.line.deinit(self.gpa);
        self.data.deinit(self.gpa);
        if (self.event_name) |value| self.gpa.free(value);
        if (self.event_id) |value| self.gpa.free(value);
        self.* = undefined;
    }
    pub fn push(self: *Parser, bytes: []const u8) !void {
        if (self.failed) |cause| return cause;
        if (self.sealed) return error.McpSseStreamEnded;
        self.decoder.push(bytes, self) catch |cause| {
            self.failed = cause;
            return cause;
        };
    }
    pub fn finish(self: *Parser) !void {
        if (self.failed) |cause| return cause;
        if (self.sealed) return;
        self.decoder.finish(self) catch |cause| {
            self.failed = cause;
            return cause;
        };
        if (self.line.items.len > 0) self.processLine() catch |cause| {
            self.failed = cause;
            return cause;
        };
        self.dispatch() catch |cause| {
            self.failed = cause;
            return cause;
        };
        self.sealed = true;
    }
    pub fn codepoint(self: *Parser, point: u21) !void {
        if (point == '\n') {
            try self.processLine();
            return;
        }
        var bytes: [4]u8 = undefined;
        const count = try std.unicode.utf8Encode(point, &bytes);
        if (count > self.options.max_event_bytes -| self.line.items.len) return error.McpSseEventTooLarge;
        try self.line.appendSlice(self.gpa, bytes[0..count]);
    }
    fn replace(self: *Parser, destination: *?[]u8, value: []const u8) !void {
        const copied = try self.gpa.dupe(u8, value);
        if (destination.*) |old| self.gpa.free(old);
        destination.* = copied;
    }
    fn processLine(self: *Parser) !void {
        const bytes = self.line.items;
        const line = if (bytes.len > 0 and bytes[bytes.len - 1] == '\r') bytes[0 .. bytes.len - 1] else bytes;
        defer self.line.clearRetainingCapacity();
        if (line.len == 0) return self.dispatch();
        if (line[0] == ':') return;
        const colon = std.mem.indexOfScalar(u8, line, ':');
        const field = if (colon) |index| line[0..index] else line;
        var value = if (colon) |index| line[index + 1 ..] else "";
        if (value.len > 0 and value[0] == ' ') value = value[1..];
        if (std.mem.eql(u8, field, "data")) {
            const separator: usize = if (self.data_lines > 0) 1 else 0;
            const additional = std.math.add(usize, value.len, separator) catch return error.McpSseEventTooLarge;
            if (additional > self.options.max_event_bytes -| self.data.items.len) return error.McpSseEventTooLarge;
            try self.data.ensureUnusedCapacity(self.gpa, additional);
            if (separator != 0) self.data.appendAssumeCapacity('\n');
            self.data.appendSliceAssumeCapacity(value);
            self.data_lines += 1;
        } else if (std.mem.eql(u8, field, "event")) try self.replace(&self.event_name, value) else if (std.mem.eql(u8, field, "id") and std.mem.indexOfScalar(u8, value, 0) == null) {
            try self.replace(&self.event_id, value);
            if (self.options.on_id) |callback| try callback(self.options.context, value);
        } else if (std.mem.eql(u8, field, "retry") and value.len > 0) {
            for (value) |byte| if (byte < '0' or byte > '9') return;
            const millis = std.fmt.parseFloat(f64, value) catch return;
            if (self.options.on_retry) |callback| try callback(self.options.context, millis);
        }
    }
    fn dispatch(self: *Parser) !void {
        defer {
            if (self.event_name) |value| self.gpa.free(value);
            self.event_name = null;
            if (self.event_id) |value| self.gpa.free(value);
            self.event_id = null;
            self.data.clearRetainingCapacity();
            self.data_lines = 0;
        }
        if (self.data_lines == 0) return;
        try self.options.on_event(self.options.context, .{ .data = self.data.items, .event = if (self.event_name) |value| if (value.len > 0) value else null else null, .id = if (self.event_id) |value| if (value.len > 0) value else null else null });
    }
};
