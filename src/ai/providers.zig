//! Provider catalog and API key resolution from environment.
const std = @import("std");
const config = @import("../config.zig");

pub const Provider = enum {
    openai,
    anthropic,
    google,
    mock,

    pub fn fromString(s: []const u8) ?Provider {
        if (std.mem.eql(u8, s, "openai")) return .openai;
        if (std.mem.eql(u8, s, "anthropic")) return .anthropic;
        if (std.mem.eql(u8, s, "google") or std.mem.eql(u8, s, "gemini")) return .google;
        if (std.mem.eql(u8, s, "mock")) return .mock;
        return null;
    }

    pub fn name(self: Provider) []const u8 {
        return switch (self) {
            .openai => "openai",
            .anthropic => "anthropic",
            .google => "google",
            .mock => "mock",
        };
    }
};

pub const ModelInfo = struct {
    provider: Provider,
    id: []const u8,
    display: []const u8,
};

pub const known_models = [_]ModelInfo{
    .{ .provider = .openai, .id = "gpt-4o-mini", .display = "OpenAI GPT-4o mini" },
    .{ .provider = .openai, .id = "gpt-4o", .display = "OpenAI GPT-4o" },
    .{ .provider = .openai, .id = "gpt-4.1-mini", .display = "OpenAI GPT-4.1 mini" },
    .{ .provider = .anthropic, .id = "claude-sonnet-4-20250514", .display = "Anthropic Claude Sonnet 4" },
    .{ .provider = .anthropic, .id = "claude-3-5-haiku-latest", .display = "Anthropic Claude 3.5 Haiku" },
    .{ .provider = .google, .id = "gemini-2.0-flash", .display = "Google Gemini 2.0 Flash" },
    .{ .provider = .google, .id = "gemini-1.5-pro", .display = "Google Gemini 1.5 Pro" },
    .{ .provider = .mock, .id = "mock", .display = "Mock (scripted)" },
};

/// Resolve API key for a provider from explicit key or environment.
pub fn resolveApiKey(provider: Provider, explicit: ?[]const u8, environ: *const std.process.Environ.Map) ?[]const u8 {
    if (explicit) |k| return k;
    if (environ.get(config.ENV_API_KEY)) |k| return k;
    return switch (provider) {
        .openai => environ.get(config.ENV_OPENAI_KEY),
        .anthropic => environ.get(config.ENV_ANTHROPIC_KEY),
        .google => environ.get(config.ENV_GOOGLE_KEY) orelse environ.get(config.ENV_GEMINI_KEY),
        .mock => null,
    };
}

pub fn resolveProvider(explicit: ?[]const u8, environ: *const std.process.Environ.Map) Provider {
    if (explicit) |p| {
        if (Provider.fromString(p)) |prov| return prov;
    }
    if (environ.get(config.ENV_PROVIDER)) |p| {
        if (Provider.fromString(p)) |prov| return prov;
    }
    // Prefer whichever key is set
    if (environ.get(config.ENV_OPENAI_KEY) != null) return .openai;
    if (environ.get(config.ENV_ANTHROPIC_KEY) != null) return .anthropic;
    if (environ.get(config.ENV_GOOGLE_KEY) != null or environ.get(config.ENV_GEMINI_KEY) != null) return .google;
    return .openai;
}

pub fn defaultModel(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "gpt-4o-mini",
        .anthropic => "claude-sonnet-4-20250514",
        .google => "gemini-2.0-flash",
        .mock => "mock",
    };
}

pub fn defaultBaseUrl(provider: Provider) []const u8 {
    return switch (provider) {
        .openai => "https://api.openai.com/v1",
        .anthropic => "https://api.anthropic.com",
        .google => "https://generativelanguage.googleapis.com/v1beta",
        .mock => "",
    };
}

test "provider from string" {
    try std.testing.expect(Provider.fromString("openai").? == .openai);
    try std.testing.expect(Provider.fromString("gemini").? == .google);
    try std.testing.expect(Provider.fromString("nope") == null);
}

test "resolveApiKey prefers explicit" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    const k = resolveApiKey(.openai, "sk-test", &env);
    try std.testing.expectEqualStrings("sk-test", k.?);
}
