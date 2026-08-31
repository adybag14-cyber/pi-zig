//! Retained fullscreen model selector used by interactive `/model`.
//!
//! The selector mirrors Pi's original all/scoped model workflow while keeping
//! the native Zig runtime authoritative for provider/model switching. It works
//! from immutable catalog snapshots and returns a canonical `provider/model`
//! reference to the slash-command layer for transactional application.
const std = @import("std");
const Io = std.Io;
const providers = @import("../ai/providers.zig");
const model_resolver = @import("model_resolver.zig");
const application = @import("../tui/application.zig");
const fuzzy = @import("../tui/fuzzy.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const Scope = enum {
    all,
    scoped,

    fn title(self: Scope) []const u8 {
        return switch (self) {
            .all => "all",
            .scoped => "scoped",
        };
    }
};

pub const Selection = struct {
    reference: ?[]u8 = null,
    cancelled: bool = true,
    persist_default: bool = false,

    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        if (self.reference) |value| gpa.free(value);
        self.* = undefined;
    }
};

const Item = struct {
    model: providers.ModelInfo,
    thinking_level: ?@import("../ai/thinking.zig").ThinkingLevel = null,
    scoped: bool = false,
};

const Ranked = struct {
    item_index: usize,
    score: i32,
};

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    all_models: []const providers.ModelInfo,
    scoped_models: []const model_resolver.ScopedModel,
    configured_providers: []const []const u8,
    current_provider: []const u8,
    current_model: []const u8,
    items: std.ArrayList(Item) = .empty,
    visible: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    viewport_rows: usize = 30,
    scope: Scope = .all,
    done: bool = false,
    cancelled: bool = true,
    persist_default: bool = false,
    result: ?[]u8 = null,
    status: ?[]u8 = null,
    rendered_start: usize = 0,
    rendered_count: usize = 0,
    last_click_ms: i64 = 0,
    last_click_index: ?usize = null,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        all_models: []const providers.ModelInfo,
        scoped_models: []const model_resolver.ScopedModel,
        configured_providers: []const []const u8,
        current_provider: []const u8,
        current_model: []const u8,
        initial_query: ?[]const u8,
    ) !Selector {
        var self: Selector = .{
            .gpa = gpa,
            .io = io,
            .all_models = all_models,
            .scoped_models = scoped_models,
            .configured_providers = configured_providers,
            .current_provider = current_provider,
            .current_model = current_model,
            .scope = if (scoped_models.len > 0) .scoped else .all,
        };
        errdefer self.deinit();
        if (initial_query) |query| try self.query.appendSlice(gpa, query);
        try self.rebuildItems();
        try self.rebuildVisible(true);
        return self;
    }

    fn deinit(self: *Selector) void {
        if (self.result) |value| self.gpa.free(value);
        if (self.status) |value| self.gpa.free(value);
        self.query.deinit(self.gpa);
        self.visible.deinit(self.gpa);
        self.items.deinit(self.gpa);
        self.* = undefined;
    }

    fn component(self: *Selector) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable: layout.Component.VTable = .{
        .render = renderCallback,
        .handle_input = inputCallback,
        .handle_mouse = mouseCallback,
        .set_focus = focusCallback,
    };

    fn renderCallback(context: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.render(gpa, width);
    }

    fn inputCallback(context: *anyopaque, data: []const u8) !void {
        const self: *Selector = @ptrCast(@alignCast(context));
        try self.handleInput(data);
    }

    fn mouseCallback(context: *anyopaque, event: mouse.Event) !bool {
        const self: *Selector = @ptrCast(@alignCast(context));
        return try self.handleMouse(event);
    }

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn isCurrent(self: *const Selector, model: providers.ModelInfo) bool {
        return std.ascii.eqlIgnoreCase(model.providerName(), self.current_provider) and
            std.mem.eql(u8, model.id, self.current_model);
    }

    fn providerConfigured(self: *const Selector, provider_id: []const u8) bool {
        if (self.configured_providers.len == 0) return true;
        for (self.configured_providers) |configured| {
            if (std.ascii.eqlIgnoreCase(configured, provider_id)) return true;
        }
        return false;
    }

    fn appendAllItems(self: *Selector) !void {
        for (self.all_models) |model| {
            // Match the original selector's available-model snapshot. Always
            // retain the current model so a transient credential/catalog issue
            // cannot make the active selection disappear from the UI.
            if (!self.providerConfigured(model.providerName()) and !self.isCurrent(model)) continue;
            try self.items.append(self.gpa, .{ .model = model });
        }
    }

    fn appendScopedItems(self: *Selector) !void {
        for (self.scoped_models) |scoped| {
            try self.items.append(self.gpa, .{
                .model = scoped.model,
                .thinking_level = scoped.thinking_level,
                .scoped = true,
            });
        }
    }

    fn itemLessThan(self: *const Selector, lhs: Item, rhs: Item) bool {
        const lhs_current = self.isCurrent(lhs.model);
        const rhs_current = self.isCurrent(rhs.model);
        if (lhs_current != rhs_current) return lhs_current;
        const provider_order = std.ascii.orderIgnoreCase(lhs.model.providerName(), rhs.model.providerName());
        if (provider_order != .eq) return provider_order == .lt;
        return std.ascii.orderIgnoreCase(lhs.model.id, rhs.model.id) == .lt;
    }

    fn rebuildItems(self: *Selector) !void {
        self.items.clearRetainingCapacity();
        switch (self.scope) {
            .all => try self.appendAllItems(),
            .scoped => try self.appendScopedItems(),
        }
        std.mem.sort(Item, self.items.items, self, struct {
            fn lessThan(ctx: *Selector, lhs: Item, rhs: Item) bool {
                return ctx.itemLessThan(lhs, rhs);
            }
        }.lessThan);
    }

    fn identityAlloc(self: *const Selector, model: providers.ModelInfo) ![]u8 {
        return std.fmt.allocPrint(self.gpa, "{s}/{s}", .{ model.providerName(), model.id });
    }

    fn scoreItem(self: *const Selector, item: Item) ?i32 {
        if (self.query.items.len == 0) return 0;
        var identity_buf: [768]u8 = undefined;
        const identity = std.fmt.bufPrint(&identity_buf, "{s}/{s}", .{ item.model.providerName(), item.model.id }) catch item.model.id;
        var search_buf: [2048]u8 = undefined;
        const search_text = std.fmt.bufPrint(&search_buf, "{s} {s} {s} {s}", .{
            identity,
            item.model.providerName(),
            item.model.id,
            item.model.display,
        }) catch identity;
        const fields = [_][]const u8{ search_text, identity, item.model.id, item.model.providerName(), item.model.display };
        return fuzzy.bestScore(&fields, self.query.items);
    }

    fn rankedLessThan(_: void, lhs: Ranked, rhs: Ranked) bool {
        if (lhs.score != rhs.score) return lhs.score > rhs.score;
        return lhs.item_index < rhs.item_index;
    }

    fn rebuildVisible(self: *Selector, prefer_current: bool) !void {
        self.visible.clearRetainingCapacity();
        var ranked: std.ArrayList(Ranked) = .empty;
        defer ranked.deinit(self.gpa);
        for (self.items.items, 0..) |item, index| {
            const score = self.scoreItem(item) orelse continue;
            try ranked.append(self.gpa, .{ .item_index = index, .score = score });
        }
        if (self.query.items.len > 0) std.mem.sort(Ranked, ranked.items, {}, rankedLessThan);
        for (ranked.items) |entry| try self.visible.append(self.gpa, entry.item_index);

        if (self.visible.items.len == 0) {
            self.selected = 0;
            return;
        }
        if (self.query.items.len > 0) {
            self.selected = 0;
            return;
        }
        if (prefer_current) {
            for (self.visible.items, 0..) |item_index, visible_index| {
                if (self.isCurrent(self.items.items[item_index].model)) {
                    self.selected = visible_index;
                    return;
                }
            }
        }
        self.selected = @min(self.selected, self.visible.items.len - 1);
    }

    fn setScope(self: *Selector, scope: Scope) !void {
        if (scope == .scoped and self.scoped_models.len == 0) return;
        if (self.scope == scope) return;
        self.scope = scope;
        try self.rebuildItems();
        try self.rebuildVisible(true);
    }

    fn cycleScope(self: *Selector) !void {
        if (self.scoped_models.len == 0) return;
        try self.setScope(if (self.scope == .all) .scoped else .all);
    }

    fn currentItem(self: *const Selector) ?Item {
        if (self.selected >= self.visible.items.len) return null;
        return self.items.items[self.visible.items[self.selected]];
    }

    fn moveSelection(self: *Selector, delta: isize) void {
        const count = self.visible.items.len;
        if (count == 0) return;
        if (delta < 0) {
            self.selected = if (self.selected == 0) count - 1 else self.selected - 1;
        } else if (delta > 0) {
            self.selected = if (self.selected + 1 >= count) 0 else self.selected + 1;
        }
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 10);
    }

    fn selectCurrent(self: *Selector) !void {
        const item = self.currentItem() orelse return;
        if (self.result) |old| self.gpa.free(old);
        self.result = try self.identityAlloc(item.model);
        self.cancelled = false;
        self.done = true;
    }

    fn clearSearchOrCancel(self: *Selector) !void {
        if (self.query.items.len > 0) {
            self.query.clearRetainingCapacity();
            try self.rebuildVisible(true);
            return;
        }
        self.cancelled = true;
        self.done = true;
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        var index = list.items.len - 1;
        while (index > 0 and (list.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        list.shrinkRetainingCapacity(index);
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        switch (key) {
            .up => self.moveSelection(-1),
            .down => self.moveSelection(1),
            .home => self.selected = 0,
            .end => if (self.visible.items.len > 0) {
                self.selected = self.visible.items.len - 1;
            },
            .left => self.selected -|= @min(self.selected, self.pageSize()),
            .right => if (self.visible.items.len > 0) {
                self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            },
            .enter => try self.selectCurrent(),
            .tab => try self.cycleScope(),
            .backspace => if (self.query.items.len > 0) {
                popUtf8(&self.query);
                try self.rebuildVisible(false);
            },
            .delete => if (self.query.items.len > 0) {
                self.query.clearRetainingCapacity();
                try self.rebuildVisible(true);
            },
            .escape => try self.clearSearchOrCancel(),
            .ctrl_c, .ctrl_d => {
                self.cancelled = true;
                self.done = true;
            },
            .text => |byte| if (byte >= 0x20) {
                try self.query.append(self.gpa, byte);
                try self.rebuildVisible(false);
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x13")) {
            self.persist_default = true;
            try self.selectCurrent();
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[5~")) {
            self.selected -|= @min(self.selected, self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[6~")) {
            if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) return self.clearSearchOrCancel();

        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) {
                    try self.query.append(self.gpa, byte);
                    try self.rebuildVisible(false);
                }
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) !bool {
        if (event.kind == .scroll) {
            switch (event.button) {
                .wheel_up => self.moveSelection(-3),
                .wheel_down => self.moveSelection(3),
                else => return false,
            }
            return true;
        }
        if (event.kind != .press or event.button != .left) return false;
        // Header + scope/search + spacer consume the first three rows.
        if (event.y < 3 or event.y >= 3 + self.rendered_count) return false;
        const visible_index = self.rendered_start + (event.y - 3);
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;

        // The shared mouse decoder deliberately exposes protocol-level presses
        // rather than synthesizing a click kind. Detect a bounded second press
        // here so a double-click can confirm without changing the mouse ABI.
        const now_ms = std.Io.Clock.awake.now(self.io).toMilliseconds();
        if (self.last_click_index != null and self.last_click_index.? == visible_index and
            now_ms >= self.last_click_ms and now_ms - self.last_click_ms <= 500)
        {
            self.last_click_index = null;
            self.last_click_ms = 0;
            try self.selectCurrent();
        } else {
            self.last_click_index = visible_index;
            self.last_click_ms = now_ms;
        }
        return true;
    }

    fn appendClipped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), width: usize, owned: []u8) !void {
        defer gpa.free(owned);
        try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
    }

    fn formatTokenCount(gpa: std.mem.Allocator, value: u64) ![]u8 {
        if (value >= 1_000_000) return std.fmt.allocPrint(gpa, "{d}.{d}M", .{ value / 1_000_000, (value % 1_000_000) / 100_000 });
        if (value >= 1_000) return std.fmt.allocPrint(gpa, "{d}K", .{value / 1_000});
        return std.fmt.allocPrint(gpa, "{d}", .{value});
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }

        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Select Model{s}  {s}Enter{s} select  {s}Ctrl+S{s} default  {s}Tab{s} scope  {s}Esc{s} clear/cancel", .{
            bold, reset, dim, reset, dim, reset, dim, reset, dim, reset,
        }));
        if (self.scoped_models.len > 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Scope: {s}{s}{s}  Search: {s}{s}_{s}", .{
                accent, self.scope.title(), reset, accent, self.query.items, reset,
            }));
        } else {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Configured providers only; use /login to add providers.{s}  Search: {s}{s}_{s}", .{
                warning, reset, accent, self.query.items, reset,
            }));
        }
        try lines.append(gpa, try gpa.dupe(u8, ""));

        self.rendered_start = 0;
        self.rendered_count = 0;
        if (self.visible.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No matching models{s}", .{ dim, reset }));
        } else {
            const count = self.pageSize();
            const half = count / 2;
            var start = self.selected -| half;
            if (start + count > self.visible.items.len) start = self.visible.items.len -| count;
            const end = @min(self.visible.items.len, start + count);
            self.rendered_start = start;
            self.rendered_count = end - start;
            for (self.visible.items[start..end], start..) |item_index, visible_index| {
                const item = self.items.items[item_index];
                const selected = visible_index == self.selected;
                const current = self.isCurrent(item.model);
                var line: std.Io.Writer.Allocating = .init(gpa);
                defer line.deinit();
                if (selected) try line.writer.writeAll(reverse);
                try line.writer.writeAll(if (selected) "> " else "  ");
                try line.writer.print("{s}{s}{s} {s}[{s}]{s}", .{
                    if (selected) accent else "",
                    item.model.id,
                    if (selected) reset else "",
                    dim,
                    item.model.providerName(),
                    reset,
                });
                if (current) try line.writer.print(" {s}✓{s}", .{ success, reset });
                if (item.thinking_level) |level| try line.writer.print(" {s}:{s}{s}", .{ dim, @tagName(level), reset });
                if (selected) try line.writer.writeAll(reset);
                try appendClipped(gpa, &lines, width, try line.toOwnedSlice());
            }

            const item = self.currentItem().?;
            const context = try formatTokenCount(gpa, item.model.context_window);
            defer gpa.free(context);
            const output = try formatTokenCount(gpa, item.model.max_tokens);
            defer gpa.free(output);
            try lines.append(gpa, try gpa.dupe(u8, ""));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {s}{s}", .{ dim, item.model.display, reset }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  context {s} · output {s} · {s} · {s} · api {s}{s}", .{
                dim,
                context,
                output,
                if (item.model.reasoning) "reasoning" else "standard",
                if (item.model.input_image) "images" else "text",
                @tagName(item.model.apiKind()),
                reset,
            }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} models · mouse selects · double-click confirms{s}", .{
                dim,
                self.selected + 1,
                self.visible.items.len,
                reset,
            }));
        }
        if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn readInputChunk(io: Io, reader: ?*Io.File.Reader, buffer: []u8) !usize {
    if (reader) |buffered| {
        const available = buffered.interface.bufferedLen();
        if (available > 0) {
            const count = @min(available, buffer.len);
            const source = try buffered.interface.take(count);
            @memcpy(buffer[0..count], source);
            return count;
        }
    }
    var slices = [_][]u8{buffer};
    return Io.File.stdin().readStreaming(io, &slices);
}

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    all_models: []const providers.ModelInfo,
    scoped_models: []const model_resolver.ScopedModel,
    configured_providers: []const []const u8,
    current_provider: []const u8,
    current_model: []const u8,
    initial_query: ?[]const u8,
    already_fullscreen: bool,
) !Selection {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.init(
        gpa,
        io,
        all_models,
        scoped_models,
        configured_providers,
        current_provider,
        current_model,
        initial_query,
    );
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());

    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    if (already_fullscreen) {
        try tui_render.writeAll(io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        defer tui_render.writeAll(io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
    } else {
        try app.start(io);
        defer app.stop(io) catch {};
    }

    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 100, .rows = 30 });
        selector.viewport_rows = dimensions.rows;
        try app.paint(io, dimensions.columns, dimensions.rows);
        const count = readInputChunk(io, reader, input_buffer[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }

    return .{
        .reference = if (selector.result) |value| try gpa.dupe(u8, value) else null,
        .cancelled = selector.cancelled,
        .persist_default = selector.persist_default,
    };
}

fn testModels() [4]providers.ModelInfo {
    return .{
        .{ .provider = .openai, .id = "gpt-z", .display = "GPT Z", .context_window = 128_000, .max_tokens = 16_000 },
        .{ .provider = .anthropic, .id = "claude-b", .display = "Claude B", .reasoning = true, .input_image = true },
        .{ .provider = .openai, .id = "gpt-a", .display = "GPT A" },
        .{ .provider = .google, .id = "gemini-c", .display = "Gemini C" },
    };
}

test "model selector defaults to scoped scope and tab switches to all" {
    const gpa = std.testing.allocator;
    const models = testModels();
    const scoped = [_]model_resolver.ScopedModel{.{ .model = models[1], .thinking_level = .high }};
    var selector = try Selector.init(gpa, std.testing.io, &models, &scoped, &.{ "openai", "anthropic" }, "anthropic", "claude-b", null);
    defer selector.deinit();
    try std.testing.expectEqual(Scope.scoped, selector.scope);
    try std.testing.expectEqual(@as(usize, 1), selector.visible.items.len);
    try selector.handleInput("\t");
    try std.testing.expectEqual(Scope.all, selector.scope);
    try std.testing.expectEqual(@as(usize, 3), selector.visible.items.len);
}

test "model selector fuzzy query ranks canonical provider identity" {
    const gpa = std.testing.allocator;
    const models = testModels();
    var selector = try Selector.init(gpa, std.testing.io, &models, &.{}, &.{}, "openai", "gpt-a", "anthropic claude");
    defer selector.deinit();
    try std.testing.expect(selector.visible.items.len > 0);
    const selected = selector.currentItem().?;
    try std.testing.expectEqualStrings("anthropic", selected.model.providerName());
    try std.testing.expectEqualStrings("claude-b", selected.model.id);
}

test "model selector selection returns canonical provider and id" {
    const gpa = std.testing.allocator;
    const models = testModels();
    var selector = try Selector.init(gpa, std.testing.io, &models, &.{}, &.{}, "openai", "gpt-a", "gemini");
    defer selector.deinit();
    try selector.selectCurrent();
    try std.testing.expect(!selector.cancelled);
    try std.testing.expectEqualStrings("google/gemini-c", selector.result.?);
}

test "model selector Ctrl+S selects and marks the global default request" {
    const gpa = std.testing.allocator;
    const models = testModels();
    var selector = try Selector.init(gpa, std.testing.io, &models, &.{}, &.{}, "openai", "gpt-a", "gemini");
    defer selector.deinit();
    try selector.handleInput("\x13");
    try std.testing.expect(selector.done);
    try std.testing.expect(selector.persist_default);
    try std.testing.expectEqualStrings("google/gemini-c", selector.result.?);
}

test "model selector escape clears search before cancelling" {
    const gpa = std.testing.allocator;
    const models = testModels();
    var selector = try Selector.init(gpa, std.testing.io, &models, &.{}, &.{}, "openai", "gpt-a", "gpt");
    defer selector.deinit();
    try selector.handleInput("\x1b");
    try std.testing.expectEqual(@as(usize, 0), selector.query.items.len);
    try std.testing.expect(!selector.done);
    try selector.handleInput("\x1b");
    try std.testing.expect(selector.done);
    try std.testing.expect(selector.cancelled);
}
