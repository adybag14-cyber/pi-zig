//! POSIX terminal adapter for the native editor core.
//! Non-TTY callers keep using the line-oriented fallback in main.zig.
const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const Editor = @import("editor.zig").Editor;
const Action = @import("editor.zig").Action;
const render = @import("render.zig");
const terminal = @import("terminal.zig");
const rich_keys = @import("keys.zig");
const keybindings = @import("keybindings.zig");
const mouse = @import("mouse.zig");

pub fn available(io: Io) bool {
    if (comptime builtin.os.tag != .linux) return false;
    return Io.File.stdin().isTty(io) catch false;
}

pub fn windowsRightClickPasteEnabled(term_program: ?[]const u8) bool {
    if (builtin.os.tag != .windows) return false;
    const program = term_program orelse return true;
    return !std.ascii.eqlIgnoreCase(std.mem.trim(u8, program, " \t\r\n"), "vscode");
}

pub const RawMode = struct {
    original: std.posix.termios,

    pub fn enter() !RawMode {
        if (comptime builtin.os.tag != .linux) return error.UnsupportedTerminal;
        const fd = Io.File.stdin().handle;
        const original = try std.posix.tcgetattr(fd);
        var raw = original;
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ECHONL = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;
        raw.iflag.ICRNL = false;
        raw.iflag.IXON = false;
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        try std.posix.tcsetattr(fd, .FLUSH, raw);
        return .{ .original = original };
    }

    pub fn leave(self: *RawMode) void {
        if (comptime builtin.os.tag == .linux) {
            std.posix.tcsetattr(Io.File.stdin().handle, .FLUSH, self.original) catch {};
        }
    }
};

const RenderState = struct {
    line_count: usize = 1,
    cursor_row: usize = 0,
    initialized: bool = false,
};

fn writeMove(io: Io, amount: usize, code: u8) !void {
    if (amount == 0) return;
    var buf: [40]u8 = undefined;
    const seq = try std.fmt.bufPrint(&buf, "\x1b[{d}{c}", .{ amount, code });
    try render.writeAll(io, seq);
}

fn erasePrevious(io: Io, state: *const RenderState) !void {
    if (!state.initialized) {
        try render.writeAll(io, "\r\x1b[2K");
        return;
    }
    try render.writeAll(io, "\r");
    try writeMove(io, state.cursor_row, 'A');
    var row: usize = 0;
    while (row < state.line_count) : (row += 1) {
        try render.writeAll(io, "\x1b[2K");
        if (row + 1 < state.line_count) try render.writeAll(io, "\n");
    }
    if (state.line_count > 1) try writeMove(io, state.line_count - 1, 'A');
    try render.writeAll(io, "\r");
}

fn lineMetrics(text: []const u8, cursor: usize) struct { count: usize, cursor_row: usize, cursor_col: usize } {
    var count: usize = 1;
    var cursor_row: usize = 0;
    var cursor_line_start: usize = 0;
    for (text, 0..) |c, i| {
        if (c != '\n') continue;
        count += 1;
        if (i < cursor) {
            cursor_row += 1;
            cursor_line_start = i + 1;
        }
    }
    return .{
        .count = count,
        .cursor_row = cursor_row,
        .cursor_col = terminal.visibleWidth(text[cursor_line_start..@min(cursor, text.len)]),
    };
}

fn redraw(io: Io, editor: *const Editor, prompt: []const u8, state: *RenderState) !void {
    try erasePrevious(io, state);
    const prompt_width = terminal.visibleWidth(prompt);
    var line_start: usize = 0;
    var row: usize = 0;
    while (true) : (row += 1) {
        const newline = std.mem.indexOfScalarPos(u8, editor.slice(), line_start, '\n');
        const line_end = newline orelse editor.slice().len;
        if (row == 0) {
            try render.writeAll(io, prompt);
        } else {
            var spaces: [64]u8 = undefined;
            const n = @min(prompt_width, spaces.len);
            @memset(spaces[0..n], ' ');
            try render.writeAll(io, spaces[0..n]);
        }
        try render.writeAll(io, editor.slice()[line_start..line_end]);
        if (newline == null) break;
        try render.writeAll(io, "\n");
        line_start = line_end + 1;
    }

    const metrics = lineMetrics(editor.slice(), editor.cursor);
    const final_row = metrics.count - 1;
    if (final_row > metrics.cursor_row) try writeMove(io, final_row - metrics.cursor_row, 'A');
    try render.writeAll(io, "\r");
    try writeMove(io, prompt_width + metrics.cursor_col, 'C');
    state.* = .{ .line_count = metrics.count, .cursor_row = metrics.cursor_row, .initialized = true };
}

fn readByte(reader: *Io.File.Reader) !u8 {
    return reader.interface.takeByte();
}

fn readUtf8(reader: *Io.File.Reader, first: u8, out: *[4]u8) ![]const u8 {
    out[0] = first;
    const n = std.unicode.utf8ByteSequenceLength(first) catch 1;
    if (n <= 1) return out[0..1];
    var i: usize = 1;
    while (i < n) : (i += 1) out[i] = try readByte(reader);
    _ = std.unicode.utf8Decode(out[0..n]) catch return out[0..1];
    return out[0..n];
}

pub const Completion = struct {
    text: []u8,
    cursor: usize,

    pub fn deinit(self: *Completion, gpa: std.mem.Allocator) void {
        gpa.free(self.text);
        self.* = undefined;
    }
};

pub const Completer = struct {
    context: *anyopaque,
    complete_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8, usize) anyerror!?Completion,

    pub fn complete(self: Completer, gpa: std.mem.Allocator, line: []const u8, cursor: usize) !?Completion {
        return self.complete_fn(self.context, gpa, line, cursor);
    }
};

pub const ShortcutResult = enum {
    not_handled,
    handled_continue,
    handled_interrupt,
};

pub const ShortcutHandler = struct {
    context: *anyopaque,
    handle_fn: *const fn (*anyopaque, std.mem.Allocator, []const u8) anyerror!ShortcutResult,
    clipboard_paste_fn: ?*const fn (*anyopaque, std.mem.Allocator) anyerror!ShortcutResult = null,
    right_click_paste_enabled: bool = builtin.os.tag == .windows,

    pub fn handle(self: ShortcutHandler, gpa: std.mem.Allocator, key_id: []const u8) !ShortcutResult {
        return self.handle_fn(self.context, gpa, key_id);
    }

    pub fn clipboardPaste(self: ShortcutHandler, gpa: std.mem.Allocator) !ShortcutResult {
        const callback = self.clipboard_paste_fn orelse return .not_handled;
        return callback(self.context, gpa);
    }
};

const Disposition = enum { keep_editing, submit, cancel, interrupt, exit };

fn applyEditorAction(editor: *Editor, action: keybindings.Action) !Disposition {
    switch (action) {
        .cursor_up => if (std.mem.indexOfScalar(u8, editor.slice(), '\n') == null) try editor.apply(.history_previous) else try editor.apply(.cursor_up),
        .cursor_down => if (std.mem.indexOfScalar(u8, editor.slice(), '\n') == null) try editor.apply(.history_next) else try editor.apply(.cursor_down),
        .cursor_left => try editor.apply(.cursor_left),
        .cursor_right => try editor.apply(.cursor_right),
        .cursor_word_left => try editor.apply(.cursor_word_left),
        .cursor_word_right => try editor.apply(.cursor_word_right),
        .cursor_line_start => try editor.apply(.cursor_line_start),
        .cursor_line_end => try editor.apply(.cursor_line_end),
        .delete_char_backward => try editor.apply(.delete_char_backward),
        .delete_char_forward => try editor.apply(.delete_char_forward),
        .delete_word_backward => try editor.apply(.delete_word_backward),
        .delete_word_forward => try editor.apply(.delete_word_forward),
        .delete_to_line_start => try editor.apply(.delete_to_line_start),
        .delete_to_line_end => try editor.apply(.delete_to_line_end),
        .yank => try editor.apply(.yank),
        .yank_pop => try editor.apply(.yank_pop),
        .undo => try editor.apply(.undo),
        .new_line => try editor.insert("\n"),
        .tab => try editor.insert("\t"),
        .clipboard_paste => {},
        .submit => return .submit,
        .clear => return .cancel,
        .exit => return .exit,
    }
    return .keep_editing;
}

fn dispatchKey(gpa: std.mem.Allocator, editor: *Editor, bindings: *const keybindings.Manager, key_id: []const u8, shortcut: ?ShortcutHandler) !Disposition {
    if (shortcut) |handler| switch (try handler.handle(gpa, key_id)) {
        .not_handled => {},
        .handled_continue => return .keep_editing,
        .handled_interrupt => return .interrupt,
    };
    // App exit is context-sensitive upstream: ctrl+d is delete-forward while
    // the editor contains text, and exits only from an empty editor.
    if (editor.slice().len == 0 and bindings.matches(key_id, .exit)) return .exit;
    if (bindings.matches(key_id, .clear)) return .cancel;
    if (bindings.actionFor(key_id)) |action| return applyEditorAction(editor, action);
    return .keep_editing;
}

fn modifierPrefix(param: u8) []const u8 {
    // xterm/Kitty modifier parameter = 1 + shift(1) + alt(2) + ctrl(4).
    return switch (param) {
        2 => "shift+",
        3 => "alt+",
        4 => "shift+alt+",
        5 => "ctrl+",
        6 => "ctrl+shift+",
        7 => "ctrl+alt+",
        8 => "ctrl+shift+alt+",
        else => "",
    };
}

fn csiKeyId(final: u8, params: []const u8, out: *[64]u8) ?[]const u8 {
    const base: []const u8 = switch (final) {
        'A' => "up",
        'B' => "down",
        'C' => "right",
        'D' => "left",
        'H' => "home",
        'F' => "end",
        else => return null,
    };
    var mod: u8 = 1;
    if (std.mem.lastIndexOfScalar(u8, params, ';')) |idx| mod = std.fmt.parseInt(u8, params[idx + 1 ..], 10) catch 1;
    const prefix = modifierPrefix(mod);
    if (prefix.len + base.len > out.len) return null;
    @memcpy(out[0..prefix.len], prefix);
    @memcpy(out[prefix.len .. prefix.len + base.len], base);
    return out[0 .. prefix.len + base.len];
}

fn kittyCsiU(gpa: std.mem.Allocator, editor: *Editor, bindings: *const keybindings.Manager, params: []const u8, shortcut: ?ShortcutHandler) !Disposition {
    // CSI-u: codepoint[:shifted[:base]];modifier[:event]u. We use the
    // identity codepoint, canonical modifier bits, and ignore key-release
    // events exactly as a text editor should.
    const semi = std.mem.indexOfScalar(u8, params, ';');
    const code_field = if (semi) |i| params[0..i] else params;
    const code_end = std.mem.indexOfScalar(u8, code_field, ':') orelse code_field.len;
    const codepoint = std.fmt.parseInt(u21, code_field[0..code_end], 10) catch return .keep_editing;
    var modifier_value: u8 = 1;
    var event_value: u8 = 1;
    if (semi) |i| {
        const modifier_field = params[i + 1 ..];
        const colon = std.mem.indexOfScalar(u8, modifier_field, ':');
        const mod_text = if (colon) |j| modifier_field[0..j] else modifier_field;
        modifier_value = std.fmt.parseInt(u8, mod_text, 10) catch 1;
        if (colon) |j| event_value = std.fmt.parseInt(u8, modifier_field[j + 1 ..], 10) catch 1;
    }
    if (event_value == 3) return .keep_editing; // release

    const base: ?[]const u8 = switch (codepoint) {
        9 => "tab",
        13 => "enter",
        27 => "escape",
        32 => "space",
        127 => "backspace",
        57414 => "enter", // keypad Enter
        57417 => "left",
        57418 => "right",
        57419 => "up",
        57420 => "down",
        57421 => "pageup",
        57422 => "pagedown",
        57423 => "home",
        57424 => "end",
        57425 => "insert",
        57426 => "delete",
        else => null,
    };
    const prefix = modifierPrefix(modifier_value);
    if (base) |named| {
        var key_buf: [64]u8 = undefined;
        if (prefix.len + named.len > key_buf.len) return .keep_editing;
        @memcpy(key_buf[0..prefix.len], prefix);
        @memcpy(key_buf[prefix.len .. prefix.len + named.len], named);
        return dispatchKey(gpa, editor, bindings, key_buf[0 .. prefix.len + named.len], shortcut);
    }

    var encoded: [4]u8 = undefined;
    const n = std.unicode.utf8Encode(codepoint, &encoded) catch return .keep_editing;
    if (prefix.len == 0) {
        if (n == 1) {
            if (bindings.actionFor(encoded[0..1])) |action| return applyEditorAction(editor, action);
        }
        try editor.insert(encoded[0..n]);
        return .keep_editing;
    }
    if (n == 1 and encoded[0] >= 0x20 and encoded[0] < 0x7f) {
        var key_buf: [64]u8 = undefined;
        if (prefix.len + 1 > key_buf.len) return .keep_editing;
        @memcpy(key_buf[0..prefix.len], prefix);
        key_buf[prefix.len] = std.ascii.toLower(encoded[0]);
        return dispatchKey(gpa, editor, bindings, key_buf[0 .. prefix.len + 1], shortcut);
    }
    return .keep_editing;
}

fn dispatchMouseShortcut(
    gpa: std.mem.Allocator,
    event: mouse.Event,
    shortcut: ?ShortcutHandler,
    right_click_paste_enabled: bool,
) !Disposition {
    if (!right_click_paste_enabled or event.kind != .press or event.button != .right) return .keep_editing;
    if (event.modifiers.shift or event.modifiers.alt or event.modifiers.ctrl) return .keep_editing;
    if (shortcut) |handler| switch (try handler.clipboardPaste(gpa)) {
        .not_handled, .handled_continue => return .keep_editing,
        .handled_interrupt => return .interrupt,
    };
    return .keep_editing;
}

fn dispatchTerminalSequence(
    gpa: std.mem.Allocator,
    editor: *Editor,
    bindings: *const keybindings.Manager,
    sequence: []const u8,
    shortcut: ?ShortcutHandler,
) !Disposition {
    if (mouse.parse(sequence)) |event| return dispatchMouseShortcut(gpa, event, shortcut, if (shortcut) |handler| handler.right_click_paste_enabled else false);
    if (rich_keys.isKeyRelease(sequence)) return .keep_editing;

    // Plain and Shift-only CSI-u/modifyOtherKeys events are text input. Use
    // the alternate shifted codepoint when the terminal supplied one.
    if (try rich_keys.decodePrintableKey(gpa, sequence)) |printable| {
        defer gpa.free(printable);
        if (shortcut) |handler| switch (try handler.handle(gpa, printable)) {
            .not_handled => {},
            .handled_continue => return .keep_editing,
            .handled_interrupt => return .interrupt,
        };
        if (printable.len == 1 and printable[0] < 0x7f) {
            if (bindings.actionFor(printable)) |action| return applyEditorAction(editor, action);
        }
        try editor.insert(printable);
        return .keep_editing;
    }

    const parsed = rich_keys.parseKeyWithOptions(sequence, .{ .kitty_active = true }) orelse return .keep_editing;
    if (parsed.event_type == .release) return .keep_editing;
    const key_id = try parsed.formatAlloc(gpa);
    defer gpa.free(key_id);
    return dispatchKey(gpa, editor, bindings, key_id, shortcut);
}

fn readBracketedPaste(gpa: std.mem.Allocator, reader: *Io.File.Reader, editor: *Editor) !void {
    const end_marker = "\x1b[201~";
    var pasted: std.ArrayList(u8) = .empty;
    defer pasted.deinit(gpa);
    while (true) {
        if (pasted.items.len >= 64 * 1024 * 1024) return error.PasteTooLarge;
        try pasted.append(gpa, try readByte(reader));
        if (std.mem.endsWith(u8, pasted.items, end_marker)) {
            pasted.items.len -= end_marker.len;
            break;
        }
    }

    const normalized = try normalizePasteAlloc(gpa, pasted.items);
    defer gpa.free(normalized);
    if (normalized.len > 0) try editor.insert(normalized);
}

/// Apply the same hygiene to bracketed terminal paste and clipboard-command
/// text fallback. This prevents platform clipboard contents from bypassing the
/// editor's newline/control normalization merely because they arrived through
/// Ctrl+V rather than the terminal's bracketed-paste protocol.
pub fn normalizePasteAlloc(gpa: std.mem.Allocator, input: []const u8) ![]u8 {
    // Match upstream paste hygiene: canonical newlines, no NUL/control bytes,
    // and tabs expanded to four spaces. Escape remains allowed because pasted
    // source can legitimately contain ANSI examples.
    var normalized: std.ArrayList(u8) = .empty;
    errdefer normalized.deinit(gpa);
    var index: usize = 0;
    while (index < input.len) : (index += 1) {
        const byte = input[index];
        if (byte == '\r') {
            if (index + 1 < input.len and input[index + 1] == '\n') index += 1;
            try normalized.append(gpa, '\n');
        } else if (byte == '\t') {
            try normalized.appendSlice(gpa, "    ");
        } else if (byte == '\n' or byte == 0x1b or byte >= 0x20) {
            try normalized.append(gpa, byte);
        }
    }
    return normalized.toOwnedSlice(gpa);
}

fn consumeControlString(reader: *Io.File.Reader, allow_bel: bool) !void {
    var previous_escape = false;
    while (true) {
        const byte = try readByte(reader);
        if (allow_bel and byte == 0x07) return;
        if (previous_escape and byte == '\\') return;
        previous_escape = byte == 0x1b;
    }
}

fn consumeEscape(
    gpa: std.mem.Allocator,
    reader: *Io.File.Reader,
    editor: *Editor,
    bindings: *const keybindings.Manager,
    shortcut: ?ShortcutHandler,
) !Disposition {
    var sequence: [4096]u8 = undefined;
    sequence[0] = 0x1b;
    var len: usize = 1;
    const second = try readByte(reader);
    sequence[len] = second;
    len += 1;

    switch (second) {
        ']' => {
            try consumeControlString(reader, true);
            return .keep_editing;
        },
        'P', '_' => {
            try consumeControlString(reader, false);
            return .keep_editing;
        },
        'O' => {
            sequence[len] = try readByte(reader);
            len += 1;
            return dispatchTerminalSequence(gpa, editor, bindings, sequence[0..len], shortcut);
        },
        '[' => {
            while (len < sequence.len) {
                const byte = try readByte(reader);
                sequence[len] = byte;
                len += 1;
                if (byte >= '@' and byte <= '~') {
                    // SGR mouse starts with '<'; only M/m terminates it.
                    if (len > 3 and sequence[2] == '<' and byte != 'M' and byte != 'm') continue;
                    if (std.mem.eql(u8, sequence[0..len], "\x1b[200~")) {
                        try readBracketedPaste(gpa, reader, editor);
                        return .keep_editing;
                    }
                    return dispatchTerminalSequence(gpa, editor, bindings, sequence[0..len], shortcut);
                }
            }
            return .keep_editing;
        },
        else => return dispatchTerminalSequence(gpa, editor, bindings, sequence[0..len], shortcut),
    }
}

fn ctrlKeyId(byte: u8, out: *[16]u8) ?[]const u8 {
    if (byte < 1 or byte > 26) return null;
    const prefix = "ctrl+";
    @memcpy(out[0..prefix.len], prefix);
    out[prefix.len] = 'a' + byte - 1;
    return out[0 .. prefix.len + 1];
}

/// Read one interactively edited line. The returned slice belongs to allocator.
pub fn readLine(gpa: std.mem.Allocator, io: Io, reader: *Io.File.Reader, editor: *Editor, bindings: *const keybindings.Manager, prompt: []const u8) ![]u8 {
    return readLineWithCompleter(gpa, io, reader, editor, bindings, prompt, null);
}

pub fn readLineWithCompleter(gpa: std.mem.Allocator, io: Io, reader: *Io.File.Reader, editor: *Editor, bindings: *const keybindings.Manager, prompt: []const u8, completer: ?Completer) ![]u8 {
    return readLineWithCompleterAndShortcuts(gpa, io, reader, editor, bindings, prompt, completer, null);
}

pub fn readLineWithCompleterAndShortcuts(gpa: std.mem.Allocator, io: Io, reader: *Io.File.Reader, editor: *Editor, bindings: *const keybindings.Manager, prompt: []const u8, completer: ?Completer, shortcut: ?ShortcutHandler) ![]u8 {
    return readLineWithCompleterAndShortcutsPrefill(gpa, io, reader, editor, bindings, prompt, completer, shortcut, "");
}

/// Read one interactively edited line with caller-supplied initial text. This
/// is used by extension dialogs and `setEditorText()` while retaining the same
/// Unicode, paste, history, keybinding and shortcut behavior as the core REPL.
/// Nested use is safe: if a shortcut opens a dialog while the outer editor is
/// already in raw mode, the inner guard restores that raw state on return.
pub fn readLineWithCompleterAndShortcutsPrefill(gpa: std.mem.Allocator, io: Io, reader: *Io.File.Reader, editor: *Editor, bindings: *const keybindings.Manager, prompt: []const u8, completer: ?Completer, shortcut: ?ShortcutHandler, prefill: []const u8) ![]u8 {
    var raw = try RawMode.enter();
    defer raw.leave();
    try render.writeAll(io, terminal.bracketed_paste_enable);
    defer render.writeAll(io, terminal.bracketed_paste_disable) catch {};

    try editor.setText(prefill);
    var render_state: RenderState = .{};
    try redraw(io, editor, prompt, &render_state);
    while (true) {
        const b = readByte(reader) catch |err| switch (err) {
            error.EndOfStream => return error.EndOfStream,
            else => return err,
        };
        var disposition: Disposition = .keep_editing;
        if (b == 0x1b) {
            disposition = try consumeEscape(gpa, reader, editor, bindings, shortcut);
        } else if (b == 0x7f or b == 0x08) {
            disposition = try dispatchKey(gpa, editor, bindings, "backspace", shortcut);
        } else if (b == 13) {
            disposition = try dispatchKey(gpa, editor, bindings, "enter", shortcut);
        } else if (b == 9) {
            if (shortcut) |handler| switch (try handler.handle(gpa, "tab")) {
                .not_handled => {},
                .handled_continue => disposition = .keep_editing,
                .handled_interrupt => disposition = .interrupt,
            };
            if (disposition == .keep_editing) {
                if (completer) |completion_provider| {
                    if (try completion_provider.complete(gpa, editor.slice(), editor.cursor)) |completion_value| {
                        var completion = completion_value;
                        defer completion.deinit(gpa);
                        try editor.setTextAt(completion.text, completion.cursor);
                    } else {
                        disposition = try dispatchKey(gpa, editor, bindings, "tab", null);
                    }
                } else {
                    disposition = try dispatchKey(gpa, editor, bindings, "tab", null);
                }
            }
        } else if (b == 10) {
            disposition = try dispatchKey(gpa, editor, bindings, "ctrl+j", shortcut);
        } else if (b >= 1 and b <= 26) {
            var key_buf: [16]u8 = undefined;
            if (ctrlKeyId(b, &key_buf)) |key| disposition = try dispatchKey(gpa, editor, bindings, key, shortcut);
        } else if (b >= 0x20) {
            var utf8: [4]u8 = undefined;
            const bytes = try readUtf8(reader, b, &utf8);
            if (shortcut) |handler| switch (try handler.handle(gpa, bytes)) {
                .not_handled => {},
                .handled_continue => disposition = .keep_editing,
                .handled_interrupt => disposition = .interrupt,
            };
            if (disposition == .keep_editing) {
                if (bytes.len == 1 and bytes[0] < 0x7f) {
                    const key = bytes[0..1];
                    if (bindings.actionFor(key)) |action| disposition = try applyEditorAction(editor, action) else try editor.insert(bytes);
                } else try editor.insert(bytes);
            }
        }

        switch (disposition) {
            .keep_editing => {},
            .submit => {
                const result = try gpa.dupe(u8, editor.slice());
                if (result.len > 0) try editor.addHistory(result);
                try render.writeAll(io, "\r\n");
                return result;
            },
            .cancel => {
                try editor.setText("");
                try render.writeAll(io, "^C\r\n");
                return try gpa.dupe(u8, "");
            },
            .interrupt => {
                try render.writeAll(io, "\r\n");
                return try gpa.dupe(u8, "");
            },
            .exit => return error.EndOfStream,
        }
        try redraw(io, editor, prompt, &render_state);
    }
}

test "paste normalization is shared by bracketed and clipboard text" {
    const normalized = try normalizePasteAlloc(std.testing.allocator, "a\r\nb\rc\td\x00\x01e");
    defer std.testing.allocator.free(normalized);
    try std.testing.expectEqualStrings("a\nb\nc    de", normalized);
}

test "extension shortcuts run before editor keybindings" {
    const Handler = struct {
        called: bool = false,
        fn handle(raw: *anyopaque, gpa: std.mem.Allocator, key: []const u8) !ShortcutResult {
            _ = gpa;
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (!std.mem.eql(u8, key, "ctrl+k")) return .not_handled;
            self.called = true;
            return .handled_interrupt;
        }
    };
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    var state = Handler{};
    const handler = ShortcutHandler{ .context = &state, .handle_fn = Handler.handle };
    try std.testing.expectEqual(Disposition.interrupt, try dispatchKey(std.testing.allocator, &editor, &bindings, "ctrl+k", handler));
    try std.testing.expect(state.called);
    try std.testing.expectEqual(@as(usize, 0), editor.slice().len);
}

test "shortcut handlers can mutate editor without ending the read" {
    const Handler = struct {
        fn handle(raw: *anyopaque, gpa: std.mem.Allocator, key: []const u8) !ShortcutResult {
            _ = gpa;
            const editor: *Editor = @ptrCast(@alignCast(raw));
            if (!std.mem.eql(u8, key, "ctrl+v")) return .not_handled;
            try editor.insert("@\"/tmp/image.png\"");
            return .handled_continue;
        }
    };
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    const handler = ShortcutHandler{ .context = &editor, .handle_fn = Handler.handle };
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchKey(std.testing.allocator, &editor, &bindings, "ctrl+v", handler));
    try std.testing.expectEqualStrings("@\"/tmp/image.png\"", editor.slice());
}

test "Kitty CSI-u dispatches modifiers and ignores releases" {
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    try editor.setText("ab");
    try std.testing.expectEqual(Disposition.keep_editing, try kittyCsiU(std.testing.allocator, &editor, &bindings, "98;5", null)); // ctrl+b
    try std.testing.expectEqual(@as(usize, 1), editor.cursor);
    try std.testing.expectEqual(Disposition.keep_editing, try kittyCsiU(std.testing.allocator, &editor, &bindings, "13;2", null)); // shift+enter
    try std.testing.expectEqualStrings("a\nb", editor.slice());
    const before = editor.cursor;
    try std.testing.expectEqual(Disposition.keep_editing, try kittyCsiU(std.testing.allocator, &editor, &bindings, "102;5:3", null)); // ctrl+f release
    try std.testing.expectEqual(before, editor.cursor);
}

test "Kitty CSI-u inserts Unicode identity codepoints" {
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    try std.testing.expectEqual(Disposition.keep_editing, try kittyCsiU(std.testing.allocator, &editor, &bindings, "20320", null)); // 你
    try std.testing.expectEqualStrings("你", editor.slice());
}

test "rich terminal sequence dispatch uses base-layout identity and ignores releases" {
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    try editor.setText("ab");
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchTerminalSequence(std.testing.allocator, &editor, &bindings, "\x1b[1089::98;5u", null));
    try std.testing.expectEqual(@as(usize, 1), editor.cursor); // Ctrl+B
    const before = editor.cursor;
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchTerminalSequence(std.testing.allocator, &editor, &bindings, "\x1b[102;5:3u", null));
    try std.testing.expectEqual(before, editor.cursor);
}

test "rich terminal sequence inserts shifted and Unicode printable CSI-u" {
    var editor = Editor.init(std.testing.allocator);
    defer editor.deinit();
    var bindings = keybindings.Manager.init(std.testing.allocator);
    defer bindings.deinit();
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchTerminalSequence(std.testing.allocator, &editor, &bindings, "\x1b[97:65;2u", null));
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchTerminalSequence(std.testing.allocator, &editor, &bindings, "\x1b[20320u", null));
    try std.testing.expectEqualStrings("A你", editor.slice());
}

test "Windows right click requests non-interrupting clipboard paste" {
    const Probe = struct {
        calls: usize = 0,
        fn handle(_: *anyopaque, _: std.mem.Allocator, _: []const u8) !ShortcutResult {
            return .not_handled;
        }
        fn paste(raw: *anyopaque, _: std.mem.Allocator) !ShortcutResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            return .handled_continue;
        }
    };
    var probe = Probe{};
    const handler = ShortcutHandler{
        .context = &probe,
        .handle_fn = Probe.handle,
        .clipboard_paste_fn = Probe.paste,
    };
    const right = mouse.parse("\x1b[<2;4;3M").?;
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchMouseShortcut(std.testing.allocator, right, handler, true));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);

    const modified = mouse.parse("\x1b[<6;4;3M").?;
    try std.testing.expectEqual(Disposition.keep_editing, try dispatchMouseShortcut(std.testing.allocator, modified, handler, true));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);

    try std.testing.expectEqual(Disposition.keep_editing, try dispatchMouseShortcut(std.testing.allocator, right, handler, false));
    try std.testing.expectEqual(@as(usize, 1), probe.calls);
    if (builtin.os.tag == .windows) {
        try std.testing.expect(windowsRightClickPasteEnabled(null));
        try std.testing.expect(!windowsRightClickPasteEnabled("vscode"));
        try std.testing.expect(!windowsRightClickPasteEnabled(" VSCode \r\n"));
    }
}
