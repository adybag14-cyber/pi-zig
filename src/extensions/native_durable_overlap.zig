//! Source Chord bounded suffix/prefix search, measured in UTF-16 code units.
const std = @import("std");
pub fn overlap(left: []const u16, right: []const u16, scan: usize, probe: usize, max_candidates: usize) usize {
    if (left.len == 0 or right.len == 0 or scan == 0) return 0;
    const tail = left[left.len - @min(scan, left.len) ..];
    for ([_]usize{ @min(probe, right.len), 1 }) |length| {
        const head = right[0..length];
        var tried: usize = 0;
        var from: usize = 0;
        while (std.mem.indexOfPos(u16, tail, from, head)) |position| {
            tried += 1;
            if (tried > max_candidates) break;
            const count = tail.len - position;
            if (count <= right.len and std.mem.eql(u16, tail[position..], right[0..count])) return count;
            from = position + 1;
            if (from > tail.len) break;
        }
        if (length == 1) break;
    }
    return 0;
}
