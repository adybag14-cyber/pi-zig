//! Generated auth provider flow helpers shard 14.
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

pub fn auth_config_14_0_provider() []const u8 { return "openai"; }
pub fn auth_config_14_0_method() AuthMethod { return .api_key; }
pub fn auth_config_14_0_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_0_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_openai_14_0.json", .{agent_dir});
}
pub fn auth_config_14_0_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/openai/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-0", .{client_id, redirect});
}
pub fn auth_config_14_0_device_url() []const u8 { return "https://auth.example.com/openai/device"; }
pub fn auth_config_14_0_token_url() []const u8 { return "https://auth.example.com/openai/token"; }
pub fn auth_config_14_0_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_0_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_0_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_1_provider() []const u8 { return "anthropic"; }
pub fn auth_config_14_1_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_1_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_1_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_anthropic_14_1.json", .{agent_dir});
}
pub fn auth_config_14_1_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/anthropic/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-1", .{client_id, redirect});
}
pub fn auth_config_14_1_device_url() []const u8 { return "https://auth.example.com/anthropic/device"; }
pub fn auth_config_14_1_token_url() []const u8 { return "https://auth.example.com/anthropic/token"; }
pub fn auth_config_14_1_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_1_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_1_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_2_provider() []const u8 { return "google"; }
pub fn auth_config_14_2_method() AuthMethod { return .bearer; }
pub fn auth_config_14_2_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_2_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_google_14_2.json", .{agent_dir});
}
pub fn auth_config_14_2_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/google/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-2", .{client_id, redirect});
}
pub fn auth_config_14_2_device_url() []const u8 { return "https://auth.example.com/google/device"; }
pub fn auth_config_14_2_token_url() []const u8 { return "https://auth.example.com/google/token"; }
pub fn auth_config_14_2_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_2_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_2_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_3_provider() []const u8 { return "groq"; }
pub fn auth_config_14_3_method() AuthMethod { return .api_key; }
pub fn auth_config_14_3_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_3_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_groq_14_3.json", .{agent_dir});
}
pub fn auth_config_14_3_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/groq/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-3", .{client_id, redirect});
}
pub fn auth_config_14_3_device_url() []const u8 { return "https://auth.example.com/groq/device"; }
pub fn auth_config_14_3_token_url() []const u8 { return "https://auth.example.com/groq/token"; }
pub fn auth_config_14_3_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_3_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_3_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_4_provider() []const u8 { return "xai"; }
pub fn auth_config_14_4_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_4_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_4_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_xai_14_4.json", .{agent_dir});
}
pub fn auth_config_14_4_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/xai/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-4", .{client_id, redirect});
}
pub fn auth_config_14_4_device_url() []const u8 { return "https://auth.example.com/xai/device"; }
pub fn auth_config_14_4_token_url() []const u8 { return "https://auth.example.com/xai/token"; }
pub fn auth_config_14_4_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_4_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_4_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_5_provider() []const u8 { return "deepseek"; }
pub fn auth_config_14_5_method() AuthMethod { return .api_key; }
pub fn auth_config_14_5_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_5_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_deepseek_14_5.json", .{agent_dir});
}
pub fn auth_config_14_5_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/deepseek/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-5", .{client_id, redirect});
}
pub fn auth_config_14_5_device_url() []const u8 { return "https://auth.example.com/deepseek/device"; }
pub fn auth_config_14_5_token_url() []const u8 { return "https://auth.example.com/deepseek/token"; }
pub fn auth_config_14_5_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_5_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_5_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_6_provider() []const u8 { return "mistral"; }
pub fn auth_config_14_6_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_6_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_6_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_mistral_14_6.json", .{agent_dir});
}
pub fn auth_config_14_6_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/mistral/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-6", .{client_id, redirect});
}
pub fn auth_config_14_6_device_url() []const u8 { return "https://auth.example.com/mistral/device"; }
pub fn auth_config_14_6_token_url() []const u8 { return "https://auth.example.com/mistral/token"; }
pub fn auth_config_14_6_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_6_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_6_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_7_provider() []const u8 { return "together"; }
pub fn auth_config_14_7_method() AuthMethod { return .bearer; }
pub fn auth_config_14_7_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_7_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_together_14_7.json", .{agent_dir});
}
pub fn auth_config_14_7_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/together/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-7", .{client_id, redirect});
}
pub fn auth_config_14_7_device_url() []const u8 { return "https://auth.example.com/together/device"; }
pub fn auth_config_14_7_token_url() []const u8 { return "https://auth.example.com/together/token"; }
pub fn auth_config_14_7_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_7_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_7_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_8_provider() []const u8 { return "fireworks"; }
pub fn auth_config_14_8_method() AuthMethod { return .api_key; }
pub fn auth_config_14_8_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_8_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_fireworks_14_8.json", .{agent_dir});
}
pub fn auth_config_14_8_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/fireworks/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-8", .{client_id, redirect});
}
pub fn auth_config_14_8_device_url() []const u8 { return "https://auth.example.com/fireworks/device"; }
pub fn auth_config_14_8_token_url() []const u8 { return "https://auth.example.com/fireworks/token"; }
pub fn auth_config_14_8_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_8_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_8_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_9_provider() []const u8 { return "openrouter"; }
pub fn auth_config_14_9_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_9_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_9_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_openrouter_14_9.json", .{agent_dir});
}
pub fn auth_config_14_9_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/openrouter/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-9", .{client_id, redirect});
}
pub fn auth_config_14_9_device_url() []const u8 { return "https://auth.example.com/openrouter/device"; }
pub fn auth_config_14_9_token_url() []const u8 { return "https://auth.example.com/openrouter/token"; }
pub fn auth_config_14_9_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_9_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_9_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_10_provider() []const u8 { return "cerebras"; }
pub fn auth_config_14_10_method() AuthMethod { return .api_key; }
pub fn auth_config_14_10_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_10_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_cerebras_14_10.json", .{agent_dir});
}
pub fn auth_config_14_10_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/cerebras/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-10", .{client_id, redirect});
}
pub fn auth_config_14_10_device_url() []const u8 { return "https://auth.example.com/cerebras/device"; }
pub fn auth_config_14_10_token_url() []const u8 { return "https://auth.example.com/cerebras/token"; }
pub fn auth_config_14_10_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_10_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_10_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_11_provider() []const u8 { return "ollama"; }
pub fn auth_config_14_11_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_11_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_11_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_ollama_14_11.json", .{agent_dir});
}
pub fn auth_config_14_11_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/ollama/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-11", .{client_id, redirect});
}
pub fn auth_config_14_11_device_url() []const u8 { return "https://auth.example.com/ollama/device"; }
pub fn auth_config_14_11_token_url() []const u8 { return "https://auth.example.com/ollama/token"; }
pub fn auth_config_14_11_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_11_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_11_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_12_provider() []const u8 { return "lmstudio"; }
pub fn auth_config_14_12_method() AuthMethod { return .bearer; }
pub fn auth_config_14_12_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_12_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lmstudio_14_12.json", .{agent_dir});
}
pub fn auth_config_14_12_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lmstudio/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-12", .{client_id, redirect});
}
pub fn auth_config_14_12_device_url() []const u8 { return "https://auth.example.com/lmstudio/device"; }
pub fn auth_config_14_12_token_url() []const u8 { return "https://auth.example.com/lmstudio/token"; }
pub fn auth_config_14_12_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_12_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_12_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_13_provider() []const u8 { return "vllm"; }
pub fn auth_config_14_13_method() AuthMethod { return .api_key; }
pub fn auth_config_14_13_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_13_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_vllm_14_13.json", .{agent_dir});
}
pub fn auth_config_14_13_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/vllm/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-13", .{client_id, redirect});
}
pub fn auth_config_14_13_device_url() []const u8 { return "https://auth.example.com/vllm/device"; }
pub fn auth_config_14_13_token_url() []const u8 { return "https://auth.example.com/vllm/token"; }
pub fn auth_config_14_13_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_13_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_13_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_14_provider() []const u8 { return "azure"; }
pub fn auth_config_14_14_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_14_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_14_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_azure_14_14.json", .{agent_dir});
}
pub fn auth_config_14_14_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/azure/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-14", .{client_id, redirect});
}
pub fn auth_config_14_14_device_url() []const u8 { return "https://auth.example.com/azure/device"; }
pub fn auth_config_14_14_token_url() []const u8 { return "https://auth.example.com/azure/token"; }
pub fn auth_config_14_14_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_14_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_14_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_15_provider() []const u8 { return "bedrock"; }
pub fn auth_config_14_15_method() AuthMethod { return .api_key; }
pub fn auth_config_14_15_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_15_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_bedrock_14_15.json", .{agent_dir});
}
pub fn auth_config_14_15_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/bedrock/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-15", .{client_id, redirect});
}
pub fn auth_config_14_15_device_url() []const u8 { return "https://auth.example.com/bedrock/device"; }
pub fn auth_config_14_15_token_url() []const u8 { return "https://auth.example.com/bedrock/token"; }
pub fn auth_config_14_15_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_15_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_15_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_16_provider() []const u8 { return "vertex"; }
pub fn auth_config_14_16_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_16_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_16_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_vertex_14_16.json", .{agent_dir});
}
pub fn auth_config_14_16_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/vertex/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-16", .{client_id, redirect});
}
pub fn auth_config_14_16_device_url() []const u8 { return "https://auth.example.com/vertex/device"; }
pub fn auth_config_14_16_token_url() []const u8 { return "https://auth.example.com/vertex/token"; }
pub fn auth_config_14_16_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_16_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_16_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_17_provider() []const u8 { return "perplexity"; }
pub fn auth_config_14_17_method() AuthMethod { return .bearer; }
pub fn auth_config_14_17_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_17_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_perplexity_14_17.json", .{agent_dir});
}
pub fn auth_config_14_17_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/perplexity/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-17", .{client_id, redirect});
}
pub fn auth_config_14_17_device_url() []const u8 { return "https://auth.example.com/perplexity/device"; }
pub fn auth_config_14_17_token_url() []const u8 { return "https://auth.example.com/perplexity/token"; }
pub fn auth_config_14_17_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_17_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_17_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_18_provider() []const u8 { return "cohere"; }
pub fn auth_config_14_18_method() AuthMethod { return .api_key; }
pub fn auth_config_14_18_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_18_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_cohere_14_18.json", .{agent_dir});
}
pub fn auth_config_14_18_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/cohere/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-18", .{client_id, redirect});
}
pub fn auth_config_14_18_device_url() []const u8 { return "https://auth.example.com/cohere/device"; }
pub fn auth_config_14_18_token_url() []const u8 { return "https://auth.example.com/cohere/token"; }
pub fn auth_config_14_18_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_18_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_18_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_19_provider() []const u8 { return "nvidia"; }
pub fn auth_config_14_19_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_19_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_19_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_nvidia_14_19.json", .{agent_dir});
}
pub fn auth_config_14_19_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/nvidia/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-19", .{client_id, redirect});
}
pub fn auth_config_14_19_device_url() []const u8 { return "https://auth.example.com/nvidia/device"; }
pub fn auth_config_14_19_token_url() []const u8 { return "https://auth.example.com/nvidia/token"; }
pub fn auth_config_14_19_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_19_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_19_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_20_provider() []const u8 { return "sambanova"; }
pub fn auth_config_14_20_method() AuthMethod { return .api_key; }
pub fn auth_config_14_20_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_20_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_sambanova_14_20.json", .{agent_dir});
}
pub fn auth_config_14_20_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/sambanova/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-20", .{client_id, redirect});
}
pub fn auth_config_14_20_device_url() []const u8 { return "https://auth.example.com/sambanova/device"; }
pub fn auth_config_14_20_token_url() []const u8 { return "https://auth.example.com/sambanova/token"; }
pub fn auth_config_14_20_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_20_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_20_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_21_provider() []const u8 { return "github"; }
pub fn auth_config_14_21_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_21_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_21_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_github_14_21.json", .{agent_dir});
}
pub fn auth_config_14_21_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/github/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-21", .{client_id, redirect});
}
pub fn auth_config_14_21_device_url() []const u8 { return "https://auth.example.com/github/device"; }
pub fn auth_config_14_21_token_url() []const u8 { return "https://auth.example.com/github/token"; }
pub fn auth_config_14_21_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_21_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_21_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_22_provider() []const u8 { return "huggingface"; }
pub fn auth_config_14_22_method() AuthMethod { return .bearer; }
pub fn auth_config_14_22_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_22_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_huggingface_14_22.json", .{agent_dir});
}
pub fn auth_config_14_22_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/huggingface/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-22", .{client_id, redirect});
}
pub fn auth_config_14_22_device_url() []const u8 { return "https://auth.example.com/huggingface/device"; }
pub fn auth_config_14_22_token_url() []const u8 { return "https://auth.example.com/huggingface/token"; }
pub fn auth_config_14_22_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_22_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_22_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_23_provider() []const u8 { return "replicate"; }
pub fn auth_config_14_23_method() AuthMethod { return .api_key; }
pub fn auth_config_14_23_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_23_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_replicate_14_23.json", .{agent_dir});
}
pub fn auth_config_14_23_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/replicate/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-23", .{client_id, redirect});
}
pub fn auth_config_14_23_device_url() []const u8 { return "https://auth.example.com/replicate/device"; }
pub fn auth_config_14_23_token_url() []const u8 { return "https://auth.example.com/replicate/token"; }
pub fn auth_config_14_23_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_23_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_23_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_24_provider() []const u8 { return "anyscale"; }
pub fn auth_config_14_24_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_24_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_24_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_anyscale_14_24.json", .{agent_dir});
}
pub fn auth_config_14_24_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/anyscale/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-24", .{client_id, redirect});
}
pub fn auth_config_14_24_device_url() []const u8 { return "https://auth.example.com/anyscale/device"; }
pub fn auth_config_14_24_token_url() []const u8 { return "https://auth.example.com/anyscale/token"; }
pub fn auth_config_14_24_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_24_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_24_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_25_provider() []const u8 { return "databricks"; }
pub fn auth_config_14_25_method() AuthMethod { return .api_key; }
pub fn auth_config_14_25_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_25_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_databricks_14_25.json", .{agent_dir});
}
pub fn auth_config_14_25_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/databricks/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-25", .{client_id, redirect});
}
pub fn auth_config_14_25_device_url() []const u8 { return "https://auth.example.com/databricks/device"; }
pub fn auth_config_14_25_token_url() []const u8 { return "https://auth.example.com/databricks/token"; }
pub fn auth_config_14_25_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_25_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_25_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_26_provider() []const u8 { return "moonshot"; }
pub fn auth_config_14_26_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_26_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_26_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_moonshot_14_26.json", .{agent_dir});
}
pub fn auth_config_14_26_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/moonshot/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-26", .{client_id, redirect});
}
pub fn auth_config_14_26_device_url() []const u8 { return "https://auth.example.com/moonshot/device"; }
pub fn auth_config_14_26_token_url() []const u8 { return "https://auth.example.com/moonshot/token"; }
pub fn auth_config_14_26_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_26_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_26_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_27_provider() []const u8 { return "qwen"; }
pub fn auth_config_14_27_method() AuthMethod { return .bearer; }
pub fn auth_config_14_27_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_27_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_qwen_14_27.json", .{agent_dir});
}
pub fn auth_config_14_27_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/qwen/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-27", .{client_id, redirect});
}
pub fn auth_config_14_27_device_url() []const u8 { return "https://auth.example.com/qwen/device"; }
pub fn auth_config_14_27_token_url() []const u8 { return "https://auth.example.com/qwen/token"; }
pub fn auth_config_14_27_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_27_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_27_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_28_provider() []const u8 { return "minimax"; }
pub fn auth_config_14_28_method() AuthMethod { return .api_key; }
pub fn auth_config_14_28_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_28_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_minimax_14_28.json", .{agent_dir});
}
pub fn auth_config_14_28_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/minimax/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-28", .{client_id, redirect});
}
pub fn auth_config_14_28_device_url() []const u8 { return "https://auth.example.com/minimax/device"; }
pub fn auth_config_14_28_token_url() []const u8 { return "https://auth.example.com/minimax/token"; }
pub fn auth_config_14_28_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_28_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_28_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_29_provider() []const u8 { return "zhipu"; }
pub fn auth_config_14_29_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_29_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_29_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_zhipu_14_29.json", .{agent_dir});
}
pub fn auth_config_14_29_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/zhipu/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-29", .{client_id, redirect});
}
pub fn auth_config_14_29_device_url() []const u8 { return "https://auth.example.com/zhipu/device"; }
pub fn auth_config_14_29_token_url() []const u8 { return "https://auth.example.com/zhipu/token"; }
pub fn auth_config_14_29_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_29_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_29_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_30_provider() []const u8 { return "baichuan"; }
pub fn auth_config_14_30_method() AuthMethod { return .api_key; }
pub fn auth_config_14_30_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_30_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_baichuan_14_30.json", .{agent_dir});
}
pub fn auth_config_14_30_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/baichuan/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-30", .{client_id, redirect});
}
pub fn auth_config_14_30_device_url() []const u8 { return "https://auth.example.com/baichuan/device"; }
pub fn auth_config_14_30_token_url() []const u8 { return "https://auth.example.com/baichuan/token"; }
pub fn auth_config_14_30_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_30_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_30_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_31_provider() []const u8 { return "yi"; }
pub fn auth_config_14_31_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_31_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_31_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_yi_14_31.json", .{agent_dir});
}
pub fn auth_config_14_31_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/yi/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-31", .{client_id, redirect});
}
pub fn auth_config_14_31_device_url() []const u8 { return "https://auth.example.com/yi/device"; }
pub fn auth_config_14_31_token_url() []const u8 { return "https://auth.example.com/yi/token"; }
pub fn auth_config_14_31_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_31_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_31_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_32_provider() []const u8 { return "siliconflow"; }
pub fn auth_config_14_32_method() AuthMethod { return .bearer; }
pub fn auth_config_14_32_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_32_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_siliconflow_14_32.json", .{agent_dir});
}
pub fn auth_config_14_32_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/siliconflow/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-32", .{client_id, redirect});
}
pub fn auth_config_14_32_device_url() []const u8 { return "https://auth.example.com/siliconflow/device"; }
pub fn auth_config_14_32_token_url() []const u8 { return "https://auth.example.com/siliconflow/token"; }
pub fn auth_config_14_32_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_32_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_32_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_33_provider() []const u8 { return "novita"; }
pub fn auth_config_14_33_method() AuthMethod { return .api_key; }
pub fn auth_config_14_33_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_33_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_novita_14_33.json", .{agent_dir});
}
pub fn auth_config_14_33_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/novita/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-33", .{client_id, redirect});
}
pub fn auth_config_14_33_device_url() []const u8 { return "https://auth.example.com/novita/device"; }
pub fn auth_config_14_33_token_url() []const u8 { return "https://auth.example.com/novita/token"; }
pub fn auth_config_14_33_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_33_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_33_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_34_provider() []const u8 { return "lepton"; }
pub fn auth_config_14_34_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_34_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_34_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lepton_14_34.json", .{agent_dir});
}
pub fn auth_config_14_34_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lepton/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-34", .{client_id, redirect});
}
pub fn auth_config_14_34_device_url() []const u8 { return "https://auth.example.com/lepton/device"; }
pub fn auth_config_14_34_token_url() []const u8 { return "https://auth.example.com/lepton/token"; }
pub fn auth_config_14_34_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_34_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_34_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_35_provider() []const u8 { return "deepinfra"; }
pub fn auth_config_14_35_method() AuthMethod { return .api_key; }
pub fn auth_config_14_35_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_35_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_deepinfra_14_35.json", .{agent_dir});
}
pub fn auth_config_14_35_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/deepinfra/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-35", .{client_id, redirect});
}
pub fn auth_config_14_35_device_url() []const u8 { return "https://auth.example.com/deepinfra/device"; }
pub fn auth_config_14_35_token_url() []const u8 { return "https://auth.example.com/deepinfra/token"; }
pub fn auth_config_14_35_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_35_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_35_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_36_provider() []const u8 { return "friendli"; }
pub fn auth_config_14_36_method() AuthMethod { return .oauth_device; }
pub fn auth_config_14_36_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_36_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_friendli_14_36.json", .{agent_dir});
}
pub fn auth_config_14_36_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/friendli/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-36", .{client_id, redirect});
}
pub fn auth_config_14_36_device_url() []const u8 { return "https://auth.example.com/friendli/device"; }
pub fn auth_config_14_36_token_url() []const u8 { return "https://auth.example.com/friendli/token"; }
pub fn auth_config_14_36_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_36_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_36_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_37_provider() []const u8 { return "hyperbolic"; }
pub fn auth_config_14_37_method() AuthMethod { return .bearer; }
pub fn auth_config_14_37_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_37_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_hyperbolic_14_37.json", .{agent_dir});
}
pub fn auth_config_14_37_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/hyperbolic/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-37", .{client_id, redirect});
}
pub fn auth_config_14_37_device_url() []const u8 { return "https://auth.example.com/hyperbolic/device"; }
pub fn auth_config_14_37_token_url() []const u8 { return "https://auth.example.com/hyperbolic/token"; }
pub fn auth_config_14_37_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_37_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_37_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_38_provider() []const u8 { return "lambda"; }
pub fn auth_config_14_38_method() AuthMethod { return .api_key; }
pub fn auth_config_14_38_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_38_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_lambda_14_38.json", .{agent_dir});
}
pub fn auth_config_14_38_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/lambda/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-38", .{client_id, redirect});
}
pub fn auth_config_14_38_device_url() []const u8 { return "https://auth.example.com/lambda/device"; }
pub fn auth_config_14_38_token_url() []const u8 { return "https://auth.example.com/lambda/token"; }
pub fn auth_config_14_38_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_38_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_38_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

pub fn auth_config_14_39_provider() []const u8 { return "nebius"; }
pub fn auth_config_14_39_method() AuthMethod { return .oauth_browser; }
pub fn auth_config_14_39_scopes() []const u8 { return "openid profile offline_access model.invoke"; }
pub fn auth_config_14_39_token_path(gpa: std.mem.Allocator, agent_dir: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{s}/oauth_nebius_14_39.json", .{agent_dir});
}
pub fn auth_config_14_39_authorize_url(gpa: std.mem.Allocator, client_id: []const u8, redirect: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "https://auth.example.com/nebius/authorize?client_id={s}&redirect_uri={s}&response_type=code&state=14-39", .{client_id, redirect});
}
pub fn auth_config_14_39_device_url() []const u8 { return "https://auth.example.com/nebius/device"; }
pub fn auth_config_14_39_token_url() []const u8 { return "https://auth.example.com/nebius/token"; }
pub fn auth_config_14_39_parse_error(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "error") != null;
}
pub fn auth_config_14_39_header_name() []const u8 { return "Authorization"; }
pub fn auth_config_14_39_format_header(gpa: std.mem.Allocator, token: []const u8) ![]u8 {
    return try std.fmt.allocPrint(gpa, "Bearer {s}", .{token});
}

test "auth shard 14" {
    try std.testing.expectEqualStrings("openai", auth_config_14_0_provider());
    const gpa = std.testing.allocator;
    const h = try auth_config_14_0_format_header(gpa, "tok");
    defer gpa.free(h);
    try std.testing.expect(std.mem.startsWith(u8, h, "Bearer "));
}

