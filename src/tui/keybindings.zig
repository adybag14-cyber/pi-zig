//! Upstream-style configurable keybinding registry for the native TUI editor.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

pub const Action = enum {
    cursor_up,
    cursor_down,
    cursor_left,
    cursor_right,
    cursor_word_left,
    cursor_word_right,
    cursor_line_start,
    cursor_line_end,
    delete_char_backward,
    delete_char_forward,
    delete_word_backward,
    delete_word_forward,
    delete_to_line_start,
    delete_to_line_end,
    yank,
    yank_pop,
    undo,
    new_line,
    submit,
    tab,
    clipboard_paste,
    clear,
    exit,
};

const Definition = struct {
    id: []const u8,
    legacy: ?[]const u8 = null,
    action: Action,
    defaults: []const []const u8,
};

const definitions = [_]Definition{
    .{ .id = "tui.editor.cursorUp", .legacy = "cursorUp", .action = .cursor_up, .defaults = &.{"up"} },
    .{ .id = "tui.editor.cursorDown", .legacy = "cursorDown", .action = .cursor_down, .defaults = &.{"down"} },
    .{ .id = "tui.editor.cursorLeft", .legacy = "cursorLeft", .action = .cursor_left, .defaults = &.{ "left", "ctrl+b" } },
    .{ .id = "tui.editor.cursorRight", .legacy = "cursorRight", .action = .cursor_right, .defaults = &.{ "right", "ctrl+f" } },
    .{ .id = "tui.editor.cursorWordLeft", .legacy = "cursorWordLeft", .action = .cursor_word_left, .defaults = &.{ "alt+left", "ctrl+left", "alt+b" } },
    .{ .id = "tui.editor.cursorWordRight", .legacy = "cursorWordRight", .action = .cursor_word_right, .defaults = &.{ "alt+right", "ctrl+right", "alt+f" } },
    .{ .id = "tui.editor.cursorLineStart", .legacy = "cursorLineStart", .action = .cursor_line_start, .defaults = &.{ "home", "ctrl+a" } },
    .{ .id = "tui.editor.cursorLineEnd", .legacy = "cursorLineEnd", .action = .cursor_line_end, .defaults = &.{ "end", "ctrl+e" } },
    .{ .id = "tui.editor.deleteCharBackward", .legacy = "deleteCharBackward", .action = .delete_char_backward, .defaults = &.{"backspace"} },
    .{ .id = "tui.editor.deleteCharForward", .legacy = "deleteCharForward", .action = .delete_char_forward, .defaults = &.{ "delete", "ctrl+d" } },
    .{ .id = "tui.editor.deleteWordBackward", .legacy = "deleteWordBackward", .action = .delete_word_backward, .defaults = &.{ "ctrl+w", "alt+backspace" } },
    .{ .id = "tui.editor.deleteWordForward", .legacy = "deleteWordForward", .action = .delete_word_forward, .defaults = &.{ "alt+d", "alt+delete" } },
    .{ .id = "tui.editor.deleteToLineStart", .legacy = "deleteToLineStart", .action = .delete_to_line_start, .defaults = &.{"ctrl+u"} },
    .{ .id = "tui.editor.deleteToLineEnd", .legacy = "deleteToLineEnd", .action = .delete_to_line_end, .defaults = &.{"ctrl+k"} },
    .{ .id = "tui.editor.yank", .legacy = "yank", .action = .yank, .defaults = &.{"ctrl+y"} },
    .{ .id = "tui.editor.yankPop", .legacy = "yankPop", .action = .yank_pop, .defaults = &.{"alt+y"} },
    .{ .id = "tui.editor.undo", .legacy = "undo", .action = .undo, .defaults = &.{"ctrl+-"} },
    .{ .id = "tui.input.newLine", .legacy = "newLine", .action = .new_line, .defaults = &.{ "shift+enter", "ctrl+j" } },
    .{ .id = "tui.input.submit", .legacy = "submit", .action = .submit, .defaults = &.{"enter"} },
    .{ .id = "tui.input.tab", .legacy = "tab", .action = .tab, .defaults = &.{"tab"} },
    .{ .id = "app.clipboard.pasteImage", .legacy = "pasteImage", .action = .clipboard_paste, .defaults = if (builtin.os.tag == .windows) &.{"alt+v"} else &.{"ctrl+v"} },
    .{ .id = "app.clear", .legacy = "clear", .action = .clear, .defaults = &.{"ctrl+c"} },
    .{ .id = "app.exit", .legacy = "exit", .action = .exit, .defaults = &.{"ctrl+d"} },
};

/// Shared editor/action defaults for native extension keybinding objects.
pub fn defaultKeysForAction(id: []const u8) []const []const u8 {
    for (definitions) |definition| if (std.mem.eql(u8, id, definition.id)) return definition.defaults;
    if (std.mem.eql(u8, id, "app.interrupt")) return &.{"escape"};
    if (std.mem.eql(u8, id, "tui.editor.historyPrevious")) return &.{"up"};
    if (std.mem.eql(u8, id, "tui.editor.historyNext")) return &.{"down"};
    if (std.mem.eql(u8, id, "tui.select.up")) return &.{"up"};
    if (std.mem.eql(u8, id, "tui.select.down")) return &.{"down"};
    if (std.mem.eql(u8, id, "tui.select.pageUp")) return &.{"pageup"};
    if (std.mem.eql(u8, id, "tui.select.pageDown")) return &.{"pagedown"};
    if (std.mem.eql(u8, id, "tui.select.confirm")) return &.{"enter"};
    if (std.mem.eql(u8, id, "tui.select.cancel")) return &.{ "escape", "ctrl+c" };
    return &.{};
}

pub const ViewportAction = enum { page_up, page_down, half_page_up, half_page_down, line_up, line_down, top, bottom };
const viewport_definitions = .{
    .{ "tui.altScreen.pageUp", ViewportAction.page_up, &.{"pageup"} },
    .{ "tui.altScreen.pageDown", ViewportAction.page_down, &.{"pagedown"} },
    .{ "tui.altScreen.halfPageUp", ViewportAction.half_page_up, &.{} },
    .{ "tui.altScreen.halfPageDown", ViewportAction.half_page_down, &.{} },
    .{ "tui.altScreen.lineUp", ViewportAction.line_up, &.{} },
    .{ "tui.altScreen.lineDown", ViewportAction.line_down, &.{} },
    .{ "tui.altScreen.top", ViewportAction.top, &.{"ctrl+home"} },
    .{ "tui.altScreen.bottom", ViewportAction.bottom, &.{"ctrl+end"} },
};

pub const Manager = struct {
    gpa: std.mem.Allocator,
    parsed: ?std.json.Parsed(std.json.Value) = null,

    pub fn init(gpa: std.mem.Allocator) Manager {
        return .{ .gpa = gpa };
    }

    pub fn load(gpa: std.mem.Allocator, io: Io, agent_dir: []const u8) !Manager {
        const path = try std.fs.path.join(gpa, &.{ agent_dir, "keybindings.json" });
        defer gpa.free(path);
        const raw = std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1024 * 1024)) catch |err| switch (err) {
            error.FileNotFound => return init(gpa),
            else => return err,
        };
        defer gpa.free(raw);
        var parsed = std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always }) catch return error.InvalidKeybindingsJson;
        errdefer parsed.deinit();
        if (parsed.value != .object) return error.InvalidKeybindingsJson;
        var index: usize = 0;
        while (index < parsed.value.object.count()) {
            const id = parsed.value.object.keys()[index];
            if (std.mem.eql(u8, id, "$schema") or !validBindingValue(parsed.value.object.values()[index])) {
                _ = parsed.value.object.orderedRemove(id);
            } else index += 1;
        }
        return .{ .gpa = gpa, .parsed = parsed };
    }

    pub fn deinit(self: *Manager) void {
        if (self.parsed) |*parsed| parsed.deinit();
        self.* = undefined;
    }

    pub fn matches(self: *const Manager, input_key: []const u8, action: Action) bool {
        var input_buf: [96]u8 = undefined;
        const normalized_input = normalizeKey(input_key, &input_buf) orelse return false;
        for (definitions) |def| {
            if (def.action != action) continue;
            if (self.configValue(def)) |value| return valueMatches(value, normalized_input);
            for (def.defaults) |key| {
                var buf: [96]u8 = undefined;
                const normalized = normalizeKey(key, &buf) orelse continue;
                if (std.mem.eql(u8, normalized, normalized_input)) return true;
            }
        }
        return false;
    }

    /// Match a named TUI action against a complete raw terminal sequence.
    /// Explicit empty arrays disable defaults and overrides retain Source order.
    pub fn matchesActionName(self: *const Manager, action: []const u8, sequence: []const u8) bool {
        if (self.parsed) |parsed| if (parsed.value == .object) if (parsed.value.object.get(action)) |value| {
            return switch (value) {
                .string => |key| @import("keys.zig").matchesKey(sequence, key),
                .array => |array| blk: {
                    for (array.items) |item| if (item == .string and @import("keys.zig").matchesKey(sequence, item.string)) break :blk true;
                    break :blk false;
                },
                else => false,
            };
        };
        for (defaultKeysForAction(action)) |key| if (@import("keys.zig").matchesKey(sequence, key)) return true;
        return false;
    }

    pub fn actionFor(self: *const Manager, input_key: []const u8) ?Action {
        var input_buf: [96]u8 = undefined;
        const normalized_input = normalizeKey(input_key, &input_buf) orelse return null;
        for (definitions) |def| {
            if (self.configValue(def)) |value| {
                if (valueMatches(value, normalized_input)) return def.action;
            } else {
                for (def.defaults) |key| {
                    var buf: [96]u8 = undefined;
                    if (normalizeKey(key, &buf)) |normalized| {
                        if (std.mem.eql(u8, normalized, normalized_input)) return def.action;
                    }
                }
            }
        }
        return null;
    }

    /// Fullscreen bindings have their own precedence and never become editor
    /// actions. Explicit JSON arrays replace defaults, including empty arrays.
    pub fn viewportActionFor(self: *const Manager, input_key: []const u8) ?ViewportAction {
        var input_buf: [96]u8 = undefined;
        const normalized = normalizeKey(input_key, &input_buf) orelse return null;
        inline for (viewport_definitions) |definition| {
            const configured = if (self.parsed) |parsed| parsed.value.object.get(definition[0]) else null;
            if (configured) |value| {
                if (valueMatches(value, normalized)) return definition[1];
            } else {
                const defaults: []const []const u8 = definition[2];
                for (defaults) |key| if (std.mem.eql(u8, normalized, key)) return definition[1];
            }
        }
        return null;
    }

    /// Count keys explicitly claimed by more than one configured binding.
    pub fn conflictCount(self: *const Manager) usize {
        const parsed = self.parsed orelse return 0;
        if (parsed.value != .object) return 0;
        var conflicts: usize = 0;
        var i: usize = 0;
        while (i < definitions.len) : (i += 1) {
            const a = self.configValue(definitions[i]) orelse continue;
            var j = i + 1;
            while (j < definitions.len) : (j += 1) {
                const b = self.configValue(definitions[j]) orelse continue;
                if (valuesOverlap(a, b)) conflicts += 1;
            }
        }
        return conflicts;
    }

    fn configValue(self: *const Manager, def: Definition) ?std.json.Value {
        const parsed = self.parsed orelse return null;
        if (parsed.value != .object) return null;
        if (parsed.value.object.get(def.id)) |value| return value;
        if (def.legacy) |legacy| if (parsed.value.object.get(legacy)) |value| return value;
        return null;
    }
};

pub fn validBindingValue(value: std.json.Value) bool {
    return switch (value) {
        .string => |key| validKeyId(key),
        .array => |array| blk: {
            for (array.items) |item| if (item != .string or !validKeyId(item.string)) break :blk false;
            break :blk true;
        },
        else => false,
    };
}
pub fn validKeyId(id: []const u8) bool {
    var remaining = id;
    var seen: u8 = 0;
    var count: u8 = 0;
    while (true) {
        var consumed = false;
        inline for (.{ "ctrl+", "shift+", "alt+", "super+" }, 0..) |prefix, index| {
            if (!consumed and std.mem.startsWith(u8, remaining, prefix)) {
                const bit: u8 = @as(u8, 1) << @intCast(index);
                if (seen & bit != 0) return false;
                seen |= bit;
                count += 1;
                remaining = remaining[prefix.len..];
                consumed = true;
            }
        }
        if (!consumed) break;
    }
    if (count > 4 or remaining.len == 0) return false;
    if (remaining.len == 1) return std.ascii.isLower(remaining[0]) or std.ascii.isDigit(remaining[0]) or std.mem.indexOfScalar(u8, "`-=[]\\;',./!@#$%^&*()_+|~{}:<>?", remaining[0]) != null;
    for ([_][]const u8{ "escape", "esc", "enter", "return", "tab", "space", "backspace", "delete", "insert", "clear", "home", "end", "pageUp", "pageDown", "up", "down", "left", "right", "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12" }) |name| if (std.mem.eql(u8, remaining, name)) return true;
    return false;
}

fn valueMatches(value: std.json.Value, normalized_input: []const u8) bool {
    switch (value) {
        .string => |key| {
            var buf: [96]u8 = undefined;
            const normalized = normalizeKey(key, &buf) orelse return false;
            return std.mem.eql(u8, normalized, normalized_input);
        },
        .array => |array| {
            for (array.items) |item| {
                if (item != .string) continue;
                var buf: [96]u8 = undefined;
                const normalized = normalizeKey(item.string, &buf) orelse continue;
                if (std.mem.eql(u8, normalized, normalized_input)) return true;
            }
            return false;
        },
        else => return false,
    }
}

fn valuesOverlap(a: std.json.Value, b: std.json.Value) bool {
    const Values = struct {
        fn visit(left: std.json.Value, right: std.json.Value) bool {
            switch (left) {
                .string => |key| {
                    var buf: [96]u8 = undefined;
                    const normalized = normalizeKey(key, &buf) orelse return false;
                    return valueMatches(right, normalized);
                },
                .array => |array| {
                    for (array.items) |item| if (item == .string) {
                        var buf: [96]u8 = undefined;
                        const normalized = normalizeKey(item.string, &buf) orelse continue;
                        if (valueMatches(right, normalized)) return true;
                    };
                    return false;
                },
                else => return false,
            }
        }
    };
    return Values.visit(a, b);
}

pub fn normalizeKey(input: []const u8, out: *[96]u8) ?[]const u8 {
    var ctrl = false;
    var shift = false;
    var alt = false;
    var super = false;
    var base_value = input;
    while (true) {
        if (std.ascii.startsWithIgnoreCase(base_value, "ctrl+")) {
            if (ctrl) return null;
            ctrl = true;
            base_value = base_value[5..];
        } else if (std.ascii.startsWithIgnoreCase(base_value, "shift+")) {
            if (shift) return null;
            shift = true;
            base_value = base_value[6..];
        } else if (std.ascii.startsWithIgnoreCase(base_value, "alt+")) {
            if (alt) return null;
            alt = true;
            base_value = base_value[4..];
        } else if (std.ascii.startsWithIgnoreCase(base_value, "super+")) {
            if (super) return null;
            super = true;
            base_value = base_value[6..];
        } else break;
    }
    if (base_value.len == 0 or (std.mem.indexOfScalar(u8, base_value, '+') != null and !std.mem.eql(u8, base_value, "+"))) return null;
    if (std.ascii.eqlIgnoreCase(base_value, "esc")) base_value = "escape";
    if (std.ascii.eqlIgnoreCase(base_value, "return")) base_value = "enter";

    var pos: usize = 0;
    const Writer = struct {
        fn append(buf: *[96]u8, index: *usize, bytes: []const u8) bool {
            if (index.* + bytes.len > buf.len) return false;
            @memcpy(buf[index.* .. index.* + bytes.len], bytes);
            index.* += bytes.len;
            return true;
        }
    };
    if (ctrl and !Writer.append(out, &pos, "ctrl+")) return null;
    if (shift and !Writer.append(out, &pos, "shift+")) return null;
    if (alt and !Writer.append(out, &pos, "alt+")) return null;
    if (super and !Writer.append(out, &pos, "super+")) return null;
    if (pos + base_value.len > out.len) return null;
    for (base_value) |c| {
        out[pos] = std.ascii.toLower(c);
        pos += 1;
    }
    return out[0..pos];
}

test "named selection keybindings accept raw terminal sequences configurable arrays and explicit disable" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    try std.testing.expect(manager.matchesActionName("tui.select.up", "\x1b[A"));
    try std.testing.expect(manager.matchesActionName("tui.select.confirm", "\r"));
    try std.testing.expect(manager.matchesActionName("tui.select.cancel", "\x1b"));
    try std.testing.expect(manager.matchesActionName("tui.select.cancel", "\x03"));
    try std.testing.expect(!manager.matchesActionName("tui.select.up", "k"));
    manager.parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"tui.select.up\":[\"ctrl+k\",\"alt+up\"],\"tui.select.cancel\":[],\"tui.select.confirm\":\"ctrl+y\"}", .{});
    try std.testing.expect(!manager.matchesActionName("tui.select.up", "\x1b[A"));
    try std.testing.expect(manager.matchesActionName("tui.select.up", "\x0b"));
    try std.testing.expect(manager.matchesActionName("tui.select.up", "\x1b[1;3A"));
    try std.testing.expect(!manager.matchesActionName("tui.select.cancel", "\x1b"));
    try std.testing.expect(manager.matchesActionName("tui.select.confirm", "\x19"));
    try std.testing.expect(!manager.matchesActionName("tui.select.confirm", "\r"));
}

test "current keybinding value schema replays actual TypeBox validation and drops invalid configured values" {
    var normalized: [96]u8 = undefined;
    try std.testing.expectEqualStrings("ctrl++", normalizeKey("ctrl++", &normalized).?);
    try std.testing.expect(normalizeKey("ctrl+ctrl+c", &normalized) == null);
    const gpa = std.testing.allocator;
    const capture = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("fixtures/keybinding-schema-6fb-original.json"), .{});
    defer capture.deinit();
    for (capture.value.object.get("rows").?.array.items) |row| try std.testing.expectEqual(row.object.get("result").?.bool, validBindingValue(row.object.get("input").?));
    var scratch = std.testing.tmpDir(.{});
    defer scratch.cleanup();
    try scratch.dir.writeFile(std.testing.io, .{ .sub_path = "keybindings.json", .data = "{\"$schema\":\"schema.json\",\"tui.select.up\":[\"up\",3],\"tui.select.cancel\":[],\"tui.select.confirm\":\"ctrl++\"}" });
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try scratch.dir.realPath(std.testing.io, &buffer);
    var manager = try Manager.load(gpa, std.testing.io, buffer[0..len]);
    defer manager.deinit();
    try std.testing.expect(manager.matchesActionName("tui.select.up", "\x1b[A"));
    try std.testing.expect(!manager.matchesActionName("tui.select.cancel", "\x1b"));
    try std.testing.expect(manager.matchesActionName("tui.select.confirm", "\x1b[61:43;6u"));
    try std.testing.expect(manager.parsed.?.value.object.get("$schema") == null);
}

test "keybinding defaults normalize modifier order" {
    var manager = Manager.init(std.testing.allocator);
    defer manager.deinit();
    try std.testing.expectEqual(Action.cursor_left, manager.actionFor("ctrl+b").?);
    try std.testing.expectEqual(Action.cursor_word_left, manager.actionFor("ctrl+left").?);
    try std.testing.expectEqual(Action.cursor_line_start, manager.actionFor("home").?);
    try std.testing.expectEqual(Action.cursor_line_end, manager.actionFor("end").?);
    try std.testing.expect(manager.actionFor("ctrl+home") == null);
    try std.testing.expect(manager.actionFor("ctrl+end") == null);
    try std.testing.expectEqual(ViewportAction.top, manager.viewportActionFor("ctrl+home").?);
    try std.testing.expectEqual(ViewportAction.bottom, manager.viewportActionFor("ctrl+end").?);
    try std.testing.expectEqual(Action.clipboard_paste, manager.actionFor(if (builtin.os.tag == .windows) "alt+v" else "ctrl+v").?);
    var buf: [96]u8 = undefined;
    try std.testing.expectEqualStrings("ctrl+shift+p", normalizeKey("shift+ctrl+P", &buf).?);
}

test "keybindings json replaces defaults, accepts legacy ids and reports conflicts" {
    const gpa = std.testing.allocator;
    const raw =
        \\{"cursorLeft":"alt+h","tui.editor.cursorRight":["alt+l"],"tui.editor.yank":"alt+l","pasteImage":"alt+v"}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{ .allocate = .alloc_always });
    var manager = Manager{ .gpa = gpa, .parsed = parsed };
    defer manager.deinit();
    try std.testing.expect(manager.actionFor("left") == null);
    try std.testing.expectEqual(Action.cursor_left, manager.actionFor("alt+h").?);
    try std.testing.expectEqual(Action.cursor_right, manager.actionFor("alt+l").?);
    try std.testing.expect(manager.conflictCount() >= 1);
    try std.testing.expectEqual(Action.clipboard_paste, manager.actionFor("alt+v").?);
    if (builtin.os.tag != .windows) try std.testing.expect(manager.actionFor("ctrl+v") == null);
}
