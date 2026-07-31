//! Theme JSON load/apply (pi themes package subset).
const std = @import("std");
const Io = std.Io;

pub const Theme = struct {
    name: []const u8 = "default",
    accent: []const u8 = "cyan",
    error_color: []const u8 = "red",
    success_color: []const u8 = "green",
    muted: []const u8 = "brightBlack",
    /// ANSI SGR codes resolved from color names
    accent_sgr: []const u8 = "36",
    error_sgr: []const u8 = "31",
    success_sgr: []const u8 = "32",
    muted_sgr: []const u8 = "90",

    pub fn deinit(self: *Theme, gpa: std.mem.Allocator) void {
        if (self.name.len > 0 and !std.mem.eql(u8, self.name, "default")) gpa.free(self.name);
        // color name fields may be owned
        self.* = undefined;
    }
};

fn colorToSgr(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "red")) return "31";
    if (std.mem.eql(u8, name, "green")) return "32";
    if (std.mem.eql(u8, name, "yellow")) return "33";
    if (std.mem.eql(u8, name, "blue")) return "34";
    if (std.mem.eql(u8, name, "magenta")) return "35";
    if (std.mem.eql(u8, name, "cyan")) return "36";
    if (std.mem.eql(u8, name, "white")) return "37";
    if (std.mem.eql(u8, name, "brightBlack") or std.mem.eql(u8, name, "gray")) return "90";
    return "39";
}

pub fn parse(gpa: std.mem.Allocator, raw: []const u8) !Theme {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    var t = Theme{};
    if (parsed.value != .object) return t;
    if (parsed.value.object.get("name")) |v| {
        if (v == .string) t.name = try gpa.dupe(u8, v.string);
    }
    if (parsed.value.object.get("accent")) |v| {
        if (v == .string) {
            t.accent = v.string;
            t.accent_sgr = colorToSgr(v.string);
        }
    }
    if (parsed.value.object.get("error")) |v| {
        if (v == .string) {
            t.error_color = v.string;
            t.error_sgr = colorToSgr(v.string);
        }
    }
    if (parsed.value.object.get("success")) |v| {
        if (v == .string) {
            t.success_color = v.string;
            t.success_sgr = colorToSgr(v.string);
        }
    }
    if (parsed.value.object.get("muted")) |v| {
        if (v == .string) {
            t.muted = v.string;
            t.muted_sgr = colorToSgr(v.string);
        }
    }
    return t;
}

pub fn loadFile(gpa: std.mem.Allocator, io: Io, path: []const u8) !Theme {
    const raw = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024));
    defer gpa.free(raw);
    return try parse(gpa, raw);
}

pub fn wrap(sgr: []const u8, text: []const u8, gpa: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(gpa, "\x1b[{s}m{s}\x1b[0m", .{ sgr, text });
}

test "parse theme json" {
    const gpa = std.testing.allocator;
    const t = try parse(gpa,
        \\{"name":"dracula","accent":"magenta","error":"red","success":"green"}
    );
    defer {
        gpa.free(t.name);
    }
    try std.testing.expectEqualStrings("dracula", t.name);
    try std.testing.expectEqualStrings("35", t.accent_sgr);
}
