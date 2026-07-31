//! Generated auth provider flow helpers shard 13.
const std = @import("std");

pub const AuthMethod = enum { api_key, oauth_device, oauth_browser, bearer, basic, none };

pub fn methodName(m: AuthMethod) []const u8 {
    return switch (m) {
        .api_key => "api_key",
        .oauth_device => "oauth_device",
        .oauth_browser => "oauth_browser",
        .bearer => "bearer",
        .basic => "basic",
        .none => "none",
    };
}

pub fn auth_config_13_0_provider() []const u8 { return "openai"; }
pub fn auth_config_13_0_method() AuthMethod { return .api_key; }
pub fn auth_config_13_0_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_0_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_openai_13_0.json", .{agent_dir});
}
pub fn auth_config_13_0_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/openai/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-0", .{client_id, redirect});
}
pub fn auth_config_13_0_device_url() []const u8 { return "https://auth.example.com/openai/device"; }
pub fn auth_config_13_0_token_url() []const u8 { return "https://auth.example.com/openai/token"; }
pub fn auth_config_13_0_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_0_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_0_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_1_provider() []const u8 { return "anthropic"; }
pub fn auth_config_13_1_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_1_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_1_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_anthropic_13_1.json", .{agent_dir});
}
pub fn auth_config_13_1_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/anthropic/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-1", .{client_id, redirect});
}
pub fn auth_config_13_1_device_url() []const u8 { return "https://auth.example.com/anthropic/device"; }
pub fn auth_config_13_1_token_url() []const u8 { return "https://auth.example.com/anthropic/token"; }
pub fn auth_config_13_1_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_1_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_1_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_2_provider() []const u8 { return "google"; }
pub fn auth_config_13_2_method() AuthMethod { return .bearer; }
pub fn auth_config_13_2_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_2_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_google_13_2.json", .{agent_dir});
}
pub fn auth_config_13_2_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/google/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-2", .{client_id, redirect});
}
pub fn auth_config_13_2_device_url() []const u8 { return "https://auth.example.com/google/device"; }
pub fn auth_config_13_2_token_url() []const u8 { return "https://auth.example.com/google/token"; }
pub fn auth_config_13_2_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_2_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_2_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_3_provider() []const u8 { return "groq"; }
pub fn auth_config_13_3_method() AuthMethod { return .api_key; }
pub fn auth_config_13_3_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_3_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_groq_13_3.json", .{agent_dir});
}
pub fn auth_config_13_3_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/groq/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-3", .{client_id, redirect});
}
pub fn auth_config_13_3_device_url() []const u8 { return "https://auth.example.com/groq/device"; }
pub fn auth_config_13_3_token_url() []const u8 { return "https://auth.example.com/groq/token"; }
pub fn auth_config_13_3_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_3_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_3_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_4_provider() []const u8 { return "xai"; }
pub fn auth_config_13_4_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_4_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_4_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_xai_13_4.json", .{agent_dir});
}
pub fn auth_config_13_4_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/xai/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-4", .{client_id, redirect});
}
pub fn auth_config_13_4_device_url() []const u8 { return "https://auth.example.com/xai/device"; }
pub fn auth_config_13_4_token_url() []const u8 { return "https://auth.example.com/xai/token"; }
pub fn auth_config_13_4_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_4_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_4_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_5_provider() []const u8 { return "deepseek"; }
pub fn auth_config_13_5_method() AuthMethod { return .api_key; }
pub fn auth_config_13_5_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_5_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_deepseek_13_5.json", .{agent_dir});
}
pub fn auth_config_13_5_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/deepseek/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-5", .{client_id, redirect});
}
pub fn auth_config_13_5_device_url() []const u8 { return "https://auth.example.com/deepseek/device"; }
pub fn auth_config_13_5_token_url() []const u8 { return "https://auth.example.com/deepseek/token"; }
pub fn auth_config_13_5_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_5_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_5_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_6_provider() []const u8 { return "mistral"; }
pub fn auth_config_13_6_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_6_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_6_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_mistral_13_6.json", .{agent_dir});
}
pub fn auth_config_13_6_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/mistral/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-6", .{client_id, redirect});
}
pub fn auth_config_13_6_device_url() []const u8 { return "https://auth.example.com/mistral/device"; }
pub fn auth_config_13_6_token_url() []const u8 { return "https://auth.example.com/mistral/token"; }
pub fn auth_config_13_6_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_6_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_6_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_7_provider() []const u8 { return "together"; }
pub fn auth_config_13_7_method() AuthMethod { return .bearer; }
pub fn auth_config_13_7_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_7_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_together_13_7.json", .{agent_dir});
}
pub fn auth_config_13_7_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/together/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-7", .{client_id, redirect});
}
pub fn auth_config_13_7_device_url() []const u8 { return "https://auth.example.com/together/device"; }
pub fn auth_config_13_7_token_url() []const u8 { return "https://auth.example.com/together/token"; }
pub fn auth_config_13_7_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_7_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_7_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_8_provider() []const u8 { return "fireworks"; }
pub fn auth_config_13_8_method() AuthMethod { return .api_key; }
pub fn auth_config_13_8_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_8_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_fireworks_13_8.json", .{agent_dir});
}
pub fn auth_config_13_8_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/fireworks/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-8", .{client_id, redirect});
}
pub fn auth_config_13_8_device_url() []const u8 { return "https://auth.example.com/fireworks/device"; }
pub fn auth_config_13_8_token_url() []const u8 { return "https://auth.example.com/fireworks/token"; }
pub fn auth_config_13_8_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_8_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_8_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_9_provider() []const u8 { return "openrouter"; }
pub fn auth_config_13_9_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_9_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_9_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_openrouter_13_9.json", .{agent_dir});
}
pub fn auth_config_13_9_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/openrouter/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-9", .{client_id, redirect});
}
pub fn auth_config_13_9_device_url() []const u8 { return "https://auth.example.com/openrouter/device"; }
pub fn auth_config_13_9_token_url() []const u8 { return "https://auth.example.com/openrouter/token"; }
pub fn auth_config_13_9_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_9_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_9_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_10_provider() []const u8 { return "cerebras"; }
pub fn auth_config_13_10_method() AuthMethod { return .api_key; }
pub fn auth_config_13_10_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_10_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_cerebras_13_10.json", .{agent_dir});
}
pub fn auth_config_13_10_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/cerebras/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-10", .{client_id, redirect});
}
pub fn auth_config_13_10_device_url() []const u8 { return "https://auth.example.com/cerebras/device"; }
pub fn auth_config_13_10_token_url() []const u8 { return "https://auth.example.com/cerebras/token"; }
pub fn auth_config_13_10_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_10_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_10_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_11_provider() []const u8 { return "ollama"; }
pub fn auth_config_13_11_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_11_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_11_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_ollama_13_11.json", .{agent_dir});
}
pub fn auth_config_13_11_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/ollama/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-11", .{client_id, redirect});
}
pub fn auth_config_13_11_device_url() []const u8 { return "https://auth.example.com/ollama/device"; }
pub fn auth_config_13_11_token_url() []const u8 { return "https://auth.example.com/ollama/token"; }
pub fn auth_config_13_11_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_11_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_11_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_12_provider() []const u8 { return "lmstudio"; }
pub fn auth_config_13_12_method() AuthMethod { return .bearer; }
pub fn auth_config_13_12_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_12_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lmstudio_13_12.json", .{agent_dir});
}
pub fn auth_config_13_12_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lmstudio/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-12", .{client_id, redirect});
}
pub fn auth_config_13_12_device_url() []const u8 { return "https://auth.example.com/lmstudio/device"; }
pub fn auth_config_13_12_token_url() []const u8 { return "https://auth.example.com/lmstudio/token"; }
pub fn auth_config_13_12_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_12_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_12_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_13_provider() []const u8 { return "vllm"; }
pub fn auth_config_13_13_method() AuthMethod { return .api_key; }
pub fn auth_config_13_13_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_13_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_vllm_13_13.json", .{agent_dir});
}
pub fn auth_config_13_13_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/vllm/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-13", .{client_id, redirect});
}
pub fn auth_config_13_13_device_url() []const u8 { return "https://auth.example.com/vllm/device"; }
pub fn auth_config_13_13_token_url() []const u8 { return "https://auth.example.com/vllm/token"; }
pub fn auth_config_13_13_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_13_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_13_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_14_provider() []const u8 { return "azure"; }
pub fn auth_config_13_14_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_14_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_14_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_azure_13_14.json", .{agent_dir});
}
pub fn auth_config_13_14_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/azure/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-14", .{client_id, redirect});
}
pub fn auth_config_13_14_device_url() []const u8 { return "https://auth.example.com/azure/device"; }
pub fn auth_config_13_14_token_url() []const u8 { return "https://auth.example.com/azure/token"; }
pub fn auth_config_13_14_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_14_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_14_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_15_provider() []const u8 { return "bedrock"; }
pub fn auth_config_13_15_method() AuthMethod { return .api_key; }
pub fn auth_config_13_15_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_15_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_bedrock_13_15.json", .{agent_dir});
}
pub fn auth_config_13_15_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/bedrock/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-15", .{client_id, redirect});
}
pub fn auth_config_13_15_device_url() []const u8 { return "https://auth.example.com/bedrock/device"; }
pub fn auth_config_13_15_token_url() []const u8 { return "https://auth.example.com/bedrock/token"; }
pub fn auth_config_13_15_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_15_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_15_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_16_provider() []const u8 { return "vertex"; }
pub fn auth_config_13_16_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_16_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_16_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_vertex_13_16.json", .{agent_dir});
}
pub fn auth_config_13_16_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/vertex/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-16", .{client_id, redirect});
}
pub fn auth_config_13_16_device_url() []const u8 { return "https://auth.example.com/vertex/device"; }
pub fn auth_config_13_16_token_url() []const u8 { return "https://auth.example.com/vertex/token"; }
pub fn auth_config_13_16_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_16_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_16_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_17_provider() []const u8 { return "perplexity"; }
pub fn auth_config_13_17_method() AuthMethod { return .bearer; }
pub fn auth_config_13_17_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_17_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_perplexity_13_17.json", .{agent_dir});
}
pub fn auth_config_13_17_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/perplexity/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-17", .{client_id, redirect});
}
pub fn auth_config_13_17_device_url() []const u8 { return "https://auth.example.com/perplexity/device"; }
pub fn auth_config_13_17_token_url() []const u8 { return "https://auth.example.com/perplexity/token"; }
pub fn auth_config_13_17_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_17_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_17_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_18_provider() []const u8 { return "cohere"; }
pub fn auth_config_13_18_method() AuthMethod { return .api_key; }
pub fn auth_config_13_18_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_18_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_cohere_13_18.json", .{agent_dir});
}
pub fn auth_config_13_18_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/cohere/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-18", .{client_id, redirect});
}
pub fn auth_config_13_18_device_url() []const u8 { return "https://auth.example.com/cohere/device"; }
pub fn auth_config_13_18_token_url() []const u8 { return "https://auth.example.com/cohere/token"; }
pub fn auth_config_13_18_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_18_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_18_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_19_provider() []const u8 { return "nvidia"; }
pub fn auth_config_13_19_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_19_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_19_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_nvidia_13_19.json", .{agent_dir});
}
pub fn auth_config_13_19_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/nvidia/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-19", .{client_id, redirect});
}
pub fn auth_config_13_19_device_url() []const u8 { return "https://auth.example.com/nvidia/device"; }
pub fn auth_config_13_19_token_url() []const u8 { return "https://auth.example.com/nvidia/token"; }
pub fn auth_config_13_19_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_19_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_19_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_20_provider() []const u8 { return "sambanova"; }
pub fn auth_config_13_20_method() AuthMethod { return .api_key; }
pub fn auth_config_13_20_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_20_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_sambanova_13_20.json", .{agent_dir});
}
pub fn auth_config_13_20_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/sambanova/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-20", .{client_id, redirect});
}
pub fn auth_config_13_20_device_url() []const u8 { return "https://auth.example.com/sambanova/device"; }
pub fn auth_config_13_20_token_url() []const u8 { return "https://auth.example.com/sambanova/token"; }
pub fn auth_config_13_20_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_20_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_20_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_21_provider() []const u8 { return "github"; }
pub fn auth_config_13_21_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_21_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_21_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_github_13_21.json", .{agent_dir});
}
pub fn auth_config_13_21_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/github/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-21", .{client_id, redirect});
}
pub fn auth_config_13_21_device_url() []const u8 { return "https://auth.example.com/github/device"; }
pub fn auth_config_13_21_token_url() []const u8 { return "https://auth.example.com/github/token"; }
pub fn auth_config_13_21_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_21_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_21_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_22_provider() []const u8 { return "huggingface"; }
pub fn auth_config_13_22_method() AuthMethod { return .bearer; }
pub fn auth_config_13_22_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_22_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_huggingface_13_22.json", .{agent_dir});
}
pub fn auth_config_13_22_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/huggingface/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-22", .{client_id, redirect});
}
pub fn auth_config_13_22_device_url() []const u8 { return "https://auth.example.com/huggingface/device"; }
pub fn auth_config_13_22_token_url() []const u8 { return "https://auth.example.com/huggingface/token"; }
pub fn auth_config_13_22_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_22_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_22_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_23_provider() []const u8 { return "replicate"; }
pub fn auth_config_13_23_method() AuthMethod { return .api_key; }
pub fn auth_config_13_23_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_23_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_replicate_13_23.json", .{agent_dir});
}
pub fn auth_config_13_23_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/replicate/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-23", .{client_id, redirect});
}
pub fn auth_config_13_23_device_url() []const u8 { return "https://auth.example.com/replicate/device"; }
pub fn auth_config_13_23_token_url() []const u8 { return "https://auth.example.com/replicate/token"; }
pub fn auth_config_13_23_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_23_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_23_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_24_provider() []const u8 { return "anyscale"; }
pub fn auth_config_13_24_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_24_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_24_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_anyscale_13_24.json", .{agent_dir});
}
pub fn auth_config_13_24_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/anyscale/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-24", .{client_id, redirect});
}
pub fn auth_config_13_24_device_url() []const u8 { return "https://auth.example.com/anyscale/device"; }
pub fn auth_config_13_24_token_url() []const u8 { return "https://auth.example.com/anyscale/token"; }
pub fn auth_config_13_24_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_24_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_24_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_25_provider() []const u8 { return "databricks"; }
pub fn auth_config_13_25_method() AuthMethod { return .api_key; }
pub fn auth_config_13_25_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_25_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_databricks_13_25.json", .{agent_dir});
}
pub fn auth_config_13_25_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/databricks/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-25", .{client_id, redirect});
}
pub fn auth_config_13_25_device_url() []const u8 { return "https://auth.example.com/databricks/device"; }
pub fn auth_config_13_25_token_url() []const u8 { return "https://auth.example.com/databricks/token"; }
pub fn auth_config_13_25_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_25_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_25_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_26_provider() []const u8 { return "moonshot"; }
pub fn auth_config_13_26_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_26_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_26_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_moonshot_13_26.json", .{agent_dir});
}
pub fn auth_config_13_26_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/moonshot/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-26", .{client_id, redirect});
}
pub fn auth_config_13_26_device_url() []const u8 { return "https://auth.example.com/moonshot/device"; }
pub fn auth_config_13_26_token_url() []const u8 { return "https://auth.example.com/moonshot/token"; }
pub fn auth_config_13_26_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_26_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_26_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_27_provider() []const u8 { return "qwen"; }
pub fn auth_config_13_27_method() AuthMethod { return .bearer; }
pub fn auth_config_13_27_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_27_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_qwen_13_27.json", .{agent_dir});
}
pub fn auth_config_13_27_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/qwen/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-27", .{client_id, redirect});
}
pub fn auth_config_13_27_device_url() []const u8 { return "https://auth.example.com/qwen/device"; }
pub fn auth_config_13_27_token_url() []const u8 { return "https://auth.example.com/qwen/token"; }
pub fn auth_config_13_27_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_27_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_27_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_28_provider() []const u8 { return "minimax"; }
pub fn auth_config_13_28_method() AuthMethod { return .api_key; }
pub fn auth_config_13_28_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_28_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_minimax_13_28.json", .{agent_dir});
}
pub fn auth_config_13_28_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/minimax/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-28", .{client_id, redirect});
}
pub fn auth_config_13_28_device_url() []const u8 { return "https://auth.example.com/minimax/device"; }
pub fn auth_config_13_28_token_url() []const u8 { return "https://auth.example.com/minimax/token"; }
pub fn auth_config_13_28_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_28_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_28_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_29_provider() []const u8 { return "zhipu"; }
pub fn auth_config_13_29_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_29_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_29_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_zhipu_13_29.json", .{agent_dir});
}
pub fn auth_config_13_29_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/zhipu/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-29", .{client_id, redirect});
}
pub fn auth_config_13_29_device_url() []const u8 { return "https://auth.example.com/zhipu/device"; }
pub fn auth_config_13_29_token_url() []const u8 { return "https://auth.example.com/zhipu/token"; }
pub fn auth_config_13_29_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_29_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_29_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_30_provider() []const u8 { return "baichuan"; }
pub fn auth_config_13_30_method() AuthMethod { return .api_key; }
pub fn auth_config_13_30_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_30_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_baichuan_13_30.json", .{agent_dir});
}
pub fn auth_config_13_30_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/baichuan/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-30", .{client_id, redirect});
}
pub fn auth_config_13_30_device_url() []const u8 { return "https://auth.example.com/baichuan/device"; }
pub fn auth_config_13_30_token_url() []const u8 { return "https://auth.example.com/baichuan/token"; }
pub fn auth_config_13_30_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_30_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_30_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_31_provider() []const u8 { return "yi"; }
pub fn auth_config_13_31_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_31_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_31_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_yi_13_31.json", .{agent_dir});
}
pub fn auth_config_13_31_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/yi/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-31", .{client_id, redirect});
}
pub fn auth_config_13_31_device_url() []const u8 { return "https://auth.example.com/yi/device"; }
pub fn auth_config_13_31_token_url() []const u8 { return "https://auth.example.com/yi/token"; }
pub fn auth_config_13_31_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_31_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_31_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_32_provider() []const u8 { return "siliconflow"; }
pub fn auth_config_13_32_method() AuthMethod { return .bearer; }
pub fn auth_config_13_32_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_32_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_siliconflow_13_32.json", .{agent_dir});
}
pub fn auth_config_13_32_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/siliconflow/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-32", .{client_id, redirect});
}
pub fn auth_config_13_32_device_url() []const u8 { return "https://auth.example.com/siliconflow/device"; }
pub fn auth_config_13_32_token_url() []const u8 { return "https://auth.example.com/siliconflow/token"; }
pub fn auth_config_13_32_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_32_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_32_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_33_provider() []const u8 { return "novita"; }
pub fn auth_config_13_33_method() AuthMethod { return .api_key; }
pub fn auth_config_13_33_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_33_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_novita_13_33.json", .{agent_dir});
}
pub fn auth_config_13_33_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/novita/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-33", .{client_id, redirect});
}
pub fn auth_config_13_33_device_url() []const u8 { return "https://auth.example.com/novita/device"; }
pub fn auth_config_13_33_token_url() []const u8 { return "https://auth.example.com/novita/token"; }
pub fn auth_config_13_33_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_33_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_33_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_34_provider() []const u8 { return "lepton"; }
pub fn auth_config_13_34_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_34_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_34_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lepton_13_34.json", .{agent_dir});
}
pub fn auth_config_13_34_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lepton/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-34", .{client_id, redirect});
}
pub fn auth_config_13_34_device_url() []const u8 { return "https://auth.example.com/lepton/device"; }
pub fn auth_config_13_34_token_url() []const u8 { return "https://auth.example.com/lepton/token"; }
pub fn auth_config_13_34_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_34_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_34_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_35_provider() []const u8 { return "deepinfra"; }
pub fn auth_config_13_35_method() AuthMethod { return .api_key; }
pub fn auth_config_13_35_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_35_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_deepinfra_13_35.json", .{agent_dir});
}
pub fn auth_config_13_35_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/deepinfra/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-35", .{client_id, redirect});
}
pub fn auth_config_13_35_device_url() []const u8 { return "https://auth.example.com/deepinfra/device"; }
pub fn auth_config_13_35_token_url() []const u8 { return "https://auth.example.com/deepinfra/token"; }
pub fn auth_config_13_35_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_35_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_35_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_36_provider() []const u8 { return "friendli"; }
pub fn auth_config_13_36_method() AuthMethod { return .oauth_device; }
pub fn auth_config_13_36_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_36_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_friendli_13_36.json", .{agent_dir});
}
pub fn auth_config_13_36_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/friendli/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-36", .{client_id, redirect});
}
pub fn auth_config_13_36_device_url() []const u8 { return "https://auth.example.com/friendli/device"; }
pub fn auth_config_13_36_token_url() []const u8 { return "https://auth.example.com/friendli/token"; }
pub fn auth_config_13_36_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_36_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_36_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_37_provider() []const u8 { return "hyperbolic"; }
pub fn auth_config_13_37_method() AuthMethod { return .bearer; }
pub fn auth_config_13_37_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_37_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_hyperbolic_13_37.json", .{agent_dir});
}
pub fn auth_config_13_37_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/hyperbolic/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-37", .{client_id, redirect});
}
pub fn auth_config_13_37_device_url() []const u8 { return "https://auth.example.com/hyperbolic/device"; }
pub fn auth_config_13_37_token_url() []const u8 { return "https://auth.example.com/hyperbolic/token"; }
pub fn auth_config_13_37_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_37_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_37_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_38_provider() []const u8 { return "lambda"; }
pub fn auth_config_13_38_method() AuthMethod { return .api_key; }
pub fn auth_config_13_38_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_38_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lambda_13_38.json", .{agent_dir});
}
pub fn auth_config_13_38_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lambda/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-38", .{client_id, redirect});
}
pub fn auth_config_13_38_device_url() []const u8 { return "https://auth.example.com/lambda/device"; }
pub fn auth_config_13_38_token_url() []const u8 { return "https://auth.example.com/lambda/token"; }
pub fn auth_config_13_38_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_38_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_38_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_13_39_provider() []const u8 { return "nebius"; }
pub fn auth_config_13_39_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_13_39_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_13_39_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_nebius_13_39.json", .{agent_dir});
}
pub fn auth_config_13_39_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/nebius/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=13-39", .{client_id, redirect});
}
pub fn auth_config_13_39_device_url() []const u8 { return "https://auth.example.com/nebius/device"; }
pub fn auth_config_13_39_token_url() []const u8 { return "https://auth.example.com/nebius/token"; }
pub fn auth_config_13_39_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_13_39_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_13_39_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

test "auth shard 13" {
    try std.testing.expectEqualStrings("openai", auth_config_13_0_provider());
    const gpa = std.testing.allocator;
    const h = try auth_config_13_0_format_header(gpa, "tok");
    defer gpa.free(h);
    try std.testing.expect(std.mem.startsWith(u8, h, "Bearer "));
}

