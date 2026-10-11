//! ICU Locale's existing C conversion/field APIs, with owned native buffers.
const std = @import("std");
const data_mod = @import("native_icu_locale_data.zig");
extern fn uloc_getDefault_78() callconv(.c) [*:0]const u8;
extern fn uloc_forLanguageTag_78([*:0]const u8, ?[*]u8, i32, *i32, *i32) callconv(.c) i32;
extern fn uloc_toLanguageTag_78([*:0]const u8, ?[*]u8, i32, i8, *i32) callconv(.c) i32;
extern fn uloc_getLanguage_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getScript_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getCountry_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getVariant_78([*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_getKeywordValue_78([*:0]const u8, [*:0]const u8, ?[*]u8, i32, *i32) callconv(.c) i32;
extern fn uloc_toLegacyKey_78([*:0]const u8) callconv(.c) ?[*:0]const u8;
extern fn uloc_toUnicodeLocaleType_78([*:0]const u8, [*:0]const u8) callconv(.c) ?[*:0]const u8;
const ULocaleBuilder = opaque {};
extern fn ulocbld_open_78() callconv(.c) ?*ULocaleBuilder;
extern fn ulocbld_close_78(*ULocaleBuilder) callconv(.c) void;
extern fn ulocbld_setLocale_78(*ULocaleBuilder, [*]const u8, i32) callconv(.c) void;
extern fn ulocbld_clearExtensions_78(*ULocaleBuilder) callconv(.c) void;
extern fn ulocbld_setUnicodeLocaleKeyword_78(*ULocaleBuilder, [*]const u8, i32, ?[*]const u8, i32) callconv(.c) void;
extern fn ulocbld_buildLocaleID_78(*ULocaleBuilder, ?[*]u8, i32, *i32) callconv(.c) i32;
pub fn check(status: i32) !void {
    if (status == 7) return error.OutOfMemory;
    if (status > 0) return error.InvalidIcuLocale;
}
fn output(gpa: std.mem.Allocator, operation: anytype, args: anytype) ![:0]const u8 {
    var status: i32 = 0;
    const count = @call(.auto, operation, args ++ .{ null, @as(i32, 0), &status });
    if (status != 15) try check(status);
    if (count < 0 or count == std.math.maxInt(i32)) return error.InvalidIcuLocale;
    const buffer = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = @call(.auto, operation, args ++ .{ buffer.ptr, count + 1, &status });
    try check(status);
    if (actual != count) return error.UnstableIcuLocaleResult;
    return buffer;
}
pub fn toTag(gpa: std.mem.Allocator, id: [:0]const u8) ![:0]const u8 {
    var status: i32 = 0;
    const count = uloc_toLanguageTag_78(id, null, 0, 0, &status);
    if (status != 15) try check(status);
    if (count < 0 or count == std.math.maxInt(i32)) return error.InvalidIcuLocale;
    const buffer = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = uloc_toLanguageTag_78(id, buffer.ptr, count + 1, 0, &status);
    try check(status);
    if (actual != count) return error.UnstableIcuLocaleResult;
    return buffer;
}
pub fn fromTag(gpa: std.mem.Allocator, tag: []const u8) !Locale {
    const tag_z = try gpa.dupeZ(u8, tag);
    var consumed: i32 = 0;
    var status: i32 = 0;
    const count = uloc_forLanguageTag_78(tag_z, null, 0, &consumed, &status);
    if (status != 15) try check(status);
    if (consumed != tag.len or count < 0 or count == std.math.maxInt(i32)) return error.InvalidIcuLocale;
    const id = try gpa.allocSentinel(u8, @intCast(count), 0);
    status = 0;
    const actual = uloc_forLanguageTag_78(tag_z, id.ptr, count + 1, &consumed, &status);
    try check(status);
    if (actual != count or consumed != tag.len) return error.InvalidIcuLocale;
    return fromId(gpa, id);
}
pub fn fromId(gpa: std.mem.Allocator, raw: [:0]const u8) !Locale {
    const id = try gpa.dupeZ(u8, raw);
    return .{ .id = id, .tag = try toTag(gpa, id), .lsr = .{ .language = try output(gpa, uloc_getLanguage_78, .{id.ptr}), .script = try output(gpa, uloc_getScript_78, .{id.ptr}), .region = try output(gpa, uloc_getCountry_78, .{id.ptr}) }, .variant = try output(gpa, uloc_getVariant_78, .{id.ptr}) };
}
pub fn defaultTag(gpa: std.mem.Allocator) ![:0]const u8 {
    const name = std.mem.span(uloc_getDefault_78());
    if (std.mem.eql(u8, name, "en_US_POSIX") or std.mem.eql(u8, name, "c")) return gpa.dupeZ(u8, "en-US");
    return toTag(gpa, name);
}
pub fn unicodeKeyword(gpa: std.mem.Allocator, locale: Locale, key: [:0]const u8) !?[:0]const u8 {
    const legacy = uloc_toLegacyKey_78(key) orelse return null;
    const raw = try output(gpa, uloc_getKeywordValue_78, .{ locale.id.ptr, legacy });
    if (raw.len == 0) return null;
    const mapped = uloc_toUnicodeLocaleType_78(key, raw) orelse return null;
    return try gpa.dupeZ(u8, std.mem.span(mapped));
}
pub const Builder = struct {
    handle: *ULocaleBuilder,
    pub fn init(locale: Locale) !Builder {
        const handle = ulocbld_open_78() orelse return error.OutOfMemory;
        ulocbld_setLocale_78(handle, locale.id.ptr, -1);
        return .{ .handle = handle };
    }
    pub fn deinit(self: *Builder) void {
        ulocbld_close_78(self.handle);
        self.* = undefined;
    }
    pub fn clearExtensions(self: *Builder) void {
        ulocbld_clearExtensions_78(self.handle);
    }
    pub fn setUnicodeKeyword(self: *Builder, key: []const u8, value: []const u8) !void {
        const key_len = std.math.cast(i32, key.len) orelse return error.InvalidIcuLocale;
        const value_len = std.math.cast(i32, value.len) orelse return error.InvalidIcuLocale;
        ulocbld_setUnicodeLocaleKeyword_78(self.handle, key.ptr, key_len, value.ptr, value_len);
    }
    pub fn removeUnicodeKeyword(self: *Builder, key: []const u8) !void {
        const key_len = std.math.cast(i32, key.len) orelse return error.InvalidIcuLocale;
        ulocbld_setUnicodeLocaleKeyword_78(self.handle, key.ptr, key_len, null, 0);
    }
    pub fn build(self: *Builder, gpa: std.mem.Allocator) !Locale {
        const id = try output(gpa, ulocbld_buildLocaleID_78, .{self.handle});
        return fromId(gpa, id);
    }
};
pub const Locale = struct {
    id: [:0]const u8,
    tag: [:0]const u8,
    lsr: data_mod.Lsr,
    variant: [:0]const u8,
    pub fn keywords(self: Locale) []const u8 {
        const start = std.mem.indexOfScalar(u8, self.id, '@') orelse return "";
        return self.id[start..];
    }
    pub fn withDesired(self: Locale, gpa: std.mem.Allocator, desired: Locale) !Locale {
        // ICU LocaleMatcher::Result::makeResolvedLocale: retain supported
        // language/script and copy nonempty desired region/variants/extensions.
        const region = if (desired.lsr.region.len != 0) desired.lsr.region else self.lsr.region;
        const variant = if (desired.variant.len != 0) desired.variant else self.variant;
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(gpa, self.lsr.language);
        if (self.lsr.script.len != 0) {
            try text.append(gpa, '_');
            try text.appendSlice(gpa, self.lsr.script);
        }
        if (region.len != 0) {
            try text.append(gpa, '_');
            try text.appendSlice(gpa, region);
        }
        if (variant.len != 0) {
            if (self.lsr.script.len == 0 and region.len == 0) try text.append(gpa, '_');
            try text.append(gpa, '_');
            try text.appendSlice(gpa, variant);
        }
        try text.appendSlice(gpa, if (desired.keywords().len != 0) desired.keywords() else self.keywords());
        return fromId(gpa, try gpa.dupeZ(u8, text.items));
    }
};
