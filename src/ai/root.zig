//! AI package: multi-provider model clients.
const std = @import("std");

pub const providers = @import("providers.zig");
pub const openai = @import("openai.zig");
pub const anthropic = @import("anthropic.zig");
pub const google = @import("google.zig");
pub const mock = @import("mock.zig");
pub const stream = @import("stream.zig");
pub const images = @import("images.zig");
/// Expanded monorepo-scale model catalog shards (40×100 models + capability helpers).
pub const generated = @import("generated_root.zig");
/// Product-facing catalog index (used by CLI --list-models and cost helpers).
pub const catalog_index = @import("catalog_index.zig");
pub const catalog_surface_test = @import("catalog_surface_test.zig");

pub const Provider = providers.Provider;
pub const resolveApiKey = providers.resolveApiKey;
pub const resolveProvider = providers.resolveProvider;
pub const StreamDelta = stream.StreamDelta;
pub const StreamHandler = stream.StreamHandler;

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

/// Token/cost totals (upstream Usage shape, simplified).
pub const Usage = struct {
    input: u64 = 0,
    output: u64 = 0,
    cache_read: u64 = 0,
    cache_write: u64 = 0,
    total_tokens: u64 = 0,

    pub fn total(self: Usage) u64 {
        if (self.total_tokens > 0) return self.total_tokens;
        return self.input + self.output + self.cache_read + self.cache_write;
    }
};

pub const ModelResponse = struct {
    content: []const u8,
    tool_calls: []ToolCall,
    /// Upstream-shaped assistant metadata (owned heap strings when non-empty).
    provider: []const u8 = "",
    model: []const u8 = "",
    /// "stop" | "toolUse" | "length" | "error" | "aborted"
    stop_reason: []const u8 = "",
    usage: Usage = .{},

    pub fn deinit(self: *ModelResponse, gpa: std.mem.Allocator) void {
        gpa.free(self.content);
        for (self.tool_calls) |*tc| tc.deinit(gpa);
        gpa.free(self.tool_calls);
        if (self.provider.len > 0) gpa.free(self.provider);
        if (self.model.len > 0) gpa.free(self.model);
        if (self.stop_reason.len > 0) gpa.free(self.stop_reason);
        self.* = undefined;
    }

    /// Infer stop_reason from tool_calls when not set by the transport.
    pub fn ensureStopReason(self: *ModelResponse, gpa: std.mem.Allocator) !void {
        if (self.stop_reason.len > 0) return;
        const reason: []const u8 = if (self.tool_calls.len > 0) "toolUse" else "stop";
        self.stop_reason = try gpa.dupe(u8, reason);
    }
};

pub const ChatMessage = struct {
    role: []const u8,
    content: []const u8,
    tool_call_id: ?[]const u8 = null,
    tool_calls_json: ?[]const u8 = null,
    tool_name: ?[]const u8 = null,
    /// Optional multimodal image (base64) attached to user messages.
    image_b64: ?[]const u8 = null,
    image_mime: ?[]const u8 = null,
};

/// Thinking / reasoning level mapped to provider API fields.
pub const ThinkingLevel = enum {
    off,
    low,
    medium,
    high,
    xhigh,

    pub fn fromString(s: []const u8) ThinkingLevel {
        if (std.mem.eql(u8, s, "off") or std.mem.eql(u8, s, "none")) return .off;
        if (std.mem.eql(u8, s, "low") or std.mem.eql(u8, s, "minimal")) return .low;
        if (std.mem.eql(u8, s, "medium") or std.mem.eql(u8, s, "mid")) return .medium;
        if (std.mem.eql(u8, s, "high")) return .high;
        if (std.mem.eql(u8, s, "xhigh") or std.mem.eql(u8, s, "max")) return .xhigh;
        return .medium;
    }

    /// Anthropic budget_tokens mapping.
    pub fn anthropicBudget(self: ThinkingLevel) ?u32 {
        return switch (self) {
            .off => null,
            .low => 1024,
            .medium => 4096,
            .high => 10000,
            .xhigh => 32000,
        };
    }

    /// OpenAI reasoning_effort string.
    pub fn openaiEffort(self: ThinkingLevel) ?[]const u8 {
        return switch (self) {
            .off => null,
            .low => "low",
            .medium => "medium",
            .high => "high",
            .xhigh => "high",
        };
    }
};

pub const StreamCompleteFn = *const fn (
    ptr: *anyopaque,
    gpa: std.mem.Allocator,
    messages: []const ChatMessage,
    tools_json: []const u8,
    on_delta: ?StreamHandler,
    delta_ctx: ?*anyopaque,
) anyerror!ModelResponse;

pub const ModelClient = struct {
    ptr: *anyopaque,
    completeFn: *const fn (ptr: *anyopaque, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8) anyerror!ModelResponse,
    /// Optional streaming path; when null, completeStreaming synthesizes deltas from complete().
    streamFn: ?StreamCompleteFn = null,

    pub fn complete(self: ModelClient, gpa: std.mem.Allocator, messages: []const ChatMessage, tools_json: []const u8) !ModelResponse {
        return self.completeFn(self.ptr, gpa, messages, tools_json);
    }

    pub fn completeStreaming(
        self: ModelClient,
        gpa: std.mem.Allocator,
        messages: []const ChatMessage,
        tools_json: []const u8,
        on_delta: ?StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ModelResponse {
        if (self.streamFn) |sf| {
            return sf(self.ptr, gpa, messages, tools_json, on_delta, delta_ctx);
        }
        const resp = try self.complete(gpa, messages, tools_json);
        if (on_delta) |h| {
            if (resp.content.len > 0) {
                h(delta_ctx, .{ .kind = .text_delta, .text = resp.content });
            }
            for (resp.tool_calls) |tc| {
                h(delta_ctx, .{
                    .kind = .tool_call_delta,
                    .tool_call_id = tc.id,
                    .tool_name = tc.name,
                    .tool_arguments = tc.arguments,
                });
            }
            h(delta_ctx, .{ .kind = .done });
        }
        return resp;
    }
};

test {
    std.testing.refAllDecls(@This());
}
