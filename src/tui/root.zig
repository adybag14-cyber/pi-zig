//! Native terminal UI primitives.
const std = @import("std");
pub const ansi = @import("ansi.zig");
pub const render = @import("render.zig");
pub const diff = @import("diff.zig");
pub const terminal = @import("terminal.zig");
pub const terminal_text = @import("terminal_text.zig");
pub const layout = @import("layout.zig");
pub const keys = @import("keys.zig");
pub const stdin_buffer = @import("stdin_buffer.zig");
pub const word_navigation = @import("word_navigation.zig");
pub const kill_ring = @import("kill_ring.zig");
pub const editor = @import("editor.zig");
pub const line_editor = @import("line_editor.zig");
pub const keybindings = @import("keybindings.zig");
pub const fuzzy = @import("fuzzy.zig");
pub const terminal_image = @import("terminal_image.zig");
pub const osc52 = @import("osc52.zig");
pub const markdown = @import("markdown.zig");
pub const latex = @import("latex.zig");
pub const undo_stack = @import("undo_stack.zig");
pub const mouse = @import("mouse.zig");
pub const widgets = @import("widgets.zig");
pub const application = @import("application.zig");
test {
    std.testing.refAllDecls(@This());
}
