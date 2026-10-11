//! ICU78 pinned langInfo resources through the existing resource C ABI.
//! Native LSR and encoded-data translation from loclikelysubtags.cpp/lsr.cpp.
const std = @import("std");
const icu = @import("native_icu_collation.zig");
pub const Bundle = opaque {};
extern fn ures_openDirect_78(?[*:0]const u8, [*:0]const u8, *i32) callconv(.c) ?*Bundle;
extern fn ures_getByKey_78(*const Bundle, [*:0]const u8, ?*Bundle, *i32) callconv(.c) ?*Bundle;
extern fn ures_getStringByIndex_78(*const Bundle, i32, *i32, *i32) callconv(.c) ?[*]const u16;
extern fn ures_getBinary_78(*const Bundle, *i32, *i32) callconv(.c) ?[*]const u8;
extern fn ures_getIntVector_78(*const Bundle, *i32, *i32) callconv(.c) ?[*]const i32;
extern fn ures_getSize_78(*const Bundle) callconv(.c) i32;
extern fn ures_close_78(*Bundle) callconv(.c) void;
extern fn uscript_getShortName_78(i32) callconv(.c) ?[*:0]const u8;
fn check(status: i32) !void {
    if (status == 7) return error.OutOfMemory;
    if (status > 0) return error.IcuLocaleDataUnavailable;
}
fn child(parent: *const Bundle, key: [:0]const u8) !*Bundle {
    var status: i32 = 0;
    const result = ures_getByKey_78(parent, key, null, &status) orelse {
        try check(status);
        return error.IcuLocaleDataUnavailable;
    };
    try check(status);
    return result;
}
fn strings(gpa: std.mem.Allocator, parent: *const Bundle, key: [:0]const u8) ![][]const u8 {
    const array = try child(parent, key);
    defer ures_close_78(array);
    const count = ures_getSize_78(array);
    if (count < 0) return error.InvalidIcuLocaleData;
    const result = try gpa.alloc([]const u8, @intCast(count));
    for (result, 0..) |*entry, index| {
        var status: i32 = 0;
        var length: i32 = 0;
        const units = ures_getStringByIndex_78(array, @intCast(index), &length, &status) orelse {
            try check(status);
            return error.IcuLocaleDataUnavailable;
        };
        try check(status);
        if (length < 0) return error.InvalidIcuLocaleData;
        const text = try gpa.alloc(u8, @intCast(length));
        for (text, units[0..text.len]) |*byte, unit| {
            if (unit > 127) return error.NonAsciiIcuLocaleData;
            byte.* = @intCast(unit);
        }
        entry.* = text;
    }
    return result;
}
fn binary(parent: *const Bundle, key: [:0]const u8) ![]const u8 {
    const resource = try child(parent, key);
    defer ures_close_78(resource);
    var status: i32 = 0;
    var count: i32 = 0;
    const result = ures_getBinary_78(resource, &count, &status) orelse {
        try check(status);
        return error.IcuLocaleDataUnavailable;
    };
    try check(status);
    if (count < 0) return error.InvalidIcuLocaleData;
    return result[0..@intCast(count)];
}
fn integers(parent: *const Bundle, key: [:0]const u8) ![]const i32 {
    const resource = try child(parent, key);
    defer ures_close_78(resource);
    var status: i32 = 0;
    var count: i32 = 0;
    const result = ures_getIntVector_78(resource, &count, &status) orelse {
        try check(status);
        return error.IcuLocaleDataUnavailable;
    };
    try check(status);
    if (count < 0) return error.InvalidIcuLocaleData;
    return result[0..@intCast(count)];
}
pub const Lsr = struct {
    language: []const u8,
    script: []const u8,
    region: []const u8,
    flags: u3 = 0,
    pub fn equivalent(left: Lsr, right: Lsr) bool {
        return std.mem.eql(u8, left.language, right.language) and std.mem.eql(u8, left.script, right.script) and std.mem.eql(u8, left.region, right.region);
    }
    pub fn equal(left: Lsr, right: Lsr) bool {
        return left.flags == right.flags and left.equivalent(right);
    }
    pub fn regionIndex(self: Lsr) usize {
        if (self.region.len == 3 and std.ascii.isDigit(self.region[0]) and std.ascii.isDigit(self.region[1]) and std.ascii.isDigit(self.region[2])) return @as(usize, self.region[0] - '0') * 100 + @as(usize, self.region[1] - '0') * 10 + self.region[2] - '0' + 1;
        if (self.region.len == 2 and self.region[0] >= 'A' and self.region[0] <= 'Z' and self.region[1] >= 'A' and self.region[1] <= 'Z') return @as(usize, self.region[0] - 'A') * 26 + self.region[1] - 'A' + 1001;
        return 0;
    }
};
fn decode(gpa: std.mem.Allocator, encoded: []const i32, m49: []const []const u8) ![]Lsr {
    const result = try gpa.alloc(Lsr, encoded.len);
    for (encoded, result) |signed, *entry| {
        const value: u32 = @bitCast(signed);
        if (value <= 1) {
            entry.* = .{ .language = if (value == 0) "" else "skip", .script = if (value == 0) "" else "script", .region = "" };
            continue;
        }
        const language_code = (value & 0xffffff) % (27 * 27 * 27);
        var language: [3]u8 = undefined;
        if (language_code % 27 == 0 or (language_code / 27) % 27 == 0) return error.InvalidIcuLsrLanguage;
        language[0] = @intCast('a' + language_code % 27 - 1);
        language[1] = @intCast('a' + (language_code / 27) % 27 - 1);
        const language_length: usize = if (language_code / (27 * 27) == 0) 2 else 3;
        if (language_length == 3) language[2] = @intCast('a' + language_code / (27 * 27) - 1);
        const script_z = uscript_getShortName_78(@intCast(value >> 24));
        const script = if (script_z) |text| std.mem.span(text) else "";
        const region_code = ((value & 0xffffff) / (27 * 27 * 27)) % (27 * 27);
        var region: []const u8 = undefined;
        if (region_code < 27) {
            if (region_code >= m49.len) return error.InvalidIcuLsrRegion;
            region = m49[region_code];
        } else {
            if (region_code % 27 == 0) return error.InvalidIcuLsrRegion;
            const letters = [_]u8{ @intCast('A' + region_code % 27 - 1), @intCast('A' + (region_code / 27) % 27 - 1) };
            region = try gpa.dupe(u8, &letters);
        }
        entry.* = .{ .language = try gpa.dupe(u8, language[0..language_length]), .script = try gpa.dupe(u8, script), .region = region };
    }
    return result;
}
pub const Data = struct {
    backing: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    root: *Bundle,
    likely_trie: []const u8,
    likely_lsrs: []Lsr,
    language_aliases: [][]const u8,
    region_aliases: [][]const u8,
    distance_trie: []const u8,
    region_to_partitions: []const u8,
    partitions: [][]const u8,
    paradigms: []Lsr,
    distances: []const i32,
    macroregions: [][]const u8,
    pub fn init(backing: std.mem.Allocator) !Data {
        try icu.initialize();
        const arena = try backing.create(std.heap.ArenaAllocator);
        arena.* = .init(backing);
        errdefer {
            arena.deinit();
            backing.destroy(arena);
        }
        const gpa = arena.allocator();
        var status: i32 = 0;
        const root = ures_openDirect_78(null, "langInfo", &status) orelse {
            try check(status);
            return error.IcuLocaleDataUnavailable;
        };
        errdefer ures_close_78(root);
        try check(status);
        const likely = try child(root, "likely");
        defer ures_close_78(likely);
        const match = try child(root, "match");
        defer ures_close_78(match);
        const m49 = try strings(gpa, likely, "m49");
        const supplemental = ures_openDirect_78(null, "supplementalData", &status) orelse {
            try check(status);
            return error.IcuLocaleDataUnavailable;
        };
        defer ures_close_78(supplemental);
        const validity = try child(supplemental, "idValidity");
        defer ures_close_78(validity);
        const regions = try child(validity, "region");
        defer ures_close_78(regions);
        const result: Data = .{ .backing = backing, .arena = arena, .root = root, .likely_trie = try binary(likely, "trie"), .likely_lsrs = try decode(gpa, try integers(likely, "lsrnum"), m49), .language_aliases = try strings(gpa, likely, "languageAliases"), .region_aliases = try strings(gpa, likely, "regionAliases"), .distance_trie = try binary(match, "trie"), .region_to_partitions = try binary(match, "regionToPartitions"), .partitions = try strings(gpa, match, "partitions"), .paradigms = try decode(gpa, try integers(match, "paradigmnum"), m49), .distances = try integers(match, "distances"), .macroregions = try strings(gpa, regions, "macroregion") };
        if (result.distances.len < 4 or result.region_to_partitions.len < 1677 or result.language_aliases.len % 2 != 0 or result.region_aliases.len % 2 != 0 or result.likely_lsrs.len < 2) return error.InvalidIcuLocaleData;
        return result;
    }
    pub fn deinit(self: *Data) void {
        ures_close_78(self.root);
        self.arena.deinit();
        self.backing.destroy(self.arena);
        self.* = undefined;
    }
    pub fn alias(pairs: []const []const u8, value: []const u8) []const u8 {
        var index: usize = 0;
        while (index < pairs.len) : (index += 2) if (std.mem.eql(u8, pairs[index], value)) return pairs[index + 1];
        return value;
    }
    pub fn isMacroregion(self: *const Data, value: []const u8) bool {
        for (self.macroregions) |range| {
            if (std.mem.indexOfScalar(u8, range, '~')) |at| {
                if (at != value.len or at == 0 or range.len != at + 2) continue;
                if (std.mem.eql(u8, value[0 .. at - 1], range[0 .. at - 1]) and value[at - 1] >= range[at - 1] and value[at - 1] <= range[at + 1]) return true;
            } else if (std.mem.eql(u8, range, value)) return true;
        }
        return false;
    }
};
