//! Rich terminal key parsing compatible with legacy terminals, xterm's
//! modifyOtherKeys mode, and the Kitty keyboard protocol.
const std = @import("std");

pub const modifier_shift: u16 = 1;
pub const modifier_alt: u16 = 2;
pub const modifier_ctrl: u16 = 4;
pub const modifier_super: u16 = 8;
pub const modifier_caps_lock: u16 = 64;
pub const modifier_num_lock: u16 = 128;
pub const lock_mask: u16 = modifier_caps_lock | modifier_num_lock;
pub const supported_modifier_mask: u16 = modifier_shift | modifier_alt | modifier_ctrl | modifier_super;

var kitty_protocol_active: bool = false;

pub fn setKittyProtocolActive(active: bool) void {
    kitty_protocol_active = active;
}

pub fn isKittyProtocolActive() bool {
    return kitty_protocol_active;
}

pub const EventType = enum {
    press,
    repeat,
    release,
};

pub const NamedKey = enum {
    escape,
    enter,
    tab,
    space,
    backspace,
    delete,
    insert,
    clear,
    home,
    end,
    page_up,
    page_down,
    up,
    down,
    left,
    right,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
};

pub const KeyName = union(enum) {
    named: NamedKey,
    codepoint: u21,
};

pub const ParsedKey = struct {
    key: KeyName,
    modifiers: u16 = 0,
    event_type: EventType = .press,

    pub fn effectiveModifiers(self: ParsedKey) u16 {
        return self.modifiers & ~lock_mask;
    }

    pub fn eql(a: ParsedKey, b: ParsedKey) bool {
        return std.meta.eql(a.key, b.key) and a.effectiveModifiers() == b.effectiveModifiers();
    }

    pub fn formatAlloc(self: ParsedKey, allocator: std.mem.Allocator) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        const modifiers = self.effectiveModifiers();
        if ((modifiers & modifier_shift) != 0) try out.writer.writeAll("shift+");
        if ((modifiers & modifier_ctrl) != 0) try out.writer.writeAll("ctrl+");
        if ((modifiers & modifier_alt) != 0) try out.writer.writeAll("alt+");
        if ((modifiers & modifier_super) != 0) try out.writer.writeAll("super+");
        switch (self.key) {
            .named => |named| try out.writer.writeAll(namedKeyId(named)),
            .codepoint => |cp| {
                var encoded: [4]u8 = undefined;
                const count = try std.unicode.utf8Encode(cp, &encoded);
                try out.writer.writeAll(encoded[0..count]);
            },
        }
        return out.toOwnedSlice();
    }
};

pub const ParseOptions = struct {
    kitty_active: bool = false,
    windows_terminal: bool = false,
};

pub fn parseOptionsFromEnvironment(environ: *const std.process.Environ.Map) ParseOptions {
    const has_wt = environ.get("WT_SESSION") != null;
    const ssh = environ.get("SSH_CONNECTION") != null or environ.get("SSH_CLIENT") != null or environ.get("SSH_TTY") != null;
    return .{ .kitty_active = kitty_protocol_active, .windows_terminal = has_wt and !ssh };
}

const ParsedSequence = struct {
    codepoint: i32,
    shifted_key: ?u21 = null,
    base_layout_key: ?u21 = null,
    modifiers: u16 = 0,
    event_type: EventType = .press,
};

const cp_arrow_up: i32 = -1;
const cp_arrow_down: i32 = -2;
const cp_arrow_right: i32 = -3;
const cp_arrow_left: i32 = -4;
const cp_delete: i32 = -10;
const cp_insert: i32 = -11;
const cp_page_up: i32 = -12;
const cp_page_down: i32 = -13;
const cp_home: i32 = -14;
const cp_end: i32 = -15;
const cp_kp_enter: i32 = 57414;

fn parseUnsigned(comptime T: type, bytes: []const u8) ?T {
    if (bytes.len == 0) return null;
    return std.fmt.parseUnsigned(T, bytes, 10) catch null;
}

fn eventType(value: ?u16) EventType {
    return switch (value orelse 1) {
        2 => .repeat,
        3 => .release,
        else => .press,
    };
}

fn parseModifierAndEvent(bytes: []const u8) ?struct { modifiers: u16, event_type: EventType } {
    var fields = std.mem.splitScalar(u8, bytes, ':');
    const raw_modifier = parseUnsigned(u16, fields.next() orelse return null) orelse return null;
    if (raw_modifier == 0) return null;
    const raw_event = if (fields.next()) |field| parseUnsigned(u16, field) else null;
    if (fields.next() != null) return null;
    return .{ .modifiers = raw_modifier - 1, .event_type = eventType(raw_event) };
}

fn normalizeFunctionalCodepoint(codepoint: i32) i32 {
    return switch (codepoint) {
        57399...57408 => 48 + (codepoint - 57399),
        57409 => '.',
        57410 => '/',
        57411 => '*',
        57412 => '-',
        57413 => '+',
        57415 => '=',
        57416 => ',',
        57417 => cp_arrow_left,
        57418 => cp_arrow_right,
        57419 => cp_arrow_up,
        57420 => cp_arrow_down,
        57421 => cp_page_up,
        57422 => cp_page_down,
        57423 => cp_home,
        57424 => cp_end,
        57425 => cp_insert,
        57426 => cp_delete,
        else => codepoint,
    };
}

fn normalizeShiftedLetter(codepoint: i32, modifiers: u16) i32 {
    const effective = modifiers & ~lock_mask;
    if ((effective & modifier_shift) != 0 and codepoint >= 'A' and codepoint <= 'Z') return codepoint + 32;
    return codepoint;
}

fn parseKittySequence(data: []const u8) ?ParsedSequence {
    if (data.len < 3 or !std.mem.startsWith(u8, data, "\x1b[")) return null;

    // CSI-u, including alternate shifted/base-layout codepoints.
    if (data[data.len - 1] == 'u') {
        const payload = data[2 .. data.len - 1];
        var semicolon = std.mem.splitScalar(u8, payload, ';');
        const key_field = semicolon.next() orelse return null;
        const modifier_field = semicolon.next();
        if (semicolon.next() != null) return null;

        var alternate = std.mem.splitScalar(u8, key_field, ':');
        const raw_cp = parseUnsigned(u32, alternate.next() orelse return null) orelse return null;
        if (raw_cp > std.math.maxInt(i32)) return null;
        const shifted_field = alternate.next();
        const base_field = alternate.next();
        if (alternate.next() != null) return null;
        const shifted = if (shifted_field) |field| if (field.len == 0) null else parseUnsigned(u21, field) else null;
        const base = if (base_field) |field| parseUnsigned(u21, field) else null;
        var modifiers: u16 = 0;
        var kind: EventType = .press;
        if (modifier_field) |field| {
            const parsed = parseModifierAndEvent(field) orelse return null;
            modifiers = parsed.modifiers;
            kind = parsed.event_type;
        }
        return .{
            .codepoint = @intCast(raw_cp),
            .shifted_key = shifted,
            .base_layout_key = base,
            .modifiers = modifiers,
            .event_type = kind,
        };
    }

    const final = data[data.len - 1];
    if (final == 'A' or final == 'B' or final == 'C' or final == 'D' or final == 'H' or final == 'F') {
        const payload = data[2 .. data.len - 1];
        if (!std.mem.startsWith(u8, payload, "1;")) return null;
        const parsed = parseModifierAndEvent(payload[2..]) orelse return null;
        const codepoint: i32 = switch (final) {
            'A' => cp_arrow_up,
            'B' => cp_arrow_down,
            'C' => cp_arrow_right,
            'D' => cp_arrow_left,
            'H' => cp_home,
            'F' => cp_end,
            else => unreachable,
        };
        return .{ .codepoint = codepoint, .modifiers = parsed.modifiers, .event_type = parsed.event_type };
    }

    if (data[data.len - 1] == '~') {
        const payload = data[2 .. data.len - 1];
        var semicolon = std.mem.splitScalar(u8, payload, ';');
        const key_number = parseUnsigned(u16, semicolon.next() orelse return null) orelse return null;
        const codepoint: i32 = switch (key_number) {
            2 => cp_insert,
            3 => cp_delete,
            5 => cp_page_up,
            6 => cp_page_down,
            7 => cp_home,
            8 => cp_end,
            else => return null,
        };
        const modifier_field = semicolon.next();
        if (semicolon.next() != null) return null;
        if (modifier_field) |field| {
            const parsed = parseModifierAndEvent(field) orelse return null;
            return .{ .codepoint = codepoint, .modifiers = parsed.modifiers, .event_type = parsed.event_type };
        }
        return .{ .codepoint = codepoint };
    }
    return null;
}

fn parseModifyOtherKeys(data: []const u8) ?ParsedSequence {
    if (!std.mem.startsWith(u8, data, "\x1b[27;") or !std.mem.endsWith(u8, data, "~")) return null;
    const payload = data[5 .. data.len - 1];
    var fields = std.mem.splitScalar(u8, payload, ';');
    const modifier_value = parseUnsigned(u16, fields.next() orelse return null) orelse return null;
    const codepoint = parseUnsigned(u21, fields.next() orelse return null) orelse return null;
    if (fields.next() != null or modifier_value == 0) return null;
    return .{ .codepoint = @intCast(codepoint), .modifiers = modifier_value - 1 };
}

fn isKnownSymbol(cp: i32) bool {
    if (cp < 0 or cp > 127) return false;
    return std.mem.indexOfScalar(u8, "`-=[]\\;',./!@#$%^&*()_+|~{}:<>?", @intCast(cp)) != null;
}

fn sequenceToParsed(sequence: ParsedSequence) ?ParsedKey {
    const normalized = normalizeShiftedLetter(normalizeFunctionalCodepoint(sequence.codepoint), sequence.modifiers);
    var effective = normalized;
    const recognized = (normalized >= 'a' and normalized <= 'z') or (normalized >= '0' and normalized <= '9') or isKnownSymbol(normalized);
    if (!recognized) {
        if (sequence.base_layout_key) |base| effective = base;
    }
    if (effective >= 0 and effective < 32 and effective != 9 and effective != 13 and effective != 27) return null;
    const key: KeyName = switch (effective) {
        27 => .{ .named = .escape },
        9 => .{ .named = .tab },
        13, cp_kp_enter => .{ .named = .enter },
        32 => .{ .named = .space },
        127 => .{ .named = .backspace },
        cp_delete => .{ .named = .delete },
        cp_insert => .{ .named = .insert },
        cp_page_up => .{ .named = .page_up },
        cp_page_down => .{ .named = .page_down },
        cp_home => .{ .named = .home },
        cp_end => .{ .named = .end },
        cp_arrow_up => .{ .named = .up },
        cp_arrow_down => .{ .named = .down },
        cp_arrow_left => .{ .named = .left },
        cp_arrow_right => .{ .named = .right },
        else => if (effective <= std.math.maxInt(u21)) .{ .codepoint = @intCast(effective) } else return null,
    };
    if ((sequence.modifiers & ~lock_mask & ~supported_modifier_mask) != 0) return null;
    return .{ .key = key, .modifiers = sequence.modifiers, .event_type = sequence.event_type };
}

const Legacy = struct { sequence: []const u8, key: NamedKey, modifiers: u16 = 0 };

const legacy_sequences = [_]Legacy{
    .{ .sequence = "\x1b[A", .key = .up },                                     .{ .sequence = "\x1bOA", .key = .up },
    .{ .sequence = "\x1b[B", .key = .down },                                   .{ .sequence = "\x1bOB", .key = .down },
    .{ .sequence = "\x1b[C", .key = .right },                                  .{ .sequence = "\x1bOC", .key = .right },
    .{ .sequence = "\x1b[D", .key = .left },                                   .{ .sequence = "\x1bOD", .key = .left },
    .{ .sequence = "\x1b[H", .key = .home },                                   .{ .sequence = "\x1bOH", .key = .home },
    .{ .sequence = "\x1b[1~", .key = .home },                                  .{ .sequence = "\x1b[7~", .key = .home },
    .{ .sequence = "\x1b[F", .key = .end },                                    .{ .sequence = "\x1bOF", .key = .end },
    .{ .sequence = "\x1b[4~", .key = .end },                                   .{ .sequence = "\x1b[8~", .key = .end },
    .{ .sequence = "\x1b[2~", .key = .insert },                                .{ .sequence = "\x1b[3~", .key = .delete },
    .{ .sequence = "\x1b[5~", .key = .page_up },                               .{ .sequence = "\x1b[[5~", .key = .page_up },
    .{ .sequence = "\x1b[6~", .key = .page_down },                             .{ .sequence = "\x1b[[6~", .key = .page_down },
    .{ .sequence = "\x1b[E", .key = .clear },                                  .{ .sequence = "\x1bOE", .key = .clear },
    .{ .sequence = "\x1bOP", .key = .f1 },                                     .{ .sequence = "\x1b[11~", .key = .f1 },
    .{ .sequence = "\x1b[[A", .key = .f1 },                                    .{ .sequence = "\x1bOQ", .key = .f2 },
    .{ .sequence = "\x1b[12~", .key = .f2 },                                   .{ .sequence = "\x1b[[B", .key = .f2 },
    .{ .sequence = "\x1bOR", .key = .f3 },                                     .{ .sequence = "\x1b[13~", .key = .f3 },
    .{ .sequence = "\x1b[[C", .key = .f3 },                                    .{ .sequence = "\x1bOS", .key = .f4 },
    .{ .sequence = "\x1b[14~", .key = .f4 },                                   .{ .sequence = "\x1b[[D", .key = .f4 },
    .{ .sequence = "\x1b[15~", .key = .f5 },                                   .{ .sequence = "\x1b[[E", .key = .f5 },
    .{ .sequence = "\x1b[17~", .key = .f6 },                                   .{ .sequence = "\x1b[18~", .key = .f7 },
    .{ .sequence = "\x1b[19~", .key = .f8 },                                   .{ .sequence = "\x1b[20~", .key = .f9 },
    .{ .sequence = "\x1b[21~", .key = .f10 },                                  .{ .sequence = "\x1b[23~", .key = .f11 },
    .{ .sequence = "\x1b[24~", .key = .f12 },                                  .{ .sequence = "\x1b[a", .key = .up, .modifiers = modifier_shift },
    .{ .sequence = "\x1b[b", .key = .down, .modifiers = modifier_shift },      .{ .sequence = "\x1b[c", .key = .right, .modifiers = modifier_shift },
    .{ .sequence = "\x1b[d", .key = .left, .modifiers = modifier_shift },      .{ .sequence = "\x1b[e", .key = .clear, .modifiers = modifier_shift },
    .{ .sequence = "\x1b[2$", .key = .insert, .modifiers = modifier_shift },   .{ .sequence = "\x1b[3$", .key = .delete, .modifiers = modifier_shift },
    .{ .sequence = "\x1b[5$", .key = .page_up, .modifiers = modifier_shift },  .{ .sequence = "\x1b[6$", .key = .page_down, .modifiers = modifier_shift },
    .{ .sequence = "\x1b[7$", .key = .home, .modifiers = modifier_shift },     .{ .sequence = "\x1b[8$", .key = .end, .modifiers = modifier_shift },
    .{ .sequence = "\x1bOa", .key = .up, .modifiers = modifier_ctrl },         .{ .sequence = "\x1bOb", .key = .down, .modifiers = modifier_ctrl },
    .{ .sequence = "\x1bOc", .key = .right, .modifiers = modifier_ctrl },      .{ .sequence = "\x1bOd", .key = .left, .modifiers = modifier_ctrl },
    .{ .sequence = "\x1bOe", .key = .clear, .modifiers = modifier_ctrl },      .{ .sequence = "\x1b[2^", .key = .insert, .modifiers = modifier_ctrl },
    .{ .sequence = "\x1b[3^", .key = .delete, .modifiers = modifier_ctrl },    .{ .sequence = "\x1b[5^", .key = .page_up, .modifiers = modifier_ctrl },
    .{ .sequence = "\x1b[6^", .key = .page_down, .modifiers = modifier_ctrl }, .{ .sequence = "\x1b[7^", .key = .home, .modifiers = modifier_ctrl },
    .{ .sequence = "\x1b[8^", .key = .end, .modifiers = modifier_ctrl },       .{ .sequence = "\x1bb", .key = .left, .modifiers = modifier_alt },
    .{ .sequence = "\x1bf", .key = .right, .modifiers = modifier_alt },        .{ .sequence = "\x1bp", .key = .up, .modifiers = modifier_alt },
    .{ .sequence = "\x1bn", .key = .down, .modifiers = modifier_alt },
};

fn parseLegacy(data: []const u8, options: ParseOptions) ?ParsedKey {
    for (legacy_sequences) |entry| {
        if (std.mem.eql(u8, data, entry.sequence)) return .{ .key = .{ .named = entry.key }, .modifiers = entry.modifiers };
    }
    if (std.mem.eql(u8, data, "\x1b")) return .{ .key = .{ .named = .escape } };
    if (std.mem.eql(u8, data, "\x1c")) return .{ .key = .{ .codepoint = '\\' }, .modifiers = modifier_ctrl };
    if (std.mem.eql(u8, data, "\x1d")) return .{ .key = .{ .codepoint = ']' }, .modifiers = modifier_ctrl };
    if (std.mem.eql(u8, data, "\x1f")) return .{ .key = .{ .codepoint = '-' }, .modifiers = modifier_ctrl };
    if (std.mem.eql(u8, data, "\x1b\x1b")) return .{ .key = .{ .codepoint = '[' }, .modifiers = modifier_ctrl | modifier_alt };
    if (std.mem.eql(u8, data, "\x1b\x1c")) return .{ .key = .{ .codepoint = '\\' }, .modifiers = modifier_ctrl | modifier_alt };
    if (std.mem.eql(u8, data, "\x1b\x1d")) return .{ .key = .{ .codepoint = ']' }, .modifiers = modifier_ctrl | modifier_alt };
    if (std.mem.eql(u8, data, "\x1b\x1f")) return .{ .key = .{ .codepoint = '-' }, .modifiers = modifier_ctrl | modifier_alt };
    if (std.mem.eql(u8, data, "\x1b[Z")) return .{ .key = .{ .named = .tab }, .modifiers = modifier_shift };
    if (std.mem.eql(u8, data, "\x1bOM")) return .{ .key = .{ .named = .enter } };
    if (std.mem.eql(u8, data, "\x1b\x7f") or std.mem.eql(u8, data, "\x1b\x08")) return .{ .key = .{ .named = .backspace }, .modifiers = modifier_alt };
    if (std.mem.eql(u8, data, "\x00")) return .{ .key = .{ .named = .space }, .modifiers = modifier_ctrl };
    if (std.mem.eql(u8, data, "\t")) return .{ .key = .{ .named = .tab } };
    if (std.mem.eql(u8, data, "\r") or (!options.kitty_active and std.mem.eql(u8, data, "\n"))) return .{ .key = .{ .named = .enter } };
    if (options.kitty_active and (std.mem.eql(u8, data, "\x1b\r") or std.mem.eql(u8, data, "\n"))) return .{ .key = .{ .named = .enter }, .modifiers = modifier_shift };
    if (!options.kitty_active and std.mem.eql(u8, data, "\x1b\r")) return .{ .key = .{ .named = .enter }, .modifiers = modifier_alt };
    if (!options.kitty_active and std.mem.eql(u8, data, "\x1b ")) return .{ .key = .{ .named = .space }, .modifiers = modifier_alt };
    if (std.mem.eql(u8, data, " ")) return .{ .key = .{ .named = .space } };
    if (std.mem.eql(u8, data, "\x7f")) return .{ .key = .{ .named = .backspace } };
    if (std.mem.eql(u8, data, "\x08")) return .{ .key = .{ .named = .backspace }, .modifiers = if (options.windows_terminal) modifier_ctrl else 0 };

    if (!options.kitty_active and data.len == 2 and data[0] == 0x1b) {
        const byte = data[1];
        if (byte >= 1 and byte <= 26) return .{ .key = .{ .codepoint = @as(u21, byte + 96) }, .modifiers = modifier_ctrl | modifier_alt };
        if ((byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9') or isKnownSymbol(byte)) {
            return .{ .key = .{ .codepoint = @intCast(byte) }, .modifiers = modifier_alt };
        }
    }

    if (data.len == 1) {
        const byte = data[0];
        if (byte >= 1 and byte <= 26) return .{ .key = .{ .codepoint = @as(u21, byte + 96) }, .modifiers = modifier_ctrl };
        if (byte >= 'A' and byte <= 'Z') return .{ .key = .{ .codepoint = @as(u21, byte + 32) }, .modifiers = modifier_shift };
        if (byte >= 32 and byte <= 126) return .{ .key = .{ .codepoint = @intCast(byte) } };
    }
    if (std.unicode.utf8ValidateSlice(data)) {
        const view = std.unicode.Utf8View.init(data) catch return null;
        var iterator = view.iterator();
        const cp = iterator.nextCodepoint() orelse return null;
        if (iterator.nextCodepoint() == null and cp >= 32) return .{ .key = .{ .codepoint = cp } };
    }
    return null;
}

pub fn parseKeyWithOptions(data: []const u8, options: ParseOptions) ?ParsedKey {
    if (parseKittySequence(data)) |sequence| return sequenceToParsed(sequence);
    if (parseModifyOtherKeys(data)) |sequence| return sequenceToParsed(sequence);
    return parseLegacy(data, options);
}

pub fn parseKey(data: []const u8) ?ParsedKey {
    return parseKeyWithOptions(data, .{ .kitty_active = kitty_protocol_active });
}

fn namedKeyId(key: NamedKey) []const u8 {
    return switch (key) {
        .escape => "escape",
        .enter => "enter",
        .tab => "tab",
        .space => "space",
        .backspace => "backspace",
        .delete => "delete",
        .insert => "insert",
        .clear => "clear",
        .home => "home",
        .end => "end",
        .page_up => "pageUp",
        .page_down => "pageDown",
        .up => "up",
        .down => "down",
        .left => "left",
        .right => "right",
        .f1 => "f1",
        .f2 => "f2",
        .f3 => "f3",
        .f4 => "f4",
        .f5 => "f5",
        .f6 => "f6",
        .f7 => "f7",
        .f8 => "f8",
        .f9 => "f9",
        .f10 => "f10",
        .f11 => "f11",
        .f12 => "f12",
    };
}

fn parseExpectedKeyId(key_id: []const u8) ?ParsedKey {
    var modifiers: u16 = 0;
    var last: []const u8 = "";
    var fields = std.mem.splitScalar(u8, key_id, '+');
    while (fields.next()) |part| {
        if (std.ascii.eqlIgnoreCase(part, "shift")) modifiers |= modifier_shift else if (std.ascii.eqlIgnoreCase(part, "ctrl")) modifiers |= modifier_ctrl else if (std.ascii.eqlIgnoreCase(part, "alt")) modifiers |= modifier_alt else if (std.ascii.eqlIgnoreCase(part, "super")) modifiers |= modifier_super else last = part;
    }
    if (last.len == 0) return null;
    const named: ?NamedKey = if (std.ascii.eqlIgnoreCase(last, "escape") or std.ascii.eqlIgnoreCase(last, "esc")) .escape else if (std.ascii.eqlIgnoreCase(last, "enter") or std.ascii.eqlIgnoreCase(last, "return")) .enter else if (std.ascii.eqlIgnoreCase(last, "tab")) .tab else if (std.ascii.eqlIgnoreCase(last, "space")) .space else if (std.ascii.eqlIgnoreCase(last, "backspace")) .backspace else if (std.ascii.eqlIgnoreCase(last, "delete")) .delete else if (std.ascii.eqlIgnoreCase(last, "insert")) .insert else if (std.ascii.eqlIgnoreCase(last, "clear")) .clear else if (std.ascii.eqlIgnoreCase(last, "home")) .home else if (std.ascii.eqlIgnoreCase(last, "end")) .end else if (std.ascii.eqlIgnoreCase(last, "pageup")) .page_up else if (std.ascii.eqlIgnoreCase(last, "pagedown")) .page_down else if (std.ascii.eqlIgnoreCase(last, "up")) .up else if (std.ascii.eqlIgnoreCase(last, "down")) .down else if (std.ascii.eqlIgnoreCase(last, "left")) .left else if (std.ascii.eqlIgnoreCase(last, "right")) .right else if (std.ascii.eqlIgnoreCase(last, "f1")) .f1 else if (std.ascii.eqlIgnoreCase(last, "f2")) .f2 else if (std.ascii.eqlIgnoreCase(last, "f3")) .f3 else if (std.ascii.eqlIgnoreCase(last, "f4")) .f4 else if (std.ascii.eqlIgnoreCase(last, "f5")) .f5 else if (std.ascii.eqlIgnoreCase(last, "f6")) .f6 else if (std.ascii.eqlIgnoreCase(last, "f7")) .f7 else if (std.ascii.eqlIgnoreCase(last, "f8")) .f8 else if (std.ascii.eqlIgnoreCase(last, "f9")) .f9 else if (std.ascii.eqlIgnoreCase(last, "f10")) .f10 else if (std.ascii.eqlIgnoreCase(last, "f11")) .f11 else if (std.ascii.eqlIgnoreCase(last, "f12")) .f12 else null;
    if (named) |key| return .{ .key = .{ .named = key }, .modifiers = modifiers };
    const view = std.unicode.Utf8View.init(last) catch return null;
    var iterator = view.iterator();
    var cp = iterator.nextCodepoint() orelse return null;
    if (iterator.nextCodepoint() != null) return null;
    if (cp >= 'A' and cp <= 'Z') cp += 32;
    return .{ .key = .{ .codepoint = cp }, .modifiers = modifiers };
}

pub fn matchesKeyWithOptions(data: []const u8, key_id: []const u8, options: ParseOptions) bool {
    const actual = parseKeyWithOptions(data, options) orelse return false;
    const expected = parseExpectedKeyId(key_id) orelse return false;
    return actual.eql(expected);
}

pub fn matchesKey(data: []const u8, key_id: []const u8) bool {
    return matchesKeyWithOptions(data, key_id, .{ .kitty_active = kitty_protocol_active });
}

pub fn isKeyRelease(data: []const u8) bool {
    if (std.mem.indexOf(u8, data, "\x1b[200~") != null) return false;
    inline for (.{ ":3u", ":3~", ":3A", ":3B", ":3C", ":3D", ":3H", ":3F" }) |needle| {
        if (std.mem.indexOf(u8, data, needle) != null) return true;
    }
    return false;
}

pub fn isKeyRepeat(data: []const u8) bool {
    if (std.mem.indexOf(u8, data, "\x1b[200~") != null) return false;
    inline for (.{ ":2u", ":2~", ":2A", ":2B", ":2C", ":2D", ":2H", ":2F" }) |needle| {
        if (std.mem.indexOf(u8, data, needle) != null) return true;
    }
    return false;
}

pub fn decodePrintableCodepoint(data: []const u8) ?u21 {
    const sequence = parseKittySequence(data) orelse parseModifyOtherKeys(data) orelse return null;
    const modifiers = sequence.modifiers & ~lock_mask;
    if ((modifiers & ~(modifier_shift)) != 0) return null;
    var effective = sequence.codepoint;
    if ((modifiers & modifier_shift) != 0) {
        if (sequence.shifted_key) |shifted| effective = shifted;
    }
    effective = normalizeFunctionalCodepoint(effective);
    if (effective < 32 or effective > std.math.maxInt(u21)) return null;
    return @intCast(effective);
}

pub fn decodePrintableKey(allocator: std.mem.Allocator, data: []const u8) !?[]u8 {
    const cp = decodePrintableCodepoint(data) orelse return null;
    var buffer: [4]u8 = undefined;
    const count = try std.unicode.utf8Encode(cp, &buffer);
    return try allocator.dupe(u8, buffer[0..count]);
}

test "Kitty CSI-u parses alternate layouts, modifiers and events" {
    const cyrillic_ctrl = parseKey("\x1b[1089::99;5u") orelse return error.TestUnexpectedResult;
    try std.testing.expect(cyrillic_ctrl.eql(.{ .key = .{ .codepoint = 'c' }, .modifiers = modifier_ctrl }));
    const shifted = parseKey("\x1b[80:112:112;6:2u") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(u21, 'p'), shifted.key.codepoint);
    try std.testing.expectEqual(modifier_shift | modifier_ctrl, shifted.effectiveModifiers());
    try std.testing.expectEqual(EventType.repeat, shifted.event_type);
    try std.testing.expect(isKeyRepeat("\x1b[80:112:112;6:2u"));
    try std.testing.expect(isKeyRelease("\x1b[99;5:3u"));
}

test "Kitty codepoint remains authoritative for Latin and symbol remaps" {
    try std.testing.expect(matchesKey("\x1b[107::118;5u", "ctrl+k"));
    try std.testing.expect(!matchesKey("\x1b[107::118;5u", "ctrl+v"));
    try std.testing.expect(matchesKey("\x1b[47::91;5u", "ctrl+/"));
    try std.testing.expect(!matchesKey("\x1b[47::91;5u", "ctrl+["));
}

test "Kitty keypad and navigation functional keys normalize" {
    try std.testing.expect(matchesKey("\x1b[57400;1u", "1"));
    try std.testing.expect(matchesKey("\x1b[57410;5u", "ctrl+/"));
    try std.testing.expect(matchesKey("\x1b[57417;3u", "alt+left"));
    try std.testing.expect(matchesKey("\x1b[1;5:3D", "ctrl+left"));
    try std.testing.expect(isKeyRelease("\x1b[1;5:3D"));
}

test "modifyOtherKeys and printable decoding" {
    try std.testing.expect(matchesKey("\x1b[27;5;99~", "ctrl+c"));
    try std.testing.expect(matchesKey("\x1b[27;2;13~", "shift+enter"));
    const printable = try decodePrintableKey(std.testing.allocator, "\x1b[27;2;65~");
    defer if (printable) |value| std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("A", printable.?);
}

test "legacy parsing covers control symbols, aliases, functions and rxvt" {
    try std.testing.expect(matchesKey("\x03", "ctrl+c"));
    try std.testing.expect(matchesKey("\x1f", "ctrl+-"));
    try std.testing.expect(matchesKey("\x1b\x1c", "ctrl+alt+\\"));
    try std.testing.expect(matchesKey("\x1bOA", "up"));
    try std.testing.expect(matchesKey("\x1b[3$", "shift+delete"));
    try std.testing.expect(matchesKey("\x1b[23~", "f11"));
    try std.testing.expect(matchesKey("\x1bb", "alt+left"));
}

test "Kitty mode disambiguates linefeed and escape return" {
    try std.testing.expect(matchesKeyWithOptions("\n", "enter", .{ .kitty_active = false }));
    try std.testing.expect(matchesKeyWithOptions("\n", "shift+enter", .{ .kitty_active = true }));
    try std.testing.expect(matchesKeyWithOptions("\x1b\r", "alt+enter", .{ .kitty_active = false }));
    try std.testing.expect(matchesKeyWithOptions("\x1b\r", "shift+enter", .{ .kitty_active = true }));
}

test "raw backspace Windows Terminal heuristic is SSH-safe at options boundary" {
    try std.testing.expect(matchesKeyWithOptions("\x08", "backspace", .{ .windows_terminal = false }));
    try std.testing.expect(matchesKeyWithOptions("\x08", "ctrl+backspace", .{ .windows_terminal = true }));
}

test "formatAlloc uses canonical modifier and key names" {
    const parsed = parseKey("\x1b[1;8D") orelse return error.TestUnexpectedResult;
    const formatted = try parsed.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(formatted);
    try std.testing.expectEqualStrings("shift+ctrl+alt+left", formatted);
}
