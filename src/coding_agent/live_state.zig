//! Mutable live REPL state so slash commands affect subsequent agent turns.
const std = @import("std");
const Io = std.Io;
const app_config = @import("../config.zig");
const agent_loop = @import("../agent/loop.zig");
const context_mod = @import("context.zig");
const skills_mod = @import("skills.zig");
const packages_mod = @import("packages.zig");
const top_level_resources_mod = @import("top_level_resources.zig");
const system_prompt = @import("system_prompt.zig");
const model_resolver = @import("model_resolver.zig");
const ai = @import("../ai/root.zig");
const providers = @import("../ai/providers.zig");
const metadata = @import("../ai/request_metadata.zig");
const thinking_mod = @import("../ai/thinking.zig");
const codex_ws = @import("../ai/codex_websocket.zig");
const retry_mod = @import("../ai/retry.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const cloudflare = @import("../ai/cloudflare.zig");
const aws_credentials = @import("../ai/aws_credentials.zig");
const aws_web_identity = @import("../ai/aws_web_identity.zig");
const aws_process = @import("../ai/aws_process.zig");
const aws_container = @import("../ai/aws_container.zig");
const aws_imds = @import("../ai/aws_imds.zig");
const aws_assume_role = @import("../ai/aws_assume_role.zig");
const google_adc = @import("../ai/google_adc.zig");
const radius_oauth = @import("../auth/radius_oauth.zig");
const codex_oauth = @import("../auth/openai_codex_oauth.zig");
const copilot_oauth = @import("../auth/github_copilot_oauth.zig");
const anthropic_oauth = @import("../auth/anthropic_oauth.zig");
const kimi_oauth = @import("../auth/kimi_coding_oauth.zig");
const openrouter_oauth = @import("../auth/openrouter_oauth.zig");
const xai_oauth = @import("../auth/xai_oauth.zig");
const radius_config = @import("../ai/radius_config.zig");
const auth_storage = @import("../auth/storage.zig");
const models_file_mod = @import("models_file.zig");
const radius_cached_catalogs = @import("radius_cached_catalogs.zig");
const effective_catalog = @import("effective_catalog.zig");
const copilot_catalog_filter = @import("copilot_catalog_filter.zig");
const runtime_config = @import("runtime_config.zig");

/// Live knobs shared by the interactive loop and slash handlers.
pub const RuntimeReloadResult = struct {
    extensions: usize = 0,
    commands: usize = 0,
    prompts: usize = 0,
    themes: usize = 0,
    keybindings_reloaded: bool = false,
    settings_reloaded: bool = false,
    models_reloaded: bool = false,
    credentials_reloaded: bool = false,
};

pub const RuntimeReloadFn = *const fn (?*anyopaque) anyerror!RuntimeReloadResult;

pub const LiveState = struct {
    gpa: std.mem.Allocator,
    io: Io,
    cwd: []const u8,
    agent_dir: ?[]const u8,
    trust_project: bool = true,
    thinking: ?[]const u8 = null,

    /// Agent loop config used on every turn (updated in place).
    agent_cfg: *agent_loop.AgentConfig,
    /// Heap-owned system/context strings currently referenced by agent_cfg.
    owned_system: *?[]u8,
    owned_context: *?[]u8,
    /// Thinking-independent system prompt assembled from every active source.
    /// Optional for embedders/tests that do not need live prompt reassembly.
    owned_system_base: ?*?[]u8 = null,
    /// Heap-owned copy used when an RPC/slash thinking value outlives its input buffer.
    owned_thinking: ?*?[]u8 = null,
    /// Last skills summary (owned) so set_thinking_level can reassemble without dropping skills.
    owned_skills_summary: *?[]u8,

    /// Immutable command-line prompt inputs retained across `/reload`.
    cli_system_override: ?[]const u8 = null,
    cli_system_appends: []const []const u8 = &.{},
    include_context_files: bool = true,
    include_skills: bool = true,
    selected_skill_names: []const []const u8 = &.{},

    /// Display copy of model id (may be env-backed or heap-owned).
    model_display: *?[]const u8,
    /// Points at the live ModelClient storage `.model` field so /model takes effect immediately.
    active_model: ?*[]const u8 = null,

    /// Set true when /model allocated model_display (so we free on replace).
    model_display_owned: *bool,

    /// Optional live client pool for provider switches (RPC /model).
    client_pool: ?*ClientPool = null,
    provider_name: ?*?[]const u8 = null,

    /// Runtime model registry, including models.json providers. Empty falls back to built-ins.
    model_catalog: []const providers.ModelInfo = &.{},
    /// Ordered `--models` scope, retaining optional per-model thinking levels.
    model_scope: []const model_resolver.ScopedModel = &.{},
    owned_model_scope: ?[]model_resolver.ScopedModel = null,
    /// Provider IDs that currently have usable credentials/runtime access.
    configured_providers: []const []const u8 = &.{},
    /// Owned replacement catalog/runtime snapshot installed by an interactive
    /// Radius refresh. Null means the immutable startup catalog is still active.
    dynamic_catalog_snapshot: ?DynamicCatalogSnapshot = null,

    /// Optional application-owned resource reload callback. The core reload path
    /// rebuilds context and skills itself; the executable installs this callback
    /// to transactionally replace extension workers, prompt templates, themes,
    /// extension providers, command metadata, and tool schemas.
    runtime_reload_ctx: ?*anyopaque = null,
    runtime_reload_fn: ?RuntimeReloadFn = null,

    pub fn deinitDynamicCatalog(self: *LiveState) void {
        if (self.dynamic_catalog_snapshot) |*snapshot| snapshot.deinit();
        self.dynamic_catalog_snapshot = null;
        if (self.owned_model_scope) |scope| self.gpa.free(scope);
        self.owned_model_scope = null;
    }
};

pub const RuntimeProviderConfig = struct {
    /// Public provider identity from models.json (arbitrary string).
    id: []const u8,
    /// Optional model-specific runtime. Null is a provider-wide fallback.
    model_id: ?[]const u8 = null,
    /// Native transport implementation selected by the provider/model API.
    transport: providers.Provider,
    api: @import("../ai/api.zig").Api = .openai_completions,
    model_cost: providers.ModelCost = .{},
    api_key: ?[]const u8 = null,
    oauth_refresh: ?[]const u8 = null,
    oauth_expires_ms: ?i64 = null,
    oauth_enterprise_url: ?[]const u8 = null,
    base_url: ?[]const u8 = null,
    headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    reasoning: bool = false,
    input_image: bool = false,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    max_tokens: u64 = 0,
    context_window: u64 = 0,
};

pub const DynamicCatalogSnapshot = struct {
    gpa: std.mem.Allocator,
    models_file: models_file_mod.ModelsFile,
    radius_catalogs: radius_cached_catalogs.Set,
    copilot_catalog: copilot_catalog_filter.Set,
    /// Alias of copilot_catalog.infos published through LiveState.
    model_catalog: []providers.ModelInfo,
    dynamic_runtimes: []runtime_config.ResolvedRuntime,
    runtime_configs: []RuntimeProviderConfig,

    pub fn deinit(self: *DynamicCatalogSnapshot) void {
        if (self.runtime_configs.len > 0) self.gpa.free(self.runtime_configs);
        for (self.dynamic_runtimes) |*runtime| runtime.deinit();
        if (self.dynamic_runtimes.len > 0) self.gpa.free(self.dynamic_runtimes);
        self.copilot_catalog.deinit();
        self.radius_catalogs.deinit(self.gpa);
        self.models_file.deinit();
        self.* = undefined;
    }
};

pub const CatalogReloadOptions = struct {
    /// Preserve a command-line credential override for the public provider it
    /// was explicitly assigned to. Never leak it into another provider merely
    /// because both happen to use the same native transport.
    explicit_provider: ?[]const u8 = null,
    explicit_api_key: ?[]const u8 = null,
    /// Auth-only refreshes preserve caller-owned extension runtime entries.
    /// A complete runtime reconstruction disables this so providers removed
    /// from models.json cannot be mistaken for unmanaged extension providers.
    preserve_unmanaged_runtimes: bool = true,
};

/// Rebuild the effective catalog from local disk, including every models.json
/// provider plus account-scoped Radius/pi-messages/Copilot models. Existing
/// runtime configs not owned by either of those on-disk/dynamic sources are
/// retained shallowly; this preserves live extension registrations during an
/// auth-only refresh while ensuring removed or edited models.json providers do
/// not survive as stale runtime entries.
pub fn loadDynamicAuthCatalogWithOptions(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    old_runtime_configs: []const RuntimeProviderConfig,
    options: CatalogReloadOptions,
) !DynamicCatalogSnapshot {
    var models_file = try models_file_mod.load(gpa, io, agent_dir);
    errdefer models_file.deinit();
    var cached = try radius_cached_catalogs.load(gpa, io, agent_dir, &models_file);
    errdefer cached.deinit(gpa);
    const unfiltered_catalog = try effective_catalog.buildWithExtras(gpa, &models_file, cached.infos);
    defer gpa.free(unfiltered_catalog);
    var copilot_catalog = try copilot_catalog_filter.load(gpa, io, agent_dir, unfiltered_catalog);
    errdefer copilot_catalog.deinit();
    const catalog = copilot_catalog.infos;

    var runtimes: std.ArrayList(runtime_config.ResolvedRuntime) = .empty;
    errdefer {
        for (runtimes.items) |*runtime| runtime.deinit();
        runtimes.deinit(gpa);
    }
    var configs: std.ArrayList(RuntimeProviderConfig) = .empty;
    errdefer configs.deinit(gpa);

    if (options.preserve_unmanaged_runtimes) for (old_runtime_configs) |config| {
        const configured_on_disk = models_file.findProvider(config.id) != null;
        if (configured_on_disk or config.transport == .radius or config.api == .pi_messages or std.ascii.eqlIgnoreCase(config.id, "github-copilot")) continue;
        try configs.append(gpa, config);
    };
    for (catalog) |model| {
        const configured_on_disk = models_file.findProvider(model.providerName()) != null;
        const dynamic_auth_model = model.provider == .radius or model.apiKind() == .pi_messages or std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot");
        if (!configured_on_disk and !dynamic_auth_model) continue;
        const explicit_key = if (options.explicit_provider != null and options.explicit_api_key != null and
            std.ascii.eqlIgnoreCase(options.explicit_provider.?, model.providerName()))
            options.explicit_api_key
        else
            null;
        var resolved = try runtime_config.resolveForModel(gpa, io, environ, &models_file, model, .{
            .agent_dir = agent_dir,
            .explicit_api_key = explicit_key,
        });
        errdefer resolved.deinit();
        try runtimes.append(gpa, resolved);
        const stored = &runtimes.items[runtimes.items.len - 1];
        try configs.append(gpa, .{
            .id = model.providerName(),
            .model_id = model.id,
            .transport = stored.transport,
            .api = stored.api,
            .model_cost = stored.model_cost,
            .api_key = stored.api_key,
            .oauth_refresh = stored.oauth_refresh,
            .oauth_expires_ms = stored.oauth_expires_ms,
            .oauth_enterprise_url = stored.oauth_enterprise_url,
            .base_url = stored.base_url,
            .headers = stored.headers,
            .sampling_params = stored.sampling_params,
            .compat = stored.compat,
            .reasoning = stored.reasoning,
            .input_image = stored.input_image,
            .thinking_level_map = stored.thinking_level_map,
            .max_tokens = stored.max_tokens,
            .context_window = stored.context_window,
        });
    }
    return .{
        .gpa = gpa,
        .models_file = models_file,
        .radius_catalogs = cached,
        .copilot_catalog = copilot_catalog,
        .model_catalog = catalog,
        .dynamic_runtimes = try runtimes.toOwnedSlice(gpa),
        .runtime_configs = try configs.toOwnedSlice(gpa),
    };
}

pub fn loadDynamicAuthCatalog(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: []const u8,
    old_runtime_configs: []const RuntimeProviderConfig,
) !DynamicCatalogSnapshot {
    return loadDynamicAuthCatalogWithOptions(gpa, io, environ, agent_dir, old_runtime_configs, .{});
}

pub const OpenRouterPendingFlow = struct {
    verifier: []u8,
    url: []u8,
    pub fn deinit(self: *OpenRouterPendingFlow, gpa: std.mem.Allocator) void {
        gpa.free(self.verifier);
        gpa.free(self.url);
        self.* = undefined;
    }
};

/// Holds concrete provider clients and a mutable ModelClient used by agent runs.
pub const LiveCredentialSnapshot = struct {
    gpa: std.mem.Allocator,
    provider_id: ?[]u8 = null,
    credential: ?auth_storage.Credential = null,

    pub fn deinit(self: *LiveCredentialSnapshot) void {
        if (self.credential) |*credential| credential.deinit(self.gpa);
        if (self.provider_id) |provider_id| self.gpa.free(provider_id);
        self.* = undefined;
    }
};

/// Provider-agnostic OAuth material resolved by the extension layer. The key
/// is owned by the caller and may be derived from arbitrary credential fields.
pub const ExtensionOAuthResolution = struct {
    api_key: []u8,
    expires_ms: i64,

    pub fn deinit(self: *ExtensionOAuthResolution, gpa: std.mem.Allocator) void {
        gpa.free(self.api_key);
        self.* = undefined;
    }
};

/// Cycle-free callback surface implemented by `extensions/provider_oauth.zig`.
/// Keeping this interface in live_state lets ClientPool resolve extension OAuth
/// without importing the provider registry back into its own dependency graph.
pub const ExtensionOAuthBridge = struct {
    context: ?*anyopaque = null,
    supports_fn: *const fn (?*anyopaque, []const u8) bool,
    resolve_fn: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        []const u8,
        i64,
        ?*bool,
        bool,
    ) anyerror!?ExtensionOAuthResolution,
};

/// Complete request metadata passed to an extension-owned stream backend. All
/// slices are borrowed from the active ClientPool for the duration of one call.
pub const ExtensionStreamRequest = struct {
    provider_id: []const u8,
    model_id: []const u8,
    api: []const u8,
    api_key: ?[]const u8 = null,
    base_url: []const u8,
    headers: []const metadata.Header = &.{},
    sampling_params: []const metadata.SamplingParam = &.{},
    compat: metadata.Compat = .{},
    reasoning: bool = false,
    input_image: bool = false,
    thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    thinking: ai.ThinkingLevel = .off,
    max_tokens: u64 = 0,
    context_window: u64 = 0,
    model_cost: providers.ModelCost = .{},
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
};

/// Cycle-free callback surface implemented by `extensions/provider_stream.zig`.
/// ClientPool owns request selection while the extension runtime owns JSON/event
/// adaptation and callback-worker routing.
pub const ExtensionStreamBridge = struct {
    context: ?*anyopaque = null,
    supports_fn: *const fn (?*anyopaque, []const u8) bool,
    supports_fetch_deferred_fn: *const fn (?*anyopaque, []const u8) bool,
    supports_cancel_deferred_fn: *const fn (?*anyopaque, []const u8) bool,
    complete_fn: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        ExtensionStreamRequest,
        []const ai.ChatMessage,
        []const u8,
        ?ai.StreamHandler,
        ?*anyopaque,
        ?*bool,
    ) anyerror!ai.ModelResponse,
    fetch_deferred_fn: *const fn (
        ?*anyopaque,
        std.mem.Allocator,
        ExtensionStreamRequest,
        []const u8,
        []const u8,
        ?ai.StreamHandler,
        ?*anyopaque,
        ?*bool,
    ) anyerror!ai.ModelResponse,
    cancel_deferred_fn: *const fn (
        ?*anyopaque,
        ExtensionStreamRequest,
        []const u8,
        []const u8,
        ?*bool,
    ) anyerror!void,
};

pub const ClientPool = struct {
    gpa: std.mem.Allocator,
    io: Io,
    openai: ?@import("../ai/openai.zig").OpenAIClient = null,
    responses: ?@import("../ai/openai_responses.zig").ResponsesClient = null,
    anthropic: ?@import("../ai/anthropic.zig").AnthropicClient = null,
    google: ?@import("../ai/google.zig").GoogleClient = null,
    google_adc_credential: ?google_adc.Credential = null,
    google_access_token: ?google_adc.AccessToken = null,
    mistral: ?@import("../ai/mistral.zig").MistralClient = null,
    bedrock: ?@import("../ai/bedrock.zig").BedrockClient = null,
    /// Owned AWS shared-profile material backing Bedrock credential slices.
    aws_profile: ?aws_credentials.OwnedProfile = null,
    aws_source_profile: ?aws_credentials.OwnedProfile = null,
    /// Owned temporary credentials returned by refreshable AWS providers.
    aws_temporary_credentials: ?aws_web_identity.OwnedTemporaryCredentials = null,
    aws_process_credentials: ?aws_process.OwnedProcessCredentials = null,
    aws_container_credentials: ?aws_container.OwnedContainerCredentials = null,
    aws_imds_credentials: ?aws_imds.OwnedImdsCredentials = null,
    aws_assumed_credentials: ?aws_assume_role.OwnedAssumedCredentials = null,
    pi_messages: ?@import("../ai/pi_messages.zig").PiMessagesClient = null,
    /// OpenAI Codex OAuth refresh material, owned by the pool.
    codex_initial_refresh: ?[]u8 = null,
    codex_oauth_token: ?codex_oauth.Token = null,
    /// Pending browser/manual PKCE flow retained across REPL commands when the
    /// loopback callback cannot be used.
    codex_pending_flow: ?codex_oauth.AuthorizationFlow = null,
    /// Pending Anthropic browser/manual flow retained when the loopback port is unavailable.
    anthropic_pending_flow: ?anthropic_oauth.AuthorizationFlow = null,
    /// Pending OpenRouter manual PKCE flow. OpenRouter's callback URL contains
    /// an ephemeral port, but its key exchange itself only needs the verifier.
    openrouter_pending_flow: ?OpenRouterPendingFlow = null,
    /// GitHub Copilot OAuth state. The long-lived GitHub token stays separate
    /// from the short-lived Copilot API token used by provider clients.
    copilot_initial_refresh: ?[]u8 = null,
    copilot_enterprise_domain: ?[]u8 = null,
    copilot_oauth_credential: ?copilot_oauth.CopilotCredential = null,
    copilot_base_url: ?[]u8 = null,
    /// Radius OAuth state. Initial refresh material is owned separately; after
    /// the first refresh `radius_oauth_token` becomes the source of truth.
    radius_initial_refresh: ?[]u8 = null,
    radius_oauth_token: ?radius_oauth.Token = null,
    radius_gateway: ?[]u8 = null,
    /// Credential installed by an interactive login during this process. It
    /// outranks the startup snapshot so `/login` is immediately usable.
    live_credential_provider: ?[]u8 = null,
    live_credential: ?auth_storage.Credential = null,
    auth_agent_dir: ?[]const u8 = null,
    primary_oauth_refresh: ?[]const u8 = null,
    primary_oauth_expires_ms: ?i64 = null,
    primary_oauth_enterprise_url: ?[]const u8 = null,
    /// Cached API keys (not owned if from env; owned if from credentials dupe).
    openai_key: ?[]const u8 = null,
    anthropic_key: ?[]const u8 = null,
    google_key: ?[]const u8 = null,
    /// Reload-installed key copies. Startup callers may continue to provide
    /// arena/environment-backed slices through setKeys(); hot reload uses the
    /// owned setter so changed auth.json data outlives the reload transaction.
    owned_openai_key: ?[]u8 = null,
    owned_anthropic_key: ?[]u8 = null,
    owned_google_key: ?[]u8 = null,
    openai_base: []const u8 = "https://api.openai.com/v1",
    /// Process environment used to resolve credentials when switching named providers.
    environ: ?*const std.process.Environ.Map = null,
    /// Global settings.json `httpProxy` fallback for every provider client.
    http_proxy_url: ?[]const u8 = null,
    owned_http_proxy_url: ?[]u8 = null,
    /// Initial provider request config, including credentials.json fallback and --base-url.
    primary_provider: providers.Provider = .openai,
    primary_provider_id: []const u8 = "openai",
    primary_key: ?[]const u8 = null,
    primary_base_url: ?[]const u8 = null,
    primary_headers: []const metadata.Header = &.{},
    primary_sampling_params: []const metadata.SamplingParam = &.{},
    primary_compat: metadata.Compat = .{},
    primary_reasoning: bool = false,
    primary_input_image: bool = false,
    primary_thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
    primary_max_tokens: u64 = 0,
    primary_context_window: u64 = 0,
    primary_model_cost: providers.ModelCost = .{},
    primary_api: @import("../ai/api.zig").Api = .openai_completions,
    /// Live client handle (updated on switch).
    client: @import("../ai/root.zig").ModelClient = undefined,
    active_provider: providers.Provider = .openai,
    active_provider_id: []const u8 = "openai",
    active_api: @import("../ai/api.zig").Api = .openai_completions,
    /// Resolved models.json runtime endpoints/credentials. Borrowed for process lifetime.
    runtime_providers: []const RuntimeProviderConfig = &.{},
    /// Effective static plus models.json catalog used for native hot switching.
    model_catalog: []const providers.ModelInfo = &providers.known_models,
    /// Extension-defined OAuth resolver and currently derived request key.
    extension_oauth_bridge: ?ExtensionOAuthBridge = null,
    extension_oauth_provider: ?[]u8 = null,
    extension_oauth_key: ?[]u8 = null,
    extension_oauth_expires_ms: ?i64 = null,
    /// Extension-defined streamSimple backend. The model slice aliases
    /// `model_owned` and exists only to satisfy LiveState's mutable model pointer.
    extension_stream_bridge: ?ExtensionStreamBridge = null,
    extension_stream_active: bool = false,
    extension_stream_model: []const u8 = "",
    /// Owned public provider and model IDs used by the active storage. Provider
    /// ownership prevents credential-dependent model projection from invalidating
    /// client identity slices while switchToIdentity is still executing.
    provider_owned: ?[]u8 = null,
    model_owned: ?[]u8 = null,
    /// Provider API thinking budgets (wired into OpenAI/Anthropic request bodies).
    thinking: @import("../ai/root.zig").ThinkingLevel = .off,
    /// Shared cooperative abort flag for mid-HTTP SSE cancel + bash kill.
    abort_flag: ?*bool = null,
    /// Stable Pi session identity used for prompt-cache affinity across provider calls.
    session_id: ?[]const u8 = null,
    cache_retention: metadata.CacheRetention = .short,
    /// Preferred Codex Responses streaming transport.
    codex_transport: codex_ws.Transport = .auto,
    /// HTTP response header/body idle timeout for Codex SSE; zero disables it.
    codex_http_idle_timeout_ms: u64 = @import("../ai/openai_responses.zig").DEFAULT_HTTP_IDLE_TIMEOUT_MS,
    /// Codex WebSocket connection deadline; zero disables it.
    codex_websocket_connect_timeout_ms: u64 = @import("../ai/openai_responses.zig").DEFAULT_WEBSOCKET_CONNECT_TIMEOUT_MS,
    /// Provider-internal request retry settings shared by every concrete client.
    provider_retry_policy: retry_mod.ProviderPolicy = .{ .max_retries = 2 },
    /// Session-scoped sticky fallback after a pre-stream WebSocket transport failure.
    codex_ws_fallback_active: bool = false,

    pub fn deinit(self: *ClientPool) void {
        if (self.responses) |*client| client.deinit();
        if (self.provider_owned) |provider_id| self.gpa.free(provider_id);
        if (self.model_owned) |m| self.gpa.free(m);
        self.clearExtensionOAuthState();
        if (self.google_adc_credential) |*credential| credential.deinit(self.gpa);
        if (self.google_access_token) |*token| token.deinit(self.gpa);
        if (self.aws_profile) |*profile| profile.deinit(self.gpa);
        if (self.aws_source_profile) |*profile| profile.deinit(self.gpa);
        if (self.aws_temporary_credentials) |*credentials| credentials.deinit(self.gpa);
        if (self.aws_process_credentials) |*credentials| credentials.deinit(self.gpa);
        if (self.aws_container_credentials) |*credentials| credentials.deinit(self.gpa);
        if (self.aws_imds_credentials) |*credentials| credentials.deinit(self.gpa);
        if (self.aws_assumed_credentials) |*credentials| credentials.deinit(self.gpa);
        self.clearCodexOAuthState();
        self.clearCodexPendingFlow();
        self.clearAnthropicPendingFlow();
        self.clearOpenRouterPendingFlow();
        self.clearCopilotOAuthState();
        if (self.radius_initial_refresh) |refresh| self.gpa.free(refresh);
        if (self.radius_oauth_token) |*token| token.deinit(self.gpa);
        if (self.radius_gateway) |gateway| self.gpa.free(gateway);
        if (self.live_credential) |*credential| credential.deinit(self.gpa);
        if (self.live_credential_provider) |provider_id| self.gpa.free(provider_id);
        if (self.owned_openai_key) |value| self.gpa.free(value);
        if (self.owned_anthropic_key) |value| self.gpa.free(value);
        if (self.owned_google_key) |value| self.gpa.free(value);
        if (self.owned_http_proxy_url) |value| self.gpa.free(value);
        self.* = undefined;
    }

    pub fn setKeys(self: *ClientPool, openai_key: ?[]const u8, anthropic_key: ?[]const u8, google_key: ?[]const u8, openai_base: []const u8) void {
        if (self.owned_openai_key) |value| self.gpa.free(value);
        if (self.owned_anthropic_key) |value| self.gpa.free(value);
        if (self.owned_google_key) |value| self.gpa.free(value);
        self.owned_openai_key = null;
        self.owned_anthropic_key = null;
        self.owned_google_key = null;
        self.openai_key = openai_key;
        self.anthropic_key = anthropic_key;
        self.google_key = google_key;
        self.openai_base = openai_base;
    }

    /// Atomically replace reloadable built-in credentials with pool-owned
    /// copies. Allocation failure leaves the currently published credentials
    /// untouched, which lets the outer reload transaction roll back safely.
    pub fn setKeysOwned(self: *ClientPool, openai_key: ?[]const u8, anthropic_key: ?[]const u8, google_key: ?[]const u8) !void {
        const next_openai = if (openai_key) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (next_openai) |value| self.gpa.free(value);
        const next_anthropic = if (anthropic_key) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (next_anthropic) |value| self.gpa.free(value);
        const next_google = if (google_key) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (next_google) |value| self.gpa.free(value);

        if (self.owned_openai_key) |value| self.gpa.free(value);
        if (self.owned_anthropic_key) |value| self.gpa.free(value);
        if (self.owned_google_key) |value| self.gpa.free(value);
        self.owned_openai_key = next_openai;
        self.owned_anthropic_key = next_anthropic;
        self.owned_google_key = next_google;
        self.openai_key = if (self.owned_openai_key) |value| value else null;
        self.anthropic_key = if (self.owned_anthropic_key) |value| value else null;
        self.google_key = if (self.owned_google_key) |value| value else null;
    }

    pub fn setRuntimeConfig(
        self: *ClientPool,
        environ: *const std.process.Environ.Map,
        primary_provider: providers.Provider,
        primary_provider_id: []const u8,
        primary_key: ?[]const u8,
        primary_base_url: []const u8,
    ) void {
        self.environ = environ;
        self.primary_provider = primary_provider;
        self.primary_provider_id = primary_provider_id;
        self.primary_key = primary_key;
        self.primary_base_url = primary_base_url;
    }

    pub fn setAuthAgentDir(self: *ClientPool, agent_dir: ?[]const u8) void {
        self.auth_agent_dir = agent_dir;
    }

    pub fn setHttpProxy(self: *ClientPool, proxy_url: ?[]const u8) void {
        if (self.owned_http_proxy_url) |value| self.gpa.free(value);
        self.owned_http_proxy_url = null;
        self.http_proxy_url = proxy_url;
    }

    /// Atomically publish an owned proxy URL suitable for hot-reloaded
    /// settings. Existing clients are rebuilt by the caller after this update.
    pub fn setHttpProxyOwned(self: *ClientPool, proxy_url: ?[]const u8) !void {
        const next = if (proxy_url) |value| try self.gpa.dupe(u8, value) else null;
        if (self.owned_http_proxy_url) |value| self.gpa.free(value);
        self.owned_http_proxy_url = next;
        self.http_proxy_url = if (self.owned_http_proxy_url) |value| value else null;
    }

    fn clearLiveCredential(self: *ClientPool) void {
        if (self.live_credential) |*credential| credential.deinit(self.gpa);
        self.live_credential = null;
        if (self.live_credential_provider) |provider_id| self.gpa.free(provider_id);
        self.live_credential_provider = null;
    }

    /// Publish an API key entered during an interactive login immediately.
    /// The value is owned by the client pool and takes precedence over startup
    /// environment/config snapshots for the selected public provider identity.
    pub fn installApiKeyCredential(self: *ClientPool, provider_id: []const u8, key: []const u8) !void {
        self.clearLiveCredential();
        errdefer self.clearLiveCredential();
        self.live_credential_provider = try self.gpa.dupe(u8, provider_id);
        self.live_credential = .{ .api_key = .{ .key = try self.gpa.dupe(u8, key) } };
    }

    /// Remove a process-local interactive credential only when it belongs to
    /// the requested provider. Persisted credentials are removed separately by
    /// the authoritative auth storage transaction.
    pub fn removeLiveCredential(self: *ClientPool, provider_id: []const u8) bool {
        const stored_provider = self.live_credential_provider orelse return false;
        if (!std.ascii.eqlIgnoreCase(stored_provider, provider_id)) return false;
        self.clearLiveCredential();
        return true;
    }

    /// Capture a deep, allocator-owned copy of the process-local interactive
    /// credential. Runtime reload uses this as rollback state while making the
    /// fresh auth.json/models.json snapshot authoritative for the replacement.
    pub fn snapshotLiveCredential(self: *const ClientPool) !LiveCredentialSnapshot {
        var snapshot = LiveCredentialSnapshot{ .gpa = self.gpa };
        errdefer snapshot.deinit();
        if (self.live_credential_provider) |provider_id| {
            snapshot.provider_id = try self.gpa.dupe(u8, provider_id);
        }
        if (self.live_credential) |*credential| {
            snapshot.credential = try credential.clone(self.gpa);
        }
        return snapshot;
    }

    /// Clear process-local precedence while a replacement provider snapshot is
    /// being built. Persisted auth.json and models.json values then determine
    /// the new client credential instead of stale interactive state.
    pub fn clearLiveCredentialForReload(self: *ClientPool) void {
        self.clearLiveCredential();
    }

    /// Restore a captured credential by ownership transfer. The snapshot is
    /// emptied so its later deinit is safe and does not erase the restored key.
    pub fn restoreLiveCredentialSnapshot(self: *ClientPool, snapshot: *LiveCredentialSnapshot) void {
        self.clearLiveCredential();
        self.live_credential_provider = snapshot.provider_id;
        self.live_credential = snapshot.credential;
        snapshot.provider_id = null;
        snapshot.credential = null;
    }

    fn installOAuthValue(
        self: *ClientPool,
        provider_id: []const u8,
        refresh_value: []const u8,
        access_value: []const u8,
        expires_ms: i64,
        scope_value: ?[]const u8,
        account_id_value: ?[]const u8,
        enterprise_url_value: ?[]const u8,
        available_model_ids_value: []const []const u8,
    ) !void {
        self.clearLiveCredential();
        errdefer self.clearLiveCredential();
        self.live_credential_provider = try self.gpa.dupe(u8, provider_id);
        const refresh = try self.gpa.dupe(u8, refresh_value);
        errdefer self.gpa.free(refresh);
        const access = try self.gpa.dupe(u8, access_value);
        errdefer self.gpa.free(access);
        const scope = if (scope_value) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (scope) |value| self.gpa.free(value);
        const account_id = if (account_id_value) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (account_id) |value| self.gpa.free(value);
        const enterprise_url = if (enterprise_url_value) |value| try self.gpa.dupe(u8, value) else null;
        errdefer if (enterprise_url) |value| self.gpa.free(value);
        var available_model_ids: [][]u8 = &.{};
        if (available_model_ids_value.len > 0) {
            available_model_ids = try self.gpa.alloc([]u8, available_model_ids_value.len);
            var copied: usize = 0;
            errdefer {
                for (available_model_ids[0..copied]) |id| self.gpa.free(id);
                self.gpa.free(available_model_ids);
            }
            for (available_model_ids_value, 0..) |id, i| {
                available_model_ids[i] = try self.gpa.dupe(u8, id);
                copied += 1;
            }
        }
        self.live_credential = .{ .oauth = .{
            .refresh = refresh,
            .access = access,
            .expires = expires_ms,
            .scope = scope,
            .account_id = account_id,
            .enterprise_url = enterprise_url,
            .available_model_ids = available_model_ids,
            .available_model_ids_present = available_model_ids_value.len > 0 or std.ascii.eqlIgnoreCase(provider_id, "github-copilot"),
        } };
    }

    pub fn installOAuthCredential(self: *ClientPool, provider_id: []const u8, token: *const radius_oauth.Token) !void {
        try self.installOAuthValue(provider_id, token.refresh, token.access, token.expires_ms, token.scope, null, null, &.{});
    }

    pub fn installCodexOAuthCredential(self: *ClientPool, token: *const codex_oauth.Token) !void {
        try self.installOAuthValue("openai-codex", token.refresh, token.access, token.expires_ms, null, token.account_id, null, &.{});
        self.clearCodexPendingFlow();
    }

    pub fn installGitHubCopilotOAuthCredential(self: *ClientPool, token: *const copilot_oauth.CopilotCredential) !void {
        const ids: []const []const u8 = token.available_model_ids;
        try self.installOAuthValue("github-copilot", token.refresh, token.access, token.expires_ms, null, null, token.enterprise_domain, ids);
        self.clearCopilotOAuthState();
    }

    pub fn installAnthropicOAuthCredential(self: *ClientPool, token: *const anthropic_oauth.Token) !void {
        try self.installOAuthValue("anthropic", token.refresh, token.access, token.expires_ms, null, null, null, &.{});
        self.clearAnthropicPendingFlow();
    }

    pub fn installKimiOAuthCredential(self: *ClientPool, token: *const kimi_oauth.Token) !void {
        try self.installOAuthValue("kimi-coding", token.refresh, token.access, token.expires_ms, null, null, null, &.{});
    }

    /// OpenRouter OAuth mints a permanent user API key, so it is installed as
    /// OAuth for persistence/identity but intentionally has no refresh hook.
    pub fn installOpenRouterOAuthCredential(self: *ClientPool, token: *const openrouter_oauth.Token) !void {
        try self.installOAuthValue("openrouter", "", token.access, token.expires_ms, null, null, null, &.{});
        self.clearOpenRouterPendingFlow();
    }

    pub fn installXaiOAuthCredential(self: *ClientPool, token: *const xai_oauth.Token) !void {
        try self.installOAuthValue("xai", token.refresh, token.access, token.expires_ms, null, null, null, &.{});
    }

    fn clearAnthropicPendingFlow(self: *ClientPool) void {
        if (self.anthropic_pending_flow) |*flow| flow.deinit(self.gpa);
        self.anthropic_pending_flow = null;
    }

    fn clearOpenRouterPendingFlow(self: *ClientPool) void {
        if (self.openrouter_pending_flow) |*flow| flow.deinit(self.gpa);
        self.openrouter_pending_flow = null;
    }

    pub fn installOpenRouterPendingFlow(self: *ClientPool, verifier: []const u8, url: []const u8) !void {
        self.clearOpenRouterPendingFlow();
        errdefer self.clearOpenRouterPendingFlow();
        self.openrouter_pending_flow = .{
            .verifier = try self.gpa.dupe(u8, verifier),
            .url = try self.gpa.dupe(u8, url),
        };
    }

    pub fn completeOpenRouterPendingFlow(self: *ClientPool, input: []const u8) !openrouter_oauth.ExchangeOutcome {
        const flow = if (self.openrouter_pending_flow) |*value| value else return error.MissingOpenRouterPendingFlow;
        var parsed = try openrouter_oauth.parseAuthorizationInput(self.gpa, input);
        defer parsed.deinit(self.gpa);
        const code = parsed.code orelse return error.OpenRouterOAuthMissingAuthorizationCode;
        var outcome = try openrouter_oauth.exchangeAuthorizationCodeWithOptions(self.gpa, self.io, code, flow.verifier, self.bootstrapHttpOptions());
        errdefer outcome.deinit(self.gpa);
        switch (outcome) {
            .complete => self.clearOpenRouterPendingFlow(),
            .failed => {},
        }
        return outcome;
    }

    pub fn installAnthropicPendingFlow(self: *ClientPool, flow: *const anthropic_oauth.AuthorizationFlow) !void {
        self.clearAnthropicPendingFlow();
        errdefer self.clearAnthropicPendingFlow();
        self.anthropic_pending_flow = .{
            .verifier = try self.gpa.dupe(u8, flow.verifier),
            .url = try self.gpa.dupe(u8, flow.url),
        };
    }

    pub fn completeAnthropicPendingFlow(self: *ClientPool, input: []const u8) !anthropic_oauth.Token {
        const flow = if (self.anthropic_pending_flow) |*value| value else return error.MissingAnthropicPendingFlow;
        var parsed = try anthropic_oauth.parseAuthorizationInput(self.gpa, input);
        defer parsed.deinit(self.gpa);
        if (parsed.state) |state| if (!std.mem.eql(u8, state, flow.verifier)) return error.AnthropicOAuthStateMismatch;
        const code = parsed.code orelse return error.AnthropicOAuthMissingAuthorizationCode;
        const state = parsed.state orelse flow.verifier;
        var token = try anthropic_oauth.exchangeAuthorizationCodeWithOptions(self.gpa, self.io, code, state, flow.verifier, anthropic_oauth.REDIRECT_URI, self.bootstrapHttpOptions());
        errdefer token.deinit(self.gpa);
        self.clearAnthropicPendingFlow();
        return token;
    }

    fn clearCodexPendingFlow(self: *ClientPool) void {
        if (self.codex_pending_flow) |*flow| flow.deinit(self.gpa);
        self.codex_pending_flow = null;
    }

    pub fn installCodexPendingFlow(self: *ClientPool, flow: *const codex_oauth.AuthorizationFlow) !void {
        self.clearCodexPendingFlow();
        errdefer self.clearCodexPendingFlow();
        self.codex_pending_flow = .{
            .verifier = try self.gpa.dupe(u8, flow.verifier),
            .state = try self.gpa.dupe(u8, flow.state),
            .url = try self.gpa.dupe(u8, flow.url),
        };
    }

    pub fn completeCodexPendingFlow(self: *ClientPool, input: []const u8) !codex_oauth.Token {
        const flow = if (self.codex_pending_flow) |*value| value else return error.MissingOpenAICodexPendingFlow;
        var parsed = try codex_oauth.parseAuthorizationInput(self.gpa, input);
        defer parsed.deinit(self.gpa);
        if (parsed.state) |state| if (!std.mem.eql(u8, state, flow.state)) return error.OpenAICodexStateMismatch;
        const code = parsed.code orelse return error.OpenAICodexMissingAuthorizationCode;
        var token = try codex_oauth.exchangeAuthorizationCodeWithOptions(self.gpa, self.io, code, flow.verifier, codex_oauth.REDIRECT_URI, self.bootstrapHttpOptions());
        errdefer token.deinit(self.gpa);
        self.clearCodexPendingFlow();
        return token;
    }

    fn liveCredentialForIdentity(self: *const ClientPool, provider_id: []const u8) ?*const auth_storage.Credential {
        const stored_provider = self.live_credential_provider orelse return null;
        if (!std.ascii.eqlIgnoreCase(stored_provider, provider_id)) return null;
        return if (self.live_credential) |*credential| credential else null;
    }

    pub fn setPrimaryOAuthMetadata(self: *ClientPool, refresh: ?[]const u8, expires_ms: ?i64, enterprise_url: ?[]const u8) void {
        self.primary_oauth_refresh = refresh;
        self.primary_oauth_expires_ms = expires_ms;
        self.primary_oauth_enterprise_url = enterprise_url;
    }

    pub fn setPrimaryRequestMetadata(
        self: *ClientPool,
        headers: []const metadata.Header,
        sampling_params: []const metadata.SamplingParam,
        compat: metadata.Compat,
        max_tokens: u64,
        context_window: u64,
        input_image: bool,
    ) void {
        self.primary_headers = headers;
        self.primary_sampling_params = sampling_params;
        self.primary_compat = compat;
        self.primary_max_tokens = max_tokens;
        self.primary_context_window = context_window;
        self.primary_input_image = input_image;
    }

    pub fn setPrimaryModelRuntime(self: *ClientPool, api: @import("../ai/api.zig").Api, model_cost: providers.ModelCost) void {
        self.primary_api = api;
        self.primary_model_cost = model_cost;
    }

    pub fn setPrimaryThinkingMetadata(self: *ClientPool, reasoning: bool, thinking_level_map: ?thinking_mod.ThinkingLevelMap) void {
        self.primary_reasoning = reasoning;
        self.primary_thinking_level_map = thinking_level_map;
    }

    pub fn setRuntimeProviders(self: *ClientPool, configs: []const RuntimeProviderConfig) void {
        self.runtime_providers = configs;
    }

    pub fn setModelCatalog(self: *ClientPool, catalog: []const providers.ModelInfo) void {
        self.model_catalog = if (catalog.len > 0) catalog else &providers.known_models;
    }

    pub fn setExtensionOAuthBridge(self: *ClientPool, bridge: ?ExtensionOAuthBridge) void {
        self.extension_oauth_bridge = bridge;
        if (bridge == null) self.invalidateExtensionOAuth();
    }

    pub fn setExtensionStreamBridge(self: *ClientPool, bridge: ?ExtensionStreamBridge) void {
        self.extension_stream_bridge = bridge;
        if (bridge == null) {
            self.extension_stream_active = false;
            self.extension_stream_model = "";
        }
    }

    /// Detach every concrete client from the derived extension key before its
    /// backing allocation is released. Provider unregister/reload may leave the
    /// current model absent from the replacement catalog, so merely clearing the
    /// pool cache would otherwise leave a stale (and dangling) request key in
    /// the active client.
    pub fn invalidateExtensionOAuth(self: *ClientPool) void {
        const provider_id = self.extension_oauth_provider orelse return;
        if (self.openai) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
        };
        if (self.responses) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
        };
        if (self.anthropic) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
        };
        if (self.pi_messages) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
        };
        if (self.google) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
            client.bearer_expiration_unix = null;
        };
        if (self.mistral) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.token_expiration_ms = null;
            client.token_refresh_ctx = null;
            client.token_refresh_fn = null;
        };
        if (self.bedrock) |*client| if (std.ascii.eqlIgnoreCase(client.provider_id, provider_id)) {
            client.api_key = "";
            client.credential_expiration_unix = null;
            client.credential_refresh_ctx = null;
            client.credential_refresh_fn = null;
        };
        self.clearExtensionOAuthState();
    }

    fn clearExtensionOAuthState(self: *ClientPool) void {
        if (self.extension_oauth_provider) |provider_id| self.gpa.free(provider_id);
        if (self.extension_oauth_key) |key| self.gpa.free(key);
        self.extension_oauth_provider = null;
        self.extension_oauth_key = null;
        self.extension_oauth_expires_ms = null;
    }

    fn hasExtensionOAuth(self: *const ClientPool, provider_id: []const u8) bool {
        const current = self.extension_oauth_provider orelse return false;
        return std.ascii.eqlIgnoreCase(current, provider_id) and self.extension_oauth_key != null;
    }

    fn resolveExtensionOAuth(self: *ClientPool, provider_id: []const u8, now_ms: i64, apply_models: bool) !bool {
        const bridge = self.extension_oauth_bridge orelse {
            self.invalidateExtensionOAuth();
            return false;
        };
        if (!bridge.supports_fn(bridge.context, provider_id)) {
            self.invalidateExtensionOAuth();
            return false;
        }
        const maybe_resolution = try bridge.resolve_fn(bridge.context, self.gpa, provider_id, now_ms, self.abort_flag, apply_models);
        var resolution = maybe_resolution orelse {
            self.invalidateExtensionOAuth();
            return false;
        };
        errdefer resolution.deinit(self.gpa);
        const owned_provider = try self.gpa.dupe(u8, provider_id);
        self.invalidateExtensionOAuth();
        self.extension_oauth_provider = owned_provider;
        self.extension_oauth_key = resolution.api_key;
        self.extension_oauth_expires_ms = resolution.expires_ms;
        resolution.api_key = &.{};
        return true;
    }

    fn refreshExtensionOAuthState(self: *ClientPool, provider_id: []const u8, now_ms: i64) !void {
        if (!try self.resolveExtensionOAuth(provider_id, now_ms, false)) return error.MissingExtensionOAuthCredential;
    }

    fn runtimeProvider(self: *const ClientPool, provider_id: []const u8, model_id: []const u8) ?RuntimeProviderConfig {
        var provider_fallback: ?RuntimeProviderConfig = null;
        for (self.runtime_providers) |config| {
            if (!std.ascii.eqlIgnoreCase(config.id, provider_id)) continue;
            if (config.model_id) |configured_model| {
                if (std.mem.eql(u8, configured_model, model_id)) return config;
            } else if (provider_fallback == null) {
                provider_fallback = config;
            }
        }
        return provider_fallback;
    }

    fn catalogModel(self: *const ClientPool, provider_id: []const u8, model_id: []const u8) ?providers.ModelInfo {
        for (self.model_catalog) |model| {
            if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id) and std.mem.eql(u8, model.id, model_id)) return model;
        }
        return null;
    }

    const RequestMetadata = struct {
        headers: []const metadata.Header = &.{},
        sampling_params: []const metadata.SamplingParam = &.{},
        compat: metadata.Compat = .{},
        reasoning: bool = false,
        input_image: bool = false,
        thinking_level_map: ?thinking_mod.ThinkingLevelMap = null,
        max_tokens: u64 = 0,
        context_window: u64 = 0,
        api: @import("../ai/api.zig").Api = .openai_completions,
        model_cost: providers.ModelCost = .{},
    };

    fn requestMetadataForIdentity(self: *const ClientPool, provider_id: []const u8, model_id: []const u8) RequestMetadata {
        var out: RequestMetadata = if (self.runtimeProvider(provider_id, model_id)) |runtime| .{
            .headers = runtime.headers,
            .sampling_params = runtime.sampling_params,
            .compat = runtime.compat,
            .reasoning = runtime.reasoning,
            .input_image = runtime.input_image,
            .thinking_level_map = runtime.thinking_level_map,
            .max_tokens = runtime.max_tokens,
            .context_window = runtime.context_window,
            .api = if (runtime.api == .openai_completions) switch (runtime.transport) {
                .anthropic => .anthropic_messages,
                .google => .google_generative_ai,
                else => runtime.api,
            } else runtime.api,
            .model_cost = runtime.model_cost,
        } else if (std.ascii.eqlIgnoreCase(provider_id, self.primary_provider_id)) .{
            .headers = self.primary_headers,
            .sampling_params = self.primary_sampling_params,
            .compat = self.primary_compat,
            .reasoning = self.primary_reasoning,
            .input_image = self.primary_input_image,
            .thinking_level_map = self.primary_thinking_level_map,
            .max_tokens = self.primary_max_tokens,
            .context_window = self.primary_context_window,
            .api = self.primary_api,
            .model_cost = self.primary_model_cost,
        } else if (self.catalogModel(provider_id, model_id)) |model| .{
            .headers = model.headers,
            .sampling_params = model.sampling_params,
            .compat = model.compat,
            .reasoning = model.reasoning,
            .input_image = model.input_image,
            .thinking_level_map = model.thinking_level_map,
            .max_tokens = model.max_tokens,
            .context_window = model.context_window,
            .api = model.apiKind(),
            .model_cost = model.cost,
        } else .{};
        if (self.catalogModel(provider_id, model_id)) |model| {
            const base_url = model.base_url orelse providers.defaultBaseUrl(model.provider);
            const detected: metadata.Compat = switch (out.api) {
                .openai_completions => metadata.detectOpenAICompat(provider_id, base_url, model.id),
                .openai_responses, .openai_codex_responses, .azure_openai_responses => metadata.detectOpenAIResponsesCompat(provider_id, base_url, model.id),
                .anthropic_messages => metadata.detectAnthropicCompat(provider_id, model.id),
                else => .{},
            };
            out.compat = metadata.Compat.merge(detected, out.compat);
        }
        out.compat = cloudflare.applyCompatDefaults(provider_id, model_id, out.compat);
        return out;
    }

    const OAuthMetadata = struct { refresh: ?[]const u8 = null, expires_ms: ?i64 = null, enterprise_url: ?[]const u8 = null };

    fn oauthForIdentity(self: *ClientPool, provider_id: []const u8, model_id: []const u8) OAuthMetadata {
        if (self.liveCredentialForIdentity(provider_id)) |credential| {
            switch (credential.*) {
                .oauth => |oauth| return .{ .refresh = oauth.refresh, .expires_ms = oauth.expires, .enterprise_url = oauth.enterprise_url },
                else => {},
            }
        }
        if (self.runtimeProvider(provider_id, model_id)) |runtime| {
            if (runtime.oauth_refresh != null) return .{ .refresh = runtime.oauth_refresh, .expires_ms = runtime.oauth_expires_ms, .enterprise_url = runtime.oauth_enterprise_url };
        }
        if (std.ascii.eqlIgnoreCase(provider_id, self.primary_provider_id))
            return .{ .refresh = self.primary_oauth_refresh, .expires_ms = self.primary_oauth_expires_ms, .enterprise_url = self.primary_oauth_enterprise_url };
        return .{};
    }

    fn clearCodexOAuthState(self: *ClientPool) void {
        if (self.codex_initial_refresh) |refresh_value| self.gpa.free(refresh_value);
        self.codex_initial_refresh = null;
        if (self.codex_oauth_token) |*token| token.deinit(self.gpa);
        self.codex_oauth_token = null;
    }

    fn refreshCodexOAuth(ctx: *anyopaque, client: *@import("../ai/openai_responses.zig").ResponsesClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        const refresh_token: []const u8 = if (self.codex_oauth_token) |*token| token.refresh else self.codex_initial_refresh orelse return error.MissingOpenAICodexRefreshToken;
        var fresh = try codex_oauth.refreshWithOptions(self.gpa, self.io, refresh_token, self.bootstrapHttpOptions());
        errdefer fresh.deinit(self.gpa);
        if (self.codex_oauth_token) |*old| old.deinit(self.gpa);
        self.codex_oauth_token = fresh;
        client.api_key = self.codex_oauth_token.?.access;
        client.token_expiration_ms = self.codex_oauth_token.?.expires_ms;

        if (self.auth_agent_dir) |agent_dir| {
            codex_oauth.persistToken(self.gpa, self.io, agent_dir, &self.codex_oauth_token.?) catch {};
        }
    }

    fn clearCopilotOAuthState(self: *ClientPool) void {
        if (self.copilot_initial_refresh) |value| self.gpa.free(value);
        self.copilot_initial_refresh = null;
        if (self.copilot_enterprise_domain) |value| self.gpa.free(value);
        self.copilot_enterprise_domain = null;
        if (self.copilot_oauth_credential) |*credential| credential.deinit(self.gpa);
        self.copilot_oauth_credential = null;
        if (self.copilot_base_url) |value| self.gpa.free(value);
        self.copilot_base_url = null;
    }

    fn configureCopilotOAuth(self: *ClientPool, provider_id: []const u8, model_id: []const u8) !void {
        if (!std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) {
            self.clearCopilotOAuthState();
            return;
        }
        const oauth = self.oauthForIdentity(provider_id, model_id);
        const refresh = oauth.refresh orelse {
            self.clearCopilotOAuthState();
            return;
        };
        // Preserve a freshly refreshed token while hot-switching between Copilot models
        // under the same GitHub account.
        if (self.copilot_oauth_credential) |*credential| {
            if (std.mem.eql(u8, credential.refresh, refresh)) return;
        }
        if (self.copilot_initial_refresh) |existing| {
            if (std.mem.eql(u8, existing, refresh)) return;
        }
        self.clearCopilotOAuthState();
        errdefer self.clearCopilotOAuthState();
        self.copilot_initial_refresh = try self.gpa.dupe(u8, refresh);
        if (oauth.enterprise_url) |domain| self.copilot_enterprise_domain = try self.gpa.dupe(u8, domain);
        const access = self.keyForIdentity(provider_id, .openai, model_id) orelse return error.MissingApiKey;
        self.copilot_base_url = try copilot_oauth.getBaseUrl(self.gpa, access, self.copilot_enterprise_domain);
    }

    fn refreshCopilotState(self: *ClientPool) !void {
        const refresh: []const u8 = if (self.copilot_oauth_credential) |*credential| credential.refresh else self.copilot_initial_refresh orelse return error.MissingGitHubCopilotRefreshToken;
        var fresh = try copilot_oauth.refreshCredentialWithOptions(self.gpa, self.io, refresh, self.copilot_enterprise_domain, self.bootstrapHttpOptions());
        errdefer fresh.deinit(self.gpa);
        const fresh_base = try copilot_oauth.getBaseUrl(self.gpa, fresh.access, fresh.enterprise_domain);
        errdefer self.gpa.free(fresh_base);
        if (self.copilot_oauth_credential) |*old| old.deinit(self.gpa);
        self.copilot_oauth_credential = fresh;
        if (self.copilot_base_url) |old_base| self.gpa.free(old_base);
        self.copilot_base_url = fresh_base;

        if (self.auth_agent_dir) |agent_dir| {
            copilot_oauth.persistCredential(self.gpa, self.io, agent_dir, &self.copilot_oauth_credential.?) catch {};
        }
    }

    fn refreshCopilotOpenAI(ctx: *anyopaque, client: *@import("../ai/openai.zig").OpenAIClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshCopilotState();
        client.api_key = self.copilot_oauth_credential.?.access;
        client.base_url = self.copilot_base_url.?;
        client.token_expiration_ms = self.copilot_oauth_credential.?.expires_ms;
    }

    fn refreshXaiOpenAI(ctx: *anyopaque, client: *@import("../ai/openai.zig").OpenAIClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        const oauth = self.oauthForIdentity("xai", client.model);
        const refresh_token = oauth.refresh orelse return error.MissingXaiRefreshToken;
        var fresh = try xai_oauth.refreshWithOptions(self.gpa, self.io, refresh_token, self.bootstrapHttpOptions());
        defer fresh.deinit(self.gpa);
        try self.installXaiOAuthCredential(&fresh);
        const live = self.liveCredentialForIdentity("xai") orelse return error.MissingXaiOAuthCredential;
        const value = switch (live.*) {
            .oauth => |credential| credential,
            else => return error.MissingXaiOAuthCredential,
        };
        client.api_key = value.access;
        client.token_expiration_ms = value.expires;
        if (self.auth_agent_dir) |agent_dir| xai_oauth.persistCredential(self.gpa, self.io, agent_dir, &fresh) catch {};
    }

    fn refreshCopilotResponses(ctx: *anyopaque, client: *@import("../ai/openai_responses.zig").ResponsesClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshCopilotState();
        client.api_key = self.copilot_oauth_credential.?.access;
        client.base_url = self.copilot_base_url.?;
        client.token_expiration_ms = self.copilot_oauth_credential.?.expires_ms;
    }

    fn refreshCopilotAnthropic(ctx: *anyopaque, client: *@import("../ai/anthropic.zig").AnthropicClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshCopilotState();
        client.api_key = self.copilot_oauth_credential.?.access;
        client.base_url = self.copilot_base_url.?;
        client.token_expiration_ms = self.copilot_oauth_credential.?.expires_ms;
    }

    fn refreshAnthropicOAuth(ctx: *anyopaque, client: *@import("../ai/anthropic.zig").AnthropicClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        const oauth = self.oauthForIdentity("anthropic", client.model);
        const refresh_token = oauth.refresh orelse return error.MissingAnthropicRefreshToken;
        var fresh = try anthropic_oauth.refreshWithOptions(self.gpa, self.io, refresh_token, self.bootstrapHttpOptions());
        defer fresh.deinit(self.gpa);
        try self.installAnthropicOAuthCredential(&fresh);
        const live = self.liveCredentialForIdentity("anthropic") orelse return error.MissingAnthropicOAuthCredential;
        const value = switch (live.*) {
            .oauth => |credential| credential,
            else => return error.MissingAnthropicOAuthCredential,
        };
        client.api_key = value.access;
        client.token_expiration_ms = value.expires;
        client.auth_mode = .oauth;
        if (self.auth_agent_dir) |agent_dir| anthropic_oauth.persistCredential(self.gpa, self.io, agent_dir, &fresh) catch {};
    }

    fn refreshKimiOAuth(ctx: *anyopaque, client: *@import("../ai/anthropic.zig").AnthropicClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        const oauth = self.oauthForIdentity("kimi-coding", client.model);
        const refresh_token = oauth.refresh orelse return error.MissingKimiRefreshToken;
        const host = kimi_oauth.oauthHost(self.environ);
        var fresh = try kimi_oauth.refreshWithOptions(self.gpa, self.io, host, refresh_token, self.bootstrapHttpOptions());
        defer fresh.deinit(self.gpa);
        try self.installKimiOAuthCredential(&fresh);
        const live = self.liveCredentialForIdentity("kimi-coding") orelse return error.MissingKimiOAuthCredential;
        const value = switch (live.*) {
            .oauth => |credential| credential,
            else => return error.MissingKimiOAuthCredential,
        };
        client.api_key = value.access;
        client.token_expiration_ms = value.expires;
        client.auth_mode = .bearer;
        if (self.auth_agent_dir) |agent_dir| kimi_oauth.persistCredential(self.gpa, self.io, agent_dir, &fresh) catch {};
    }

    fn clearRadiusOAuthState(self: *ClientPool) void {
        if (self.radius_initial_refresh) |refresh| self.gpa.free(refresh);
        self.radius_initial_refresh = null;
        if (self.radius_oauth_token) |*token| token.deinit(self.gpa);
        self.radius_oauth_token = null;
        if (self.radius_gateway) |gateway| self.gpa.free(gateway);
        self.radius_gateway = null;
    }

    fn refreshRadiusOAuth(ctx: *anyopaque, client: *@import("../ai/pi_messages.zig").PiMessagesClient, now_ms: i64) anyerror!void {
        _ = now_ms;
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        const refresh_token: []const u8 = if (self.radius_oauth_token) |*token| token.refresh else self.radius_initial_refresh orelse return error.MissingRadiusRefreshToken;
        const gateway = self.radius_gateway orelse return error.MissingRadiusGateway;
        var fresh = try radius_oauth.refreshWithOptions(self.gpa, self.io, gateway, refresh_token, self.bootstrapHttpOptions());
        errdefer fresh.deinit(self.gpa);
        if (self.radius_oauth_token) |*old| old.deinit(self.gpa);
        self.radius_oauth_token = fresh;
        client.api_key = self.radius_oauth_token.?.access;
        client.token_expiration_ms = self.radius_oauth_token.?.expires_ms;

        // Persistence is best-effort: a read-only auth store must not make a
        // freshly refreshed in-memory token unusable for the current process.
        if (self.auth_agent_dir) |agent_dir| {
            var store = auth_storage.AuthStorage.init(self.gpa, self.io, agent_dir) catch return;
            defer store.deinit();
            const token = &self.radius_oauth_token.?;
            store.setOAuth(client.provider_id, .{
                .refresh = token.refresh,
                .access = token.access,
                .expires = token.expires_ms,
                .scope = token.scope,
            }) catch {};
        }
    }

    fn refreshExtensionOpenAI(ctx: *anyopaque, client: *@import("../ai/openai.zig").OpenAIClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
    }

    fn refreshExtensionResponses(ctx: *anyopaque, client: *@import("../ai/openai_responses.zig").ResponsesClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
    }

    fn refreshExtensionAnthropic(ctx: *anyopaque, client: *@import("../ai/anthropic.zig").AnthropicClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
    }

    fn refreshExtensionPiMessages(ctx: *anyopaque, client: *@import("../ai/pi_messages.zig").PiMessagesClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
    }

    fn refreshExtensionGoogle(ctx: *anyopaque, client: *@import("../ai/google.zig").GoogleClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
        if (client.auth_mode == .bearer) client.bearer_expiration_unix = if (self.extension_oauth_expires_ms) |expires| @divFloor(expires, 1000) else null;
    }

    fn refreshExtensionMistral(ctx: *anyopaque, client: *@import("../ai/mistral.zig").MistralClient, now_ms: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_ms);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.token_expiration_ms = self.extension_oauth_expires_ms;
    }

    fn refreshExtensionBedrock(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        try self.refreshExtensionOAuthState(client.provider_id, now_unix * 1000);
        client.api_key = self.extension_oauth_key orelse return error.MissingExtensionOAuthCredential;
        client.credential_expiration_unix = if (self.extension_oauth_expires_ms) |expires| @divFloor(expires, 1000) else null;
    }

    fn anthropicAuthMode(self: *ClientPool, provider_id: []const u8, model_id: []const u8, key: []const u8) @import("../ai/anthropic.zig").AuthMode {
        const oauth = self.oauthForIdentity(provider_id, model_id);
        if (std.ascii.eqlIgnoreCase(provider_id, "kimi-coding")) return if (oauth.refresh != null) .bearer else .api_key;
        if (!std.ascii.eqlIgnoreCase(provider_id, "anthropic")) return .api_key;
        if (oauth.refresh != null or anthropic_oauth.isOAuthAccessToken(key)) return .oauth;
        if (self.environ) |env| {
            if (env.get(app_config.ENV_ANTHROPIC_AUTH_TOKEN)) |value| if (std.mem.eql(u8, value, key)) return .bearer;
            if (env.get(app_config.ENV_ANTHROPIC_OAUTH_TOKEN)) |value| if (std.mem.eql(u8, value, key)) return .oauth;
        }
        return .api_key;
    }

    fn keyForIdentity(self: *ClientPool, provider_id: []const u8, provider: providers.Provider, model_id: []const u8) ?[]const u8 {
        if (self.hasExtensionOAuth(provider_id)) return self.extension_oauth_key;
        if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) if (self.copilot_oauth_credential) |*credential| return credential.access;
        if (self.liveCredentialForIdentity(provider_id)) |credential| {
            switch (credential.*) {
                .api_key => |api_key| if (api_key.key) |key| return key,
                .oauth => |oauth| return oauth.access,
            }
        }
        if (self.runtimeProvider(provider_id, model_id)) |runtime| {
            if (runtime.api_key) |key| return key;
        }
        if (std.ascii.eqlIgnoreCase(provider_id, self.primary_provider_id)) {
            if (self.primary_key) |key| return key;
        }
        // Only apply a built-in provider's env/cache credential when the public
        // identity is actually that provider. A custom OpenAI-compatible provider
        // must not accidentally inherit OPENAI_API_KEY.
        if (!std.ascii.eqlIgnoreCase(provider_id, provider.name())) {
            if (providers.Provider.fromString(provider_id)) |public_provider| {
                return if (self.environ) |env| providers.resolveApiKey(public_provider, null, env) else null;
            }
            return null;
        }
        return switch (provider) {
            .openai => self.openai_key,
            .anthropic => if (self.environ) |env| providers.resolveApiKey(.anthropic, null, env) orelse self.anthropic_key else self.anthropic_key,
            .google => self.google_key,
            .ollama, .lmstudio, .vllm, .mock => "local",
            else => if (self.environ) |env| providers.resolveApiKey(provider, null, env) else null,
        };
    }

    fn baseUrlForIdentity(self: *ClientPool, provider_id: []const u8, provider: providers.Provider, model_id: []const u8) []const u8 {
        if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) if (self.copilot_base_url) |url| return url;
        if (self.runtimeProvider(provider_id, model_id)) |runtime| {
            if (runtime.base_url) |url| return url;
        }
        if (std.ascii.eqlIgnoreCase(provider_id, self.primary_provider_id)) {
            if (self.primary_base_url) |url| return url;
        }
        if (std.ascii.eqlIgnoreCase(provider_id, "openai")) return self.openai_base;
        if (self.catalogModel(provider_id, model_id)) |model| if (model.base_url) |url| return url;
        return providers.defaultBaseUrl(provider);
    }

    pub fn setAbortFlag(self: *ClientPool, flag: ?*bool) void {
        self.abort_flag = flag;
        self.syncClientFields();
    }

    pub fn setSessionContext(self: *ClientPool, session_id: ?[]const u8, cache_retention: metadata.CacheRetention) void {
        const same_session = if (self.session_id) |old| if (session_id) |new_id| std.mem.eql(u8, old, new_id) else false else session_id == null;
        if (!same_session or cache_retention == .none) self.codex_ws_fallback_active = false;
        self.session_id = session_id;
        self.cache_retention = cache_retention;
        self.syncClientFields();
    }

    pub fn setThinking(self: *ClientPool, level: @import("../ai/root.zig").ThinkingLevel) void {
        self.thinking = level;
        self.syncClientFields();
    }

    pub fn setCodexTransport(self: *ClientPool, transport: codex_ws.Transport) void {
        if (self.codex_transport != transport) self.codex_ws_fallback_active = false;
        self.codex_transport = transport;
        if (self.responses) |*client| client.transport = transport;
    }

    pub fn setCodexHttpIdleTimeout(self: *ClientPool, timeout_ms: u64) void {
        self.codex_http_idle_timeout_ms = timeout_ms;
        if (self.responses) |*client| client.http_idle_timeout_ms = timeout_ms;
    }

    pub fn setCodexWebSocketConnectTimeout(self: *ClientPool, timeout_ms: u64) void {
        self.codex_websocket_connect_timeout_ms = timeout_ms;
        if (self.responses) |*client| client.websocket_connect_timeout_ms = timeout_ms;
    }

    pub fn setProviderRetryPolicy(self: *ClientPool, policy: retry_mod.ProviderPolicy) void {
        self.provider_retry_policy = policy;
        self.syncClientFields();
    }

    /// OAuth, credential, discovery, and catalog bootstrap requests use the
    /// same retry/deadline/proxy/cancellation contract as model transports.
    pub fn bootstrapHttpOptions(self: *const ClientPool) bootstrap_http.Options {
        return .{
            .policy = self.provider_retry_policy,
            .abort_flag = self.abort_flag,
            .proxy = .{
                .environ = self.environ,
                .setting = self.http_proxy_url,
            },
        };
    }

    pub fn setThinkingFromString(self: *ClientPool, level: ?[]const u8) void {
        if (level) |s| {
            self.setThinking(@import("../ai/root.zig").ThinkingLevel.fromString(s));
        } else {
            self.setThinking(.off);
        }
    }

    fn syncClientFields(self: *ClientPool) void {
        if (self.openai) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
            c.session_id = self.session_id;
            c.cache_retention = self.cache_retention;
        }
        if (self.responses) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
            c.session_id = self.session_id;
            c.cache_retention = self.cache_retention;
        }
        if (self.anthropic) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
            c.session_id = self.session_id;
            c.cache_retention = self.cache_retention;
        }
        if (self.google) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
        }
        if (self.mistral) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
        }
        if (self.bedrock) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
            c.cache_retention = self.cache_retention;
        }
        if (self.pi_messages) |*c| {
            c.provider_retry = self.provider_retry_policy;
            c.thinking = self.thinking;
            c.abort_flag = self.abort_flag;
            c.session_id = self.session_id;
            c.cache_retention = self.cache_retention;
        }
    }

    fn refreshGoogleAdc(ctx: *anyopaque, client: *@import("../ai/google.zig").GoogleClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.google_access_token) |*current| {
            if (current.expiration_unix > now_unix + 60) {
                client.api_key = current.token;
                client.bearer_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.google_access_token = null;
        }
        const credential = if (self.google_adc_credential) |*value| value else return error.MissingGoogleAdcCredential;
        self.google_access_token = switch (credential.kind) {
            .authorized_user => try google_adc.refreshAuthorizedUserWithOptions(self.gpa, self.io, credential, self.bootstrapHttpOptions()),
            .service_account => try google_adc.refreshServiceAccountWithOptions(self.gpa, self.io, credential, self.bootstrapHttpOptions()),
        };
        const stored = &self.google_access_token.?;
        client.api_key = stored.token;
        client.bearer_expiration_unix = stored.expiration_unix;
    }

    fn refreshBedrockWebIdentity(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.aws_temporary_credentials) |*current| {
            if (current.expiration_unix > now_unix + 60) {
                client.aws_credentials = current.borrowed();
                client.credential_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.aws_temporary_credentials = null;
        }
        const env = self.environ orelse return error.MissingAwsEnvironment;
        const profile_ptr: ?*const aws_credentials.OwnedProfile = if (self.aws_profile) |*profile| profile else null;
        const config = aws_web_identity.resolveConfig(env, profile_ptr) orelse return error.MissingWebIdentityConfiguration;
        const fresh = try aws_web_identity.assumeRoleWithOptions(self.gpa, self.io, config, self.bootstrapHttpOptions());
        self.aws_temporary_credentials = fresh;
        const stored = &self.aws_temporary_credentials.?;
        client.aws_credentials = stored.borrowed();
        client.credential_expiration_unix = stored.expiration_unix;
    }

    fn refreshBedrockProcess(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.aws_process_credentials) |*current| {
            if (current.expiration_unix == null or current.expiration_unix.? > now_unix + 60) {
                client.aws_credentials = current.borrowed();
                client.credential_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.aws_process_credentials = null;
        }
        const profile = if (self.aws_profile) |*value| value else return error.MissingAwsProfile;
        const command = profile.credential_process orelse return error.MissingCredentialProcess;
        const fresh = try aws_process.runCredentialProcess(self.gpa, self.io, command);
        self.aws_process_credentials = fresh;
        const stored = &self.aws_process_credentials.?;
        client.aws_credentials = stored.borrowed();
        client.credential_expiration_unix = stored.expiration_unix;
    }

    fn refreshBedrockContainer(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.aws_container_credentials) |*current| {
            if (current.expiration_unix > now_unix + 60) {
                client.aws_credentials = current.borrowed();
                client.credential_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.aws_container_credentials = null;
        }
        const env = self.environ orelse return error.MissingAwsEnvironment;
        var config = (try aws_container.resolveConfig(self.gpa, self.io, env)) orelse return error.MissingContainerCredentialConfiguration;
        defer config.deinit(self.gpa);
        const fresh = try aws_container.fetchCredentialsWithOptions(self.gpa, self.io, config, self.bootstrapHttpOptions());
        self.aws_container_credentials = fresh;
        const stored = &self.aws_container_credentials.?;
        client.aws_credentials = stored.borrowed();
        client.credential_expiration_unix = stored.expiration_unix;
    }

    fn refreshBedrockImds(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.aws_imds_credentials) |*current| {
            if (current.expiration_unix > now_unix + 60) {
                client.aws_credentials = current.borrowed();
                client.credential_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.aws_imds_credentials = null;
        }
        const env = self.environ orelse return error.MissingAwsEnvironment;
        const profile_ptr: ?*const aws_credentials.OwnedProfile = if (self.aws_profile) |*profile| profile else null;
        const config = try aws_imds.resolveConfig(env, profile_ptr);
        const fresh = try aws_imds.fetchCredentialsWithOptions(self.gpa, self.io, config, self.bootstrapHttpOptions());
        self.aws_imds_credentials = fresh;
        const stored = &self.aws_imds_credentials.?;
        client.aws_credentials = stored.borrowed();
        client.credential_expiration_unix = stored.expiration_unix;
    }

    fn resolveAssumeRoleSource(self: *ClientPool, source_name: []const u8) anyerror!@import("../ai/bedrock.zig").AwsCredentials {
        if (std.ascii.eqlIgnoreCase(source_name, "Environment")) {
            const env = self.environ orelse return error.MissingAwsEnvironment;
            const access = env.get("AWS_ACCESS_KEY_ID") orelse return error.MissingSourceCredentials;
            const secret = env.get("AWS_SECRET_ACCESS_KEY") orelse return error.MissingSourceCredentials;
            return .{ .access_key_id = access, .secret_access_key = secret, .session_token = env.get("AWS_SESSION_TOKEN") };
        }
        if (std.ascii.eqlIgnoreCase(source_name, "EcsContainer")) {
            const env = self.environ orelse return error.MissingAwsEnvironment;
            var config = (try aws_container.resolveConfig(self.gpa, self.io, env)) orelse return error.MissingContainerCredentialConfiguration;
            defer config.deinit(self.gpa);
            if (self.aws_container_credentials) |*old| old.deinit(self.gpa);
            self.aws_container_credentials = try aws_container.fetchCredentialsWithOptions(self.gpa, self.io, config, self.bootstrapHttpOptions());
            return self.aws_container_credentials.?.borrowed();
        }
        if (std.ascii.eqlIgnoreCase(source_name, "Ec2InstanceMetadata")) {
            const env = self.environ orelse return error.MissingAwsEnvironment;
            const profile_ptr: ?*const aws_credentials.OwnedProfile = if (self.aws_profile) |*profile| profile else null;
            if (self.aws_imds_credentials) |*old| old.deinit(self.gpa);
            self.aws_imds_credentials = try aws_imds.fetchCredentialsWithOptions(self.gpa, self.io, try aws_imds.resolveConfig(env, profile_ptr), self.bootstrapHttpOptions());
            return self.aws_imds_credentials.?.borrowed();
        }
        return error.UnsupportedCredentialSource;
    }

    fn extensionCompleteImpl(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
    ) anyerror!ai.ModelResponse {
        return extensionCompleteOptionsImpl(ptr, allocator, messages, tools_json, .{});
    }

    fn extensionCompleteOptionsImpl(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        completion_options: ai.CompletionOptions,
    ) anyerror!ai.ModelResponse {
        const self: *ClientPool = @ptrCast(@alignCast(ptr));
        return self.invokeExtensionStream(allocator, messages, tools_json, completion_options, null, null);
    }

    fn extensionStreamImpl(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        const self: *ClientPool = @ptrCast(@alignCast(ptr));
        return self.invokeExtensionStream(allocator, messages, tools_json, .{}, on_delta, delta_ctx);
    }

    fn extensionFetchDeferredImpl(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        handle_json: []const u8,
        options_json: []const u8,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) anyerror!ai.ModelResponse {
        const self: *ClientPool = @ptrCast(@alignCast(ptr));
        const bridge = self.extension_stream_bridge orelse return error.ExtensionProviderStreamUnavailable;
        const request = try self.prepareExtensionRequest(.{});
        if (!bridge.supports_fetch_deferred_fn(bridge.context, request.provider_id)) return error.DeferredResponsesUnsupported;
        return bridge.fetch_deferred_fn(bridge.context, allocator, request, handle_json, options_json, on_delta, delta_ctx, self.abort_flag);
    }

    fn extensionCancelDeferredImpl(ptr: *anyopaque, handle_json: []const u8, options_json: []const u8) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ptr));
        const bridge = self.extension_stream_bridge orelse return error.ExtensionProviderStreamUnavailable;
        const request = try self.prepareExtensionRequest(.{});
        if (!bridge.supports_cancel_deferred_fn(bridge.context, request.provider_id)) return error.DeferredResponsesUnsupported;
        return bridge.cancel_deferred_fn(bridge.context, request, handle_json, options_json, self.abort_flag);
    }

    fn prepareExtensionRequest(self: *ClientPool, completion_options: ai.CompletionOptions) !ExtensionStreamRequest {
        const provider_id = self.provider_owned orelse self.active_provider_id;
        const model_id = self.model_owned orelse self.extension_stream_model;
        _ = try self.resolveExtensionOAuth(provider_id, std.Io.Clock.real.now(self.io).toMilliseconds(), false);
        const request_metadata = self.requestMetadataForIdentity(provider_id, model_id);
        return .{
            .provider_id = provider_id,
            .model_id = model_id,
            .api = request_metadata.api.name(),
            .api_key = self.keyForIdentity(provider_id, self.active_provider, model_id),
            .base_url = self.baseUrlForIdentity(provider_id, self.active_provider, model_id),
            .headers = request_metadata.headers,
            .sampling_params = request_metadata.sampling_params,
            .compat = request_metadata.compat,
            .reasoning = request_metadata.reasoning,
            .input_image = request_metadata.input_image,
            .thinking_level_map = request_metadata.thinking_level_map,
            .thinking = self.thinking,
            .max_tokens = ai.resolveMaxTokens(request_metadata.max_tokens, completion_options.max_tokens),
            .context_window = request_metadata.context_window,
            .model_cost = request_metadata.model_cost,
            .session_id = ai.resolveSessionAffinity(self.session_id, completion_options),
            .cache_retention = ai.resolveCacheRetention(self.cache_retention, completion_options),
        };
    }

    fn invokeExtensionStream(
        self: *ClientPool,
        allocator: std.mem.Allocator,
        messages: []const ai.ChatMessage,
        tools_json: []const u8,
        completion_options: ai.CompletionOptions,
        on_delta: ?ai.StreamHandler,
        delta_ctx: ?*anyopaque,
    ) !ai.ModelResponse {
        const bridge = self.extension_stream_bridge orelse return error.ExtensionProviderStreamUnavailable;
        const provider_id = self.provider_owned orelse self.active_provider_id;
        if (!bridge.supports_fn(bridge.context, provider_id)) return error.ExtensionProviderStreamUnavailable;

        const request = try self.prepareExtensionRequest(completion_options);
        return bridge.complete_fn(
            bridge.context,
            allocator,
            request,
            messages,
            tools_json,
            on_delta,
            delta_ctx,
            self.abort_flag,
        );
    }

    fn refreshBedrockAssumeRole(ctx: *anyopaque, client: *@import("../ai/bedrock.zig").BedrockClient, now_unix: i64) anyerror!void {
        const self: *ClientPool = @ptrCast(@alignCast(ctx));
        if (self.aws_assumed_credentials) |*current| {
            if (current.expiration_unix > now_unix + 60) {
                client.aws_credentials = current.borrowed();
                client.credential_expiration_unix = current.expiration_unix;
                return;
            }
            current.deinit(self.gpa);
            self.aws_assumed_credentials = null;
        }
        const profile = if (self.aws_profile) |*value| value else return error.MissingAwsProfile;
        const role_arn = profile.role_arn orelse return error.MissingRoleArn;
        var source: @import("../ai/bedrock.zig").AwsCredentials = undefined;
        if (profile.source_profile) |_| {
            const source_profile = if (self.aws_source_profile) |*value| value else return error.MissingSourceProfile;
            if (source_profile.staticCredentials()) |credentials| {
                source = credentials;
            } else if (source_profile.credential_process) |command| {
                if (self.aws_process_credentials) |*old| old.deinit(self.gpa);
                self.aws_process_credentials = try aws_process.runCredentialProcess(self.gpa, self.io, command);
                source = self.aws_process_credentials.?.borrowed();
            } else return error.MissingSourceCredentials;
        } else if (profile.credential_source) |source_name| {
            source = try self.resolveAssumeRoleSource(source_name);
        } else return error.MissingAssumeRoleSource;

        const fresh = try aws_assume_role.assumeRoleWithHttpOptions(self.gpa, self.io, source, .{
            .role_arn = role_arn,
            .role_session_name = profile.role_session_name orelse "pi-zig",
            .external_id = profile.external_id,
            .duration_seconds = profile.duration_seconds,
            .region = client.region orelse "us-east-1",
        }, now_unix, self.bootstrapHttpOptions());
        self.aws_assumed_credentials = fresh;
        const stored = &self.aws_assumed_credentials.?;
        client.aws_credentials = stored.borrowed();
        client.credential_expiration_unix = stored.expiration_unix;
    }

    /// Switch a built-in provider/model and rebuild ModelClient.
    pub fn switchTo(self: *ClientPool, provider: providers.Provider, model_id: []const u8) !void {
        return self.switchToIdentity(provider.name(), provider, model_id);
    }

    /// Switch a public provider identity to the native transport backing it.
    /// This is what keeps arbitrary models.json IDs (for example `corp`) from
    /// collapsing into the built-in `openai` identity during live `/model` use.
    pub fn switchToIdentity(self: *ClientPool, requested_provider_id: []const u8, provider: providers.Provider, requested_model_id: []const u8) !void {
        return self.switchToIdentityWithOAuthProjection(requested_provider_id, provider, requested_model_id, true);
    }

    /// Rebuild the active client after login has already published its
    /// credential-dependent model projection. This prevents non-idempotent
    /// extension `modifyModels` callbacks from being applied twice.
    pub fn switchToIdentityAfterOAuthUpdate(self: *ClientPool, requested_provider_id: []const u8, provider: providers.Provider, requested_model_id: []const u8) !void {
        return self.switchToIdentityWithOAuthProjection(requested_provider_id, provider, requested_model_id, false);
    }

    fn switchToIdentityWithOAuthProjection(
        self: *ClientPool,
        requested_provider_id: []const u8,
        provider: providers.Provider,
        requested_model_id: []const u8,
        apply_oauth_models: bool,
    ) !void {
        var next_provider: ?[]u8 = try self.gpa.dupe(u8, requested_provider_id);
        errdefer if (next_provider) |value| self.gpa.free(value);
        var next_model: ?[]u8 = try self.gpa.dupe(u8, requested_model_id);
        errdefer if (next_model) |value| self.gpa.free(value);

        _ = try self.resolveExtensionOAuth(next_provider.?, std.Io.Clock.real.now(self.io).toMilliseconds(), apply_oauth_models);

        if (self.responses) |*client| client.deinit();
        self.responses = null;
        if (self.provider_owned) |value| self.gpa.free(value);
        if (self.model_owned) |value| self.gpa.free(value);
        self.provider_owned = next_provider.?;
        next_provider = null;
        self.model_owned = next_model.?;
        next_model = null;
        const provider_id = self.provider_owned.?;
        const model_id = self.model_owned.?;
        const mid = model_id;
        try self.configureCopilotOAuth(provider_id, model_id);
        const base_url = self.baseUrlForIdentity(provider_id, provider, model_id);
        const request_metadata = self.requestMetadataForIdentity(provider_id, model_id);
        const extension_oauth_active = self.hasExtensionOAuth(provider_id);
        self.extension_stream_active = false;
        self.extension_stream_model = "";
        if (self.extension_stream_bridge) |bridge| {
            if (bridge.supports_fn(bridge.context, provider_id)) {
                self.extension_stream_active = true;
                self.extension_stream_model = model_id;
                self.client = .{
                    .ptr = self,
                    .completeFn = extensionCompleteImpl,
                    .completeOptionsFn = extensionCompleteOptionsImpl,
                    .streamFn = extensionStreamImpl,
                    .fetchDeferredFn = if (bridge.supports_fetch_deferred_fn(bridge.context, provider_id)) extensionFetchDeferredImpl else null,
                    .cancelDeferredFn = if (bridge.supports_cancel_deferred_fn(bridge.context, provider_id)) extensionCancelDeferredImpl else null,
                };
                self.active_provider = provider;
                self.active_provider_id = provider_id;
                self.active_api = request_metadata.api;
                return;
            }
        }

        const transport = provider.transport();
        switch (request_metadata.api) {
            .openai_completions => {
                if (transport != .openai and transport != .mock) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.openai = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .thinking = self.thinking,
                    .reasoning = request_metadata.reasoning,
                    .thinking_level_map = request_metadata.thinking_level_map,
                    .abort_flag = self.abort_flag,
                    .session_id = self.session_id,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .compat = request_metadata.compat,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or std.ascii.eqlIgnoreCase(provider_id, "xai")) self.oauthForIdentity(provider_id, model_id).expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else if ((std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or std.ascii.eqlIgnoreCase(provider_id, "xai")) and self.oauthForIdentity(provider_id, model_id).refresh != null) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionOpenAI else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshCopilotOpenAI else if (std.ascii.eqlIgnoreCase(provider_id, "xai") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshXaiOpenAI else null,
                };
                self.client = self.openai.?.client();
            },
            .openai_responses, .openai_codex_responses => {
                if (transport != .openai and transport != .mock) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.clearCodexOAuthState();
                const codex_oauth_meta = if (request_metadata.api == .openai_codex_responses) self.oauthForIdentity(provider_id, model_id) else OAuthMetadata{};
                if (codex_oauth_meta.refresh) |refresh_value| self.codex_initial_refresh = try self.gpa.dupe(u8, refresh_value);
                self.responses = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .thinking = self.thinking,
                    .reasoning = request_metadata.reasoning,
                    .input_image = request_metadata.input_image,
                    .thinking_level_map = request_metadata.thinking_level_map,
                    .abort_flag = self.abort_flag,
                    .session_id = self.session_id,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .compat = request_metadata.compat,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .model_cost = request_metadata.model_cost,
                    .protocol_mode = if (request_metadata.api == .openai_codex_responses) .codex else .standard,
                    .transport = self.codex_transport,
                    .http_idle_timeout_ms = self.codex_http_idle_timeout_ms,
                    .websocket_connect_timeout_ms = self.codex_websocket_connect_timeout_ms,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) self.oauthForIdentity(provider_id, model_id).expires_ms else codex_oauth_meta.expires_ms,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") and self.oauthForIdentity(provider_id, model_id).refresh != null) @ptrCast(self) else if (codex_oauth_meta.refresh != null) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionResponses else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshCopilotResponses else if (codex_oauth_meta.refresh != null) refreshCodexOAuth else null,
                    .ws_fallback_flag = &self.codex_ws_fallback_active,
                };
                self.client = self.responses.?.client();
            },
            .azure_openai_responses => {
                if (transport != .openai and transport != .mock) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.responses = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .thinking = self.thinking,
                    .reasoning = request_metadata.reasoning,
                    .input_image = request_metadata.input_image,
                    .thinking_level_map = request_metadata.thinking_level_map,
                    .abort_flag = self.abort_flag,
                    .session_id = self.session_id,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .compat = request_metadata.compat,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .model_cost = request_metadata.model_cost,
                    .auth_mode = .azure_api_key,
                    .api_version = "v1",
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionResponses else null,
                };
                self.client = self.responses.?.client();
            },
            .anthropic_messages => {
                if (transport != .anthropic) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.anthropic = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                    .session_id = self.session_id,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .compat = request_metadata.compat,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or std.ascii.eqlIgnoreCase(provider_id, "anthropic") or std.ascii.eqlIgnoreCase(provider_id, "kimi-coding")) self.oauthForIdentity(provider_id, model_id).expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else if ((std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or std.ascii.eqlIgnoreCase(provider_id, "anthropic") or std.ascii.eqlIgnoreCase(provider_id, "kimi-coding")) and self.oauthForIdentity(provider_id, model_id).refresh != null) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionAnthropic else if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshCopilotAnthropic else if (std.ascii.eqlIgnoreCase(provider_id, "anthropic") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshAnthropicOAuth else if (std.ascii.eqlIgnoreCase(provider_id, "kimi-coding") and self.oauthForIdentity(provider_id, model_id).refresh != null) refreshKimiOAuth else null,
                    .auth_mode = self.anthropicAuthMode(provider_id, model_id, key),
                };
                self.client = self.anthropic.?.client();
            },
            .google_generative_ai => {
                if (transport != .google) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.google = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .thinking = self.thinking,
                    .thinking_level_map = request_metadata.thinking_level_map,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                    .abort_flag = self.abort_flag,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionGoogle else null,
                };
                self.client = self.google.?.client();
            },
            .google_vertex => {
                if (transport != .google) return error.UnsupportedApiTransport;
                const resolved_key = self.keyForIdentity(provider_id, provider, model_id);
                const use_adc = !extension_oauth_active and (resolved_key == null or google_adc.isAuthMarker(resolved_key.?));
                if (self.google_access_token) |*token| {
                    token.deinit(self.gpa);
                    self.google_access_token = null;
                }
                if (self.google_adc_credential) |*credential| {
                    credential.deinit(self.gpa);
                    self.google_adc_credential = null;
                }
                var quota_project: ?[]const u8 = null;
                var refresh_fn: ?@import("../ai/google.zig").BearerRefreshFn = null;
                var key: []const u8 = resolved_key orelse "";
                var auth_mode: @import("../ai/google.zig").AuthMode = if (extension_oauth_active) .bearer else .query_key;
                if (use_adc) {
                    const env = self.environ orelse return error.MissingGoogleEnvironment;
                    self.google_adc_credential = (try google_adc.load(self.gpa, self.io, env)) orelse return error.MissingGoogleAdcCredential;
                    const credential = &self.google_adc_credential.?;
                    quota_project = credential.quota_project_id;
                    auth_mode = .bearer;
                    key = "";
                    refresh_fn = refreshGoogleAdc;
                }
                self.google = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .auth_mode = auth_mode,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .thinking = self.thinking,
                    .thinking_level_map = request_metadata.thinking_level_map,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                    .abort_flag = self.abort_flag,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionGoogle else null,
                    .bearer_refresh_ctx = if (refresh_fn != null) @ptrCast(self) else null,
                    .bearer_refresh_fn = refresh_fn,
                    .bearer_expiration_unix = if (extension_oauth_active) if (self.extension_oauth_expires_ms) |expires| @divFloor(expires, 1000) else null else null,
                    .quota_project_id = quota_project,
                };
                self.client = self.google.?.client();
            },
            .mistral_conversations => {
                if (provider != .mistral and transport != .openai) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.mistral = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                    .custom_headers = request_metadata.headers,
                    .sampling_params = request_metadata.sampling_params,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else null,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionMistral else null,
                };
                self.client = self.mistral.?.client();
            },
            .bedrock_converse_stream => {
                if (transport != .amazon_bedrock) return error.UnsupportedApiTransport;
                const key = self.keyForIdentity(provider_id, provider, model_id);
                if (self.aws_profile) |*profile| {
                    profile.deinit(self.gpa);
                    self.aws_profile = null;
                }
                if (self.aws_source_profile) |*profile| {
                    profile.deinit(self.gpa);
                    self.aws_source_profile = null;
                }
                if (self.aws_temporary_credentials) |*credentials| {
                    credentials.deinit(self.gpa);
                    self.aws_temporary_credentials = null;
                }
                if (self.aws_process_credentials) |*credentials| {
                    credentials.deinit(self.gpa);
                    self.aws_process_credentials = null;
                }
                if (self.aws_container_credentials) |*credentials| {
                    credentials.deinit(self.gpa);
                    self.aws_container_credentials = null;
                }
                if (self.aws_imds_credentials) |*credentials| {
                    credentials.deinit(self.gpa);
                    self.aws_imds_credentials = null;
                }
                if (self.aws_assumed_credentials) |*credentials| {
                    credentials.deinit(self.gpa);
                    self.aws_assumed_credentials = null;
                }
                var resolved_aws_credentials: ?@import("../ai/bedrock.zig").AwsCredentials = null;
                var region: ?[]const u8 = null;
                var skip_auth = false;
                if (self.environ) |env| {
                    if (env.get("AWS_ACCESS_KEY_ID")) |access_key_id| {
                        if (env.get("AWS_SECRET_ACCESS_KEY")) |secret_access_key| {
                            resolved_aws_credentials = .{
                                .access_key_id = access_key_id,
                                .secret_access_key = secret_access_key,
                                .session_token = env.get("AWS_SESSION_TOKEN"),
                            };
                        }
                    }
                    region = env.get("AWS_REGION") orelse env.get("AWS_DEFAULT_REGION");
                    skip_auth = if (env.get("AWS_BEDROCK_SKIP_AUTH")) |value| std.mem.eql(u8, value, "1") else false;
                    // Load shared profile metadata whenever Bedrock is using AWS auth.
                    // Explicit environment access keys retain credential precedence, but
                    // the selected profile may still provide region/role configuration.
                    if (key == null and !skip_auth) {
                        if (try aws_credentials.loadSelectedProfile(self.gpa, self.io, env)) |profile| {
                            self.aws_profile = profile;
                            if (resolved_aws_credentials == null) resolved_aws_credentials = self.aws_profile.?.staticCredentials();
                            if (region == null) region = self.aws_profile.?.region;
                            if (self.aws_profile.?.source_profile) |source_name| {
                                self.aws_source_profile = try aws_credentials.loadProfileByName(self.gpa, self.io, env, source_name);
                            }
                        }
                    }
                }
                const profile_ptr: ?*const aws_credentials.OwnedProfile = if (self.aws_profile) |*profile| profile else null;
                const has_assume_role = if (profile_ptr) |profile| profile.role_arn != null and profile.web_identity_token_file == null and (profile.source_profile != null or profile.credential_source != null) else false;
                const has_process = if (profile_ptr) |profile| profile.credential_process != null else false;
                const has_web_identity = if (self.environ) |env| aws_web_identity.resolveConfig(env, profile_ptr) != null else false;
                const has_container = if (self.environ) |env| env.get("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") != null or env.get("AWS_CONTAINER_CREDENTIALS_FULL_URI") != null else false;
                const has_imds = if (self.environ) |env| !aws_imds.metadataDisabled(env) else false;
                const refresh_fn: ?@import("../ai/bedrock.zig").CredentialRefreshFn = if (extension_oauth_active)
                    refreshExtensionBedrock
                else if (resolved_aws_credentials != null)
                    null
                else if (has_assume_role)
                    refreshBedrockAssumeRole
                else if (has_process)
                    refreshBedrockProcess
                else if (has_web_identity)
                    refreshBedrockWebIdentity
                else if (has_container)
                    refreshBedrockContainer
                else if (has_imds)
                    refreshBedrockImds
                else
                    null;
                if (key == null and resolved_aws_credentials == null and refresh_fn == null and !skip_auth) return error.MissingApiKey;
                self.bedrock = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key orelse "",
                    .aws_credentials = resolved_aws_credentials,
                    .credential_refresh_ctx = if (refresh_fn != null) @ptrCast(self) else null,
                    .credential_refresh_fn = refresh_fn,
                    .credential_expiration_unix = if (extension_oauth_active) if (self.extension_oauth_expires_ms) |expires| @divFloor(expires, 1000) else null else null,
                    .region = region,
                    .skip_auth = skip_auth,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .model_cost = request_metadata.model_cost,
                };
                self.client = self.bedrock.?.client();
            },
            .pi_messages => {
                const key = self.keyForIdentity(provider_id, provider, model_id) orelse return error.MissingApiKey;
                self.clearCodexOAuthState();
                self.clearRadiusOAuthState();
                const oauth = self.oauthForIdentity(provider_id, model_id);
                if (oauth.refresh) |refresh| {
                    self.radius_initial_refresh = try self.gpa.dupe(u8, refresh);
                    self.radius_gateway = try radius_config.gatewayFromApiBase(self.gpa, base_url);
                }
                self.pi_messages = .{
                    .gpa = self.gpa,
                    .io = self.io,
                    .environ = self.environ,
                    .proxy_url = self.http_proxy_url,
                    .provider_retry = self.provider_retry_policy,
                    .api_key = key,
                    .base_url = base_url,
                    .model = mid,
                    .provider_id = provider_id,
                    .api_id = request_metadata.api.name(),
                    .thinking = self.thinking,
                    .abort_flag = self.abort_flag,
                    .session_id = self.session_id,
                    .cache_retention = self.cache_retention,
                    .custom_headers = request_metadata.headers,
                    .max_tokens = request_metadata.max_tokens,
                    .context_window = request_metadata.context_window,
                    .input_image = request_metadata.input_image,
                    .token_expiration_ms = if (extension_oauth_active) self.extension_oauth_expires_ms else oauth.expires_ms,
                    .token_refresh_ctx = if (extension_oauth_active) @ptrCast(self) else if (oauth.refresh != null) @ptrCast(self) else null,
                    .token_refresh_fn = if (extension_oauth_active) refreshExtensionPiMessages else if (oauth.refresh != null) refreshRadiusOAuth else null,
                };
                self.client = self.pi_messages.?.client();
            },
        }
        self.active_provider = provider;
        self.active_provider_id = provider_id;
        self.active_api = request_metadata.api;
    }

    pub fn modelPtr(self: *ClientPool) *[]const u8 {
        if (self.extension_stream_active) return &self.extension_stream_model;
        return switch (self.active_api) {
            .openai_completions => &self.openai.?.model,
            .openai_responses, .openai_codex_responses, .azure_openai_responses => &self.responses.?.model,
            .anthropic_messages => &self.anthropic.?.model,
            .google_generative_ai, .google_vertex => &self.google.?.model,
            .mistral_conversations => &self.mistral.?.model,
            .bedrock_converse_stream => &self.bedrock.?.model,
            .pi_messages => &self.pi_messages.?.model,
        };
    }
};

pub fn reloadDynamicAuthCatalog(state: *LiveState) !void {
    const agent_dir = state.agent_dir orelse return error.MissingAgentDir;
    const pool = state.client_pool orelse return error.MissingClientPool;
    const environ = pool.environ orelse return error.MissingEnvironment;
    var fresh = try loadDynamicAuthCatalog(state.gpa, state.io, environ, agent_dir, pool.runtime_providers);
    errdefer fresh.deinit();

    // Publish all borrowed slices before releasing the previous snapshot.
    state.model_catalog = fresh.model_catalog;
    pool.setModelCatalog(fresh.model_catalog);
    pool.setRuntimeProviders(fresh.runtime_configs);
    if (state.dynamic_catalog_snapshot) |*old| old.deinit();
    state.dynamic_catalog_snapshot = fresh;
}

pub fn reloadDynamicRadiusCatalog(state: *LiveState) !void {
    return reloadDynamicAuthCatalog(state);
}

/// Apply `/model <id>` to display + live client storage.
/// If id looks like `provider/model` or maps to another provider in catalog, rebuild client.
pub fn applyModel(state: *LiveState, new_id: []const u8) !void {
    var selected_id = new_id;

    if (state.client_pool) |pool| {
        var fallback_configured_buf: [256][]const u8 = undefined;
        var fallback_configured_len: usize = 0;
        if (state.configured_providers.len == 0) {
            inline for (std.meta.fields(providers.Provider)) |field| {
                const candidate: providers.Provider = @enumFromInt(field.value);
                var configured = candidate == pool.active_provider or switch (candidate) {
                    .ollama, .lmstudio, .vllm, .mock => true,
                    else => false,
                };
                if (!configured and std.ascii.eqlIgnoreCase(candidate.name(), pool.primary_provider_id) and pool.primary_key != null) configured = true;
                if (!configured) {
                    configured = switch (candidate) {
                        .openai => pool.openai_key != null,
                        .anthropic => pool.anthropic_key != null,
                        .google => pool.google_key != null,
                        else => if (pool.environ) |env| providers.hasUsableCredential(candidate, null, env) else false,
                    };
                }
                if (configured and fallback_configured_len < fallback_configured_buf.len) {
                    fallback_configured_buf[fallback_configured_len] = candidate.name();
                    fallback_configured_len += 1;
                }
            }
            for (pool.runtime_providers) |runtime| {
                if (runtime.api_key == null) continue;
                var duplicate = false;
                for (fallback_configured_buf[0..fallback_configured_len]) |existing| {
                    if (std.ascii.eqlIgnoreCase(existing, runtime.id)) {
                        duplicate = true;
                        break;
                    }
                }
                if (!duplicate and fallback_configured_len < fallback_configured_buf.len) {
                    fallback_configured_buf[fallback_configured_len] = runtime.id;
                    fallback_configured_len += 1;
                }
            }
        }
        const configured = if (state.configured_providers.len > 0) state.configured_providers else fallback_configured_buf[0..fallback_configured_len];
        const catalog = if (state.model_catalog.len > 0) state.model_catalog else &providers.known_models;

        const resolved = model_resolver.resolveCliModel(null, new_id, null, catalog, configured);

        var selected_provider = pool.active_provider;
        var selected_provider_id = pool.active_provider_id;
        if (resolved.model) |model| {
            selected_provider = model.provider;
            selected_provider_id = model.providerName();
            selected_id = model.id;
        } else if (resolved.err == .ambiguous_model) {
            return error.AmbiguousModel;
        } else if (std.mem.indexOfScalar(u8, new_id, '/')) |slash| {
            // Built-in explicit provider + unknown model remains supported even
            // when no matching static catalog entry exists.
            if (providers.Provider.fromString(new_id[0..slash])) |provider| {
                selected_provider = provider;
                selected_provider_id = provider.name();
                selected_id = new_id[slash + 1 ..];
            }
        }

        // Rebuild even for same-provider custom IDs so ModelClient points at pool-owned memory.
        try pool.switchToIdentity(selected_provider_id, selected_provider, selected_id);
        state.active_model = pool.modelPtr();
        if (state.provider_name) |pn| pn.* = selected_provider_id;
        state.agent_cfg.provider_name = selected_provider_id;
        state.agent_cfg.model_id = pool.modelPtr().*;
        state.agent_cfg.compaction_context_window = pool.requestMetadataForIdentity(selected_provider_id, selected_id).context_window;

        const display_owned = try state.gpa.dupe(u8, selected_id);
        if (state.model_display_owned.*) {
            if (state.model_display.*) |old| state.gpa.free(old);
        }
        state.model_display.* = display_owned;
        state.model_display_owned.* = true;
        return;
    }

    // Embedders and deterministic mock runs may intentionally omit a ClientPool.
    // Resolve the canonical identity anyway so `/model provider/id` updates both
    // halves of the live model state and produces the same durable session entry.
    const catalog = if (state.model_catalog.len > 0) state.model_catalog else &providers.known_models;
    const resolved = model_resolver.resolveCliModel(null, new_id, null, catalog, state.configured_providers);
    var selected_model: ?providers.ModelInfo = null;
    var selected_provider_id: ?[]const u8 = null;
    if (resolved.model) |model| {
        selected_model = model;
        selected_provider_id = model.providerName();
        selected_id = model.id;
    } else if (resolved.err == .ambiguous_model) {
        return error.AmbiguousModel;
    } else if (std.mem.indexOfScalar(u8, new_id, '/')) |slash| {
        if (providers.Provider.fromString(new_id[0..slash])) |provider| {
            selected_provider_id = provider.name();
            selected_id = new_id[slash + 1 ..];
        }
    }

    const owned = try state.gpa.dupe(u8, selected_id);
    errdefer state.gpa.free(owned);
    if (state.model_display_owned.*) {
        if (state.model_display.*) |old| state.gpa.free(old);
    }
    state.model_display.* = owned;
    state.model_display_owned.* = true;
    if (state.active_model) |am| am.* = owned;
    if (selected_provider_id) |provider_id| {
        if (state.provider_name) |provider_slot| provider_slot.* = provider_id;
        state.agent_cfg.provider_name = provider_id;
    }
    state.agent_cfg.model_id = owned;
    state.agent_cfg.compaction_context_window = if (selected_model) |model|
        model.context_window
    else if (activeModelInfo(state)) |model|
        model.context_window
    else
        0;
}

pub fn activeModelInfo(state: *const LiveState) ?providers.ModelInfo {
    const model_id = state.model_display.* orelse return null;
    const provider_id = if (state.provider_name) |provider_ptr|
        provider_ptr.* orelse if (state.client_pool) |pool| pool.active_provider_id else ""
    else if (state.client_pool) |pool|
        pool.active_provider_id
    else
        "";
    const catalog = if (state.model_catalog.len > 0) state.model_catalog else &providers.known_models;
    for (catalog) |model| {
        if (std.mem.eql(u8, model.id, model_id) and std.ascii.eqlIgnoreCase(model.providerName(), provider_id)) return model;
    }
    var unique: ?providers.ModelInfo = null;
    for (catalog) |model| {
        if (!std.mem.eql(u8, model.id, model_id)) continue;
        if (unique != null) return null;
        unique = model;
    }
    return unique;
}

pub fn scopedThinkingForModel(state: *const LiveState, model: providers.ModelInfo) ?thinking_mod.ThinkingLevel {
    for (state.model_scope) |scoped| {
        if (std.mem.eql(u8, scoped.model.id, model.id) and std.ascii.eqlIgnoreCase(scoped.model.providerName(), model.providerName())) {
            return scoped.thinking_level;
        }
    }
    return null;
}

/// Keep a Ctrl+S default reachable from a non-empty persistent/CLI model scope
/// for the rest of the process. Settings persistence separately appends the
/// canonical provider/model reference to enabledModels when applicable.
pub fn addPersistedDefaultToScope(state: *LiveState, model: providers.ModelInfo) !void {
    if (state.model_scope.len == 0) return;
    for (state.model_scope) |scoped| {
        if (std.mem.eql(u8, scoped.model.id, model.id) and std.ascii.eqlIgnoreCase(scoped.model.providerName(), model.providerName())) return;
    }
    const next = try state.gpa.alloc(model_resolver.ScopedModel, state.model_scope.len + 1);
    @memcpy(next[0..state.model_scope.len], state.model_scope);
    next[state.model_scope.len] = .{ .model = model };
    if (state.owned_model_scope) |old| state.gpa.free(old);
    state.owned_model_scope = next;
    state.model_scope = next;
}

/// Clamp the current or explicitly scoped thinking level to the newly selected
/// model. Returns true only when the effective session level changed.
pub fn applyThinkingForModelSwitch(
    state: *LiveState,
    model: providers.ModelInfo,
    explicit: ?thinking_mod.ThinkingLevel,
) !bool {
    const requested = explicit orelse if (state.thinking) |level|
        thinking_mod.ThinkingLevel.parse(level) orelse .off
    else
        .off;
    const effective = model.clampThinkingLevel(requested);
    const next = @tagName(effective);
    if (state.thinking) |current| {
        if (std.ascii.eqlIgnoreCase(current, next)) {
            if (state.client_pool) |pool| pool.setThinkingFromString(next);
            state.agent_cfg.reasoning_level = next;
            return false;
        }
    }
    try applyThinking(state, next);
    return true;
}

/// Rebuild the live prompt from the retained thinking-independent base.
fn rebuildSystemFromBase(state: *LiveState, thinking_level: ?[]const u8) !void {
    const new_sys = if (state.owned_system_base) |base_slot| blk: {
        if (base_slot.*) |base| {
            break :blk try system_prompt.assemble(state.gpa, .{
                .system_override = base,
                .thinking_level = thinking_level,
            });
        }
        const skills_sum = if (state.owned_skills_summary.*) |summary| summary else "";
        break :blk try system_prompt.assemble(state.gpa, .{
            .skills_summary = skills_sum,
            .thinking_level = thinking_level,
        });
    } else blk: {
        // Backwards-compatible path for embedders that do not retain a base.
        const skills_sum = if (state.owned_skills_summary.*) |summary| summary else "";
        break :blk try system_prompt.assemble(state.gpa, .{
            .skills_summary = skills_sum,
            .thinking_level = thinking_level,
        });
    };
    errdefer state.gpa.free(new_sys);
    if (state.owned_system.*) |old| state.gpa.free(old);
    state.owned_system.* = new_sys;
    state.agent_cfg.system_prompt = new_sys;
}

/// Reassemble system prompt with thinking level without dropping CLI SYSTEM.md,
/// APPEND_SYSTEM.md, custom appends, or skills. Also pushes ThinkingLevel into
/// ClientPool so provider API budgets update.
pub fn applyThinking(state: *LiveState, level: []const u8) !void {
    const stable_level = if (state.owned_thinking) |slot| blk: {
        const copy = try state.gpa.dupe(u8, level);
        if (slot.*) |old| state.gpa.free(old);
        slot.* = copy;
        break :blk @as([]const u8, copy);
    } else level;

    state.thinking = stable_level;
    state.agent_cfg.reasoning_level = stable_level;
    if (state.client_pool) |pool| pool.setThinkingFromString(stable_level);
    try rebuildSystemFromBase(state, stable_level);
}

fn freeStringSlice(gpa: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| gpa.free(value);
    gpa.free(values);
}

fn finishReloadStatus(state: *LiveState, context_count: usize, skill_count: usize) ![]u8 {
    if (state.runtime_reload_fn) |reload| {
        const runtime = reload(state.runtime_reload_ctx) catch |err| {
            return std.fmt.allocPrint(
                state.gpa,
                "Reloaded: {d} context file(s), {d} skill(s); runtime resources unchanged ({s})",
                .{ context_count, skill_count, @errorName(err) },
            );
        };
        return std.fmt.allocPrint(
            state.gpa,
            "Reloaded: {d} context file(s), {d} skill(s), {d} extension(s), {d} command(s), {d} prompt template(s), {d} theme(s){s}{s}{s}{s}",
            .{
                context_count,
                skill_count,
                runtime.extensions,
                runtime.commands,
                runtime.prompts,
                runtime.themes,
                if (runtime.keybindings_reloaded) ", keybindings" else "",
                if (runtime.settings_reloaded) ", settings" else "",
                if (runtime.models_reloaded) ", models" else "",
                if (runtime.credentials_reloaded) ", credentials" else "",
            },
        );
    }
    return std.fmt.allocPrint(
        state.gpa,
        "Reloaded: {d} context file(s), {d} skill(s) — applied to subsequent turns",
        .{ context_count, skill_count },
    );
}

/// Re-read context/skills from disk and update agent_cfg for subsequent turns.
/// Returns a short status line (caller frees).
pub fn applyReload(state: *LiveState) ![]u8 {
    var bundle_storage: ?context_mod.ContextBundle = null;
    defer if (bundle_storage) |*bundle| bundle.deinit(state.gpa);
    if (state.include_context_files) {
        bundle_storage = try context_mod.discoverTrusted(state.gpa, state.io, state.cwd, state.agent_dir, state.trust_project);
    }

    var package_resources = packages_mod.Resources.init(state.gpa);
    defer package_resources.deinit();
    var top_resources = top_level_resources_mod.Resources.init(state.gpa);
    defer top_resources.deinit();
    if (state.include_context_files and state.include_skills) {
        if (state.agent_dir) |agent_dir| {
            const packages = try packages_mod.listConfigured(
                state.gpa,
                state.io,
                agent_dir,
                state.cwd,
                state.trust_project,
            );
            defer {
                for (packages) |*package| package.deinit(state.gpa);
                state.gpa.free(packages);
            }
            package_resources.deinit();
            package_resources = try packages_mod.resolveResources(state.gpa, state.io, packages);
            top_resources.deinit();
            top_resources = try top_level_resources_mod.resolve(state.gpa, state.io, agent_dir, state.cwd, state.trust_project);
        }
    }

    var skills: []skills_mod.Skill = try state.gpa.alloc(skills_mod.Skill, 0);
    if (state.include_context_files and state.include_skills) {
        state.gpa.free(skills);
        var resolved_skill_paths: std.ArrayList([]const u8) = .empty;
        defer resolved_skill_paths.deinit(state.gpa);
        try resolved_skill_paths.appendSlice(state.gpa, top_resources.skills.items);
        try resolved_skill_paths.appendSlice(state.gpa, package_resources.skills.items);
        skills = if (state.agent_dir != null)
            try skills_mod.loadTrusted(
                state.gpa,
                state.io,
                state.cwd,
                state.agent_dir,
                state.trust_project,
                resolved_skill_paths.items,
                false,
            )
        else
            try skills_mod.discoverTrusted(
                state.gpa,
                state.io,
                state.cwd,
                state.agent_dir,
                package_resources.skills.items,
                state.trust_project,
            );
        if (state.selected_skill_names.len > 0) {
            skills = try skills_mod.filterByNames(state.gpa, skills, state.selected_skill_names);
        }
    }
    defer {
        for (skills) |*skill| skill.deinit(state.gpa);
        state.gpa.free(skills);
    }

    const skills_summary = try skills_mod.summarize(state.gpa, skills);
    defer state.gpa.free(skills_summary);
    if (state.owned_skills_summary.*) |old| state.gpa.free(old);
    state.owned_skills_summary.* = try state.gpa.dupe(u8, skills_summary);

    if (state.owned_context.*) |old| state.gpa.free(old);
    const new_context = if (bundle_storage) |bundle|
        try context_mod.assembleContextPrompt(state.gpa, bundle.files)
    else
        try state.gpa.dupe(u8, "");
    state.owned_context.* = new_context;
    state.agent_cfg.context_prompt = new_context;

    const bundle_override = if (bundle_storage) |bundle| bundle.system_override else null;
    const bundle_append = if (bundle_storage) |bundle| bundle.append_system else "";
    const new_base = try system_prompt.assemble(state.gpa, .{
        .base_prompt = state.cli_system_override orelse bundle_override orelse agent_loop.default_system_prompt,
        .system_override = state.cli_system_override orelse bundle_override,
        .append_system = bundle_append,
        .skills_summary = state.owned_skills_summary.* orelse "",
        .extra_appends = state.cli_system_appends,
        .thinking_level = null,
    });
    errdefer state.gpa.free(new_base);

    if (state.owned_system_base) |base_slot| {
        if (base_slot.*) |old| state.gpa.free(old);
        base_slot.* = new_base;
    } else {
        // Legacy/embedder state has no retained-base slot. Use the base directly
        // as current prompt and let a subsequent thinking change rebuild normally.
        if (state.owned_system.*) |old| state.gpa.free(old);
        state.owned_system.* = new_base;
        state.agent_cfg.system_prompt = new_base;
        if (state.thinking) |level| {
            const with_thinking = try system_prompt.assemble(state.gpa, .{
                .system_override = new_base,
                .thinking_level = level,
            });
            state.owned_system.* = with_thinking;
            state.agent_cfg.system_prompt = with_thinking;
            state.gpa.free(new_base);
        }
        return finishReloadStatus(state, if (bundle_storage) |bundle| bundle.files.len else 0, skills.len);
    }

    try rebuildSystemFromBase(state, state.thinking);
    return finishReloadStatus(state, if (bundle_storage) |bundle| bundle.files.len else 0, skills.len);
}

test "applyModel mutates active client model field" {
    const gpa = std.testing.allocator;
    var display: ?[]const u8 = try gpa.dupe(u8, "old-model");
    defer if (display) |d| gpa.free(d);
    var owned_flag = true;
    var client_model: []const u8 = display.?;
    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var prov: ?[]const u8 = null;

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = &client_model,
        .model_display_owned = &owned_flag,
        .provider_name = &prov,
    };

    try applyModel(&state, "new-model-id");
    try std.testing.expectEqualStrings("new-model-id", display.?);
    try std.testing.expectEqualStrings("new-model-id", client_model);
    // Same pointer so OpenAI/Anthropic client.model field sees the change
    try std.testing.expect(display.?.ptr == client_model.ptr);
}

test "persisted default joins a non-empty model scope once" {
    const gpa = std.testing.allocator;
    var display: ?[]const u8 = "gpt-a";
    var display_owned = false;
    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    var owned_ctx: ?[]u8 = null;
    var owned_skills: ?[]u8 = null;
    const models = [_]providers.ModelInfo{
        .{ .provider = .openai, .id = "gpt-a", .display = "GPT A" },
        .{ .provider = .anthropic, .id = "claude-b", .display = "Claude B" },
    };
    const initial = [_]model_resolver.ScopedModel{.{ .model = models[0] }};
    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .model_display_owned = &display_owned,
        .model_scope = &initial,
    };
    defer state.deinitDynamicCatalog();
    try addPersistedDefaultToScope(&state, models[1]);
    try std.testing.expectEqual(@as(usize, 2), state.model_scope.len);
    try std.testing.expectEqualStrings("claude-b", state.model_scope[1].model.id);
    try addPersistedDefaultToScope(&state, models[1]);
    try std.testing.expectEqual(@as(usize, 2), state.model_scope.len);
}

test "applyModel without client pool resolves canonical provider identity" {
    const gpa = std.testing.allocator;
    var display: ?[]const u8 = try gpa.dupe(u8, "old-model");
    defer if (display) |value| gpa.free(value);
    var display_owned = true;
    var active_model: []const u8 = display.?;
    var provider_name: ?[]const u8 = "mock";
    var cfg = agent_loop.AgentConfig{ .provider_name = "mock", .model_id = "old-model" };
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |value| gpa.free(value);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |value| gpa.free(value);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |value| gpa.free(value);

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = &active_model,
        .model_display_owned = &display_owned,
        .provider_name = &provider_name,
    };

    try applyModel(&state, "openai/gpt-4.1-mini");
    try std.testing.expectEqualStrings("openai", provider_name.?);
    try std.testing.expectEqualStrings("openai", cfg.provider_name.?);
    try std.testing.expectEqualStrings("gpt-4.1-mini", display.?);
    try std.testing.expectEqualStrings("gpt-4.1-mini", active_model);
    try std.testing.expectEqualStrings("gpt-4.1-mini", cfg.model_id.?);
    const selected = activeModelInfo(&state).?;
    try std.testing.expectEqualStrings("openai", selected.providerName());
    try std.testing.expectEqualStrings("gpt-4.1-mini", selected.id);
    try std.testing.expectEqual(selected.context_window, cfg.compaction_context_window);
}

test "model switch thinking uses explicit scope and clamps to capabilities" {
    const gpa = std.testing.allocator;
    var display: ?[]const u8 = "plain";
    var owned_flag = false;
    var cfg = agent_loop.AgentConfig{ .reasoning_level = "high" };
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |value| gpa.free(value);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |value| gpa.free(value);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |value| gpa.free(value);
    var provider_name: ?[]const u8 = "openai";
    const plain = providers.ModelInfo{ .provider = .openai, .id = "plain", .display = "Plain", .reasoning = false };
    const scoped = [_]model_resolver.ScopedModel{.{ .model = plain, .thinking_level = .high }};
    const catalog = [_]providers.ModelInfo{plain};
    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .thinking = "high",
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .model_display_owned = &owned_flag,
        .provider_name = &provider_name,
        .model_catalog = &catalog,
        .model_scope = &scoped,
    };
    try std.testing.expectEqual(thinking_mod.ThinkingLevel.high, scopedThinkingForModel(&state, plain).?);
    try std.testing.expect(try applyThinkingForModelSwitch(&state, plain, scopedThinkingForModel(&state, plain)));
    try std.testing.expectEqualStrings("off", state.thinking.?);
    try std.testing.expectEqualStrings("off", cfg.reasoning_level.?);
    try std.testing.expect(!try applyThinkingForModelSwitch(&state, plain, null));
}

test "applyReload updates agent_cfg context from AGENTS.md" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    const agents_path = try std.fs.path.join(gpa, &.{ root, "AGENTS.md" });
    defer gpa.free(agents_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents_path, .data = "agents-v1-token" });

    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |s| gpa.free(s);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |c| gpa.free(c);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |s| gpa.free(s);
    var display: ?[]const u8 = null;
    var owned_flag = false;
    var prov: ?[]const u8 = null;

    var state = LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .agent_dir = null,
        .trust_project = true,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = null,
        .model_display_owned = &owned_flag,
        .provider_name = &prov,
    };

    const msg1 = try applyReload(&state);
    defer gpa.free(msg1);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v1-token") != null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = agents_path, .data = "agents-v2-UNIQUE-TOKEN" });
    const msg2 = try applyReload(&state);
    defer gpa.free(msg2);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v2-UNIQUE-TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.context_prompt, "agents-v1-token") == null);
}

test "ClientPool named gateway uses its own env key and base URL" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("GROQ_API_KEY", "gsk-runtime-test");

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setKeys(null, null, null, "https://api.openai.com/v1");
    pool.setRuntimeConfig(&env, .openai, "openai", null, "https://api.openai.com/v1");

    try pool.switchTo(.groq, "llama-3.3-70b-versatile");
    try std.testing.expect(pool.active_provider == .groq);
    try std.testing.expectEqualStrings("gsk-runtime-test", pool.openai.?.api_key);
    try std.testing.expectEqualStrings("https://api.groq.com/openai/v1", pool.openai.?.base_url);
}

test "ClientPool preserves primary custom base URL" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setKeys(null, null, null, "https://api.openai.com/v1");
    pool.setRuntimeConfig(&env, .openrouter, "openrouter", "or-test", "https://proxy.example/v1");

    try pool.switchTo(.openrouter, "anthropic/claude-sonnet-4");
    try std.testing.expect(pool.active_provider == .openrouter);
    try std.testing.expectEqualStrings("or-test", pool.openai.?.api_key);
    try std.testing.expectEqualStrings("https://proxy.example/v1", pool.openai.?.base_url);
}

test "ClientPool propagates provider retry policy across client switches" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setKeys("openai-key", "anthropic-key", "google-key", "https://api.openai.com/v1");
    pool.setRuntimeConfig(&env, .openai, "openai", "openai-key", "https://api.openai.com/v1");
    pool.setProviderRetryPolicy(.{ .timeout_ms = 1_234, .max_retries = 5, .max_retry_delay_ms = 9_876 });

    try pool.switchTo(.openai, "gpt-4o");
    try std.testing.expectEqual(@as(?u64, 1_234), pool.openai.?.provider_retry.timeout_ms);
    try std.testing.expectEqual(@as(usize, 5), pool.openai.?.provider_retry.max_retries);
    try std.testing.expectEqual(@as(u64, 9_876), pool.openai.?.provider_retry.max_retry_delay_ms);

    // Existing clients are updated in place as well, which is the path used by
    // a transactional settings reload before the next model switch.
    pool.anthropic = .{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = "anthropic-key",
        .base_url = "https://api.anthropic.com",
        .model = "claude-sonnet-4-20250514",
    };
    pool.setProviderRetryPolicy(.{ .timeout_ms = 2_468, .max_retries = 6, .max_retry_delay_ms = 19_752 });
    try std.testing.expectEqual(@as(?u64, 2_468), pool.openai.?.provider_retry.timeout_ms);
    try std.testing.expectEqual(@as(?u64, 2_468), pool.anthropic.?.provider_retry.timeout_ms);
    try std.testing.expectEqual(@as(usize, 6), pool.anthropic.?.provider_retry.max_retries);
    try std.testing.expectEqual(@as(u64, 19_752), pool.anthropic.?.provider_retry.max_retry_delay_ms);
}

test "applyModel fuzzy selection switches concrete provider" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("OPENAI_API_KEY", "sk-openai");
    try env.put("XAI_API_KEY", "xai-key");

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setKeys("sk-openai", null, null, "https://api.openai.com/v1");
    pool.setRuntimeConfig(&env, .openai, "openai", "sk-openai", "https://api.openai.com/v1");
    try pool.switchTo(.openai, "gpt-4o");

    var display: ?[]const u8 = null;
    var owned_flag = false;
    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |v| gpa.free(v);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |v| gpa.free(v);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |v| gpa.free(v);
    var provider_name: ?[]const u8 = "openai";

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = pool.modelPtr(),
        .model_display_owned = &owned_flag,
        .client_pool = &pool,
        .provider_name = &provider_name,
    };
    defer if (owned_flag) if (display) |v| gpa.free(v);

    try applyModel(&state, "grok-4.5");
    try std.testing.expect(pool.active_provider == .openai);
    try std.testing.expectEqualStrings("xai", provider_name.?);
    try std.testing.expectEqualStrings("grok-4.5", display.?);
    try std.testing.expectEqualStrings("https://api.x.ai/v1", pool.responses.?.base_url);
    try std.testing.expectEqualStrings("xai-key", pool.responses.?.api_key);
}

test "applyModel hot-switches into arbitrary models.json provider identity" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    const runtime = [_]RuntimeProviderConfig{
        .{ .id = "corp", .transport = .openai, .api_key = "corp-hot-key", .base_url = "https://corp.example/v1" },
        .{ .id = "claude-proxy", .transport = .anthropic, .api_key = "anthropic-hot-key", .base_url = "https://claude-proxy.example" },
    };
    const catalog = [_]providers.ModelInfo{
        .{ .provider = .openai, .provider_id = "corp", .id = "corp-model", .display = "Corp Model" },
        .{ .provider = .anthropic, .provider_id = "claude-proxy", .id = "sonnet-proxy", .display = "Sonnet Proxy" },
    };

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setKeys("openai-key", null, null, "https://api.openai.com/v1");
    pool.setRuntimeConfig(&env, .openai, "openai", "openai-key", "https://api.openai.com/v1");
    pool.setRuntimeProviders(&runtime);
    try pool.switchTo(.openai, "gpt-4o");

    var display: ?[]const u8 = null;
    var display_owned = false;
    var cfg = agent_loop.AgentConfig{};
    var owned_sys: ?[]u8 = null;
    defer if (owned_sys) |v| gpa.free(v);
    var owned_ctx: ?[]u8 = null;
    defer if (owned_ctx) |v| gpa.free(v);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |v| gpa.free(v);
    var provider_name: ?[]const u8 = "openai";

    var state = LiveState{
        .gpa = gpa,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = &cfg,
        .owned_system = &owned_sys,
        .owned_context = &owned_ctx,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .active_model = pool.modelPtr(),
        .model_display_owned = &display_owned,
        .client_pool = &pool,
        .provider_name = &provider_name,
        .model_catalog = &catalog,
    };
    defer if (display_owned) if (display) |v| gpa.free(v);

    try applyModel(&state, "corp/corp-model");
    try std.testing.expectEqualStrings("corp", pool.active_provider_id);
    try std.testing.expectEqualStrings("corp", provider_name.?);
    try std.testing.expectEqualStrings("corp-hot-key", pool.openai.?.api_key);
    try std.testing.expectEqualStrings("https://corp.example/v1", pool.openai.?.base_url);

    try applyModel(&state, "claude-proxy/sonnet-proxy");
    try std.testing.expect(pool.active_provider == .anthropic);
    try std.testing.expectEqualStrings("claude-proxy", pool.active_provider_id);
    try std.testing.expectEqualStrings("anthropic-hot-key", pool.anthropic.?.api_key);
    try std.testing.expectEqualStrings("https://claude-proxy.example", pool.anthropic.?.base_url);
}

test "ClientPool prefers model-specific runtime over provider fallback" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{
        .{ .id = "corp", .transport = .openai, .api_key = "provider-key", .base_url = "https://provider.example/v1" },
        .{ .id = "corp", .model_id = "special", .transport = .openai, .api_key = "special-key", .base_url = "https://special.example/v1" },
    };
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "other", null, "https://unused.example/v1");
    pool.setRuntimeProviders(&runtime);

    try pool.switchToIdentity("corp", .openai, "special");
    try std.testing.expectEqualStrings("special-key", pool.openai.?.api_key);
    try std.testing.expectEqualStrings("https://special.example/v1", pool.openai.?.base_url);

    try pool.switchToIdentity("corp", .openai, "ordinary");
    try std.testing.expectEqualStrings("provider-key", pool.openai.?.api_key);
    try std.testing.expectEqualStrings("https://provider.example/v1", pool.openai.?.base_url);
}

test "ClientPool dispatches custom pi-messages runtime without collapsing provider identity" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "corp-radius",
        .model_id = "auto",
        .transport = .radius,
        .api = .pi_messages,
        .api_key = "radius-key",
        .base_url = "https://radius.example/v1",
        .max_tokens = 4096,
    }};
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "openai", null, "https://api.openai.com/v1");
    pool.setRuntimeProviders(&runtime);
    pool.setSessionContext("session-pi", .long);
    pool.setThinking(.high);

    try pool.switchToIdentity("corp-radius", .radius, "auto");
    try std.testing.expect(pool.active_provider == .radius);
    try std.testing.expect(pool.active_api == .pi_messages);
    try std.testing.expectEqualStrings("corp-radius", pool.active_provider_id);
    try std.testing.expectEqualStrings("radius-key", pool.pi_messages.?.api_key);
    try std.testing.expectEqualStrings("https://radius.example/v1", pool.pi_messages.?.base_url);
    try std.testing.expectEqualStrings("session-pi", pool.pi_messages.?.session_id.?);
    try std.testing.expect(pool.pi_messages.?.cache_retention == .long);
    try std.testing.expect(pool.pi_messages.?.thinking == .high);
    try std.testing.expectEqual(@as(u64, 4096), pool.pi_messages.?.max_tokens);
}

test "ClientPool dispatches custom Bedrock runtime with bearer auth metadata" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "corp-bedrock",
        .model_id = "anthropic.claude-test",
        .transport = .amazon_bedrock,
        .api = .bedrock_converse_stream,
        .api_key = "bedrock-bearer",
        .base_url = "https://bedrock-runtime.eu-west-2.amazonaws.com",
        .max_tokens = 8192,
        .model_cost = .{ .input = 3, .output = 15, .cache_read = 0.3, .cache_write = 3.75 },
    }};
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "openai", null, "https://api.openai.com/v1");
    pool.setRuntimeProviders(&runtime);
    pool.setSessionContext("session-bedrock", .long);
    pool.setThinking(.high);

    try pool.switchToIdentity("corp-bedrock", .amazon_bedrock, "anthropic.claude-test");
    try std.testing.expect(pool.active_provider == .amazon_bedrock);
    try std.testing.expect(pool.active_api == .bedrock_converse_stream);
    try std.testing.expectEqualStrings("corp-bedrock", pool.active_provider_id);
    try std.testing.expectEqualStrings("bedrock-bearer", pool.bedrock.?.api_key);
    try std.testing.expectEqualStrings("https://bedrock-runtime.eu-west-2.amazonaws.com", pool.bedrock.?.base_url);
    try std.testing.expect(pool.bedrock.?.cache_retention == .long);
    try std.testing.expect(pool.bedrock.?.thinking == .high);
    try std.testing.expectEqual(@as(u64, 8192), pool.bedrock.?.max_tokens);
}

test "ClientPool dispatches built-in Bedrock with ambient SigV4 credentials" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_ACCESS_KEY_ID", "AKIA_TEST");
    try env.put("AWS_SECRET_ACCESS_KEY", "secret-test");
    try env.put("AWS_SESSION_TOKEN", "session-test");
    try env.put("AWS_REGION", "eu-west-2");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});

    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expectEqualStrings("", pool.bedrock.?.api_key);
    try std.testing.expectEqualStrings("AKIA_TEST", pool.bedrock.?.aws_credentials.?.access_key_id);
    try std.testing.expectEqualStrings("secret-test", pool.bedrock.?.aws_credentials.?.secret_access_key);
    try std.testing.expectEqualStrings("session-test", pool.bedrock.?.aws_credentials.?.session_token.?);
    try std.testing.expectEqualStrings("eu-west-2", pool.bedrock.?.region.?);
}

test "ClientPool hot-switches GitHub Copilot across native APIs" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{
        .{ .id = "github-copilot", .model_id = "gpt-5-mini", .transport = .openai, .api = .openai_responses, .api_key = "copilot-token", .base_url = "https://api.individual.githubcopilot.com" },
        .{ .id = "github-copilot", .model_id = "claude-sonnet-4.6", .transport = .anthropic, .api = .anthropic_messages, .api_key = "copilot-token", .base_url = "https://api.individual.githubcopilot.com" },
    };
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "github-copilot", "copilot-token", "https://api.individual.githubcopilot.com");
    pool.setRuntimeProviders(&runtime);

    try pool.switchToIdentity("github-copilot", .openai, "gpt-5-mini");
    try std.testing.expect(pool.responses != null);
    try std.testing.expect(pool.active_api == .openai_responses);
    try std.testing.expectEqualStrings("github-copilot", pool.responses.?.provider_id);

    try pool.switchToIdentity("github-copilot", .anthropic, "claude-sonnet-4.6");
    try std.testing.expect(pool.anthropic != null);
    try std.testing.expect(pool.active_api == .anthropic_messages);
    try std.testing.expectEqualStrings("github-copilot", pool.anthropic.?.provider_id);
}

test "ClientPool session context survives model switches" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{
        .{ .id = "corp", .model_id = "chat", .transport = .openai, .api = .openai_completions, .api_key = "k", .base_url = "https://example.test/v1" },
        .{ .id = "corp", .model_id = "resp", .transport = .openai, .api = .openai_responses, .api_key = "k", .base_url = "https://example.test/v1" },
    };
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "corp", "k", "https://example.test/v1");
    pool.setRuntimeProviders(&runtime);
    pool.setSessionContext("session-stable", .long);
    try pool.switchToIdentity("corp", .openai, "chat");
    try std.testing.expectEqualStrings("session-stable", pool.openai.?.session_id.?);
    try std.testing.expect(pool.openai.?.cache_retention == .long);
    try pool.switchToIdentity("corp", .openai, "resp");
    try std.testing.expectEqualStrings("session-stable", pool.responses.?.session_id.?);
    try std.testing.expect(pool.responses.?.cache_retention == .long);
}

test "ClientPool dispatches Bedrock with selected AWS shared profile" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "credentials", .data = "[research]\naws_access_key_id = AKIA_PROFILE\naws_secret_access_key = profile-secret\naws_session_token = profile-session\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "[profile research]\nregion = ap-southeast-2\n" });
    const cred_path = try tmp.dir.realPathFileAlloc(std.testing.io, "credentials", gpa);
    defer gpa.free(cred_path);
    const config_path = try tmp.dir.realPathFileAlloc(std.testing.io, "config", gpa);
    defer gpa.free(config_path);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_PROFILE", "research");
    try env.put("AWS_SHARED_CREDENTIALS_FILE", cred_path);
    try env.put("AWS_CONFIG_FILE", config_path);

    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expectEqualStrings("AKIA_PROFILE", pool.bedrock.?.aws_credentials.?.access_key_id);
    try std.testing.expectEqualStrings("profile-secret", pool.bedrock.?.aws_credentials.?.secret_access_key);
    try std.testing.expectEqualStrings("profile-session", pool.bedrock.?.aws_credentials.?.session_token.?);
    try std.testing.expectEqualStrings("ap-southeast-2", pool.bedrock.?.region.?);
}

test "Bedrock environment keys outrank profile keys while profile supplies region" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "credentials", .data = "[research]\naws_access_key_id=AKIA_PROFILE\naws_secret_access_key=profile-secret\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "[profile research]\nregion=eu-north-1\n" });
    const cred_path = try tmp.dir.realPathFileAlloc(std.testing.io, "credentials", gpa);
    defer gpa.free(cred_path);
    const config_path = try tmp.dir.realPathFileAlloc(std.testing.io, "config", gpa);
    defer gpa.free(config_path);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_PROFILE", "research");
    try env.put("AWS_SHARED_CREDENTIALS_FILE", cred_path);
    try env.put("AWS_CONFIG_FILE", config_path);
    try env.put("AWS_ACCESS_KEY_ID", "AKIA_ENV");
    try env.put("AWS_SECRET_ACCESS_KEY", "env-secret");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expectEqualStrings("AKIA_ENV", pool.bedrock.?.aws_credentials.?.access_key_id);
    try std.testing.expectEqualStrings("eu-north-1", pool.bedrock.?.region.?);
}

test "ClientPool accepts Bedrock web identity lazily" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_ROLE_ARN", "arn:aws:iam::123456789012:role/pi-zig-test");
    try env.put("AWS_WEB_IDENTITY_TOKEN_FILE", "/tmp/pi-zig-no-network-token");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expect(pool.bedrock.?.aws_credentials == null);
    try std.testing.expect(pool.bedrock.?.credential_refresh_fn != null);
}

test "ClientPool accepts Bedrock credential_process lazily" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "[profile proc]\nregion=us-west-2\ncredential_process=/definitely/not/executed --json\n" });
    const config_path = try tmp.dir.realPathFileAlloc(std.testing.io, "config", gpa);
    defer gpa.free(config_path);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_PROFILE", "proc");
    try env.put("AWS_CONFIG_FILE", config_path);
    try env.put("AWS_SHARED_CREDENTIALS_FILE", "/definitely/missing");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expect(pool.bedrock.?.aws_credentials == null);
    try std.testing.expect(pool.bedrock.?.credential_refresh_fn != null);
    try std.testing.expectEqualStrings("us-west-2", pool.bedrock.?.region.?);
}

test "ClientPool accepts Bedrock container credentials lazily" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI", "/v2/credentials/test");
    try env.put("AWS_SHARED_CREDENTIALS_FILE", "/definitely/missing");
    try env.put("AWS_CONFIG_FILE", "/definitely/missing");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expect(pool.bedrock.?.aws_credentials == null);
    try std.testing.expect(pool.bedrock.?.credential_refresh_fn != null);
}

test "ClientPool accepts Bedrock IMDS lazily when metadata is enabled" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_SHARED_CREDENTIALS_FILE", "/definitely/missing");
    try env.put("AWS_CONFIG_FILE", "/definitely/missing");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expect(pool.bedrock.?.aws_credentials == null);
    try std.testing.expect(pool.bedrock.?.credential_refresh_fn != null);
}

test "ClientPool rejects credentialless Bedrock when IMDS is disabled" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_EC2_METADATA_DISABLED", "true");
    try env.put("AWS_SHARED_CREDENTIALS_FILE", "/definitely/missing");
    try env.put("AWS_CONFIG_FILE", "/definitely/missing");
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try std.testing.expectError(error.MissingApiKey, pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0"));
}

test "ClientPool accepts source_profile AssumeRole lazily" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "credentials", .data = "[base]\naws_access_key_id=AKIA_BASE\naws_secret_access_key=base-secret\n" });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "config", .data = "[profile cross]\nrole_arn=arn:aws:iam::123456789012:role/Cross\nsource_profile=base\nregion=eu-west-1\n" });
    const cp = try tmp.dir.realPathFileAlloc(std.testing.io, "credentials", gpa);
    defer gpa.free(cp);
    const fp = try tmp.dir.realPathFileAlloc(std.testing.io, "config", gpa);
    defer gpa.free(fp);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("AWS_PROFILE", "cross");
    try env.put("AWS_SHARED_CREDENTIALS_FILE", cp);
    try env.put("AWS_CONFIG_FILE", fp);
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .amazon_bedrock, "amazon-bedrock", null, "https://bedrock-runtime.us-east-1.amazonaws.com");
    pool.setPrimaryModelRuntime(.bedrock_converse_stream, .{});
    try pool.switchToIdentity("amazon-bedrock", .amazon_bedrock, "anthropic.claude-sonnet-4-20250514-v1:0");
    try std.testing.expect(pool.bedrock.?.aws_credentials == null);
    try std.testing.expect(pool.bedrock.?.credential_refresh_fn != null);
    try std.testing.expectEqualStrings("AKIA_BASE", pool.aws_source_profile.?.staticCredentials().?.access_key_id);
    try std.testing.expectEqualStrings("eu-west-1", pool.bedrock.?.region.?);
}

test "ClientPool wires stored Radius OAuth expiry and custom gateway" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "radius-dev",
        .model_id = "auto",
        .transport = .radius,
        .api = .pi_messages,
        .api_key = "old-access",
        .oauth_refresh = "refresh-1",
        .oauth_expires_ms = 42,
        .base_url = "http://localhost:8788/v1",
    }};
    var pool = ClientPool{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .radius, "radius-dev", "old-access", "http://localhost:8788/v1");
    pool.setRuntimeProviders(&runtime);
    try pool.switchToIdentity("radius-dev", .radius, "auto");
    try std.testing.expectEqualStrings("old-access", pool.pi_messages.?.api_key);
    try std.testing.expectEqual(@as(?i64, 42), pool.pi_messages.?.token_expiration_ms);
    try std.testing.expect(pool.pi_messages.?.token_refresh_fn != null);
    try std.testing.expectEqualStrings("http://localhost:8788", pool.radius_gateway.?);
    try std.testing.expectEqualStrings("refresh-1", pool.radius_initial_refresh.?);
}

test "interactive Radius OAuth credential overrides startup runtime snapshot" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var pool: ClientPool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .radius, "radius-dev", null, "http://localhost:8788/v1");
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "radius-dev",
        .model_id = "auto",
        .transport = .radius,
        .api = .pi_messages,
        .api_key = null,
        .base_url = "http://localhost:8788/v1",
    }};
    pool.setRuntimeProviders(&runtime);
    var token = radius_oauth.Token{
        .access = try gpa.dupe(u8, "live-access"),
        .refresh = try gpa.dupe(u8, "live-refresh"),
        .expires_ms = 9_999_999_999_999,
        .scope = try gpa.dupe(u8, "gateway offline_access"),
    };
    defer token.deinit(gpa);
    try pool.installOAuthCredential("radius-dev", &token);
    try pool.switchToIdentity("radius-dev", .radius, "auto");
    try std.testing.expectEqualStrings("live-access", pool.pi_messages.?.api_key);
    try std.testing.expectEqualStrings("live-refresh", pool.radius_initial_refresh.?);
}

test "interactive API key credential is owned and removable" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var pool: ClientPool = .{ .gpa = gpa, .io = io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "openai", null, "https://api.openai.com/v1");

    var source = [_]u8{ 'l', 'i', 'v', 'e', '-', 'k', 'e', 'y' };
    try pool.installApiKeyCredential("openai", &source);
    source[0] = 'X';
    try std.testing.expectEqualStrings("live-key", pool.keyForIdentity("openai", .openai, "gpt-test").?);
    try pool.switchToIdentity("openai", .openai, "gpt-test");
    try std.testing.expectEqualStrings("live-key", pool.openai.?.api_key);
    try std.testing.expect(!pool.removeLiveCredential("anthropic"));
    try std.testing.expect(pool.removeLiveCredential("OPENAI"));
    try std.testing.expect(pool.keyForIdentity("openai", .openai, "gpt-test") == null);
}

test "live credential snapshot clears and restores owned API key" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    pool.setRuntimeConfig(&env, .openai, "openai", null, "https://api.openai.com/v1");

    try pool.installApiKeyCredential("openai", "snapshot-key-177");
    var snapshot = try pool.snapshotLiveCredential();
    defer snapshot.deinit();
    pool.clearLiveCredentialForReload();
    try std.testing.expect(pool.keyForIdentity("openai", .openai, "gpt-test") == null);

    pool.restoreLiveCredentialSnapshot(&snapshot);
    try std.testing.expectEqualStrings("snapshot-key-177", pool.keyForIdentity("openai", .openai, "gpt-test").?);
    try std.testing.expect(snapshot.provider_id == null);
    try std.testing.expect(snapshot.credential == null);
}

test "dynamic Radius catalog reload rebuilds model and runtime snapshots" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const models_path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(models_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = models_path, .data = "{\"providers\":{\"radius-dev\":{\"baseUrl\":\"http://dev\",\"oauth\":\"radius\"}}}" });
    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    try store.setOAuth("radius-dev", .{ .refresh = @constCast("r"), .access = @constCast("a"), .expires = 9999999999999 });
    const store_path = try std.fs.path.join(gpa, &.{ root, "models-store.json" });
    defer gpa.free(store_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = store_path, .data = "{\"radius-dev\":{\"models\":[{\"id\":\"fresh\",\"name\":\"Fresh\",\"api\":\"pi-messages\",\"provider\":\"radius-dev\",\"baseUrl\":\"http://dev/v1\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{},\"contextWindow\":4096,\"maxTokens\":512}]}}" });
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const old = [_]RuntimeProviderConfig{.{ .id = "corp", .model_id = "m", .transport = .openai, .api = .openai_completions, .api_key = "k", .base_url = "http://corp/v1" }};
    var snapshot = try loadDynamicAuthCatalog(gpa, io, &env, root, &old);
    defer snapshot.deinit();
    var saw_model = false;
    var saw_radius_runtime = false;
    var saw_old = false;
    for (snapshot.model_catalog) |model| {
        if (std.mem.eql(u8, model.providerName(), "radius-dev") and std.mem.eql(u8, model.id, "fresh")) saw_model = true;
    }
    for (snapshot.runtime_configs) |runtime| {
        if (std.mem.eql(u8, runtime.id, "radius-dev") and runtime.model_id != null and std.mem.eql(u8, runtime.model_id.?, "fresh")) {
            saw_radius_runtime = std.mem.eql(u8, runtime.base_url.?, "http://dev/v1") and std.mem.eql(u8, runtime.api_key.?, "a");
        }
        if (std.mem.eql(u8, runtime.id, "corp")) saw_old = true;
    }
    try std.testing.expect(saw_model and saw_radius_runtime and saw_old);
}

test "dynamic catalog reload replaces models json runtime and auth without retaining removed providers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];
    const models_path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(models_path);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = models_path,
        .data =
        \\{"providers":{"corp":{"baseUrl":"https://one.invalid/v1","api":"openai-completions","models":[{"id":"m","contextWindow":4096,"maxTokens":512}]}}}
        ,
    });
    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    try store.setApiKey("corp", "secret-one");
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var first = try loadDynamicAuthCatalog(gpa, io, &env, root, &.{});
    defer first.deinit();
    var first_corp: ?RuntimeProviderConfig = null;
    for (first.runtime_configs) |runtime| {
        if (std.ascii.eqlIgnoreCase(runtime.id, "corp") and runtime.model_id != null and std.mem.eql(u8, runtime.model_id.?, "m")) first_corp = runtime;
    }
    try std.testing.expect(first_corp != null);
    try std.testing.expectEqualStrings("secret-one", first_corp.?.api_key.?);
    try std.testing.expectEqualStrings("https://one.invalid/v1", first_corp.?.base_url.?);

    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = models_path,
        .data =
        \\{"providers":{"corp":{"baseUrl":"https://two.invalid/v1","api":"openai-responses","models":[{"id":"m","contextWindow":8192,"maxTokens":1024}]}}}
        ,
    });
    try store.setApiKey("corp", "secret-two");
    var second = try loadDynamicAuthCatalog(gpa, io, &env, root, first.runtime_configs);
    defer second.deinit();
    var second_corp: ?RuntimeProviderConfig = null;
    for (second.runtime_configs) |runtime| {
        if (std.ascii.eqlIgnoreCase(runtime.id, "corp") and runtime.model_id != null and std.mem.eql(u8, runtime.model_id.?, "m")) second_corp = runtime;
    }
    try std.testing.expect(second_corp != null);
    try std.testing.expectEqualStrings("secret-two", second_corp.?.api_key.?);
    try std.testing.expectEqualStrings("https://two.invalid/v1", second_corp.?.base_url.?);
    try std.testing.expect(second_corp.?.api == .openai_responses);
    try std.testing.expectEqual(@as(u64, 8192), second_corp.?.context_window);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = models_path, .data = "{\"providers\":{}}" });
    var third = try loadDynamicAuthCatalogWithOptions(gpa, io, &env, root, second.runtime_configs, .{ .preserve_unmanaged_runtimes = false });
    defer third.deinit();
    for (third.runtime_configs) |runtime| {
        try std.testing.expect(!std.ascii.eqlIgnoreCase(runtime.id, "corp"));
    }
    for (third.model_catalog) |model| {
        try std.testing.expect(!std.ascii.eqlIgnoreCase(model.providerName(), "corp"));
    }
}

test "ClientPool owned reload keys and proxy do not borrow caller storage" {
    const gpa = std.testing.allocator;
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();

    var openai = [_]u8{ 'o', 'n', 'e' };
    var anthropic = [_]u8{ 't', 'w', 'o' };
    var google = [_]u8{ 't', 'h', 'r', 'e', 'e' };
    var proxy = [_]u8{ 'h', 't', 't', 'p', ':', '/', '/', 'p' };
    try pool.setKeysOwned(&openai, &anthropic, &google);
    try pool.setHttpProxyOwned(&proxy);
    @memset(&openai, 'x');
    @memset(&anthropic, 'x');
    @memset(&google, 'x');
    @memset(&proxy, 'x');
    try std.testing.expectEqualStrings("one", pool.openai_key.?);
    try std.testing.expectEqualStrings("two", pool.anthropic_key.?);
    try std.testing.expectEqualStrings("three", pool.google_key.?);
    try std.testing.expectEqualStrings("http://p", pool.http_proxy_url.?);

    try pool.setKeysOwned(null, "replacement", null);
    try pool.setHttpProxyOwned(null);
    try std.testing.expect(pool.openai_key == null);
    try std.testing.expectEqualStrings("replacement", pool.anthropic_key.?);
    try std.testing.expect(pool.google_key == null);
    try std.testing.expect(pool.http_proxy_url == null);
}

test "dynamic Copilot catalog reload synthesizes account model runtime" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..n];

    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    var ids = [_][]u8{@constCast("gpt-5.4")};
    try store.setOAuth("github-copilot", .{
        .refresh = @constCast("gh-refresh"),
        .access = @constCast("copilot-access"),
        .expires = 9_999_999_999_999,
        .available_model_ids = &ids,
        .available_model_ids_present = true,
    });

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var snapshot = try loadDynamicAuthCatalog(gpa, io, &env, root, &.{});
    defer snapshot.deinit();

    var model_ok = false;
    var runtime_ok = false;
    for (snapshot.model_catalog) |model| {
        if (!std.ascii.eqlIgnoreCase(model.providerName(), "github-copilot") or !std.mem.eql(u8, model.id, "gpt-5.4")) continue;
        model_ok = model.apiKind() == .openai_responses and
            model.context_window == 1_000_000 and model.max_tokens == 128_000;
    }
    for (snapshot.runtime_configs) |runtime| {
        if (!std.ascii.eqlIgnoreCase(runtime.id, "github-copilot") or runtime.model_id == null or
            !std.mem.eql(u8, runtime.model_id.?, "gpt-5.4")) continue;
        runtime_ok = runtime.transport == .openai and runtime.api == .openai_responses and
            runtime.context_window == 1_000_000 and runtime.max_tokens == 128_000 and
            runtime.api_key != null and std.mem.eql(u8, runtime.api_key.?, "copilot-access");
    }
    try std.testing.expect(model_ok);
    try std.testing.expect(runtime_ok);
}

test "ClientPool Codex live OAuth credential preserves accountId" {
    const gpa = std.testing.allocator;
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    var token = codex_oauth.Token{
        .access = try gpa.dupe(u8, "access-codex"),
        .refresh = try gpa.dupe(u8, "refresh-codex"),
        .expires_ms = 123456,
        .account_id = try gpa.dupe(u8, "acct-codex"),
    };
    defer token.deinit(gpa);
    try pool.installCodexOAuthCredential(&token);
    const cred = pool.liveCredentialForIdentity("openai-codex").?;
    try std.testing.expectEqualStrings("access-codex", cred.oauth.access);
    try std.testing.expectEqualStrings("refresh-codex", cred.oauth.refresh);
    try std.testing.expectEqualStrings("acct-codex", cred.oauth.account_id.?);
}

test "ClientPool owns pending Codex PKCE flow across commands" {
    const gpa = std.testing.allocator;
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    var flow = codex_oauth.AuthorizationFlow{
        .verifier = try gpa.dupe(u8, "verifier-1"),
        .state = try gpa.dupe(u8, "state-1"),
        .url = try gpa.dupe(u8, "https://auth.example/?state=state-1"),
    };
    defer flow.deinit(gpa);
    try pool.installCodexPendingFlow(&flow);
    flow.verifier[0] = 'X';
    try std.testing.expectEqualStrings("verifier-1", pool.codex_pending_flow.?.verifier);
    try std.testing.expectEqualStrings("state-1", pool.codex_pending_flow.?.state);
}

test "ClientPool stored Anthropic OAuth selects bearer mode with refresh" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "anthropic",
        .model_id = "claude-sonnet-4-6",
        .transport = .anthropic,
        .api = .anthropic_messages,
        .api_key = "sk-ant-oat-live",
        .oauth_refresh = "refresh-anthropic",
        .oauth_expires_ms = 12345,
        .base_url = "https://api.anthropic.com",
    }};
    pool.setRuntimeConfig(&env, .anthropic, "anthropic", "sk-ant-oat-live", "https://api.anthropic.com");
    pool.setRuntimeProviders(&runtime);
    try pool.switchToIdentity("anthropic", .anthropic, "claude-sonnet-4-6");
    try std.testing.expect(pool.anthropic != null);
    try std.testing.expect(pool.anthropic.?.auth_mode == .oauth);
    try std.testing.expectEqual(@as(?i64, 12345), pool.anthropic.?.token_expiration_ms);
    try std.testing.expect(pool.anthropic.?.token_refresh_fn != null);
}

test "ClientPool Anthropic environment auth token and OAuth token select distinct modes" {
    const gpa = std.testing.allocator;
    {
        var env = std.process.Environ.Map.init(gpa);
        defer env.deinit();
        try env.put(app_config.ENV_ANTHROPIC_AUTH_TOKEN, "bearer-auth-token");
        try env.put(app_config.ENV_ANTHROPIC_OAUTH_TOKEN, "sk-ant-oat-lower-priority");
        try env.put(app_config.ENV_ANTHROPIC_KEY, "api-key-lower-priority");
        var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
        defer pool.deinit();
        pool.setKeys(null, null, null, "https://api.openai.com/v1");
        pool.setRuntimeConfig(&env, .anthropic, "anthropic", null, "https://api.anthropic.com");
        pool.setPrimaryModelRuntime(.anthropic_messages, .{});
        try pool.switchToIdentity("anthropic", .anthropic, "claude-test");
        try std.testing.expectEqualStrings("bearer-auth-token", pool.anthropic.?.api_key);
        try std.testing.expect(pool.anthropic.?.auth_mode == .bearer);
    }
    {
        var env = std.process.Environ.Map.init(gpa);
        defer env.deinit();
        try env.put(app_config.ENV_ANTHROPIC_OAUTH_TOKEN, "sk-ant-oat-env-only");
        try env.put(app_config.ENV_ANTHROPIC_KEY, "api-key-lower-priority");
        var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
        defer pool.deinit();
        pool.setKeys(null, null, null, "https://api.openai.com/v1");
        pool.setRuntimeConfig(&env, .anthropic, "anthropic", null, "https://api.anthropic.com");
        pool.setPrimaryModelRuntime(.anthropic_messages, .{});
        try pool.switchToIdentity("anthropic", .anthropic, "claude-test");
        try std.testing.expectEqualStrings("sk-ant-oat-env-only", pool.anthropic.?.api_key);
        try std.testing.expect(pool.anthropic.?.auth_mode == .oauth);
    }
}

test "ClientPool owns pending Anthropic PKCE flow across commands" {
    const gpa = std.testing.allocator;
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    var flow = anthropic_oauth.AuthorizationFlow{
        .verifier = try gpa.dupe(u8, "anthropic-verifier"),
        .url = try gpa.dupe(u8, "https://claude.ai/oauth/authorize?state=anthropic-verifier"),
    };
    defer flow.deinit(gpa);
    try pool.installAnthropicPendingFlow(&flow);
    flow.verifier[0] = 'X';
    try std.testing.expectEqualStrings("anthropic-verifier", pool.anthropic_pending_flow.?.verifier);
    try std.testing.expect(std.mem.indexOf(u8, pool.anthropic_pending_flow.?.url, "claude.ai/oauth/authorize") != null);
}

test "ClientPool stored Kimi OAuth uses Anthropic bearer mode with lazy refresh" {
    const gpa = std.testing.allocator;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();
    const runtime = [_]RuntimeProviderConfig{.{
        .id = "kimi-coding",
        .model_id = "k3",
        .transport = .kimi_coding,
        .api = .anthropic_messages,
        .api_key = "kimi-access",
        .oauth_refresh = "kimi-refresh",
        .oauth_expires_ms = 23456,
        .base_url = "https://api.kimi.com/coding",
        .reasoning = true,
    }};
    pool.setRuntimeConfig(&env, .kimi_coding, "kimi-coding", "kimi-access", "https://api.kimi.com/coding");
    pool.setRuntimeProviders(&runtime);
    try pool.switchToIdentity("kimi-coding", .kimi_coding, "k3");
    try std.testing.expect(pool.anthropic != null);
    try std.testing.expectEqualStrings("https://api.kimi.com/coding", pool.anthropic.?.base_url);
    try std.testing.expectEqualStrings("kimi-coding", pool.anthropic.?.provider_id);
    try std.testing.expect(pool.anthropic.?.auth_mode == .bearer);
    try std.testing.expectEqual(@as(?i64, 23456), pool.anthropic.?.token_expiration_ms);
    try std.testing.expect(pool.anthropic.?.token_refresh_fn != null);
}

test "reload honors top-level skill settings changes" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_len = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..path_len];
    const agent_dir = try std.fs.path.join(gpa, &.{ root, "agent" });
    defer gpa.free(agent_dir);
    const skill_path = try std.fs.path.join(gpa, &.{ agent_dir, "skills", "reloadable", "SKILL.md" });
    defer gpa.free(skill_path);
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(skill_path).?);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = skill_path, .data =
        \\---
        \\name: reloadable
        \\description: RELOADABLE-SKILL-158
        \\---
        \\body
    });
    const settings_path = try std.fs.path.join(gpa, &.{ agent_dir, "settings.json" });
    defer gpa.free(settings_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data =
        \\{"skills":["-skills/reloadable/SKILL.md"]}
    });

    var owned_base: ?[]u8 = null;
    defer if (owned_base) |value| gpa.free(value);
    var owned_system: ?[]u8 = null;
    defer if (owned_system) |value| gpa.free(value);
    var owned_context: ?[]u8 = null;
    defer if (owned_context) |value| gpa.free(value);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |value| gpa.free(value);
    var display: ?[]const u8 = null;
    var display_owned = false;
    var cfg = agent_loop.AgentConfig{};
    var state = LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .agent_dir = agent_dir,
        .trust_project = false,
        .agent_cfg = &cfg,
        .owned_system = &owned_system,
        .owned_context = &owned_context,
        .owned_system_base = &owned_base,
        .owned_skills_summary = &owned_skills,
        .model_display = &display,
        .model_display_owned = &display_owned,
    };

    const disabled_status = try applyReload(&state);
    defer gpa.free(disabled_status);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "RELOADABLE-SKILL-158") == null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = settings_path, .data =
        \\{"skills":["+skills/reloadable/SKILL.md"]}
    });
    const enabled_status = try applyReload(&state);
    defer gpa.free(enabled_status);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "RELOADABLE-SKILL-158") != null);
}

test "thinking and reload preserve every custom prompt source" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const path_len = try tmp.dir.realPath(io, &path_buf);
    const root = path_buf[0..path_len];

    const system_path = try std.fs.path.join(gpa, &.{ root, "SYSTEM.md" });
    defer gpa.free(system_path);
    const append_path = try std.fs.path.join(gpa, &.{ root, "APPEND_SYSTEM.md" });
    defer gpa.free(append_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = system_path, .data = "DISK SYSTEM MUST LOSE TO CLI" });
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = append_path, .data = "DISK APPEND V1" });

    const cli_appends = [_][]const u8{"CLI APPEND TOKEN"};
    var owned_base: ?[]u8 = try system_prompt.assemble(gpa, .{
        .system_override = "CLI SYSTEM TOKEN",
        .append_system = "DISK APPEND V1",
        .extra_appends = &cli_appends,
    });
    defer if (owned_base) |value| gpa.free(value);
    var owned_system: ?[]u8 = try system_prompt.assemble(gpa, .{
        .system_override = owned_base.?,
        .thinking_level = "low",
    });
    defer if (owned_system) |value| gpa.free(value);
    var owned_context: ?[]u8 = null;
    defer if (owned_context) |value| gpa.free(value);
    var owned_skills: ?[]u8 = null;
    defer if (owned_skills) |value| gpa.free(value);
    var owned_thinking: ?[]u8 = null;
    defer if (owned_thinking) |value| gpa.free(value);
    var display: ?[]const u8 = null;
    var display_owned = false;
    var cfg = agent_loop.AgentConfig{ .system_prompt = owned_system.? };

    var state = LiveState{
        .gpa = gpa,
        .io = io,
        .cwd = root,
        .agent_dir = null,
        .trust_project = true,
        .thinking = "low",
        .agent_cfg = &cfg,
        .owned_system = &owned_system,
        .owned_context = &owned_context,
        .owned_system_base = &owned_base,
        .owned_thinking = &owned_thinking,
        .owned_skills_summary = &owned_skills,
        .cli_system_override = "CLI SYSTEM TOKEN",
        .cli_system_appends = &cli_appends,
        .model_display = &display,
        .model_display_owned = &display_owned,
    };

    try applyThinking(&state, "high");
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "CLI SYSTEM TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "CLI APPEND TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "Thinking level: high") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, agent_loop.default_system_prompt) == null);

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = append_path, .data = "DISK APPEND V2 RELOADED" });
    const status = try applyReload(&state);
    defer gpa.free(status);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "CLI SYSTEM TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "DISK SYSTEM MUST LOSE TO CLI") == null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "DISK APPEND V2 RELOADED") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "CLI APPEND TOKEN") != null);
    try std.testing.expect(std.mem.indexOf(u8, cfg.system_prompt, "Thinking level: high") != null);
}

test "runtime reload callback contributes resource counts to status" {
    const Stub = struct {
        fn call(_: ?*anyopaque) anyerror!RuntimeReloadResult {
            return .{ .extensions = 3, .commands = 7, .prompts = 4, .themes = 2, .keybindings_reloaded = true };
        }
    };
    var state = LiveState{
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = undefined,
        .owned_system = undefined,
        .owned_context = undefined,
        .owned_system_base = undefined,
        .owned_skills_summary = undefined,
        .model_display = undefined,
        .model_display_owned = undefined,
        .runtime_reload_fn = Stub.call,
    };
    const status = try finishReloadStatus(&state, 5, 6);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings(
        "Reloaded: 5 context file(s), 6 skill(s), 3 extension(s), 7 command(s), 4 prompt template(s), 2 theme(s), keybindings",
        status,
    );
}

test "runtime reload failure reports rollback without hiding core reload" {
    const Stub = struct {
        fn call(_: ?*anyopaque) anyerror!RuntimeReloadResult {
            return error.InvalidRuntimeFixture;
        }
    };
    var state = LiveState{
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .cwd = ".",
        .agent_dir = null,
        .agent_cfg = undefined,
        .owned_system = undefined,
        .owned_context = undefined,
        .owned_system_base = undefined,
        .owned_skills_summary = undefined,
        .model_display = undefined,
        .model_display_owned = undefined,
        .runtime_reload_fn = Stub.call,
    };
    const status = try finishReloadStatus(&state, 1, 2);
    defer std.testing.allocator.free(status);
    try std.testing.expectEqualStrings(
        "Reloaded: 1 context file(s), 2 skill(s); runtime resources unchanged (InvalidRuntimeFixture)",
        status,
    );
}

test "extension OAuth invalidation scrubs the active transport before releasing its key" {
    const gpa = std.testing.allocator;
    var pool: ClientPool = .{ .gpa = gpa, .io = std.testing.io };
    defer pool.deinit();

    pool.provider_owned = try gpa.dupe(u8, "removed-oauth");
    pool.model_owned = try gpa.dupe(u8, "removed-model");
    pool.extension_oauth_provider = try gpa.dupe(u8, "removed-oauth");
    pool.extension_oauth_key = try gpa.dupe(u8, "stale-secret");
    pool.extension_oauth_expires_ms = 9999999999999;
    pool.openai = .{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = pool.extension_oauth_key.?,
        .base_url = "https://removed.invalid/v1",
        .model = pool.model_owned.?,
        .provider_id = pool.provider_owned.?,
        .token_expiration_ms = pool.extension_oauth_expires_ms,
        .token_refresh_ctx = @ptrCast(&pool),
        .token_refresh_fn = ClientPool.refreshExtensionOpenAI,
    };
    pool.client = pool.openai.?.client();

    pool.invalidateExtensionOAuth();
    try std.testing.expect(pool.extension_oauth_provider == null);
    try std.testing.expect(pool.extension_oauth_key == null);
    try std.testing.expect(pool.extension_oauth_expires_ms == null);
    try std.testing.expectEqualStrings("", pool.openai.?.api_key);
    try std.testing.expect(pool.openai.?.token_expiration_ms == null);
    try std.testing.expect(pool.openai.?.token_refresh_ctx == null);
    try std.testing.expect(pool.openai.?.token_refresh_fn == null);
}
