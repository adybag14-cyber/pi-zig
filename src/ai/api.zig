//! Native API protocol identity, separate from public provider identity.
const std = @import("std");
const providers = @import("providers.zig");

pub const Api = enum {
    openai_completions,
    openai_responses,
    openai_codex_responses,
    azure_openai_responses,
    anthropic_messages,
    google_generative_ai,
    google_vertex,
    mistral_conversations,
    bedrock_converse_stream,
    pi_messages,

    pub fn parse(value: []const u8) ?Api {
        if (std.mem.eql(u8, value, "openai-completions")) return .openai_completions;
        if (std.mem.eql(u8, value, "openai-responses")) return .openai_responses;
        if (std.mem.eql(u8, value, "openai-codex-responses")) return .openai_codex_responses;
        if (std.mem.eql(u8, value, "azure-openai-responses")) return .azure_openai_responses;
        if (std.mem.eql(u8, value, "anthropic-messages")) return .anthropic_messages;
        if (std.mem.eql(u8, value, "google-generative-ai")) return .google_generative_ai;
        if (std.mem.eql(u8, value, "google-vertex")) return .google_vertex;
        if (std.mem.eql(u8, value, "mistral-conversations")) return .mistral_conversations;
        if (std.mem.eql(u8, value, "bedrock-converse-stream")) return .bedrock_converse_stream;
        if (std.mem.eql(u8, value, "pi-messages")) return .pi_messages;
        return null;
    }

    pub fn name(self: Api) []const u8 {
        return switch (self) {
            .openai_completions => "openai-completions",
            .openai_responses => "openai-responses",
            .openai_codex_responses => "openai-codex-responses",
            .azure_openai_responses => "azure-openai-responses",
            .anthropic_messages => "anthropic-messages",
            .google_generative_ai => "google-generative-ai",
            .google_vertex => "google-vertex",
            .mistral_conversations => "mistral-conversations",
            .bedrock_converse_stream => "bedrock-converse-stream",
            .pi_messages => "pi-messages",
        };
    }

    pub fn nativeProvider(self: Api) providers.Provider {
        return switch (self) {
            .openai_completions, .openai_responses, .openai_codex_responses, .azure_openai_responses => .openai,
            .anthropic_messages => .anthropic,
            .google_generative_ai, .google_vertex => .google,
            .mistral_conversations => .mistral,
            .bedrock_converse_stream => .amazon_bedrock,
            .pi_messages => .radius,
        };
    }

    pub fn runtimeSupported(self: Api) bool {
        _ = self;
        return true;
    }
};

test "api protocol names round trip" {
    inline for (std.meta.fields(Api)) |field| {
        const value: Api = @enumFromInt(field.value);
        try std.testing.expectEqual(value, Api.parse(value.name()).?);
    }
}
