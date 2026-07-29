//! Assemble default + context + skills summary + append system.
const std = @import("std");
const agent_loop = @import("../agent/loop.zig");
const context = @import("context.zig");
const skills = @import("skills.zig");

pub const AssembleOptions = struct {
    base_prompt: []const u8 = agent_loop.default_system_prompt,
    system_override: ?[]const u8 = null,
    append_system: []const u8 = "",
    context_prompt: []const u8 = "",
    skills_summary: []const u8 = "",
    extra_appends: []const []const u8 = &.{},
    thinking_level: ?[]const u8 = null,
};

/// Build full system prompt string (caller frees).
pub fn assemble(gpa: std.mem.Allocator, opts: AssembleOptions) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(gpa);

    if (opts.system_override) |ov| {
        try out.appendSlice(gpa, ov);
    } else {
        try out.appendSlice(gpa, opts.base_prompt);
    }

    if (opts.append_system.len > 0) {
        try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, opts.append_system);
    }
    for (opts.extra_appends) |a| {
        if (a.len == 0) continue;
        try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, a);
    }
    if (opts.context_prompt.len > 0) {
        try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, opts.context_prompt);
    }
    if (opts.skills_summary.len > 0) {
        try out.appendSlice(gpa, "\n\n");
        try out.appendSlice(gpa, opts.skills_summary);
    }
    if (opts.thinking_level) |level| {
        try out.appendSlice(gpa, "\n\nThinking level: ");
        try out.appendSlice(gpa, level);
        try out.appendSlice(gpa, ". Reason carefully at this depth.");
    }
    return try out.toOwnedSlice(gpa);
}

test "assemble includes override and skills" {
    const gpa = std.testing.allocator;
    const p = try assemble(gpa, .{
        .system_override = "OVERRIDE",
        .skills_summary = "SKILLS HERE",
        .context_prompt = "CTX",
        .thinking_level = "high",
    });
    defer gpa.free(p);
    try std.testing.expect(std.mem.indexOf(u8, p, "OVERRIDE") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "SKILLS HERE") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "CTX") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "Thinking level: high") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "You are pi") == null);
}
