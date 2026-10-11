//! Native Zig port of ICU78.2 common/locid.cpp AliasReplacer, Unicode license.
//! All alias values come from the pinned ICU common data via the existing C API.
//! No project C++ adapter and no legacy-uloc_canonicalize equivalence claim.
const std = @import("std");
const icu = @import("native_icu_collation.zig");
const syntax = @import("native_locale_syntax.zig");
const Bundle = opaque {};
extern fn ures_openDirect_78(?[*:0]const u8, [*:0]const u8, *i32) callconv(.c) ?*Bundle;
extern fn ures_getByKey_78(*const Bundle, [*:0]const u8, ?*Bundle, *i32) callconv(.c) ?*Bundle;
extern fn ures_getStringByKey_78(*const Bundle, [*:0]const u8, *i32, *i32) callconv(.c) ?[*]const u16;
extern fn ures_close_78(*Bundle) callconv(.c) void;
extern fn uloc_forLanguageTag_78([*:0]const u8, ?[*]u8, i32, *i32, *i32) callconv(.c) i32;
extern fn uloc_toLanguageTag_78([*:0]const u8, ?[*]u8, i32, i8, *i32) callconv(.c) i32;
extern fn uloc_getLanguage_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getScript_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getCountry_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getVariant_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_addLikelySubtags_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getKeywordValue_78([*:0]const u8, [*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_setKeywordValue_78([*:0]const u8, [*:0]const u8, [*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_toUnicodeLocaleType_78([*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8;
fn checked(status: i32) !void {
    if (status == 7) return error.OutOfMemory;
    if (status > 0) return error.IcuOperationFailed;
}
fn z(gpa: std.mem.Allocator, value: []const u8) ![:0]const u8 {
    return gpa.dupeZ(u8, value);
}
fn output(gpa: std.mem.Allocator, operation: anytype, args: anytype) ![:0]const u8 {
    var status: i32 = 0;
    const count = @call(.auto, operation, args ++ .{ null, @as(i32, 0), &status });
    if (status != 15) try checked(status);
    if (count < 0 or count == std.math.maxInt(i32)) return error.InvalidLanguageTag;
    const buffer = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = @call(.auto, operation, args ++ .{ buffer.ptr, count + 1, &status });
    try checked(status);
    if (actual != count) return error.UnstableIcuLocaleResult;
    return buffer;
}
fn parseChecked(status: i32) !void {
    if (status == 7) return error.OutOfMemory;
    if (status > 0) return error.InvalidLanguageTag;
}
fn parseTag(gpa: std.mem.Allocator, tag: [:0]const u8) ![:0]const u8 {
    var consumed: i32 = 0;
    var status: i32 = 0;
    const count = uloc_forLanguageTag_78(tag, null, 0, &consumed, &status);
    if (status != 15) try parseChecked(status);
    if (consumed != tag.len or count < 0 or count == std.math.maxInt(i32)) return error.InvalidLanguageTag;
    const buffer = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = uloc_forLanguageTag_78(tag, buffer.ptr, count + 1, &consumed, &status);
    try parseChecked(status);
    if (actual != count or consumed != tag.len) return error.InvalidLanguageTag;
    return buffer;
}
fn languageTag(gpa: std.mem.Allocator, locale: [:0]const u8) ![:0]const u8 {
    var status: i32 = 0;
    const count = uloc_toLanguageTag_78(locale, null, 0, 1, &status);
    if (status != 15) try parseChecked(status);
    if (count < 0 or count == std.math.maxInt(i32)) return error.InvalidLanguageTag;
    const buffer = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = uloc_toLanguageTag_78(locale, buffer.ptr, count + 1, 1, &status);
    try parseChecked(status);
    if (actual != count) return error.UnstableIcuLocaleResult;
    return buffer;
}
fn lower(gpa: std.mem.Allocator, value: []const u8) ![]const u8 {
    const result = try gpa.dupe(u8, value);
    for (result) |*byte| byte.* = std.ascii.toLower(byte.*);
    return result;
}
fn alias(gpa: std.mem.Allocator, kind: [:0]const u8, key: []const u8) !?[]const u8 {
    var status: i32 = 0;
    const metadata = ures_openDirect_78(null, "metadata", &status) orelse {
        try checked(status);
        return error.IcuMetadataUnavailable;
    };
    defer ures_close_78(metadata);
    const aliases = ures_getByKey_78(metadata, "alias", null, &status) orelse {
        try checked(status);
        return error.IcuAliasUnavailable;
    };
    defer ures_close_78(aliases);
    const table = ures_getByKey_78(aliases, kind, null, &status) orelse {
        try checked(status);
        return error.IcuAliasTableUnavailable;
    };
    defer ures_close_78(table);
    const key_z = try z(gpa, key);
    const entry = ures_getByKey_78(table, key_z, null, &status) orelse {
        if (status == 2) return null;
        try checked(status);
        return error.IcuAliasEntryUnavailable;
    };
    defer ures_close_78(entry);
    var length: i32 = 0;
    const units = ures_getStringByKey_78(entry, "replacement", &length, &status) orelse {
        try checked(status);
        return error.IcuAliasReplacementUnavailable;
    };
    try checked(status);
    if (length < 0) return error.InvalidIcuAliasData;
    const result = try gpa.alloc(u8, @intCast(length));
    for (result, units[0..@intCast(length)]) |*byte, unit| {
        if (unit > 127) return error.NonAsciiIcuAliasData;
        byte.* = @intCast(unit);
    }
    return result;
}
fn optional(value: []const u8) ?[]const u8 {
    return if (value.len == 0) null else value;
}
fn same(left: ?[]const u8, right: ?[]const u8) bool {
    return if (left) |a| (if (right) |b| std.mem.eql(u8, a, b) else false) else right == null;
}
fn replacement(input: ?[]const u8, type_key: ?[]const u8, next: ?[]const u8) ?[]const u8 {
    if (next) |value| if (value.len != 0) return input orelse value;
    return if (type_key == null) input else null;
}
const Fields = struct {
    gpa: std.mem.Allocator,
    language: ?[]const u8,
    script: ?[]const u8,
    region: ?[]const u8,
    variants: std.ArrayList([]const u8) = .empty,
    fn init(gpa: std.mem.Allocator, locale: [:0]const u8) !Fields {
        var fields: Fields = .{ .gpa = gpa, .language = optional(try output(gpa, uloc_getLanguage_78, .{locale.ptr})), .script = optional(try output(gpa, uloc_getScript_78, .{locale.ptr})), .region = optional(try output(gpa, uloc_getCountry_78, .{locale.ptr})) };
        const variants = try lower(gpa, try output(gpa, uloc_getVariant_78, .{locale.ptr}));
        var parts = std.mem.tokenizeScalar(u8, variants, '_');
        while (parts.next()) |part| {
            var found = false;
            for (fields.variants.items) |known| if (std.mem.eql(u8, known, part)) {
                found = true;
                break;
            };
            if (!found) try fields.variants.append(gpa, part);
        }
        std.mem.sort([]const u8, fields.variants.items, {}, less);
        return fields;
    }
    fn less(_: void, left: []const u8, right: []const u8) bool {
        return std.mem.lessThan(u8, left, right);
    }
    fn replaceLanguage(self: *Fields, use_language: bool, use_region: bool, use_variants: bool) !bool {
        if ((use_region and self.region == null) or (use_variants and self.variants.items.len == 0)) return false;
        const count = if (use_variants) self.variants.items.len else 1;
        for (0..count) |index| {
            const variant: ?[]const u8 = if (use_variants and self.variants.items[index].len >= 4) self.variants.items[index] else null;
            const region = if (use_region) self.region else null;
            var key: std.ArrayList(u8) = .empty;
            try key.appendSlice(self.gpa, if (use_language) self.language orelse "" else "und");
            if (region) |value| {
                try key.append(self.gpa, '_');
                try key.appendSlice(self.gpa, value);
            }
            if (variant) |value| {
                try key.append(self.gpa, '_');
                try key.appendSlice(self.gpa, value);
            }
            const raw = (try alias(self.gpa, "language", key.items)) orelse continue;
            var tokens = std.mem.splitScalar(u8, raw, '_');
            var next_language: ?[]const u8 = tokens.next();
            var next_script: ?[]const u8 = null;
            var next_region: ?[]const u8 = null;
            var next_variant: ?[]const u8 = null;
            var token = tokens.next();
            if (token) |value| if (value.len == 4) {
                next_script = value;
                token = tokens.next();
            };
            if (token) |value| if (value.len >= 2 and value.len <= 3) {
                next_region = value;
                token = tokens.next();
            };
            if (token) |value| if (value.len >= 4) {
                next_variant = value;
                token = tokens.next();
            };
            if (same(next_language, "und")) next_language = self.language;
            next_script = replacement(self.script, null, next_script);
            next_region = replacement(self.region, region, next_region);
            next_variant = replacement(variant, variant, next_variant);
            if (same(self.language, next_language) and same(self.script, next_script) and same(self.region, next_region) and same(variant, next_variant) and token == null) continue;
            self.language = next_language;
            self.script = next_script;
            self.region = next_region;
            if (variant != null) {
                if (next_variant) |value| {
                    self.variants.items[index] = value;
                } else _ = self.variants.orderedRemove(index);
            }
            // Upstream ignores replacement extensions: legacy forms have
            // already been transformed by the ICU language-tag parser.
            return true;
        }
        return false;
    }
    fn replaceTerritory(self: *Fields) !bool {
        const region = self.region orelse return false;
        const raw = (try alias(self.gpa, "territory", region)) orelse return false;
        var candidates = std.mem.tokenizeScalar(u8, raw, ' ');
        const first = candidates.next() orelse return error.InvalidIcuAliasData;
        var selected = first;
        if (std.mem.indexOfScalar(u8, raw, ' ') != null) {
            const base = try std.fmt.allocPrintSentinel(self.gpa, "{s}{s}{s}", .{ self.language orelse "und", if (self.script != null) "_" else "", self.script orelse "" }, 0);
            const likely = try output(self.gpa, uloc_addLikelySubtags_78, .{base.ptr});
            const likely_region = try output(self.gpa, uloc_getCountry_78, .{likely.ptr});
            var all = std.mem.tokenizeScalar(u8, raw, ' ');
            while (all.next()) |candidate| if (std.mem.eql(u8, candidate, likely_region)) {
                selected = candidate;
                break;
            };
        }
        self.region = selected;
        return true;
    }
    fn replaceScript(self: *Fields) !bool {
        const value = self.script orelse return false;
        self.script = (try alias(self.gpa, "script", value)) orelse return false;
        return true;
    }
    fn replaceVariant(self: *Fields) !bool {
        for (self.variants.items, 0..) |value, index| {
            const next = (try alias(self.gpa, "variant", value)) orelse continue;
            if (std.mem.eql(u8, value, next)) continue;
            self.variants.items[index] = next;
            if (std.mem.eql(u8, value, "heploc")) {
                var item: usize = 0;
                while (item < self.variants.items.len) {
                    if (std.mem.eql(u8, self.variants.items[item], "hepburn")) {
                        _ = self.variants.orderedRemove(item);
                    } else item += 1;
                }
            }
            return true;
        }
        return false;
    }
    fn text(self: *Fields) ![:0]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try out.appendSlice(self.gpa, self.language orelse "");
        if (self.script) |value| {
            try out.append(self.gpa, '_');
            try out.appendSlice(self.gpa, value);
        }
        if (self.region) |value| {
            try out.append(self.gpa, '_');
            try out.appendSlice(self.gpa, value);
        }
        if (self.variants.items.len != 0) {
            if (self.script == null and self.region == null) try out.append(self.gpa, '_');
            std.mem.sort([]const u8, self.variants.items, {}, less);
            for (self.variants.items) |value| {
                try out.append(self.gpa, '_');
                for (value) |byte| try out.append(self.gpa, std.ascii.toUpper(byte));
            }
        }
        return z(self.gpa, out.items);
    }
};
fn setKeyword(gpa: std.mem.Allocator, locale: [:0]const u8, key: [:0]const u8, value: []const u8) ![:0]const u8 {
    const value_z = try z(gpa, value);
    var capacity = try std.math.add(usize, locale.len, value.len + 64);
    while (true) {
        if (capacity > std.math.maxInt(i32)) return error.InvalidLanguageTag;
        const buffer = try gpa.alloc(u8, capacity);
        @memcpy(buffer[0..locale.len], locale);
        buffer[locale.len] = 0;
        var status: i32 = 0;
        const count = uloc_setKeywordValue_78(key, value_z, buffer.ptr, @intCast(capacity), &status);
        if (status == 15 and count >= 0) {
            capacity = @as(usize, @intCast(count)) + 1;
            continue;
        }
        try checked(status);
        if (count < 0 or count >= capacity) return error.UnstableIcuLocaleResult;
        return buffer[0..@intCast(count) :0];
    }
}
fn subdivision(gpa: std.mem.Allocator, value: []const u8) !?[]const u8 {
    const raw = (try alias(gpa, "subdivision", value)) orelse return null;
    const end = std.mem.indexOfScalar(u8, raw, ' ') orelse raw.len;
    const first = raw[0..end];
    return if (first.len == 2) try std.mem.concat(gpa, u8, &.{ first, "zzzz" }) else if (first.len >= 2 and first.len <= 8) first else "";
}
fn transformed(gpa: std.mem.Allocator, value: []const u8) ![]const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var tokens = std.mem.splitScalar(u8, value, '-');
    while (tokens.next()) |token| try parts.append(gpa, token);
    var first_key: usize = 0;
    while (first_key < parts.items.len) : (first_key += 1) {
        const token = parts.items[first_key];
        if (token.len == 2 and std.ascii.isAlphabetic(token[0]) and std.ascii.isDigit(token[1])) break;
    }
    var out: std.ArrayList(u8) = .empty;
    if (first_key != 0) {
        const language = try std.mem.join(gpa, "-", parts.items[0..first_key]);
        const canonical = try canonicalArena(gpa, language);
        try out.appendSlice(gpa, try lower(gpa, canonical));
    }
    var fields: std.ArrayList([]const u8) = .empty;
    var index = first_key;
    while (index < parts.items.len) {
        const start = index;
        index += 1;
        while (index < parts.items.len) : (index += 1) {
            const token = parts.items[index];
            if (token.len == 2 and std.ascii.isAlphabetic(token[0]) and std.ascii.isDigit(token[1])) break;
        }
        if (index == start + 1) return error.InvalidLanguageTag;
        try fields.append(gpa, try std.mem.join(gpa, "-", parts.items[start..index]));
    }
    std.mem.sort([]const u8, fields.items, {}, Fields.less);
    for (fields.items) |field| {
        const split = std.mem.indexOfScalar(u8, field, '-') orelse return error.InvalidLanguageTag;
        const key = try z(gpa, field[0..split]);
        const raw = try z(gpa, field[split + 1 ..]);
        const mapped = uloc_toUnicodeLocaleType_78(key, raw);
        if (out.items.len != 0) try out.append(gpa, '-');
        try out.appendSlice(gpa, key);
        try out.append(gpa, '-');
        try out.appendSlice(gpa, if (mapped) |value_z| std.mem.span(value_z) else raw);
    }
    return out.items;
}
fn canonicalArena(gpa: std.mem.Allocator, input: []const u8) anyerror![:0]const u8 {
    if (!syntax.startsWithUnicodeLanguageId(input)) return error.IncorrectLocaleInformation;
    for (input) |byte| if (byte > 127 or byte == 0) return error.InvalidLanguageTag;
    const lowered = try lower(gpa, input);
    const locale = try parseTag(gpa, try z(gpa, lowered));
    // Strict BCP47 emission performs the LocaleBuilder structural validation.
    _ = try languageTag(gpa, locale);
    var fields = try Fields.init(gpa, locale);
    while (try fields.replaceLanguage(true, true, true) or try fields.replaceLanguage(true, true, false) or try fields.replaceLanguage(true, false, true) or try fields.replaceLanguage(true, false, false) or try fields.replaceLanguage(false, false, true) or try fields.replaceTerritory() or try fields.replaceScript() or try fields.replaceVariant()) {}
    var result = try fields.text();
    if (std.mem.indexOfScalar(u8, locale, '@')) |at| result = try z(gpa, try std.mem.concat(gpa, u8, &.{ result, locale[at..] }));
    inline for (.{ "sd", "rg", "t" }) |key| {
        const value = try output(gpa, uloc_getKeywordValue_78, .{ locale.ptr, @as([*:0]const u8, key) });
        if (value.len != 0) {
            if (std.mem.eql(u8, key, "t")) {
                result = try setKeyword(gpa, result, key, try transformed(gpa, value));
            } else if (try subdivision(gpa, value)) |next| result = try setKeyword(gpa, result, key, next);
        }
    }
    return languageTag(gpa, result);
}
fn canonicalV8Arena(gpa: std.mem.Allocator, input: []const u8) anyerror![:0]const u8 {
    if (!syntax.startsWithUnicodeLanguageId(input)) return error.IncorrectLocaleInformation;
    for (input) |byte| if (byte > 127 or byte == 0) return error.InvalidLanguageTag;
    // V8's original lowercase fast path precedes ICU canonicalization. It is
    // observable for CLDR aliases such as bh/BH and tw/TW; retain it exactly.
    if (std.mem.eql(u8, input, "fil")) return z(gpa, input);
    if (input.len == 2 and std.ascii.isLower(input[0]) and std.ascii.isLower(input[1])) {
        var legacy = false;
        inline for (.{ "in", "iw", "ji", "jw", "mo", "sh", "tl", "no" }) |name| {
            if (std.mem.eql(u8, input, name)) legacy = true;
        }
        if (!legacy) return z(gpa, input);
    }
    return canonicalArena(gpa, input);
}
pub fn canonicalize(gpa: std.mem.Allocator, input: []const u8) ![:0]const u8 {
    try icu.initialize();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    return gpa.dupeZ(u8, try canonicalV8Arena(arena.allocator(), input));
}
pub fn canonicalizeIcu(gpa: std.mem.Allocator, input: []const u8) ![:0]const u8 {
    try icu.initialize();
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    return gpa.dupeZ(u8, try canonicalArena(arena.allocator(), input));
}
