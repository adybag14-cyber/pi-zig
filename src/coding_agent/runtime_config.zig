//! Shared provider/model runtime resolution for CLI and server execution.
//!
//! Public provider identity is deliberately separate from the native transport.
//! A custom `corp` provider may use the OpenAI wire format without inheriting
//! OPENAI_API_KEY or otherwise collapsing into the built-in `openai` identity.
const std = @import("std");
const Io = std.Io;
const config = @import("../config.zig");
const auth = @import("../auth/root.zig");
const providers = @import("../ai/providers.zig");
const models_file_mod = @import("models_file.zig");
const config_value = @import("config_value.zig");
const settings = @import("settings.zig");
const metadata = @import("../ai/request_metadata.zig");
const api_mod = @import("../ai/api.zig");
const thinking = @import("../ai/thinking.zig");
const google_adc = @import("../ai/google_adc.zig");
const radius_models_store = @import("radius_models_store.zig");

pub const ResolveOptions = struct {
    agent_dir: ?[]const u8 = null,
    explicit_api_key: ?[]const u8 = null,
    explicit_base_url: ?[]const u8 = null,
    /// Preserve CLI support for PI_API_KEY as an explicit generic override.
    allow_generic_api_key: bool = true,
    /// Preserve migration compatibility with the legacy KEY=value file.
    allow_legacy_credentials: bool = true,
};

pub const ResolvedRuntime = struct {
    gpa: std.mem.Allocator,
    provider_id: []const u8,
    model_id: []const u8,
    transport: providers.Provider,
    api: api_mod.Api,
    model_cost: providers.ModelCost = .{},
    api_key: ?[]u8 = null,
    /// Present only when api_key came from a stored OAuth credential.
    oauth_refresh: ?[]u8 = null,
    oauth_expires_ms: ?i64 = null,
    oauth_enterprise_url: ?[]u8 = null,
    base_url: []u8,
    headers: []metadata.Header = &.{},
    sampling_params: []metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    reasoning: bool = false,
    input_image: bool = false,
    thinking_level_map: ?thinking.ThinkingLevelMap = null,
    max_tokens: u64 = 0,
    context_window: u64 = 0,

    pub fn deinit(self: *ResolvedRuntime) void {
        if (self.api_key) |key| self.gpa.free(key);
        if (self.oauth_refresh) |refresh| self.gpa.free(refresh);
        if (self.oauth_enterprise_url) |value| self.gpa.free(value);
        self.gpa.free(self.base_url);
        for (self.headers) |header| {
            self.gpa.free(header.name);
            self.gpa.free(header.value);
        }
        if (self.headers.len > 0) self.gpa.free(self.headers);
        for (self.sampling_params) |param| {
            self.gpa.free(param.name);
            self.gpa.free(param.value_json);
        }
        if (self.sampling_params.len > 0) self.gpa.free(self.sampling_params);
        self.* = undefined;
    }
};

fn isLocalTransport(provider: providers.Provider) bool {
    return switch (provider) {
        .ollama, .lmstudio, .vllm, .mock => true,
        else => false,
    };
}

const StoredRuntimeCredential = struct {
    key: ?[]u8 = null,
    oauth_refresh: ?[]u8 = null,
    oauth_expires_ms: ?i64 = null,
    oauth_enterprise_url: ?[]u8 = null,

    fn deinit(self: *StoredRuntimeCredential, gpa: std.mem.Allocator) void {
        if (self.key) |value| gpa.free(value);
        if (self.oauth_refresh) |value| gpa.free(value);
        if (self.oauth_enterprise_url) |value| gpa.free(value);
        self.* = undefined;
    }
};

fn loadStoredRuntimeCredential(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    provider_id: []const u8,
) !StoredRuntimeCredential {
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    var credential = (try store.read(provider_id)) orelse return .{};
    defer credential.deinit(gpa);
    return switch (credential) {
        .api_key => |api_key| if (api_key.key) |key| blk: {
            var resolver = config_value.Resolver.init(gpa, io, environ);
            defer resolver.deinit();
            break :blk .{ .key = try resolver.resolve(key) };
        } else .{},
        .oauth => |oauth_credential| .{
            .key = try gpa.dupe(u8, oauth_credential.access),
            .oauth_refresh = try gpa.dupe(u8, oauth_credential.refresh),
            .oauth_expires_ms = oauth_credential.expires,
            .oauth_enterprise_url = if (oauth_credential.enterprise_url) |value| try gpa.dupe(u8, value) else null,
        },
    };
}

fn resolveConfiguredKey(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    configured: ?*const models_file_mod.ProviderConfig,
) !?[]u8 {
    const provider_config = configured orelse return null;
    const raw = provider_config.api_key orelse return null;
    var resolver = config_value.Resolver.init(gpa, io, environ);
    defer resolver.deinit();
    return resolver.resolve(raw);
}

fn putHeader(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    out: *std.ArrayList(metadata.Header),
    raw: metadata.Header,
) !void {
    var resolver = config_value.Resolver.init(gpa, io, environ);
    defer resolver.deinit();
    const resolved = (try resolver.resolve(raw.value)) orelse return error.MissingHeaderConfigValue;
    errdefer gpa.free(resolved);
    for (out.items) |*existing| {
        if (std.ascii.eqlIgnoreCase(existing.name, raw.name)) {
            gpa.free(existing.name);
            gpa.free(existing.value);
            existing.* = .{ .name = try gpa.dupe(u8, raw.name), .value = resolved };
            return;
        }
    }
    const name = try gpa.dupe(u8, raw.name);
    errdefer gpa.free(name);
    try out.append(gpa, .{ .name = name, .value = resolved });
}

fn resolveHeaders(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    builtin_model: providers.ModelInfo,
    provider: ?*const models_file_mod.ProviderConfig,
    model: ?*const models_file_mod.ModelConfig,
    override: ?*const models_file_mod.ModelOverride,
) ![]metadata.Header {
    var out: std.ArrayList(metadata.Header) = .empty;
    errdefer {
        for (out.items) |header| {
            gpa.free(header.name);
            gpa.free(header.value);
        }
        out.deinit(gpa);
    }
    if (provider) |cfg| for (cfg.headers) |header| try putHeader(gpa, io, environ, &out, header);
    // Match upstream rawModelHeaders composition: override first, then model
    // definition. A definition therefore wins on a duplicate model-header key.
    if (override) |cfg| for (cfg.headers) |header| try putHeader(gpa, io, environ, &out, header);
    for (builtin_model.headers) |header| try putHeader(gpa, io, environ, &out, header);
    if (model) |cfg| for (cfg.headers) |header| try putHeader(gpa, io, environ, &out, header);
    return try out.toOwnedSlice(gpa);
}

fn putSampling(gpa: std.mem.Allocator, out: *std.ArrayList(metadata.SamplingParam), raw: metadata.SamplingParam) !void {
    for (out.items) |*existing| {
        if (std.mem.eql(u8, existing.name, raw.name)) {
            gpa.free(existing.name);
            gpa.free(existing.value_json);
            existing.* = .{
                .name = try gpa.dupe(u8, raw.name),
                .value_json = try gpa.dupe(u8, raw.value_json),
            };
            return;
        }
    }
    try out.append(gpa, .{
        .name = try gpa.dupe(u8, raw.name),
        .value_json = try gpa.dupe(u8, raw.value_json),
    });
}

fn resolveSampling(
    gpa: std.mem.Allocator,
    builtin_model: providers.ModelInfo,
    model: ?*const models_file_mod.ModelConfig,
    override: ?*const models_file_mod.ModelOverride,
) ![]metadata.SamplingParam {
    var out: std.ArrayList(metadata.SamplingParam) = .empty;
    errdefer {
        for (out.items) |param| {
            gpa.free(param.name);
            gpa.free(param.value_json);
        }
        out.deinit(gpa);
    }
    for (builtin_model.sampling_params) |param| try putSampling(gpa, &out, param);
    if (model) |cfg| for (cfg.sampling_params) |param| try putSampling(gpa, &out, param);
    // Unlike model headers, upstream samplingParams are explicitly merged with
    // modelOverrides last, so override values win by key.
    if (override) |cfg| for (cfg.sampling_params) |param| try putSampling(gpa, &out, param);
    return try out.toOwnedSlice(gpa);
}

/// Resolve credentials and endpoint for one effective model. Returned key and
/// URL are allocator-owned and remain valid independently of env/config parser
/// storage, which is important for concurrent server turns.
fn materializeCloudflareBaseUrl(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    provider_id: []const u8,
    api: @import("../ai/api.zig").Api,
    selected_base: []const u8,
) ![]u8 {
    const is_workers = std.ascii.eqlIgnoreCase(provider_id, "cloudflare-workers-ai");
    const is_gateway = std.ascii.eqlIgnoreCase(provider_id, "cloudflare-ai-gateway");
    if (!is_workers and !is_gateway) return gpa.dupe(u8, selected_base);

    const account_id = environ.get("CLOUDFLARE_ACCOUNT_ID") orelse return error.MissingCloudflareAccountId;
    if (account_id.len == 0) return error.MissingCloudflareAccountId;
    if (is_workers) {
        // Preserve an explicit concrete custom URL; only materialize the built-in/template form.
        if (std.mem.indexOf(u8, selected_base, "{CLOUDFLARE_ACCOUNT_ID}") == null)
            return gpa.dupe(u8, selected_base);
        return std.fmt.allocPrint(gpa, "https://api.cloudflare.com/client/v4/accounts/{s}/ai/v1", .{account_id});
    }

    const gateway_id = environ.get("CLOUDFLARE_GATEWAY_ID") orelse return error.MissingCloudflareGatewayId;
    if (gateway_id.len == 0) return error.MissingCloudflareGatewayId;
    if (std.mem.indexOf(u8, selected_base, "{CLOUDFLARE_ACCOUNT_ID}") == null and
        std.mem.indexOf(u8, selected_base, "{CLOUDFLARE_GATEWAY_ID}") == null)
        return gpa.dupe(u8, selected_base);

    const suffix: []const u8 = switch (api) {
        .anthropic_messages => "anthropic",
        .openai_responses, .openai_codex_responses, .azure_openai_responses => "openai",
        else => "compat",
    };
    return std.fmt.allocPrint(gpa, "https://gateway.ai.cloudflare.com/v1/{s}/{s}/{s}", .{ account_id, gateway_id, suffix });
}

fn materializeGoogleVertexBaseUrl(
    gpa: std.mem.Allocator,
    environ: *const std.process.Environ.Map,
    api: api_mod.Api,
    selected_base: []const u8,
    has_explicit_base: bool,
    api_key: ?[]const u8,
) ![]u8 {
    if (api != .google_vertex or has_explicit_base) return gpa.dupe(u8, selected_base);
    if (api_key) |key| if (!google_adc.isAuthMarker(key))
        return gpa.dupe(u8, "https://aiplatform.googleapis.com/v1/publishers/google");
    const project = environ.get("GOOGLE_CLOUD_PROJECT") orelse environ.get("GCLOUD_PROJECT") orelse return error.MissingGoogleCloudProject;
    const location = environ.get("GOOGLE_CLOUD_LOCATION") orelse return error.MissingGoogleCloudLocation;
    return std.fmt.allocPrint(gpa, "https://{s}-aiplatform.googleapis.com/v1/projects/{s}/locations/{s}/publishers/google", .{ location, project, location });
}

fn cachedRadiusModelBase(
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    provider_id: []const u8,
    configured_provider: ?*const models_file_mod.ProviderConfig,
    effective_api: api_mod.Api,
    model_id: []const u8,
) !?[]u8 {
    if (effective_api != .pi_messages) return null;
    const is_radius = std.ascii.eqlIgnoreCase(provider_id, "radius") or
        (configured_provider != null and configured_provider.?.oauth == .radius);
    if (!is_radius) return null;
    const dir = agent_dir orelse return null;
    var catalog = (try radius_models_store.loadAvailableCatalog(gpa, io, dir, provider_id)) orelse return null;
    defer catalog.deinit(gpa);
    for (catalog.entries) |entry| {
        if (std.mem.eql(u8, entry.info.id, model_id)) return try gpa.dupe(u8, entry.base_url);
    }
    return null;
}

pub fn resolveForModel(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    models_file: ?*const models_file_mod.ModelsFile,
    model: providers.ModelInfo,
    options: ResolveOptions,
) !ResolvedRuntime {
    const provider_id = model.providerName();
    const transport = model.provider;
    const configured_provider = if (models_file) |file| file.findProvider(provider_id) else null;
    const configured_model = if (models_file) |file| file.findModel(provider_id, model.id) else null;
    const configured_override = if (configured_provider) |provider_cfg| provider_cfg.findOverride(model.id) else null;

    var owned_key: ?[]u8 = null;
    var oauth_refresh: ?[]u8 = null;
    var oauth_expires_ms: ?i64 = null;
    var oauth_enterprise_url: ?[]u8 = null;
    errdefer {
        if (owned_key) |key| gpa.free(key);
        if (oauth_refresh) |refresh| gpa.free(refresh);
        if (oauth_enterprise_url) |value| gpa.free(value);
    }

    // Explicit CLI/server key is strongest. A generic PI_API_KEY is treated as
    // an explicit process-wide override, but provider-specific built-in env vars
    // are consulted only when public identity is that built-in provider.
    if (options.explicit_api_key) |key| {
        owned_key = try gpa.dupe(u8, key);
    } else if (options.allow_generic_api_key) {
        if (environ.get(config.ENV_API_KEY)) |key| owned_key = try gpa.dupe(u8, key);
    }

    const builtin_identity = providers.Provider.fromString(provider_id);
    if (owned_key == null) {
        if (builtin_identity) |builtin| {
            if (builtin == .anthropic) {
                if (environ.get(config.ENV_ANTHROPIC_AUTH_TOKEN)) |key| owned_key = try gpa.dupe(u8, key) else if (environ.get(config.ENV_ANTHROPIC_OAUTH_TOKEN)) |key| owned_key = try gpa.dupe(u8, key) else if (environ.get(config.ENV_ANTHROPIC_KEY)) |key| owned_key = try gpa.dupe(u8, key);
            } else if (providers.credentialEnvName(builtin)) |env_name| {
                if (environ.get(env_name)) |key| owned_key = try gpa.dupe(u8, key);
            }
            if (owned_key == null and builtin == .google) {
                if (environ.get(config.ENV_GEMINI_KEY)) |key| owned_key = try gpa.dupe(u8, key);
            }
        }
    }

    if (owned_key == null and std.ascii.eqlIgnoreCase(provider_id, "google-vertex")) {
        if (environ.get("GOOGLE_CLOUD_API_KEY")) |key| {
            if (key.len > 0 and !google_adc.isAuthMarker(key)) owned_key = try gpa.dupe(u8, key);
        }
        if (owned_key == null) {
            var adc = try google_adc.load(gpa, io, environ);
            if (adc) |*credential| {
                credential.deinit(gpa);
                owned_key = try gpa.dupe(u8, "<authenticated>");
            }
        }
    }

    if (owned_key == null) {
        if (options.agent_dir) |agent_dir| {
            var stored = try loadStoredRuntimeCredential(gpa, io, environ, agent_dir, provider_id);
            defer stored.deinit(gpa);
            if (stored.key) |key| {
                owned_key = key;
                stored.key = null;
            }
            if (stored.oauth_refresh) |refresh| {
                oauth_refresh = refresh;
                stored.oauth_refresh = null;
                oauth_expires_ms = stored.oauth_expires_ms;
            }
            if (stored.oauth_enterprise_url) |value| {
                oauth_enterprise_url = value;
                stored.oauth_enterprise_url = null;
            }
        }
    }

    if (owned_key == null and options.allow_legacy_credentials) {
        if (options.agent_dir) |agent_dir| {
            if (builtin_identity) |builtin| {
                if (providers.credentialEnvName(builtin)) |key_name| {
                    owned_key = try settings.loadCredential(gpa, io, agent_dir, key_name);
                }
            }
        }
    }

    if (owned_key == null) {
        owned_key = try resolveConfiguredKey(gpa, io, environ, configured_provider);
    }
    if (owned_key == null and isLocalTransport(transport)) {
        owned_key = try gpa.dupe(u8, "local");
    }

    const effective_api = if (configured_model) |cfg| cfg.api else model.apiKind();
    var cached_radius_base: ?[]u8 = null;
    if (options.explicit_base_url == null and (configured_model == null or configured_model.?.base_url == null)) {
        cached_radius_base = try cachedRadiusModelBase(gpa, io, options.agent_dir, provider_id, configured_provider, effective_api, model.id);
    }
    defer if (cached_radius_base) |url| gpa.free(url);

    const selected_base: []const u8 = blk: {
        if (options.explicit_base_url) |url| break :blk url;
        if (configured_model) |model_config| if (model_config.base_url) |url| break :blk url;
        if (cached_radius_base) |url| break :blk url;
        if (configured_provider) |provider_config| if (provider_config.base_url) |url| break :blk url;
        if (std.ascii.eqlIgnoreCase(provider_id, "openai")) {
            if (environ.get(config.ENV_OPENAI_BASE)) |url| break :blk url;
        }
        if (model.base_url) |url| break :blk url;
        if (effective_api == .google_vertex) break :blk "https://aiplatform.googleapis.com/v1/publishers/google";
        if (providers.compatBaseUrl(provider_id)) |url| break :blk url;
        break :blk providers.defaultBaseUrl(transport);
    };

    const has_explicit_vertex_base = options.explicit_base_url != null or
        (configured_model != null and configured_model.?.base_url != null) or
        (configured_provider != null and configured_provider.?.base_url != null);
    const cf_base = try materializeCloudflareBaseUrl(gpa, environ, provider_id, effective_api, selected_base);
    defer gpa.free(cf_base);
    const owned_base = try materializeGoogleVertexBaseUrl(gpa, environ, effective_api, cf_base, has_explicit_vertex_base, owned_key);
    errdefer gpa.free(owned_base);
    const headers = try resolveHeaders(gpa, io, environ, model, configured_provider, configured_model, configured_override);
    errdefer {
        for (headers) |header| {
            gpa.free(header.name);
            gpa.free(header.value);
        }
        if (headers.len > 0) gpa.free(headers);
    }
    const sampling_params = try resolveSampling(gpa, model, configured_model, configured_override);
    errdefer {
        for (sampling_params) |param| {
            gpa.free(param.name);
            gpa.free(param.value_json);
        }
        if (sampling_params.len > 0) gpa.free(sampling_params);
    }
    var compat: metadata.Compat = switch (effective_api) {
        .openai_completions => metadata.detectOpenAICompat(provider_id, owned_base, model.id),
        .openai_responses, .openai_codex_responses, .azure_openai_responses => metadata.detectOpenAIResponsesCompat(provider_id, owned_base, model.id),
        .anthropic_messages => metadata.detectAnthropicCompat(provider_id, model.id),
        else => .{},
    };
    // Layer compatibility in increasing specificity: wire detection, generated
    // built-in model metadata, then user/provider/model overrides. This preserves
    // provider-owned dialects while keeping models.json as the final authority.
    compat = metadata.Compat.merge(compat, model.compat);
    if (configured_provider) |cfg| compat = metadata.Compat.merge(compat, cfg.compat);
    if (configured_model) |cfg| compat = metadata.Compat.merge(compat, cfg.compat);
    if (configured_override) |cfg| compat = metadata.Compat.merge(compat, cfg.compat);
    return .{
        .gpa = gpa,
        .provider_id = provider_id,
        .model_id = model.id,
        .transport = transport,
        .api = effective_api,
        .model_cost = model.cost,
        .api_key = owned_key,
        .oauth_refresh = oauth_refresh,
        .oauth_expires_ms = oauth_expires_ms,
        .oauth_enterprise_url = oauth_enterprise_url,
        .base_url = owned_base,
        .headers = headers,
        .sampling_params = sampling_params,
        .compat = compat,
        .reasoning = model.reasoning,
        .input_image = model.input_image,
        .thinking_level_map = model.thinking_level_map,
        .max_tokens = model.max_tokens,
        .context_window = model.context_window,
    };
}

test "generated built-in models retain endpoint headers auth and mixed API transport" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("COPILOT_GITHUB_TOKEN", "copilot-token");

    var responses_model: ?providers.ModelInfo = null;
    var anthropic_model: ?providers.ModelInfo = null;
    for (providers.known_models) |model| {
        if (!std.mem.eql(u8, model.providerName(), "github-copilot")) continue;
        if (std.mem.eql(u8, model.id, "gpt-5.4")) responses_model = model;
        if (std.mem.eql(u8, model.id, "claude-sonnet-4.6")) anthropic_model = model;
    }
    try std.testing.expect(responses_model != null and anthropic_model != null);

    var responses = try resolveForModel(gpa, io, &env, null, responses_model.?, .{});
    defer responses.deinit();
    try std.testing.expect(responses.transport == .openai);
    try std.testing.expect(responses.api == .openai_responses);
    try std.testing.expectEqualStrings("copilot-token", responses.api_key.?);
    try std.testing.expectEqualStrings("https://api.individual.githubcopilot.com", responses.base_url);
    try std.testing.expectEqual(@as(usize, 4), responses.headers.len);
    try std.testing.expectEqual(@as(u64, 128_000), responses.max_tokens);
    try std.testing.expectEqual(@as(usize, 1), responses.model_cost.tiers.len);

    var anthropic = try resolveForModel(gpa, io, &env, null, anthropic_model.?, .{});
    defer anthropic.deinit();
    try std.testing.expect(anthropic.transport == .anthropic);
    try std.testing.expect(anthropic.api == .anthropic_messages);
    try std.testing.expectEqualStrings("copilot-token", anthropic.api_key.?);
}

test "runtime config keeps custom identity and resolves configured env key and model URL" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"corp":{"baseUrl":"https://provider.invalid/v1","api":"openai-completions","apiKey":"$CORP_RUNTIME_KEY","models":[{"id":"m","baseUrl":"https://model.invalid/v1","contextWindow":1000,"maxTokens":100,"cost":{"input":1,"output":2,"cacheRead":0.1,"cacheWrite":0.2}}]}}}
        ,
    });
    var file = try models_file_mod.load(gpa, io, agent_dir);
    defer file.deinit();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("CORP_RUNTIME_KEY", "corp-secret");
    // Must not inherit a built-in key merely because the wire transport is OpenAI.
    try env.put("OPENAI_API_KEY", "wrong-openai-secret");
    const model = file.findModel("corp", "m").?.info;
    var runtime = try resolveForModel(gpa, io, &env, &file, model, .{ .agent_dir = agent_dir });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("corp", runtime.provider_id);
    try std.testing.expect(runtime.transport == .openai);
    try std.testing.expectEqualStrings("corp-secret", runtime.api_key.?);
    try std.testing.expectEqualStrings("https://model.invalid/v1", runtime.base_url);
}

test "runtime config auth json outranks models json and provider URL outranks default" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data =
        \\{"providers":{"corp":{"baseUrl":"https://provider.invalid/v1","api":"openai-completions","apiKey":"configured-secret","models":[{"id":"m","contextWindow":1000,"maxTokens":100,"cost":{"input":1,"output":2,"cacheRead":0.1,"cacheWrite":0.2}}]}}}
        ,
    });
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setApiKey("corp", "auth-secret");
    var file = try models_file_mod.load(gpa, io, agent_dir);
    defer file.deinit();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const model = file.findModel("corp", "m").?.info;
    var runtime = try resolveForModel(gpa, io, &env, &file, model, .{ .agent_dir = agent_dir });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("auth-secret", runtime.api_key.?);
    try std.testing.expectEqualStrings("https://provider.invalid/v1", runtime.base_url);
}

test "runtime config explicit overrides win" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("OPENAI_API_KEY", "env-key");
    const model = providers.ModelInfo{ .provider = .openai, .id = "x", .display = "X" };
    var runtime = try resolveForModel(gpa, std.testing.io, &env, null, model, .{
        .explicit_api_key = "explicit-key",
        .explicit_base_url = "https://explicit.invalid/v1",
    });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("explicit-key", runtime.api_key.?);
    try std.testing.expectEqualStrings("https://explicit.invalid/v1", runtime.base_url);
}

test "runtime config resolves header values and merges sampling and compat" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"corp":{"baseUrl":"https://provider.invalid/v1","api":"openai-completions","apiKey":"secret","headers":{"X-Provider":"$P_HEADER","X-Same":"provider"},"compat":{"supportsUsageInStreaming":true},"models":[{"id":"m","headers":{"X-Model":"literal","X-Same":"model"},"samplingParams":{"temperature":0.2,"top_p":0.9},"compat":{"supportsDeveloperRole":true}}],"modelOverrides":{"m":{"headers":{"X-Override":"$O_HEADER","X-Same":"override"},"samplingParams":{"top_p":0.5},"compat":{"supportsReasoningEffort":false}}}}}}
    });
    var file = try models_file_mod.load(gpa, io, agent_dir);
    defer file.deinit();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("P_HEADER", "provider-value");
    try env.put("O_HEADER", "override-value");
    const model = file.findModel("corp", "m").?.info;
    var runtime = try resolveForModel(gpa, io, &env, &file, model, .{ .agent_dir = agent_dir });
    defer runtime.deinit();
    try std.testing.expectEqual(@as(usize, 4), runtime.headers.len);
    var saw_provider = false;
    var saw_model = false;
    var saw_override = false;
    var same_value: ?[]const u8 = null;
    for (runtime.headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "X-Provider")) saw_provider = std.mem.eql(u8, header.value, "provider-value");
        if (std.ascii.eqlIgnoreCase(header.name, "X-Model")) saw_model = std.mem.eql(u8, header.value, "literal");
        if (std.ascii.eqlIgnoreCase(header.name, "X-Override")) saw_override = std.mem.eql(u8, header.value, "override-value");
        if (std.ascii.eqlIgnoreCase(header.name, "X-Same")) same_value = header.value;
    }
    try std.testing.expect(saw_provider and saw_model and saw_override);
    try std.testing.expectEqualStrings("model", same_value.?);
    try std.testing.expectEqual(@as(usize, 2), runtime.sampling_params.len);
    var top_p: ?[]const u8 = null;
    for (runtime.sampling_params) |param| {
        if (std.mem.eql(u8, param.name, "top_p")) top_p = param.value_json;
    }
    try std.testing.expectEqualStrings("0.5", top_p.?);
    try std.testing.expectEqual(true, runtime.compat.supports_usage_in_streaming.?);
    try std.testing.expectEqual(true, runtime.compat.supports_developer_role.?);
    try std.testing.expectEqual(false, runtime.compat.supports_reasoning_effort.?);
    try std.testing.expectEqual(@as(u64, 16_384), runtime.max_tokens);
}

test "Cloudflare endpoint templates materialize per API protocol" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("CLOUDFLARE_ACCOUNT_ID", "acct");
    try env.put("CLOUDFLARE_GATEWAY_ID", "gate");

    const compat = try materializeCloudflareBaseUrl(gpa, &env, "cloudflare-ai-gateway", .openai_completions, providers.defaultBaseUrl(.cloudflare_ai_gateway));
    defer gpa.free(compat);
    try std.testing.expectEqualStrings("https://gateway.ai.cloudflare.com/v1/acct/gate/compat", compat);
    const responses = try materializeCloudflareBaseUrl(gpa, &env, "cloudflare-ai-gateway", .openai_responses, providers.defaultBaseUrl(.cloudflare_ai_gateway));
    defer gpa.free(responses);
    try std.testing.expectEqualStrings("https://gateway.ai.cloudflare.com/v1/acct/gate/openai", responses);
    const anthropic = try materializeCloudflareBaseUrl(gpa, &env, "cloudflare-ai-gateway", .anthropic_messages, providers.defaultBaseUrl(.cloudflare_ai_gateway));
    defer gpa.free(anthropic);
    try std.testing.expectEqualStrings("https://gateway.ai.cloudflare.com/v1/acct/gate/anthropic", anthropic);
    const workers = try materializeCloudflareBaseUrl(gpa, &env, "cloudflare-workers-ai", .openai_completions, providers.defaultBaseUrl(.cloudflare_workers_ai));
    defer gpa.free(workers);
    try std.testing.expectEqualStrings("https://api.cloudflare.com/client/v4/accounts/acct/ai/v1", workers);
}

test "Cloudflare endpoint templates require scoped account and gateway ids" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try std.testing.expectError(error.MissingCloudflareAccountId, materializeCloudflareBaseUrl(gpa, &env, "cloudflare-workers-ai", .openai_completions, providers.defaultBaseUrl(.cloudflare_workers_ai)));
    try env.put("CLOUDFLARE_ACCOUNT_ID", "acct");
    try std.testing.expectError(error.MissingCloudflareGatewayId, materializeCloudflareBaseUrl(gpa, &env, "cloudflare-ai-gateway", .openai_completions, providers.defaultBaseUrl(.cloudflare_ai_gateway)));
}

test "runtime OpenAI compat layers detected provider model and override values" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"openrouter":{"baseUrl":"https://openrouter.ai/api/v1","api":"openai-completions","apiKey":"key","compat":{"supportsUsageInStreaming":false},"models":[{"id":"anthropic/test","compat":{"supportsDeveloperRole":false}}],"modelOverrides":{"anthropic/test":{"compat":{"supportsReasoningEffort":false}}}}}}
    });
    var file = try models_file_mod.load(gpa, io, agent_dir);
    defer file.deinit();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const model = file.findModel("openrouter", "anthropic/test").?.info;
    var runtime = try resolveForModel(gpa, io, &env, &file, model, .{ .agent_dir = agent_dir });
    defer runtime.deinit();
    try std.testing.expect(runtime.compat.thinking_format.? == .openrouter); // detected survives
    try std.testing.expect(runtime.compat.cache_control_format.? == .anthropic); // detected survives
    try std.testing.expectEqual(false, runtime.compat.supports_usage_in_streaming.?); // provider override
    try std.testing.expectEqual(false, runtime.compat.supports_developer_role.?); // model override
    try std.testing.expectEqual(false, runtime.compat.supports_reasoning_effort.?); // modelOverrides layer
}

test "runtime config retains stored OAuth refresh metadata without affecting env keys" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const agent_dir = path_buf[0..n];
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("radius", .{ .access = @constCast("access-old"), .refresh = @constCast("refresh-old"), .expires = 1234567 });

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const model = providers.ModelInfo{ .provider = .radius, .api = .pi_messages, .id = "auto", .display = "Radius" };
    var runtime = try resolveForModel(gpa, io, &env, null, model, .{ .agent_dir = agent_dir });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("access-old", runtime.api_key.?);
    try std.testing.expectEqualStrings("refresh-old", runtime.oauth_refresh.?);
    try std.testing.expectEqual(@as(?i64, 1234567), runtime.oauth_expires_ms);

    try env.put("RADIUS_API_KEY", "env-key");
    var env_runtime = try resolveForModel(gpa, io, &env, null, model, .{ .agent_dir = agent_dir });
    defer env_runtime.deinit();
    try std.testing.expectEqualStrings("env-key", env_runtime.api_key.?);
    try std.testing.expect(env_runtime.oauth_refresh == null);
    try std.testing.expect(env_runtime.oauth_expires_ms == null);
}

test "Radius runtime uses cached model API base instead of OAuth gateway root" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const models_path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(models_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = models_path, .data = "{\"providers\":{\"radius-dev\":{\"baseUrl\":\"http://gateway:8788\",\"oauth\":\"radius\"}}}" });
    const store_path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(store_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = store_path, .data = "{\"radius-dev\":{\"models\":[{\"id\":\"auto\",\"name\":\"Auto\",\"api\":\"pi-messages\",\"provider\":\"radius-dev\",\"baseUrl\":\"http://gateway:8788/v1\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":1000,\"maxTokens\":100}]}}" });
    var file = try models_file_mod.load(gpa, io, root);
    defer file.deinit();
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const model = providers.ModelInfo{ .provider = .radius, .provider_id = "radius-dev", .api = .pi_messages, .id = "auto", .display = "Auto" };
    var runtime = try resolveForModel(gpa, io, &env, &file, model, .{ .agent_dir = root });
    defer runtime.deinit();
    try std.testing.expectEqualStrings("http://gateway:8788/v1", runtime.base_url);
}
