//! Interactive status precedence and lifecycle from Pi 1.1.0.
const std = @import("std");
const protocol = @import("../tui/program_status.zig");
pub const Event = union(enum) {
    agent_start,
    assistant_end: struct { failed: bool, error_message: ?[]const u8 = null },
    compaction_start,
    compaction_end: struct { aborted: bool, manual: bool, error_message: ?[]const u8 = null },
    agent_settled: bool,
    session_info_changed,
};
const Outcome = struct { state: protocol.State, message: ?[]u8 = null };
const Blocked = struct { source: []u8, kind: protocol.Kind, message: []u8 };
pub const Reporter = struct {
    gpa: std.mem.Allocator,
    run_active: bool = false,
    compacting: bool = false,
    result: Outcome = .{ .state = .done },
    resting: Outcome = .{ .state = .idle },
    blocked: std.ArrayList(Blocked) = .empty,
    last: ?[]u8 = null,
    pub fn init(gpa: std.mem.Allocator) Reporter {
        return .{ .gpa = gpa };
    }
    fn clearOutcome(self: *Reporter, value: *Outcome) void {
        if (value.message) |message| self.gpa.free(message);
        value.message = null;
    }
    pub fn deinit(self: *Reporter) void {
        self.clearOutcome(&self.result);
        self.clearOutcome(&self.resting);
        for (self.blocked.items) |value| {
            self.gpa.free(value.source);
            self.gpa.free(value.message);
        }
        self.blocked.deinit(self.gpa);
        if (self.last) |bytes| self.gpa.free(bytes);
    }
    fn outcome(self: *Reporter, target: *Outcome, state: protocol.State, message: ?[]const u8) !void {
        const copied = if (message) |value| try self.gpa.dupe(u8, firstLine(value)) else null;
        self.clearOutcome(target);
        target.* = .{ .state = state, .message = copied };
    }
    pub fn handle(self: *Reporter, event: Event) !void {
        switch (event) {
            .agent_start => {
                try self.outcome(&self.result, .done, null);
                self.run_active = true;
            },
            .assistant_end => |value| try self.outcome(&self.result, if (value.failed) .@"error" else .done, if (value.failed) value.error_message orelse "Error" else null),
            .compaction_start => self.compacting = true,
            .compaction_end => |value| {
                if (self.run_active) {
                    if (value.aborted) try self.outcome(&self.result, .idle, null) else if (value.error_message) |message| try self.outcome(&self.result, .@"error", message);
                } else if (value.aborted) try self.outcome(&self.resting, .idle, null) else if (value.manual) try self.outcome(&self.resting, if (value.error_message != null) .@"error" else .done, value.error_message);
                self.compacting = false;
            },
            .agent_settled => |aborted| {
                const copied = if (!aborted and self.result.message != null) try self.gpa.dupe(u8, self.result.message.?) else null;
                self.clearOutcome(&self.resting);
                self.resting = .{ .state = if (aborted) .idle else self.result.state, .message = copied };
                self.run_active = false;
            },
            .session_info_changed => {},
        }
    }
    pub fn reset(self: *Reporter) void {
        self.run_active = false;
        self.compacting = false;
        self.clearOutcome(&self.result);
        self.clearOutcome(&self.resting);
        self.result.state = .done;
        self.resting.state = .idle;
    }
    pub fn setBlocked(self: *Reporter, source: []const u8, value: ?struct { kind: protocol.Kind, message: []const u8 }) !void {
        var owned: ?Blocked = null;
        if (value) |entry| {
            const name = try self.gpa.dupe(u8, source);
            errdefer self.gpa.free(name);
            const message = try self.gpa.dupe(u8, entry.message);
            errdefer self.gpa.free(message);
            try self.blocked.ensureUnusedCapacity(self.gpa, 1);
            owned = .{ .source = name, .kind = entry.kind, .message = message };
        }
        for (self.blocked.items, 0..) |entry, index| if (std.mem.eql(u8, entry.source, source)) {
            const removed = self.blocked.orderedRemove(index);
            self.gpa.free(removed.source);
            self.gpa.free(removed.message);
            break;
        };
        if (owned) |entry| self.blocked.appendAssumeCapacity(entry);
    }
    pub fn current(self: *const Reporter, session_name: ?[]const u8) protocol.Status {
        if (self.blocked.items.len > 0) {
            const value = self.blocked.items[self.blocked.items.len - 1];
            return .{ .state = .blocked, .app = "pi", .kind = value.kind, .message = value.message };
        }
        if (self.compacting) return .{ .state = .working, .app = "pi", .message = "Compacting context" };
        const state = if (self.run_active) protocol.State.working else self.resting.state;
        return .{ .state = state, .app = "pi", .message = if (state == .working or state == .done) session_name else self.resting.message };
    }
    pub fn report(self: *Reporter, session_name: ?[]const u8) !?[]u8 {
        const encoded = try protocol.format(self.gpa, self.current(session_name));
        errdefer self.gpa.free(encoded);
        if (self.last) |last| if (std.mem.eql(u8, last, encoded)) {
            self.gpa.free(encoded);
            return null;
        };
        const retained = try self.gpa.dupe(u8, encoded);
        if (self.last) |last| self.gpa.free(last);
        self.last = retained;
        return encoded;
    }
};
fn firstLine(text: []const u8) []const u8 {
    const end = std.mem.indexOfScalar(u8, text, '\n') orelse text.len;
    const value = std.mem.trim(u8, text[0..end], " \t\r\n");
    return if (value.len == 0) "Error" else value;
}
test "interactive program status reports latest response and dialog precedence across compaction and abort" {
    var reporter = Reporter.init(std.testing.allocator);
    defer reporter.deinit();
    try reporter.handle(.agent_start);
    try std.testing.expectEqual(protocol.State.working, reporter.current("session").state);
    try reporter.handle(.{ .assistant_end = .{ .failed = true, .error_message = " Failed\nprivate second line" } });
    try reporter.handle(.{ .assistant_end = .{ .failed = false } });
    try reporter.handle(.{ .agent_settled = false });
    try std.testing.expectEqual(protocol.State.done, reporter.current("session").state);
    try reporter.setBlocked("dialog", .{ .kind = .question, .message = "Question" });
    try reporter.setBlocked("login", .{ .kind = .auth, .message = "Log in" });
    try reporter.handle(.compaction_start);
    try std.testing.expectEqual(protocol.Kind.auth, reporter.current(null).kind.?);
    try reporter.setBlocked("login", null);
    try std.testing.expectEqual(protocol.Kind.question, reporter.current(null).kind.?);
    try reporter.setBlocked("dialog", null);
    try std.testing.expectEqualStrings("Compacting context", reporter.current(null).message.?);
    try reporter.handle(.{ .compaction_end = .{ .aborted = false, .manual = true, .error_message = "Error line\nprivate" } });
    try std.testing.expectEqualStrings("Error line", reporter.current(null).message.?);
    try reporter.handle(.{ .agent_settled = true });
    try std.testing.expectEqual(protocol.State.idle, reporter.current(null).state);
}

test "interactive status owner survives allocation failures in dialog replacement and retained outcomes" {
    const Check = struct {
        fn run(gpa: std.mem.Allocator) !void {
            var reporter = Reporter.init(gpa);
            defer reporter.deinit();
            try reporter.handle(.agent_start);
            try reporter.setBlocked("dialog", .{ .kind = .question, .message = "question" });
            try reporter.setBlocked("dialog", .{ .kind = .permission, .message = "permission" });
            try reporter.setBlocked("login", .{ .kind = .auth, .message = "auth" });
            const report = try reporter.report("session");
            if (report) |bytes| gpa.free(bytes);
            try reporter.handle(.{ .assistant_end = .{ .failed = true, .error_message = "failed\nprivate" } });
            try reporter.handle(.{ .agent_settled = false });
            try reporter.setBlocked("login", null);
            try reporter.setBlocked("dialog", null);
            reporter.reset();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}
