//! Native deterministic dictionary/model projection from pinned ICU78.2 data.
const std = @import("std");
const Input = struct { name: []const u8, hash: []const u8, output: []const u8 };
const inputs = [_]Input{
    .{ .name = "cjdict.txt", .hash = "e73fd72048981d0cc13e9dc436a7eaba07ffb6eff58c8a59dc75c1df746663a0", .output = "cjk.dict.bin" },
    .{ .name = "khmerdict.txt", .hash = "87bee2d17cd5148aa36957eb05409eefc124de8ad519b81b789298ef3e60b5d9", .output = "khmer.dict.bin" },
    .{ .name = "laodict.txt", .hash = "3c876934a3fa81031d2333525eafaca6a7c9f842e3b98f18c38880420afb5d36", .output = "lao.dict.bin" },
    .{ .name = "thaidict.txt", .hash = "3166abde40c0f44ab91c28f5ce96d7d1472cb7882e1c0bda0a72f8f69dba4274", .output = "thai.dict.bin" },
    .{ .name = "burmesedict.txt", .hash = "61d8abc3d9102b2f9bf0c9f44db0d7ab89b18172d8cd26832e4c83174bd8673b", .output = "myanmar.dict.bin" },
};
const Node = struct { terminal: u32 = 0xffffffff, first: u32 = 0, count: u32 = 0 };
const Edge = struct { parent: u32, codepoint: u21, child: u32 };
const Builder = struct {
    gpa: std.mem.Allocator,
    nodes: std.ArrayList(Node) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    index: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    entries: u32 = 0,
    fn init(gpa: std.mem.Allocator) !Builder {
        var self: Builder = .{ .gpa = gpa };
        try self.nodes.append(gpa, .{});
        return self;
    }
    fn deinit(self: *Builder) void {
        self.nodes.deinit(self.gpa);
        self.edges.deinit(self.gpa);
        self.index.deinit(self.gpa);
    }
    fn add(self: *Builder, word: []const u8, value: u32) !void {
        var iterator = (try std.unicode.Utf8View.init(word)).iterator();
        var parent: u32 = 0;
        while (iterator.nextCodepoint()) |cp| {
            const key = (@as(u64, parent) << 21) | cp;
            if (self.index.get(key)) |child| parent = child else {
                const child: u32 = @intCast(self.nodes.items.len);
                try self.nodes.append(self.gpa, .{});
                try self.edges.append(self.gpa, .{ .parent = parent, .codepoint = cp, .child = child });
                try self.index.put(self.gpa, key, child);
                parent = child;
            }
        }
        if (self.nodes.items[parent].terminal != 0xffffffff) return error.DuplicateDictionaryEntry;
        self.nodes.items[parent].terminal = value;
        self.entries += 1;
    }
};
fn edgeLess(_: void, a: Edge, b: Edge) bool {
    return a.parent < b.parent or (a.parent == b.parent and a.codepoint < b.codepoint);
}
fn integer(writer: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try writer.writeAll(&bytes);
}
fn render(gpa: std.mem.Allocator, builder: *Builder) ![]u8 {
    std.mem.sort(Edge, builder.edges.items, {}, edgeLess);
    for (builder.edges.items, 0..) |edge, offset| {
        const node = &builder.nodes.items[edge.parent];
        if (node.count == 0) node.first = @intCast(offset);
        node.count += 1;
    }
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    const writer = &output.writer;
    try writer.writeAll("PIWD");
    for ([_]u32{ @intCast(builder.nodes.items.len), @intCast(builder.edges.items.len), 0, builder.entries, 0, 0, 0 }) |value| try integer(writer, value);
    for (builder.nodes.items) |node| {
        try integer(writer, node.first);
        try integer(writer, node.count);
        try integer(writer, node.terminal);
    }
    for (builder.edges.items) |edge| {
        try integer(writer, edge.codepoint);
        try integer(writer, edge.child);
    }
    return output.toOwnedSlice();
}
fn dictionary(gpa: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var builder = try Builder.init(gpa);
    defer builder.deinit();
    const content = if (std.mem.startsWith(u8, bytes, "\xef\xbb\xbf")) bytes[3..] else bytes;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line, '\t');
        const word = parts.next().?;
        const value = if (parts.next()) |cost| try std.fmt.parseInt(u32, std.mem.trim(u8, cost, " \r\t"), 10) else 0;
        if (parts.next() != null) return error.InvalidDictionaryLine;
        try builder.add(word, value);
    }
    return render(gpa, &builder);
}
pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 2 or (args.len == 2 and !std.mem.eql(u8, args[1], "--check"))) return error.InvalidArguments;
    const profile = try std.Io.Dir.cwd().readFileAlloc(init.io, "src/tui/fixtures/word-icu-capabilities-original-6fb.json", init.gpa, .limited(1024 * 1024));
    defer init.gpa.free(profile);
    var profile_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(profile, &profile_hash, .{});
    if (!std.mem.eql(u8, &std.fmt.bytesToHex(profile_hash, .lower), "4905b03c6f9785f1cf441b7a703d9705f6187cd3211b8b89a7e95adba7eeb55a")) return error.SourceIcuProfileHashMismatch;
    for (inputs) |input| {
        const path = try std.fmt.allocPrint(init.gpa, "src/tui/icu78/{s}", .{input.name});
        defer init.gpa.free(path);
        const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, path, init.gpa, .limited(16 * 1024 * 1024));
        defer init.gpa.free(bytes);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        if (!std.mem.eql(u8, &std.fmt.bytesToHex(digest, .lower), input.hash)) return error.LanguageInputHashMismatch;
        const projected = try dictionary(init.gpa, bytes);
        defer init.gpa.free(projected);
        const destination = try std.fmt.allocPrint(init.gpa, "src/tui/icu78/{s}", .{input.output});
        defer init.gpa.free(destination);
        if (args.len == 2) {
            const old = try std.Io.Dir.cwd().readFileAlloc(init.io, destination, init.gpa, .limited(64 * 1024 * 1024));
            defer init.gpa.free(old);
            if (!std.mem.eql(u8, old, projected)) return error.StaleLanguageProjection;
        } else try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = destination, .data = projected });
    }
}
