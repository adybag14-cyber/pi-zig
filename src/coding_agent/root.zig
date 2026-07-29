//! Coding agent package: CLI args, context, skills, modes, packages.
const std = @import("std");

pub const args = @import("args.zig");
pub const context = @import("context.zig");
pub const skills = @import("skills.zig");
pub const prompts = @import("prompts.zig");
pub const settings = @import("settings.zig");
pub const slash = @import("slash.zig");
pub const live_state = @import("live_state.zig");
pub const modes = @import("modes.zig");
pub const export_html = @import("export_html.zig");
pub const packages = @import("packages.zig");
pub const system_prompt = @import("system_prompt.zig");

test {
    std.testing.refAllDecls(@This());
}
