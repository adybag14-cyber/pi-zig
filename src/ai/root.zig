//! AI package: multi-provider model clients.
const std = @import("std");

pub const providers = @import("providers.zig");
pub const openai = @import("openai.zig");
pub const anthropic = @import("anthropic.zig");
pub const google = @import("google.zig");
pub const mock = @import("mock.zig");

pub const Provider = providers.Provider;
pub const resolveApiKey = providers.resolveApiKey;
pub const resolveProvider = providers.resolveProvider;

pub const ToolCall = struct {
    id: []const u8,
    name: []const u8,
    /// JSON object string for tool arguments.
    arguments: []const u8,

    pub fn deinit(self: *ToolCall, gpa: std.mem.Allocator) void {
        gpa.free(self.id);
        gpa.free(self.name);
        gpa.free(self.arguments);
        self.* = undefined;
    }
};

pub const ModelResponse = struct {
    content: []const u8,
    tool_calls: []ToolCall,

    pub fn deinit(self: *ModelResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        for (self.tool_calls) |*tc| tc.deinit(gpa);
        gpa.free(self.tool_calls);
        self.* = undefined;
    }
};

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,
};

pub const ModelClient = struct {
    ptr: *anyopaque,
    completeFn: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8) anyerror!ModelResponse,

    pub fn complete(self: ModelClient, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8) !ModelResponse {
        return self.completeFn(self.ptr, gpa, messages, tools_json);
    }
};

test {
    std.testing.refAllDecls(@This());
}
