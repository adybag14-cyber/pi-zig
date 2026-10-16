//! Explicit Node24 simple-pattern admission over the unchanged Pi minimatch core.
//! Node24 bundles 10.1.2, whereas this candidate core is 10.2.6. This adapter
//! admits only literal/*/?/** components; it does not claim full equivalence.
const std = @import("std");
const builtin = @import("builtin");
pub const core = @import("native_minimatch.zig");

pub fn compile(a: std.mem.Allocator, original: []const u8) !core.Pattern {
    if (original.len > 64 * 1024) return error.NodeGlobPatternTooLong;
    if (original.len == 0) return &.{};
    const pattern = try a.dupe(u8, original);
    // Node's windowsPathsNoEscape option applies on every platform.
    for (pattern) |*ch| if (ch.* == '\\') { ch.* = '/'; };
    if (pattern[0] == '!' or pattern[0] == '#' or std.mem.startsWith(u8, pattern, "//") or
        std.mem.indexOfAny(u8, pattern, "{}[]()") != null)
        return error.NodeGlobPatternOutsideAuditedGrammar;
    const raw = try core.split(a, pattern, builtin.os.tag == .windows);
    if (raw.len > 512) return error.NodeGlobPatternResourceLimit;
    if (raw.len == 2 and std.mem.eql(u8, raw[0], ".") and raw[1].len == 0)
        return error.NodeGlobOptimization2OutsideAuditedGrammar;
    for (raw, 0..) |part, index| {
        if (std.mem.eql(u8, part, "..") or (index > 0 and std.mem.eql(u8, part, ".")))
            return error.NodeGlobOptimization2OutsideAuditedGrammar;
        if (std.mem.indexOfScalar(u8, part, ':') != null and
            !(builtin.os.tag == .windows and index == 0 and part.len == 2 and
            std.ascii.isAlphabetic(part[0]) and part[1] == ':'))
            return error.NodeGlobRootOutsideAuditedGrammar;
    }
    const plan = try core.compile(a, pattern, .{ .nocase = builtin.os.tag == .windows or builtin.os.tag.isDarwin(), .windows = builtin.os.tag == .windows });
    if (plan.patterns.len != 1 or plan.negate or plan.comment or plan.empty)
        return error.NodeGlobPatternOutsideAuditedGrammar;
    const parts = try a.dupe(core.Part, plan.patterns[0]);
    // Node's nocaseMagicOnly preserves nonmagic components as exact strings.
    for (parts) |*part| if (part.* == .regex and part.regex.literal != null) { part.regex.nocase = false; };
    return parts;
}
