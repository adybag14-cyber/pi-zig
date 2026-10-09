//! Read-only native dictionary trie generated from the actual Source ICU profile.
const std = @import("std");
const graphemes = @import("utf16_graphemes.zig");
pub const Match = struct { units: usize, codepoints: usize, value: u32 };
pub const Matches = struct { count: usize, prefix: usize, consumed_units: usize };
pub const Dictionary = struct {
    bytes: []const u8,
    nodes: usize,
    edges: usize,
    entries: usize,
    edge_offset: usize,
    pub fn init(bytes: []const u8) !Dictionary {
        if (bytes.len < 32 or !std.mem.eql(u8, bytes[0..4], "PIWD")) return error.InvalidWordDictionary;
        const nodes = read(bytes, 4);
        const edges = read(bytes, 8);
        const edge_offset = 32 + @as(usize, nodes) * 12;
        if (nodes == 0 or bytes.len != edge_offset + @as(usize, edges) * 8 or read(bytes, 12) != 0 or read(bytes, 20) != 0 or read(bytes, 24) != 0 or read(bytes, 28) != 0) return error.InvalidWordDictionary;
        return .{ .bytes = bytes, .nodes = nodes, .edges = edges, .entries = read(bytes, 16), .edge_offset = edge_offset };
    }
    fn read(bytes: []const u8, at: usize) u32 {
        return std.mem.readInt(u32, bytes[at..][0..4], .little);
    }
    fn terminal(self: Dictionary, node: usize) ?u32 {
        const value = read(self.bytes, 32 + node * 12 + 8);
        return if (value == 0xffffffff) null else value;
    }
    fn children(self: Dictionary, node: usize) usize {
        return read(self.bytes, 32 + node * 12 + 4);
    }
    fn next(self: Dictionary, node: usize, cp: u21) ?usize {
        const first = read(self.bytes, 32 + node * 12);
        var low: usize = first;
        var high = low + self.children(node);
        while (low < high) {
            const mid = low + (high - low) / 2;
            const value = read(self.bytes, self.edge_offset + mid * 8);
            if (cp < value) high = mid else if (cp > value) low = mid + 1 else return read(self.bytes, self.edge_offset + mid * 8 + 4);
        }
        return null;
    }
    pub fn exact(self: Dictionary, text: []const u16) ?u32 {
        var node: usize = 0;
        var at: usize = 0;
        while (at < text.len) {
            const cp = graphemes.scalar(text, at);
            node = self.next(node, cp.value) orelse return null;
            at = cp.end;
        }
        return self.terminal(node);
    }
    /// ICU maxLength is in native UTF16 units; prefix counts the failed scalar.
    pub fn matches(self: Dictionary, text: []const u16, maximum_units: usize, output: []Match) Matches {
        var node: usize = 0;
        var at: usize = 0;
        var count: usize = 0;
        var codepoints: usize = 0;
        while (at < text.len) {
            const cp = graphemes.scalar(text, at);
            at = cp.end;
            codepoints += 1;
            node = self.next(node, cp.value) orelse break;
            if (self.terminal(node)) |value| {
                if (count < output.len) {
                    output[count] = .{ .units = at, .codepoints = codepoints, .value = value };
                    count += 1;
                }
                if (self.children(node) == 0) break;
            }
            if (at >= maximum_units) break;
        }
        return .{ .count = count, .prefix = codepoints, .consumed_units = at };
    }
};
pub fn cjk() Dictionary {
    return Dictionary.init(@embedFile("icu78/cjk.dict.bin")) catch unreachable;
}
pub fn khmer() Dictionary {
    return Dictionary.init(@embedFile("icu78/khmer.dict.bin")) catch unreachable;
}
pub fn lao() Dictionary {
    return Dictionary.init(@embedFile("icu78/lao.dict.bin")) catch unreachable;
}
pub fn thai() Dictionary {
    return Dictionary.init(@embedFile("icu78/thai.dict.bin")) catch unreachable;
}
pub fn myanmar() Dictionary {
    return Dictionary.init(@embedFile("icu78/myanmar.dict.bin")) catch unreachable;
}
test "pinned Source ICU78 dictionary fallback containers preserve known words and entry counts" {
    const gpa = std.testing.allocator;
    const sample = try std.unicode.utf8ToUtf16LeAlloc(gpa, "中国");
    defer gpa.free(sample);
    try std.testing.expect(cjk().exact(sample) != null);
    try std.testing.expect(cjk().entries == 315964);
    try std.testing.expect(thai().entries > 10000 and myanmar().entries > 10000);
    try std.testing.expect(lao().entries > 10000 and khmer().entries > 10000);
}
