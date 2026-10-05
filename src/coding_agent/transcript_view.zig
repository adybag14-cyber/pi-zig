//! Persistent fullscreen transcript: durable branch entries plus live attempts.
const std = @import("std");
const session = @import("../agent/session.zig");
const loop = @import("../agent/loop.zig");
const layout = @import("../tui/layout.zig");
const markdown = @import("../tui/markdown.zig");

pub const Anchor = struct { key: []u8, line: usize, fallback: usize };
const Block = struct {
    key: []u8,
    role: []u8,
    text: std.ArrayList(u8) = .empty,
    revision: u64 = 1,
    painted_revision: u64 = 0,
    width: usize = 0,
    row: usize = 0,
    lines: layout.RenderedLines = .{},
    live: bool = false,
    preformatted: bool = false,
    fn deinit(self: *Block, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        gpa.free(self.role);
        self.text.deinit(gpa);
        self.lines.deinit(gpa);
    }
};

pub const Transcript = struct {
    gpa: std.mem.Allocator,
    blocks: std.ArrayList(Block) = .empty,
    next_live_id: u64 = 1,
    current_message: ?usize = null,
    theme: markdown.Theme = .{},

    pub fn init(gpa: std.mem.Allocator) Transcript {
        return .{ .gpa = gpa };
    }
    pub fn deinit(self: *Transcript) void {
        for (self.blocks.items) |*block| block.deinit(self.gpa);
        self.blocks.deinit(self.gpa);
    }
    fn add(self: *Transcript, key: []const u8, role: []const u8, text: []const u8, live: bool) !usize {
        var block: Block = .{ .key = try self.gpa.dupe(u8, key), .role = undefined, .live = live };
        errdefer self.gpa.free(block.key);
        block.role = try self.gpa.dupe(u8, role);
        errdefer self.gpa.free(block.role);
        errdefer block.text.deinit(self.gpa);
        try block.text.appendSlice(self.gpa, text);
        try self.blocks.append(self.gpa, block);
        return self.blocks.items.len - 1;
    }
    fn liveBlock(self: *Transcript, role: []const u8, text: []const u8) !usize {
        var buffer: [64]u8 = undefined;
        const key = try std.fmt.bufPrint(&buffer, "live:{d}", .{self.next_live_id});
        self.next_live_id += 1;
        return self.add(key, role, text, true);
    }
    pub fn notice(self: *Transcript, text: []const u8) !void {
        var buffer: [64]u8 = undefined;
        const key = try std.fmt.bufPrint(&buffer, "notice:{d}", .{self.next_live_id});
        self.next_live_id += 1;
        _ = try self.add(key, "notice", text, false);
    }
    pub fn anchor(self: *Transcript, row: usize) !?Anchor {
        for (self.blocks.items) |block| if (row >= block.row and row < block.row + block.lines.items.len) {
            return .{ .key = try self.gpa.dupe(u8, block.key), .line = row - block.row, .fallback = row };
        };
        return null;
    }
    pub fn anchorRow(self: *Transcript, value: Anchor) usize {
        for (self.blocks.items) |block| if (std.mem.eql(u8, block.key, value.key)) return block.row + @min(value.line, block.lines.items.len -| 1);
        return value.fallback;
    }

    /// Consume a copied active branch, never the shortened provider context.
    /// Live attempts are reconciled with committed entry identities in order.
    pub fn syncBranch(self: *Transcript, entries: []const session.SessionEntry, preserved: ?*Anchor) !void {
        var replacement = Transcript.init(self.gpa);
        errdefer replacement.deinit();
        replacement.next_live_id = self.next_live_id;
        replacement.theme = self.theme;
        for (entries) |entry| {
            if (entry.entry_type == .message) {
                const role = if (std.mem.eql(u8, entry.role, "toolResult")) entry.tool_name orelse "tool" else entry.role;
                var rendered: ?*const Block = null;
                if (entry.tool_call_id) |call_id| for (self.blocks.items) |*block| {
                    if (std.mem.startsWith(u8, block.key, "tool:") and std.mem.eql(u8, block.key[5..], call_id) and block.preformatted) {
                        rendered = block;
                        break;
                    }
                };
                // Keep a renderer's owned result through live-to-durable
                // reconciliation. Its worker storage never crosses threads.
                const index = try replacement.add(entry.id, role, if (rendered) |block| block.text.items else entry.content, false);
                replacement.blocks.items[index].preformatted = rendered != null;
            } else if (entry.entry_type == .compaction or entry.entry_type == .branch_summary or (entry.entry_type == .custom_message and entry.display)) {
                _ = try replacement.add(entry.id, @tagName(entry.entry_type), entry.content, false);
            }
        }
        if (preserved) |value| {
            var live_count: usize = 0;
            for (self.blocks.items) |block| if (block.live) {
                live_count += 1;
            };
            var index: usize = 0;
            for (self.blocks.items) |block| if (block.live) {
                if (std.mem.eql(u8, block.key, value.key) and live_count <= replacement.blocks.items.len) {
                    const committed = replacement.blocks.items[replacement.blocks.items.len - live_count + index].key;
                    const key = try self.gpa.dupe(u8, committed);
                    self.gpa.free(value.key);
                    value.key = key;
                }
                index += 1;
            };
        }
        for (self.blocks.items) |block| if (std.mem.startsWith(u8, block.key, "notice:")) {
            _ = try replacement.add(block.key, block.role, block.text.items, false);
        };
        self.deinit();
        self.* = replacement;
    }

    pub fn event(self: *Transcript, value: loop.AgentEvent) !void {
        return self.eventWithRendered(value, false);
    }
    pub fn eventWithRendered(self: *Transcript, value: loop.AgentEvent, preformatted: bool) !void {
        switch (value.kind) {
            .message_start => self.current_message = try self.liveBlock(if (value.name.len == 0) "assistant" else value.name, value.text),
            .message_update => {
                const index = self.current_message orelse try self.liveBlock("assistant", "");
                self.current_message = index;
                try self.blocks.items[index].text.appendSlice(self.gpa, value.text);
                self.blocks.items[index].revision += 1;
            },
            .message_end => if (self.current_message) |index| {
                self.blocks.items[index].text.clearRetainingCapacity();
                try self.blocks.items[index].text.appendSlice(self.gpa, value.text);
                self.blocks.items[index].revision += 1;
                self.current_message = null;
            },
            .tool_execution_start, .tool_execution_update, .tool_execution_end => {
                const key = try std.fmt.allocPrint(self.gpa, "tool:{s}", .{value.id});
                defer self.gpa.free(key);
                var found: ?usize = null;
                for (self.blocks.items, 0..) |block, index| if (std.mem.eql(u8, block.key, key)) {
                    found = index;
                    break;
                };
                const text = if (value.kind == .tool_execution_start and !preformatted) value.args_json else value.text;
                const index = found orelse try self.add(key, if (value.name.len > 0) value.name else "tool", "", true);
                self.blocks.items[index].text.clearRetainingCapacity();
                try self.blocks.items[index].text.appendSlice(self.gpa, text);
                self.blocks.items[index].revision += 1;
                self.blocks.items[index].preformatted = preformatted;
            },
            .auto_retry_start, .auto_retry_end, .session_compact_failed => try self.notice(value.error_message orelse value.text),
            else => {}, // Legacy aliases must not duplicate canonical content.
        }
    }

    pub fn component(self: *Transcript) layout.Component {
        return .{ .context = self, .vtable = &.{ .render = renderOpaque } };
    }
    fn renderOpaque(raw: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Transcript = @ptrCast(@alignCast(raw));
        var output: std.ArrayList([]u8) = .empty;
        errdefer {
            for (output.items) |line| gpa.free(line);
            output.deinit(gpa);
        }
        var row: usize = 0;
        for (self.blocks.items) |*block| {
            if (block.width != width or block.painted_revision != block.revision) {
                var lines: std.ArrayList([]u8) = .empty;
                errdefer {
                    for (lines.items) |line| self.gpa.free(line);
                    lines.deinit(self.gpa);
                }
                const heading = try std.fmt.allocPrint(self.gpa, "\x1b[1m{s}\x1b[0m", .{block.role});
                lines.append(self.gpa, heading) catch |err| {
                    self.gpa.free(heading);
                    return err;
                };
                if (block.preformatted) {
                    var iterator = std.mem.splitScalar(u8, std.mem.trimEnd(u8, block.text.items, "\n"), '\n');
                    while (iterator.next()) |line| try appendLine(self.gpa, &lines, line);
                } else {
                    var rendered = try markdown.render(self.gpa, block.text.items, width, self.theme, .{}, .{ .hyperlinks = true });
                    defer rendered.deinit(self.gpa);
                    for (rendered.lines) |line| try appendLine(self.gpa, &lines, line);
                }
                block.lines.deinit(self.gpa);
                block.lines = .{ .items = try lines.toOwnedSlice(self.gpa) };
                block.width = width;
                block.painted_revision = block.revision;
            }
            block.row = row;
            row += block.lines.items.len;
            for (block.lines.items) |line| {
                const owned = try gpa.dupe(u8, line);
                output.append(gpa, owned) catch |err| {
                    gpa.free(owned);
                    return err;
                };
            }
        }
        return .{ .items = try output.toOwnedSlice(gpa) };
    }
};

fn appendLine(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), value: []const u8) !void {
    const owned = try gpa.dupe(u8, value);
    errdefer gpa.free(owned);
    try lines.append(gpa, owned);
}
