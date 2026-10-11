//! Node24.14 default Intl::ResolveLocale port: experimental best-fit is OFF.
//! Both requested matcher modes use the complete V8 LookupMatcher algorithm.
const std = @import("std");
const icu = @import("native_icu_collation.zig");
const ids = @import("native_icu_locale_id.zig");
const aliases = @import("native_locale_alias.zig");
const Bundle = opaque {};
const Enumeration = opaque {};
extern fn ucol_countAvailable_78() callconv(.c) i32;
extern fn ucol_getAvailable_78(i32) callconv(.c) ?[*:0]const u8;
extern fn ures_open_78(?[*:0]const u8, [*:0]const u8, *i32) callconv(.c) ?*Bundle;
extern fn ures_close_78(*Bundle) callconv(.c) void;
extern fn uloc_toLegacyType_78([*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8;
extern fn ucol_getKeywordValuesForLocale_78([*:0]const u8, [*:0]const u8, i8, *i32) callconv(.c) ?*Enumeration;
extern fn uenum_next_78(*Enumeration, *i32, *i32) callconv(.c) ?[*:0]const u8;
extern fn uenum_close_78(*Enumeration) callconv(.c) void;
pub const Mode = enum { lookup, best_fit };
pub const Result = struct { locale: ids.Locale, desired_index: ?usize };
pub const Resolved = struct {
    locale: []const u8,
    usage: []const u8,
    sensitivity: []const u8,
    ignorePunctuation: bool,
    collation: []const u8,
    numeric: bool,
    caseFirst: []const u8,
};
pub const Lookup = struct {
    backing: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    default_locale: ids.Locale,
    available: []ids.Locale,
    pub fn init(backing: std.mem.Allocator) !Lookup {
        try icu.initialize();
        const arena = try backing.create(std.heap.ArenaAllocator);
        arena.* = .init(backing);
        errdefer {
            arena.deinit();
            backing.destroy(arena);
        }
        const gpa = arena.allocator();
        const default_locale = try ids.fromTag(gpa, try ids.defaultTag(gpa));
        const count = ucol_countAvailable_78();
        if (count <= 0) return error.IcuCollationLocalesUnavailable;
        var locales: std.ArrayList(ids.Locale) = .empty;
        for (0..@intCast(count)) |index| {
            const raw = ucol_getAvailable_78(@intCast(index)) orelse return error.IcuCollationLocalesUnavailable;
            const locale = try ids.fromId(gpa, std.mem.span(raw));
            if (!try validateResource(gpa, locale)) {
                if (!std.mem.eql(u8, locale.tag, "nb") or !try validateResource(gpa, try ids.fromTag(gpa, "no"))) continue;
            }
            try appendUnique(gpa, &locales, locale);
            const canonical = try ids.fromTag(gpa, try aliases.canonicalizeIcu(gpa, locale.tag));
            if (canonical.lsr.script.len != 0) {
                const shortened = try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ canonical.lsr.language, if (canonical.lsr.region.len != 0) "-" else "", canonical.lsr.region });
                const short = ids.fromTag(gpa, shortened) catch |err| {
                    if (err == error.InvalidIcuLocale) continue;
                    return err;
                };
                try appendUnique(gpa, &locales, short);
            }
        }
        std.mem.sort(ids.Locale, locales.items, {}, less);
        return .{ .backing = backing, .arena = arena, .default_locale = default_locale, .available = try locales.toOwnedSlice(gpa) };
    }
    pub fn deinit(self: *Lookup) void {
        self.arena.deinit();
        self.backing.destroy(self.arena);
        self.* = undefined;
    }
    fn less(_: void, left: ids.Locale, right: ids.Locale) bool {
        return std.mem.lessThan(u8, left.tag, right.tag);
    }
    fn appendUnique(gpa: std.mem.Allocator, values: *std.ArrayList(ids.Locale), locale: ids.Locale) !void {
        for (values.items) |known| if (std.mem.eql(u8, locale.tag, known.tag)) return;
        try values.append(gpa, locale);
    }
    fn validateResource(gpa: std.mem.Allocator, locale: ids.Locale) !bool {
        var status: i32 = 0;
        const bundle = ures_open_78("icudt78l-coll", locale.id, &status);
        if (bundle) |value| ures_close_78(value);
        if (bundle != null and status == 0) return true;
        if (status == 7) return error.OutOfMemory;
        if (locale.lsr.region.len != 0 and locale.lsr.script.len != 0) return validateResource(gpa, try ids.fromTag(gpa, try std.fmt.allocPrint(gpa, "{s}-{s}", .{ locale.lsr.language, locale.lsr.script })));
        if (locale.lsr.region.len != 0 or locale.lsr.script.len != 0) return validateResource(gpa, try ids.fromTag(gpa, locale.lsr.language));
        return false;
    }
    pub fn match(self: *const Lookup, gpa: std.mem.Allocator, requested: []const []const u8, mode: Mode) !Result {
        // This is the actual pinned Node default branch, not best-fit emulation.
        _ = mode;
        for (requested, 0..) |tag, index| {
            const parts = try removeUnicodeExtension(gpa, tag);
            var candidate = parts.base;
            while (true) {
                for (self.available) |locale| if (std.mem.eql(u8, locale.tag, candidate)) {
                    const full = try ids.fromTag(gpa, try std.mem.concat(gpa, u8, &.{ locale.tag, parts.extension }));
                    return .{ .locale = try relevantExtensions(gpa, full), .desired_index = index };
                };
                var end = std.mem.lastIndexOfScalar(u8, candidate, '-') orelse break;
                if (end >= 2 and candidate[end - 2] == '-') end -= 2;
                candidate = candidate[0..end];
            }
        }
        return .{ .locale = try relevantExtensions(gpa, self.default_locale), .desired_index = null };
    }
    pub fn resolved(self: *const Lookup, gpa: std.mem.Allocator, requested: []const []const u8, mode: Mode) !Resolved {
        const matched = try self.match(gpa, requested, mode);
        var collator = try icu.Collator.open(matched.locale.id, .{});
        defer collator.deinit();
        const valid = try ids.fromId(gpa, try collator.validLocaleId());
        const collation = (try ids.unicodeKeyword(gpa, valid, "co")) orelse "default";
        const strength = try collator.getAttribute(5);
        const sensitivity: []const u8 = switch (strength) {
            0 => if (try collator.getAttribute(3) == 17) "case" else "base",
            1 => "accent",
            else => "variant",
        };
        return .{ .locale = matched.locale.tag, .usage = "sort", .sensitivity = sensitivity, .ignorePunctuation = try collator.getAttribute(1) == 20, .collation = collation, .numeric = try collator.getAttribute(7) == 17, .caseFirst = switch (try collator.getAttribute(2)) {
            24 => "lower",
            25 => "upper",
            else => "false",
        } };
    }
    pub fn validCollation(gpa: std.mem.Allocator, locale: ids.Locale, value: [:0]const u8) !bool {
        if (std.mem.eql(u8, value, "standard") or std.mem.eql(u8, value, "search")) return false;
        const legacy = uloc_toLegacyType_78("collation", value) orelse return false;
        const end = std.mem.indexOfScalar(u8, locale.id, '@') orelse locale.id.len;
        const base = try gpa.dupeZ(u8, locale.id[0..end]);
        var status: i32 = 0;
        const enumeration = ucol_getKeywordValuesForLocale_78("collation", base, 0, &status) orelse {
            if (status == 7) return error.OutOfMemory;
            return false;
        };
        defer uenum_close_78(enumeration);
        if (status > 0) {
            if (status == 7) return error.OutOfMemory;
            return false;
        }
        while (true) {
            var length: i32 = 0;
            const item = uenum_next_78(enumeration, &length, &status) orelse break;
            if (status > 0) break;
            if (std.mem.eql(u8, std.mem.span(legacy), std.mem.span(item))) return true;
        }
        if (status == 7) return error.OutOfMemory;
        return false;
    }
    fn relevantExtensions(gpa: std.mem.Allocator, locale: ids.Locale) !ids.Locale {
        if (locale.keywords().len == 0) return locale;
        var builder = try ids.Builder.init(locale);
        defer builder.deinit();
        builder.clearExtensions();
        inline for (.{ "co", "kn", "kf" }) |key| {
            if (try ids.unicodeKeyword(gpa, locale, key)) |value| {
                const valid = if (std.mem.eql(u8, key, "co")) try validCollation(gpa, locale, value) else if (std.mem.eql(u8, key, "kn")) std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "false") else std.mem.eql(u8, value, "upper") or std.mem.eql(u8, value, "lower") or std.mem.eql(u8, value, "false");
                if (valid) try builder.setUnicodeKeyword(key, value);
            }
        }
        return builder.build(gpa);
    }
    fn removeUnicodeExtension(gpa: std.mem.Allocator, tag: []const u8) !struct { base: []const u8, extension: []const u8 } {
        if (tag.len > 1 and tag[1] == '-') return .{ .base = tag, .extension = "" };
        const start = std.mem.indexOf(u8, tag, "-u-") orelse return .{ .base = tag, .extension = "" };
        if (std.mem.indexOf(u8, tag, "-x-")) |private| if (private < start) return .{ .base = tag, .extension = "" };
        var end = tag.len;
        var cursor = start + 1;
        while (cursor + 2 < tag.len) : (cursor += 1) {
            if (tag[cursor] != '-') continue;
            if (tag[cursor + 2] == '-') {
                end = cursor;
                break;
            }
            cursor += 2;
        }
        return .{ .base = try std.mem.concat(gpa, u8, &.{ tag[0..start], tag[end..] }), .extension = tag[start..end] };
    }
};
