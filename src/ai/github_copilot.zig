//! GitHub Copilot request-local headers shared by OpenAI/Responses/Anthropic transports.
//! These are derived from the current transcript and never persisted into model context.
const std = @import("std");
const ai = @import("root.zig");

pub const USER_AGENT = "GitHubCopilotChat/0.35.0";
pub const EDITOR_VERSION = "vscode/1.107.0";
pub const EDITOR_PLUGIN_VERSION = "copilot-chat/0.35.0";
pub const INTEGRATION_ID = "vscode-chat";

pub const DynamicHeaders = struct {
    initiator: []const u8,
    has_vision: bool,
};

pub fn infer(messages: []const ai.ChatMessage) DynamicHeaders {
    const initiator: []const u8 = if (messages.len > 0 and !std.mem.eql(u8, messages[messages.len - 1].role, "user")) "agent" else "user";
    var has_vision = false;
    for (messages) |message| {
        const image_role = std.mem.eql(u8, message.role, "user") or std.mem.eql(u8, message.role, "tool") or std.mem.eql(u8, message.role, "toolResult");
        if (image_role and message.hasImages()) {
            has_vision = true;
            break;
        }
    }
    return .{ .initiator = initiator, .has_vision = has_vision };
}

pub fn isCopilot(provider_id: []const u8) bool {
    return std.ascii.eqlIgnoreCase(provider_id, "github-copilot");
}

test "Copilot dynamic headers infer initiator and vision from transcript" {
    const user = [_]ai.ChatMessage{.{ .role = "user", .content = "hello" }};
    const u = infer(&user);
    try std.testing.expectEqualStrings("user", u.initiator);
    try std.testing.expect(!u.has_vision);

    const tool_image = [_]ai.ChatMessage{
        .{ .role = "user", .content = "inspect" },
        .{ .role = "tool", .content = "screenshot", .image_b64 = "AA==", .image_mime = "image/png" },
    };
    const a = infer(&tool_image);
    try std.testing.expectEqualStrings("agent", a.initiator);
    try std.testing.expect(a.has_vision);
}
