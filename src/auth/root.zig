//! Authentication helpers.
const std = @import("std");
pub const oauth = @import("oauth.zig");
pub const pkce = @import("pkce.zig");
pub const radius_oauth = @import("radius_oauth.zig");
pub const openai_codex_oauth = @import("openai_codex_oauth.zig");
pub const github_copilot_oauth = @import("github_copilot_oauth.zig");
pub const openrouter_oauth = @import("openrouter_oauth.zig");
pub const xai_oauth = @import("xai_oauth.zig");
pub const anthropic_oauth = @import("anthropic_oauth.zig");
pub const kimi_coding_oauth = @import("kimi_coding_oauth.zig");
pub const storage = @import("storage.zig");
pub const AuthStorage = storage.AuthStorage;
pub const RuntimeCredentials = storage.RuntimeCredentials;
pub const Credential = storage.Credential;
pub const parseDeviceCodeResponse = oauth.parseDeviceCodeResponse;
pub const parseTokenResponse = oauth.parseTokenResponse;
pub const saveTokens = oauth.saveTokens;
pub const loadAccessToken = oauth.loadAccessToken;
test {
    std.testing.refAllDecls(@This());
}
