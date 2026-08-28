//! Fullscreen package-resource selector used by `pi config`.
const std = @import("std");
const Io = std.Io;
const package_config = @import("package_config.zig");
const packages = @import("packages.zig");
const application = @import("../tui/application.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: []const u8,
    cwd: []const u8,
    project_trusted: bool,
    write_scope: packages.Scope,
    inventory: package_config.Inventory,
    filtered: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    viewport_rows: usize = 24,
    done: bool = false,
    status: ?[]u8 = null,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        agent_dir: []const u8,
        cwd: []const u8,
        write_scope: packages.Scope,
        project_trusted: bool,
    ) !Selector {
        var self: Selector = .{
            .gpa = gpa,
            .io = io,
            .agent_dir = agent_dir,
            .cwd = cwd,
            .project_trusted = project_trusted,
            .write_scope = write_scope,
            .inventory = try package_config.discover(gpa, io, agent_dir, cwd, write_scope, project_trusted),
        };
        errdefer self.inventory.deinit();
        try self.rebuildFilter();
        return self;
    }

    fn deinit(self: *Selector) void {
        if (self.status) |value| self.gpa.free(value);
        self.query.deinit(self.gpa);
        self.filtered.deinit(self.gpa);
        self.inventory.deinit();
        self.* = undefined;
    }

    fn component(self: *Selector) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable: layout.Component.VTable = .{
        .render = renderCallback,
        .handle_input = inputCallback,
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

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn setStatus(self: *Selector, value: []const u8) !void {
        if (self.status) |old| self.gpa.free(old);
        self.status = try self.gpa.dupe(u8, value);
    }

    fn matches(self: *const Selector, resource: package_config.Resource) bool {
        if (self.query.items.len == 0) return true;
        inline for (.{ resource.package_name, resource.package_source, resource.selector, @tagName(resource.origin), @tagName(resource.resource_type), resource.display_name, resource.relative_path }) |candidate| {
            if (indexOfIgnoreCase(candidate, self.query.items) != null) return true;
        }
        return false;
    }

    fn rebuildFilter(self: *Selector) !void {
        self.filtered.clearRetainingCapacity();
        for (self.inventory.resources, 0..) |resource, index| {
            if (self.matches(resource)) try self.filtered.append(self.gpa, index);
        }
        if (self.filtered.items.len == 0) {
            self.selected = 0;
        } else if (self.selected >= self.filtered.items.len) {
            self.selected = self.filtered.items.len - 1;
        }
    }

    fn reload(self: *Selector, preserve_selector: ?[]const u8, preserve_type: ?package_config.ResourceType, preserve_path: ?[]const u8) !void {
        const next = try package_config.discover(
            self.gpa,
            self.io,
            self.agent_dir,
            self.cwd,
            self.write_scope,
            self.project_trusted,
        );
        self.inventory.deinit();
        self.inventory = next;
        self.selected = 0;
        try self.rebuildFilter();
        if (preserve_selector != null and preserve_type != null and preserve_path != null) {
            for (self.filtered.items, 0..) |inventory_index, filtered_index| {
                const resource = self.inventory.resources[inventory_index];
                if (std.mem.eql(u8, resource.selector, preserve_selector.?) and
                    resource.resource_type == preserve_type.? and
                    std.mem.eql(u8, resource.relative_path, preserve_path.?))
                {
                    self.selected = filtered_index;
                    break;
                }
            }
        }
    }

    fn current(self: *Selector) ?*package_config.Resource {
        if (self.filtered.items.len == 0 or self.selected >= self.filtered.items.len) return null;
        return &self.inventory.resources[self.filtered.items[self.selected]];
    }

    fn nextProjectState(resource: package_config.Resource) package_config.OverrideState {
        return switch (resource.override_state) {
            .inherit => if (resource.inherited_enabled) .unload else .load,
            .unload => if (resource.inherited_enabled) .load else .inherit,
            .load => if (resource.inherited_enabled) .inherit else .unload,
        };
    }

    fn toggleCurrent(self: *Selector) !void {
        const resource = self.current() orelse return;
        const selector = try self.gpa.dupe(u8, resource.selector);
        defer self.gpa.free(selector);
        const relative = try self.gpa.dupe(u8, resource.relative_path);
        defer self.gpa.free(relative);
        const resource_type = resource.resource_type;
        const state: package_config.OverrideState = if (self.write_scope == .project)
            nextProjectState(resource.*)
        else if (resource.enabled)
            .unload
        else
            .load;
        package_config.setResource(
            self.gpa,
            self.io,
            self.agent_dir,
            self.cwd,
            self.write_scope,
            self.project_trusted,
            selector,
            resource_type,
            relative,
            state,
        ) catch |err| {
            const message = try std.fmt.allocPrint(self.gpa, "error: {s}", .{@errorName(err)});
            defer self.gpa.free(message);
            try self.setStatus(message);
            return;
        };
        if (self.status) |old| {
            self.gpa.free(old);
            self.status = null;
        }
        try self.reload(selector, resource_type, relative);
    }

    fn switchScope(self: *Selector) !void {
        if (!self.project_trusted) {
            try self.setStatus("Project scope unavailable until this project is trusted");
            return;
        }
        self.write_scope = if (self.write_scope == .user) .project else .user;
        self.selected = 0;
        try self.reload(null, null, null);
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        switch (key) {
            .up => {
                if (self.selected > 0) self.selected -= 1;
            },
            .down => {
                if (self.selected + 1 < self.filtered.items.len) self.selected += 1;
            },
            .home => self.selected = 0,
            .end => {
                if (self.filtered.items.len > 0) self.selected = self.filtered.items.len - 1;
            },
            .enter => try self.toggleCurrent(),
            .backspace => {
                if (self.query.items.len > 0) {
                    _ = self.query.pop();
                    while (self.query.items.len > 0 and (self.query.items[self.query.items.len - 1] & 0xc0) == 0x80) _ = self.query.pop();
                    self.selected = 0;
                    try self.rebuildFilter();
                }
            },
            .tab => try self.switchScope(),
            .escape, .ctrl_c, .ctrl_d => self.done = true,
            .text => |byte| {
                if (byte == ' ') {
                    try self.toggleCurrent();
                } else if (byte >= 0x20) {
                    try self.query.append(self.gpa, byte);
                    self.selected = 0;
                    try self.rebuildFilter();
                }
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        if (std.mem.eql(u8, data, "\x1b[5~")) {
            self.selected -|= @min(self.selected, self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b[6~")) {
            if (self.filtered.items.len > 0) self.selected = @min(self.filtered.items.len - 1, self.selected + self.pageSize());
            return;
        }
        if (std.mem.eql(u8, data, "\x1b")) {
            self.done = true;
            return;
        }
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                // A fragmented or UTF-8 printable input. Keep each byte: the
                // search filter operates on UTF-8 byte sequences and redraws
                // only after the complete terminal read.
                const byte = data[offset];
                if (byte >= 0x20) try self.query.append(self.gpa, byte);
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
        try self.rebuildFilter();
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 8);
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        const scope_title = if (self.write_scope == .project) "Project Local Resources" else "Global Resources";
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}  {s}Tab{s} switch  {s}Space/Enter{s} toggle  {s}Esc{s} close", .{
            bold,
            scope_title,
            reset,
            dim,
            reset,
            dim,
            reset,
            dim,
            reset,
        }), true);
        const scope_path = if (self.write_scope == .project) ".pi/settings.json + packages.json · inherited user resources are dimmed" else "user settings.json + packages.json";
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ dim, scope_path, reset }), true);
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Search: {s}{s}_{s}", .{ accent, self.query.items, reset }), true);
        try lines.append(gpa, try gpa.dupe(u8, ""));

        if (self.filtered.items.len == 0) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  No resources found{s}", .{ dim, reset }), true);
        } else {
            const visible = self.pageSize();
            const half = visible / 2;
            var start = self.selected -| half;
            if (start + visible > self.filtered.items.len) start = self.filtered.items.len -| visible;
            const end = @min(self.filtered.items.len, start + visible);
            for (self.filtered.items[start..end], start..) |inventory_index, filtered_index| {
                const resource = self.inventory.resources[inventory_index];
                const selected = filtered_index == self.selected;
                const marker = if (self.write_scope == .project) switch (resource.override_state) {
                    .load => "[+]",
                    .unload => "[-]",
                    .inherit => if (resource.enabled) "[x]" else "[ ]",
                } else if (resource.enabled) "[x]" else "[ ]";
                const marker_color = if (resource.override_state == .unload) warning else if (resource.enabled) success else dim;
                const inherited = self.write_scope == .project and resource.override_state == .inherit;
                const line_style = if (selected) reverse else if (inherited) dim else "";
                const suffix = if (inherited)
                    if (resource.inherited_enabled) " · inherited on" else " · inherited off"
                else
                    "";
                try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s} {s}{s}{s}  {s} · {s} · {s}{s}{s}", .{
                    line_style,
                    if (selected) ">" else " ",
                    marker_color,
                    marker,
                    reset,
                    resource.package_name,
                    @tagName(resource.resource_type),
                    resource.display_name,
                    suffix,
                    reset,
                }), true);
            }
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} resource{s}{s}", .{
                dim,
                self.selected + 1,
                self.filtered.items.len,
                if (self.filtered.items.len == 1) "" else "s",
                reset,
            }), true);
        }
        if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }), true);
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn appendClipped(
    gpa: std.mem.Allocator,
    lines: *std.ArrayList([]u8),
    width: usize,
    owned: []u8,
    free_owned: bool,
) !void {
    defer if (free_owned) gpa.free(owned);
    try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return index;
    }
    return null;
}

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    cwd: []const u8,
    initial_scope: packages.Scope,
    project_trusted: bool,
) !void {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.init(gpa, io, agent_dir, cwd, initial_scope, project_trusted);
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());

    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    try app.start(io);
    defer app.stop(io) catch {};

    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 100, .rows = 30 });
        selector.viewport_rows = dimensions.rows;
        try app.paint(io, dimensions.columns, dimensions.rows);
        var slices = [_][]u8{input_buffer[0..]};
        const count = Io.File.stdin().readStreaming(io, &slices) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }
}

test "project override cycle follows inherited state" {
    try std.testing.expectEqual(package_config.OverrideState.unload, Selector.nextProjectState(.{
        .gpa = std.testing.allocator,
        .package_name = "p",
        .package_source = "p",
        .package_path = "p",
        .package_scope = .user,
        .selector = "p",
        .origin = .package,
        .resource_type = .extensions,
        .path = "p/x.ts",
        .relative_path = "x.ts",
        .display_name = "x.ts",
        .enabled = true,
        .inherited_enabled = true,
        .override_state = .inherit,
    }));
}
