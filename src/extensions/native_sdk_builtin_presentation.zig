//! Private composition of implemented Original builtin presentation bodies.
//! File tools consume the actual preview and explicit native syntax runtime.
const std = @import("std");
const em = @import("engine.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const listing = @import("native_sdk_builtin_listing_renderers.zig");
const shell = @import("native_sdk_builtin_shell_renderers.zig");
const c = em.c;

/// Append real Source renderer callbacks after the existing real execute body.
/// Definition object must retain the Source metadata and execute insertion order.
/// Unsupported names fail explicitly; callers choose the implemented subset.
pub fn attach(engine: *em.Engine, definition: c.JSValue, name: []const u8) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const renderers = if (std.mem.eql(u8, name, "find") or std.mem.eql(u8, name, "ls") or std.mem.eql(u8, name, "grep"))
        try scope.own(try listing.get(engine, name))
    else if (std.mem.eql(u8, name, "bash") or std.mem.eql(u8, name, "powershell"))
        try scope.own(try shell.create(engine, try scope.text(if (std.mem.eql(u8, name, "bash")) "$" else "PS>")))
    else if (std.mem.eql(u8, name, "read") or std.mem.eql(u8, name, "write") or std.mem.eql(u8, name, "edit"))
        try scope.own(try @import("native_sdk_builtin_file_presentation.zig").create(engine, name))
    else
        return error.BuiltinPresentationBodyUnavailable;
    inline for (.{ "renderCall", "renderResult" }) |method| try scope.put(definition, method, try scope.get(renderers, method));
}
