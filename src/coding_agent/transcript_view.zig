//! Persistent fullscreen transcript: durable branch entries plus live attempts.
const std = @import("std");
const session = @import("../agent/session.zig");
const loop = @import("../agent/loop.zig");
const layout = @import("../tui/layout.zig");
const markdown = @import("../tui/markdown.zig");
pub const renderer_rows = @import("renderer_rows.zig");

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
    tool_call_id: ?[]u8 = null,
    call_text: std.ArrayList(u8) = .empty,
    has_result: bool = false,
    tools_expansion_revision: u64 = 0,
    fn deinit(self: *Block, gpa: std.mem.Allocator) void {
        gpa.free(self.key);
        gpa.free(self.role);
        self.text.deinit(gpa);
        self.lines.deinit(gpa);
        if (self.tool_call_id) |id| gpa.free(id);
        self.call_text.deinit(gpa);
    }
};

pub const Transcript = struct {
    gpa: std.mem.Allocator,
    blocks: std.ArrayList(Block) = .empty,
    next_live_id: u64 = 1,
    current_message: ?usize = null,
    theme: markdown.Theme = .{},
    renderers: renderer_rows.Rows,
    tools_expanded: bool = false,
    tools_expansion_revision: u64 = 0,
    tools_expand_hint: []const u8 = "ctrl+o",
    palette: ?@import("../tui/theme_palette.zig").Palette = null,
    theme_signature: ?[]u8 = null,

    pub fn setThemeState(self: *Transcript, raw: ?[]const u8) !void {
        const value = raw orelse return;
        if (self.theme_signature) |old| if (std.mem.eql(u8, old, value)) return;
        var prepared = try @import("../tui/theme_palette.zig").Palette.fromState(self.gpa, value);
        errdefer prepared.deinit();
        const signature = try self.gpa.dupe(u8, value);
        if (self.palette) |*old| old.deinit();
        if (self.theme_signature) |old| self.gpa.free(old);
        self.palette = prepared;
        self.theme_signature = signature;
        const palette = &self.palette.?;
        self.theme = .{
            .heading_sgr = parameters(palette.get("mdHeading")),
            .link_sgr = parameters(palette.get("mdLink")),
            .link_url_sgr = parameters(palette.get("mdLinkUrl")),
            .code_sgr = parameters(palette.get("mdCode")),
            .code_block_sgr = parameters(palette.get("mdCodeBlock")),
            .code_border_sgr = parameters(palette.get("mdCodeBlockBorder")),
            .quote_sgr = parameters(palette.get("mdQuote")),
            .quote_border_sgr = parameters(palette.get("mdQuoteBorder")),
            .hr_sgr = parameters(palette.get("mdHr")),
            .list_bullet_sgr = parameters(palette.get("mdListBullet")),
        };
        for (self.blocks.items) |*block| block.revision += 1;
    }
    fn parameters(ansi: []const u8) []const u8 {
        const begin = std.mem.lastIndexOf(u8, ansi, "\x1b[") orelse return "";
        return if (std.mem.endsWith(u8, ansi, "m")) ansi[begin + 2 .. ansi.len - 1] else "";
    }

    pub fn setToolsExpanded(self: *Transcript, expanded: bool) void {
        if (self.tools_expanded == expanded) return;
        self.applyToolsExpansion(expanded, self.tools_expansion_revision +| 1);
    }
    pub fn applyToolsExpansion(self: *Transcript, expanded: bool, revision: u64) void {
        if (self.tools_expanded == expanded and self.tools_expansion_revision == revision) return;
        self.tools_expanded = expanded;
        self.tools_expansion_revision = revision;
        for (self.renderers.rows.items) |*row| if (!row.retired) {
            row.expanded = expanded;
        };
        for (self.blocks.items) |*block| if (block.tool_call_id != null) {
            block.revision += 1;
        };
    }

    pub fn init(gpa: std.mem.Allocator) Transcript {
        return .{ .gpa = gpa, .renderers = .init(gpa) };
    }
    pub fn deinit(self: *Transcript) void {
        for (self.blocks.items) |*block| block.deinit(self.gpa);
        self.blocks.deinit(self.gpa);
        self.renderers.deinit();
        if (self.palette) |*value| value.deinit();
        if (self.theme_signature) |value| self.gpa.free(value);
    }
    fn add(self: *Transcript, key: []const u8, role: []const u8, text: []const u8, live: bool) !usize {
        var block: Block = .{ .key = try self.gpa.dupe(u8, key), .role = undefined, .live = live, .tools_expansion_revision = self.tools_expansion_revision };
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
        replacement.tools_expanded = self.tools_expanded;
        replacement.tools_expansion_revision = self.tools_expansion_revision;
        replacement.tools_expand_hint = self.tools_expand_hint;
        for (entries) |entry| {
            if (entry.entry_type == .message) {
                var previous_tool: ?*const Block = null;
                if (entry.tool_call_id) |id| for (self.blocks.items) |*block| if (block.tool_call_id) |previous| {
                    if (std.mem.eql(u8, id, previous)) {
                        previous_tool = block;
                        break;
                    }
                };
                const role = if (std.mem.eql(u8, entry.role, "toolResult")) entry.tool_name orelse if (previous_tool) |block| block.role else "tool" else entry.role;
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
                if (entry.tool_call_id) |id| {
                    replacement.blocks.items[index].tool_call_id = try self.gpa.dupe(u8, id);
                    replacement.blocks.items[index].has_result = true;
                    if (previous_tool) |block| {
                        try replacement.blocks.items[index].call_text.appendSlice(self.gpa, block.call_text.items);
                        replacement.blocks.items[index].tools_expansion_revision = block.tools_expansion_revision;
                    }
                }
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
        // Renderer DTOs belong to tool identities, independent of a live row's
        // transition to its durable entry ID. Move only after fallible cloning.
        replacement.renderers = self.renderers;
        self.renderers = .init(self.gpa);
        replacement.palette = self.palette;
        self.palette = null;
        replacement.theme_signature = self.theme_signature;
        self.theme_signature = null;
        self.deinit();
        self.* = replacement;
        for (self.renderers.rows.items) |*row| if (row.attached and !self.hasToolRow(row.fence.tool_call_id)) self.renderers.detach(row);
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
                if (self.blocks.items[index].tool_call_id == null) self.blocks.items[index].tool_call_id = try self.gpa.dupe(u8, value.id);
                if (value.kind == .tool_execution_start) {
                    self.blocks.items[index].call_text.clearRetainingCapacity();
                    try self.blocks.items[index].call_text.appendSlice(self.gpa, text);
                    self.blocks.items[index].has_result = false;
                } else self.blocks.items[index].has_result = true;
                self.blocks.items[index].text.clearRetainingCapacity();
                try self.blocks.items[index].text.appendSlice(self.gpa, text);
                self.blocks.items[index].revision += 1;
                self.blocks.items[index].preformatted = preformatted;
                if (self.renderers.find(value.id)) |row| row.attached = true;
            },
            .auto_retry_start, .auto_retry_end, .session_compact_failed => try self.notice(value.error_message orelse value.text),
            else => {}, // Legacy aliases must not duplicate canonical content.
        }
    }

    pub fn component(self: *Transcript) layout.Component {
        return .{ .context = self, .vtable = &.{ .render = renderOpaque } };
    }
    pub fn adoptRenderer(self: *Transcript, record: *renderer_rows.protocol.Record) !bool {
        // The record may precede its canonical tool event. Retain the lease,
        // but never synthesize a transcript block from a renderer registration.
        const row_id = record.fence.tool_call_id;
        const changed = try self.renderers.adopt(record);
        if (changed) for (self.blocks.items) |*block| if (block.tool_call_id) |id| {
            if (std.mem.eql(u8, id, row_id)) {
                block.revision += 1;
                if (self.renderers.find(id)) |row| row.attached = true;
            }
        };
        return changed;
    }
    pub fn closeRendererOwner(self: *Transcript, generation: u64) bool {
        if (!self.renderers.closeOwner(generation)) return false;
        for (self.blocks.items) |*block| if (block.tool_call_id != null) {
            block.revision += 1;
        };
        return true;
    }
    pub fn hasToolRow(self: *const Transcript, id: []const u8) bool {
        for (self.blocks.items) |block| if (block.tool_call_id) |value| {
            if (std.mem.eql(u8, id, value)) return true;
        };
        return false;
    }
    pub fn toolExpansionRevision(self: *const Transcript, id: []const u8) u64 {
        for (self.blocks.items) |block| if (block.tool_call_id) |value| {
            if (std.mem.eql(u8, id, value)) return block.tools_expansion_revision;
        };
        return self.tools_expansion_revision;
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
                if (block.tool_call_id == null) {
                    const heading = try std.fmt.allocPrint(self.gpa, "\x1b[1m{s}\x1b[0m", .{block.role});
                    lines.append(self.gpa, heading) catch |err| {
                        self.gpa.free(heading);
                        return err;
                    };
                }
                const renderer = if (block.tool_call_id) |id| self.renderers.find(id) else null;
                if (renderer != null and !renderer.?.retired and (std.mem.eql(u8, renderer.?.tool_name, block.role) or std.mem.eql(u8, block.role, "tool"))) {
                    if (renderer.?.lines(.call, width)) |owned| {
                        for (owned) |line| try appendLine(self.gpa, &lines, line);
                    } else try self.appendToolCall(&lines, block, width, renderer.?.expanded);
                    if (block.has_result) {
                        if (renderer.?.lines(.result, width)) |owned| {
                            for (owned) |line| try appendLine(self.gpa, &lines, line);
                        } else try self.appendToolOutput(&lines, block.text.items, width, renderer.?.expanded);
                    }
                    if (renderer.?.diagnostic) |diagnostic| {
                        const message = try std.fmt.allocPrint(self.gpa, "Renderer failed: {s}", .{diagnostic.text});
                        defer self.gpa.free(message);
                        try appendLine(self.gpa, &lines, message);
                    }
                } else if (block.preformatted) {
                    var iterator = std.mem.splitScalar(u8, std.mem.trimEnd(u8, block.text.items, "\n"), '\n');
                    while (iterator.next()) |line| try appendLine(self.gpa, &lines, line);
                } else if (block.tool_call_id != null and block.has_result) {
                    try self.appendGenericTool(&lines, block, width);
                } else if (block.tool_call_id != null) {
                    try self.appendGenericTool(&lines, block, width);
                } else {
                    try self.appendCanonical(&lines, block.text.items, width);
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
    fn appendGenericTool(self: *Transcript, lines: *std.ArrayList([]u8), block: *const Block, width: usize) !void {
        const heading = try std.fmt.allocPrint(self.gpa, "\x1b[1m{s}\x1b[22m", .{block.role});
        defer self.gpa.free(heading);
        const styled = if (self.palette) |*palette| try palette.style("toolTitle", heading) else try self.gpa.dupe(u8, heading);
        defer self.gpa.free(styled);
        try self.appendPlainTool(lines, styled, width, "");
        if (block.call_text.items.len > 0) {
            var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, block.call_text.items, .{}) catch |err| {
                if (err == error.OutOfMemory) return err;
                try self.appendPlainTool(lines, block.call_text.items, width, "");
                if (block.has_result) try self.appendGenericOutput(lines, block.text.items, width);
                return;
            };
            defer parsed.deinit();
            const content = try std.json.Stringify.valueAlloc(self.gpa, parsed.value, .{ .whitespace = .indent_2 });
            defer self.gpa.free(content);
            try appendLine(self.gpa, lines, "");
            try self.appendPlainTool(lines, content, width, "");
        }
        if (block.has_result and block.text.items.len > 0) try self.appendGenericOutput(lines, block.text.items, width);
    }
    fn appendGenericOutput(self: *Transcript, lines: *std.ArrayList([]u8), text: []const u8, width: usize) !void {
        const output = try @import("../tui/tool_fallback.zig").textOutput(self.gpa, text);
        defer self.gpa.free(output);
        if (output.len > 0) try self.appendPlainTool(lines, output, width, "");
    }
    fn appendToolCall(self: *Transcript, lines: *std.ArrayList([]u8), block: *const Block, width: usize, expanded: bool) !void {
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, if (block.call_text.items.len > 0) block.call_text.items else "null", .{}) catch |err| {
            if (err == error.OutOfMemory) return err;
            return self.appendPlainTool(lines, block.call_text.items, width, "muted");
        };
        defer parsed.deinit();
        const formatted = try @import("../tui/tool_fallback.zig").format(self.gpa, block.role, parsed.value, expanded, if (self.palette) |*value| value else null);
        defer self.gpa.free(formatted);
        // The formatter already applies its own title/argument colors.
        try self.appendPlainTool(lines, formatted, width, "");
    }
    fn appendToolOutput(self: *Transcript, lines: *std.ArrayList([]u8), text: []const u8, width: usize, expanded: bool) !void {
        const output = try @import("../tui/tool_fallback.zig").textOutput(self.gpa, text);
        defer self.gpa.free(output);
        if (output.len == 0) return;
        if (expanded) return self.appendPlainTool(lines, output, width, "toolOutput");
        var cursor = std.mem.splitScalar(u8, output, '\n');
        var end: usize = 0;
        var count: usize = 0;
        var total: usize = 0;
        while (cursor.next()) |line| {
            total += 1;
            if (count < 10) {
                end += line.len + @intFromBool(count > 0);
                count += 1;
            }
        }
        try self.appendPlainTool(lines, output[0..end], width, "toolOutput");
        if (total > count) {
            const suffix = try std.fmt.allocPrint(self.gpa, "... ({d} more lines, {s} to expand)", .{ total - count, self.tools_expand_hint });
            defer self.gpa.free(suffix);
            try self.appendPlainTool(lines, suffix, width, "muted");
        }
    }
    fn appendPlainTool(self: *Transcript, lines: *std.ArrayList([]u8), text: []const u8, width: usize, token: []const u8) !void {
        var normalized: std.ArrayList(u8) = .empty;
        defer normalized.deinit(self.gpa);
        for (text) |byte| if (byte == '\t') try normalized.appendSlice(self.gpa, "   ") else try normalized.append(self.gpa, byte);
        const styled = if (self.palette) |*palette| try palette.style(token, normalized.items) else try self.gpa.dupe(u8, normalized.items);
        defer self.gpa.free(styled);
        const units = try std.unicode.wtf8ToWtf16LeAlloc(self.gpa, styled);
        defer self.gpa.free(units);
        const wrapped = try @import("../extensions/native_utf16_wrap.zig").wrapNative(self.gpa, units, @floatFromInt(width));
        defer {
            for (wrapped) |value| self.gpa.free(value);
            self.gpa.free(wrapped);
        }
        for (wrapped) |value| {
            const utf8 = try std.unicode.wtf16LeToWtf8Alloc(self.gpa, value);
            defer self.gpa.free(utf8);
            try appendLine(self.gpa, lines, utf8);
        }
    }
    fn appendCanonical(self: *Transcript, lines: *std.ArrayList([]u8), text: []const u8, width: usize) !void {
        // Markdown has only allocating memory writers here. Their WriteFailed
        // represents allocation failure, rather than terminal/file I/O.
        var rendered = markdown.render(self.gpa, text, width, self.theme, .{}, .{ .hyperlinks = true }) catch |err| return if (err == error.WriteFailed) error.OutOfMemory else err;
        defer rendered.deinit(self.gpa);
        for (rendered.lines) |line| try appendLine(self.gpa, lines, line);
    }
};

fn appendLine(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), value: []const u8) !void {
    const owned = try gpa.dupe(u8, value);
    errdefer gpa.free(owned);
    try lines.append(gpa, owned);
}

fn rendererTestRecord(gpa: std.mem.Allocator, source: []const u8) !renderer_rows.protocol.Record {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{});
    defer parsed.deinit();
    return renderer_rows.protocol.read(gpa, &parsed.value.object);
}
const renderer_test_prefix = "\"version\":1,\"ownerGeneration\":\"1\",\"extensionId\":\"2\",\"rowGeneration\":\"3\",\"toolCallId\":\"tool-a\",\"width\":80";
fn rendererTranscriptCase(gpa: std.mem.Allocator) !void {
    var transcript = Transcript.init(gpa);
    defer transcript.deinit();
    var registration = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_register\",\"toolName\":\"paint\"}");
    defer registration.deinit();
    try std.testing.expect(try transcript.adoptRenderer(&registration));
    var call = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_frame\",\"sequence\":\"1\",\"revision\":\"1\",\"slot\":\"call\",\"lines\":[\"owned-call Ω🦊\"]}");
    defer call.deinit();
    try std.testing.expect(try transcript.adoptRenderer(&call));
    {
        var before = try transcript.component().render(gpa, 80);
        defer before.deinit(gpa);
        try std.testing.expectEqual(@as(usize, 0), before.items.len);
    }
    try transcript.event(.{ .kind = .tool_execution_start, .id = "tool-a", .name = "paint", .args_json = "canonical-call" });
    try transcript.event(.{ .kind = .tool_execution_end, .id = "tool-a", .name = "paint", .text = "canonical-result" });
    var result = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_frame\",\"sequence\":\"2\",\"revision\":\"1\",\"slot\":\"result\",\"lines\":[\"owned-result\"]}");
    defer result.deinit();
    try std.testing.expect(try transcript.adoptRenderer(&result));
    {
        var view = try transcript.component().render(gpa, 80);
        defer view.deinit(gpa);
        try std.testing.expectEqualStrings("owned-call Ω🦊", view.items[0]);
        try std.testing.expectEqualStrings("owned-result", view.items[1]);
        try std.testing.expectEqual(@as(usize, 2), view.items.len);
    }
    var anchor = (try transcript.anchor(1)).?;
    defer gpa.free(anchor.key);
    try transcript.syncBranch(&.{.{ .entry_type = .message, .id = "durable-tool", .parent_id = null, .role = "toolResult", .content = "canonical-result", .tool_call_id = "tool-a" }}, &anchor);
    try std.testing.expectEqualStrings("durable-tool", anchor.key);
    {
        var view = try transcript.component().render(gpa, 80);
        defer view.deinit(gpa);
        try std.testing.expectEqualStrings("owned-call Ω🦊", view.items[0]);
        try std.testing.expectEqualStrings("owned-result", view.items[1]);
        try std.testing.expectEqual(@as(usize, 1), transcript.anchorRow(anchor));
    }
    {
        var resized = try transcript.component().render(gpa, 70);
        defer resized.deinit(gpa);
        try std.testing.expectEqualStrings("canonical-call", resized.items[0]);
        try std.testing.expectEqualStrings("canonical-result", resized.items[1]);
    }
    var retire = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_retire\"}");
    defer retire.deinit();
    try std.testing.expect(try transcript.adoptRenderer(&retire));
    var late = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_frame\",\"sequence\":\"9\",\"revision\":\"9\",\"slot\":\"result\",\"lines\":[\"late-forbidden\"]}");
    defer late.deinit();
    try std.testing.expect(!try transcript.adoptRenderer(&late));
    {
        var view = try transcript.component().render(gpa, 80);
        defer view.deinit(gpa);
        try std.testing.expectEqualStrings("canonical-call", view.items[1]);
        try std.testing.expectEqualStrings("canonical-result", view.items[2]);
        try std.testing.expectEqual(@as(usize, 3), view.items.len);
    }
    var next_lease = try rendererTestRecord(gpa, "{" ++ renderer_test_prefix ++ ",\"type\":\"renderer_register\",\"toolName\":\"paint\"}");
    defer next_lease.deinit();
    next_lease.fence.row_generation += 1;
    try std.testing.expect(try transcript.adoptRenderer(&next_lease));
    try transcript.syncBranch(&.{}, null);
    const detached = transcript.renderers.find("tool-a").?;
    try std.testing.expect(detached.retired and detached.needs_retire);
    try std.testing.expectEqual(@as(usize, 0), transcript.blocks.items.len);
    late.fence.row_generation += 1;
    try std.testing.expect(!try transcript.adoptRenderer(&late));
}

test "renderer slots attach only to real tools preserve durable anchor and width fallback with all allocation failures" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, rendererTranscriptCase, .{});
}
