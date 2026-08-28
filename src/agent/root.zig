//! Agent package: loop, tools, sessions, compaction and truncation.
const std = @import("std");
pub const tools = @import("tools.zig");
pub const tool_manager = @import("tool_manager.zig");
pub const loop = @import("loop.zig");
pub const session = @import("session.zig");
pub const search = @import("search.zig");
pub const session_migration = @import("session_migration.zig");
pub const compaction = @import("compaction.zig");
pub const summarization = @import("summarization.zig");
pub const branch_summary = @import("branch_summary.zig");
pub const truncate = @import("truncate.zig");
pub const ToolResult = tools.ToolResult;
pub const ToolContext = tools.ToolContext;
pub const ToolFilter = tools.ToolFilter;
pub const execute = tools.execute;
pub const toolSchemasJson = tools.toolSchemasJson;
pub const AgentConfig = loop.AgentConfig;
pub const RunResult = loop.RunResult;
pub const UserImage = loop.UserImage;
pub const AgentEvent = loop.AgentEvent;
pub const EventKind = loop.EventKind;
pub const run = loop.run;
pub const runWithImages = loop.runWithImages;
pub const default_system_prompt = loop.default_system_prompt;
pub const Session = session.Session;
pub const SessionEntry = session.SessionEntry;
test {
    std.testing.refAllDecls(@This());
}
