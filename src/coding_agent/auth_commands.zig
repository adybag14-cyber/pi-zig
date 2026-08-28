//! Non-interactive credential inspection commands compatible with upstream `pi auth`.
//!
//! The implementation deliberately reuses the native credential store and OAuth
//! refresh clients used by live sessions.  `auth check --no-refresh` is strictly
//! offline and returns the persisted access token even when it is expired.
const std = @import("std");
const Io = std.Io;
const app_config = @import("../config.zig");
const providers = @import("../ai/providers.zig");
const bootstrap_http = @import("../ai/bootstrap_http.zig");
const openai_responses = @import("../ai/openai_responses.zig");
const auth = @import("../auth/root.zig");
const auth_storage = @import("../auth/storage.zig");
const openai_codex_oauth = @import("../auth/openai_codex_oauth.zig");
const copilot_oauth = @import("../auth/github_copilot_oauth.zig");
const anthropic_oauth = @import("../auth/anthropic_oauth.zig");
const kimi_oauth = @import("../auth/kimi_coding_oauth.zig");
const xai_oauth = @import("../auth/xai_oauth.zig");
const radius_oauth = @import("../auth/radius_oauth.zig");
const config_value = @import("config_value.zig");
const models_file_mod = @import("models_file.zig");
const effective_catalog = @import("effective_catalog.zig");
const model_resolver = @import("model_resolver.zig");
const settings = @import("settings.zig");

pub const HELP =
    \\Usage:
    \\  pi auth print-api-key [--provider <provider>] [--model <model>]
    \\  pi auth print-bearer-token [--provider <provider>] [--model <model>] [--min-expiry <duration>]
    \\  pi auth check [--provider <provider>] [--model <model>] [--json] [--credentials] [--no-refresh]
    \\Auth commands require at least one of --provider or --model. Checks refresh expired OAuth credentials by default; --no-refresh prevents this. --credentials emits the credential, or includes it in JSON output.
;

const DEFAULT_BEARER_TOKEN_MIN_EXPIRY_MS: i64 = 30 * 60 * 1000;
const NORMAL_REFRESH_SKEW_MS: i64 = 5 * 60 * 1000;

pub const Result = struct {
    output: []u8,
    exit_code: u8 = 0,
    is_error: bool = false,

    pub fn deinit(self: *Result, gpa: std.mem.Allocator) void {
        gpa.free(self.output);
        self.* = undefined;
    }
};

const Kind = enum { check, api_key, bearer_token };

const Parsed = struct {
    kind: Kind,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    json: bool = false,
    credentials: bool = false,
    no_refresh: bool = false,
    min_expiry_ms: ?i64 = null,
};

const ParseOutcome = union(enum) {
    help,
    command: Parsed,
    failure: []u8,

    fn deinit(self: *ParseOutcome, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .failure => |message| gpa.free(message),
            else => {},
        }
        self.* = undefined;
    }
};

fn fail(gpa: std.mem.Allocator, comptime format: []const u8, args: anytype, code: u8) !Result {
    return .{ .output = try std.fmt.allocPrint(gpa, "Error: " ++ format, args), .exit_code = code, .is_error = true };
}

fn owned(gpa: std.mem.Allocator, output: []const u8, code: u8, is_error: bool) !Result {
    return .{ .output = try gpa.dupe(u8, output), .exit_code = code, .is_error = is_error };
}

fn parseDuration(raw: []const u8) ?i64 {
    if (raw.len < 2) return null;
    var digits_end: usize = 0;
    while (digits_end < raw.len and std.ascii.isDigit(raw[digits_end])) : (digits_end += 1) {}
    if (digits_end == 0 or digits_end == raw.len) return null;
    const amount = std.fmt.parseInt(i64, raw[0..digits_end], 10) catch return null;
    const multiplier: i64 = if (std.mem.eql(u8, raw[digits_end..], "ms"))
        1
    else if (std.ascii.eqlIgnoreCase(raw[digits_end..], "s"))
        1000
    else if (std.ascii.eqlIgnoreCase(raw[digits_end..], "m"))
        60_000
    else if (std.ascii.eqlIgnoreCase(raw[digits_end..], "h"))
        3_600_000
    else
        return null;
    return std.math.mul(i64, amount, multiplier) catch null;
}

fn commandName(kind: Kind) []const u8 {
    return switch (kind) {
        .check => "auth check",
        .api_key => "auth print-api-key",
        .bearer_token => "auth print-bearer-token",
    };
}

fn parse(gpa: std.mem.Allocator, args: []const []const u8) !ParseOutcome {
    if (args.len == 0 or std.mem.eql(u8, args[0], "help")) return .help;
    for (args) |arg| if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return .help;

    var result: Parsed = .{ .kind = if (std.mem.eql(u8, args[0], "check"))
        .check
    else if (std.mem.eql(u8, args[0], "print-api-key"))
        .api_key
    else if (std.mem.eql(u8, args[0], "print-bearer-token"))
        .bearer_token
    else
        return .{ .failure = try std.fmt.allocPrint(gpa, "Unknown auth command \"{s}\". Use \"pi auth print-api-key\", \"pi auth print-bearer-token\", or \"pi auth check\".", .{args[0]}) } };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--provider") or std.mem.eql(u8, arg, "--model")) {
            if (i + 1 >= args.len) return .{ .failure = try std.fmt.allocPrint(gpa, "Missing value for {s}", .{arg}) };
            i += 1;
            const value = std.mem.trim(u8, args[i], " \t\r\n");
            if (std.mem.eql(u8, arg, "--provider")) result.provider = if (value.len > 0) value else null else result.model = if (value.len > 0) value else null;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--provider=")) {
            const value = std.mem.trim(u8, arg["--provider=".len..], " \t\r\n");
            result.provider = if (value.len > 0) value else null;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--model=")) {
            const value = std.mem.trim(u8, arg["--model=".len..], " \t\r\n");
            result.model = if (value.len > 0) value else null;
            continue;
        }
        if (std.mem.eql(u8, arg, "--min-expiry")) {
            if (result.kind != .bearer_token) return .{ .failure = try gpa.dupe(u8, "--min-expiry is only supported by print-bearer-token") };
            if (i + 1 >= args.len) return .{ .failure = try gpa.dupe(u8, "--min-expiry must use a duration such as 30m or 1h") };
            i += 1;
            result.min_expiry_ms = parseDuration(args[i]) orelse return .{ .failure = try gpa.dupe(u8, "--min-expiry must use a duration such as 30m or 1h") };
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--min-expiry=")) {
            if (result.kind != .bearer_token) return .{ .failure = try gpa.dupe(u8, "--min-expiry is only supported by print-bearer-token") };
            result.min_expiry_ms = parseDuration(arg["--min-expiry=".len..]) orelse return .{ .failure = try gpa.dupe(u8, "--min-expiry must use a duration such as 30m or 1h") };
            continue;
        }
        if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "--credentials") or std.mem.eql(u8, arg, "--no-refresh")) {
            if (result.kind != .check) return .{ .failure = try std.fmt.allocPrint(gpa, "{s} is only supported by auth check", .{arg}) };
            if (std.mem.eql(u8, arg, "--json")) result.json = true else if (std.mem.eql(u8, arg, "--credentials")) result.credentials = true else result.no_refresh = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            const option = std.mem.trim(u8, arg, "-");
            return .{ .failure = try std.fmt.allocPrint(gpa, "Unknown option --{s} for \"{s}\".", .{ option, commandName(result.kind) }) };
        }
        return .{ .failure = try gpa.dupe(u8, "Auth commands only accept --provider and --model") };
    }

    if (result.provider == null and result.model == null) {
        return .{ .failure = try gpa.dupe(u8, if (result.kind == .check)
            "Auth checks require --provider <provider> or --model <model>"
        else
            "Credential printing requires --provider <provider> or --model <model>") };
    }
    return .{ .command = result };
}

const Context = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    models_file: models_file_mod.ModelsFile,
    catalog: []providers.ModelInfo,
    store: ?auth_storage.AuthStorage,
    infos: []auth_storage.CredentialInfo,
    network_settings: settings.Settings,

    fn init(gpa: std.mem.Allocator, io: Io, environ: *const std.process.Environ.Map, agent_dir: ?[]const u8) !Context {
        var models_file: models_file_mod.ModelsFile = if (agent_dir) |dir| try models_file_mod.load(gpa, io, dir) else .{ .gpa = gpa };
        errdefer models_file.deinit();
        const catalog = try effective_catalog.build(gpa, &models_file);
        errdefer gpa.free(catalog);
        var store: ?auth_storage.AuthStorage = null;
        var infos: []auth_storage.CredentialInfo = &.{};
        var network_settings: settings.Settings = .{};
        errdefer network_settings.deinit(gpa);
        if (agent_dir) |dir| {
            store = try auth.AuthStorage.init(gpa, io, dir);
            errdefer if (store) |*value| value.deinit();
            infos = try store.?.list();
            const settings_path = try std.fs.path.join(gpa, &.{ dir, "settings.json" });
            defer gpa.free(settings_path);
            network_settings = try settings.loadFile(gpa, io, settings_path);
        }
        return .{ .gpa = gpa, .io = io, .environ = environ, .agent_dir = agent_dir, .models_file = models_file, .catalog = catalog, .store = store, .infos = infos, .network_settings = network_settings };
    }

    fn deinit(self: *Context) void {
        for (self.infos) |*info| info.deinit(self.gpa);
        if (self.infos.len > 0) self.gpa.free(self.infos);
        if (self.store) |*store| store.deinit();
        self.network_settings.deinit(self.gpa);
        self.gpa.free(self.catalog);
        self.models_file.deinit();
        self.* = undefined;
    }

    fn bootstrapOptions(self: *const Context) bootstrap_http.Options {
        const inherited_timeout_ms = self.network_settings.http_idle_timeout_ms orelse openai_responses.DEFAULT_HTTP_IDLE_TIMEOUT_MS;
        return .{
            .policy = .{
                .timeout_ms = self.network_settings.retry_provider_timeout_ms orelse if (inherited_timeout_ms == 0) null else inherited_timeout_ms,
                .max_retries = self.network_settings.retry_provider_max_retries orelse 2,
                .max_retry_delay_ms = self.network_settings.retry_provider_max_retry_delay_ms orelse 60_000,
            },
            .proxy = .{
                .environ = self.environ,
                .setting = self.network_settings.http_proxy,
            },
        };
    }

    fn storedType(self: *const Context, provider_id: []const u8) ?auth_storage.CredentialType {
        for (self.infos) |info| if (std.ascii.eqlIgnoreCase(info.provider_id, provider_id)) return info.credential_type;
        return null;
    }

    fn providerKnown(self: *const Context, provider_id: []const u8) bool {
        if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex")) return true;
        if (providers.Provider.fromString(provider_id) != null) return true;
        if (self.models_file.findProvider(provider_id) != null) return true;
        if (self.storedType(provider_id) != null) return true;
        for (self.catalog) |model| if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id)) return true;
        return false;
    }

    fn providerHasCatalog(self: *const Context, provider_id: []const u8) bool {
        for (self.catalog) |model| if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id)) return true;
        return false;
    }

    fn configuredType(self: *const Context, provider_id: []const u8) ?auth_storage.CredentialType {
        if (self.storedType(provider_id)) |kind| return kind;
        // ANTHROPIC_OAUTH_TOKEN is accepted by Anthropic's API-key resolver;
        // it is not a durable OAuth credential with refresh metadata.
        if (std.ascii.eqlIgnoreCase(provider_id, "anthropic") and self.environ.get(app_config.ENV_ANTHROPIC_OAUTH_TOKEN) != null) return .api_key;
        if (self.models_file.findProvider(provider_id)) |provider| if (provider.api_key != null) return .api_key;
        const builtin = providers.Provider.fromString(provider_id) orelse return null;
        if (!std.ascii.eqlIgnoreCase(provider_id, builtin.name())) return null;
        if (providers.hasUsableCredential(builtin, null, self.environ)) return .api_key;
        return null;
    }

    fn collectConfiguredProviders(self: *const Context, out: *std.ArrayList([]const u8)) !void {
        for (self.infos) |info| try appendUniqueProvider(self.gpa, out, info.provider_id);
        for (self.models_file.providers) |provider| if (provider.api_key != null) try appendUniqueProvider(self.gpa, out, provider.id);
        inline for (std.meta.fields(providers.Provider)) |field| {
            const p: providers.Provider = @enumFromInt(field.value);
            if (providers.hasUsableCredential(p, null, self.environ)) try appendUniqueProvider(self.gpa, out, p.name());
        }
    }
};

fn appendUniqueProvider(gpa: std.mem.Allocator, out: *std.ArrayList([]const u8), provider_id: []const u8) !void {
    for (out.items) |existing| if (std.ascii.eqlIgnoreCase(existing, provider_id)) return;
    try out.append(gpa, provider_id);
}

const Selection = struct {
    provider_id: []const u8,
    model: ?providers.ModelInfo = null,
};

fn resolveExplicitSelection(ctx: *const Context, parsed: Parsed) !Selection {
    const provider_id = parsed.provider.?;
    if (!ctx.providerKnown(provider_id)) return error.UnknownProvider;
    if (parsed.model) |model_pattern| {
        if (!ctx.providerHasCatalog(provider_id)) {
            // OpenAI Codex credentials predate the static catalog in older checkpoints;
            // keep explicit provider/model auth inspection functional nonetheless.
            if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex")) return .{ .provider_id = "openai-codex" };
            return error.ModelNotFound;
        }
        const configured = [_][]const u8{provider_id};
        const resolved = model_resolver.resolveCliModel(provider_id, model_pattern, null, ctx.catalog, &configured);
        if (resolved.err != null or resolved.model == null) return error.ModelNotFound;
        return .{ .provider_id = resolved.model.?.providerName(), .model = resolved.model };
    }
    return .{ .provider_id = provider_id };
}

fn selectionForCheck(ctx: *const Context, parsed: Parsed) !Selection {
    if (parsed.provider != null) return resolveExplicitSelection(ctx, parsed);
    var configured: std.ArrayList([]const u8) = .empty;
    defer configured.deinit(ctx.gpa);
    try ctx.collectConfiguredProviders(&configured);
    const resolved = model_resolver.resolveCliModel(null, parsed.model, null, ctx.catalog, configured.items);
    if (resolved.err != null or resolved.model == null) return error.ModelNotFound;
    return .{ .provider_id = resolved.model.?.providerName(), .model = resolved.model };
}

fn selectPrintCandidates(ctx: *const Context, parsed: Parsed) ![]Selection {
    var out: std.ArrayList(Selection) = .empty;
    errdefer out.deinit(ctx.gpa);
    if (parsed.provider != null) {
        try out.append(ctx.gpa, try resolveExplicitSelection(ctx, parsed));
        return try out.toOwnedSlice(ctx.gpa);
    }

    var configured: std.ArrayList([]const u8) = .empty;
    defer configured.deinit(ctx.gpa);
    try ctx.collectConfiguredProviders(&configured);
    for (configured.items) |provider_id| {
        if (!ctx.providerHasCatalog(provider_id)) continue;
        const one = [_][]const u8{provider_id};
        const resolved = model_resolver.resolveCliModel(provider_id, parsed.model, null, ctx.catalog, &one);
        if (resolved.err == null and resolved.model != null and resolved.warning == null) {
            try out.append(ctx.gpa, .{ .provider_id = resolved.model.?.providerName(), .model = resolved.model });
        }
    }
    if (out.items.len == 0) return error.ModelNotFound;
    return try out.toOwnedSlice(ctx.gpa);
}

fn resolveConfigValue(ctx: *const Context, raw: []const u8) !?[]u8 {
    var resolver = config_value.Resolver.init(ctx.gpa, ctx.io, ctx.environ);
    defer resolver.deinit();
    return resolver.resolve(raw);
}

fn readStored(ctx: *const Context, provider_id: []const u8) !?auth_storage.Credential {
    const store = ctx.store orelse return null;
    return store.read(provider_id);
}

fn resolveApiKey(ctx: *const Context, provider_id: []const u8) !?[]u8 {
    if (try readStored(ctx, provider_id)) |stored_value| {
        var stored = stored_value;
        defer stored.deinit(ctx.gpa);
        switch (stored) {
            .oauth => return error.ProviderUsesOAuth,
            .api_key => |api_key| if (api_key.key) |raw| {
                if (try resolveConfigValue(ctx, raw)) |value| return value;
            },
        }
    }

    if (ctx.models_file.findProvider(provider_id)) |provider| if (provider.api_key) |raw| {
        if (try resolveConfigValue(ctx, raw)) |value| return value;
    };

    if (providers.Provider.fromString(provider_id)) |builtin| {
        if (std.ascii.eqlIgnoreCase(provider_id, builtin.name())) {
            if (providers.resolveApiKey(builtin, null, ctx.environ)) |value| return try ctx.gpa.dupe(u8, value);
            if (ctx.agent_dir) |agent_dir| if (providers.credentialEnvName(builtin)) |key_name| {
                if (try settings.loadCredential(ctx.gpa, ctx.io, agent_dir, key_name)) |legacy| return legacy;
            };
        }
    }
    if (ctx.environ.get(app_config.ENV_API_KEY)) |value| return try ctx.gpa.dupe(u8, value);
    return null;
}

fn radiusGateway(ctx: *const Context, selection: Selection) []const u8 {
    if (selection.model) |model| {
        if (ctx.models_file.findModel(selection.provider_id, model.id)) |configured_model| if (configured_model.base_url) |value| return value;
    }
    if (ctx.models_file.findProvider(selection.provider_id)) |provider| if (provider.base_url) |value| return value;
    return providers.compatBaseUrl(selection.provider_id) orelse providers.defaultBaseUrl(.radius);
}

fn refreshOAuth(ctx: *Context, selection: Selection, credential: *const auth_storage.OAuthCredential) ![]u8 {
    const agent_dir = ctx.agent_dir orelse return error.MissingAgentDir;
    const provider_id = selection.provider_id;
    if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex")) {
        var fresh = try openai_codex_oauth.refreshWithOptions(ctx.gpa, ctx.io, credential.refresh, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        try openai_codex_oauth.persistToken(ctx.gpa, ctx.io, agent_dir, &fresh);
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) {
        var fresh = try copilot_oauth.refreshCredentialWithOptions(ctx.gpa, ctx.io, credential.refresh, credential.enterprise_url, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        try copilot_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, &fresh);
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "anthropic")) {
        var fresh = try anthropic_oauth.refreshWithOptions(ctx.gpa, ctx.io, credential.refresh, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        try anthropic_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, &fresh);
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "kimi-coding")) {
        var fresh = try kimi_oauth.refreshWithOptions(ctx.gpa, ctx.io, kimi_oauth.oauthHost(ctx.environ), credential.refresh, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        try kimi_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, &fresh);
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    if (std.ascii.eqlIgnoreCase(provider_id, "xai")) {
        var fresh = try xai_oauth.refreshWithOptions(ctx.gpa, ctx.io, credential.refresh, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        try xai_oauth.persistCredential(ctx.gpa, ctx.io, agent_dir, &fresh);
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    const radius_configured = if (ctx.models_file.findProvider(provider_id)) |provider| provider.oauth == .radius else false;
    if (std.ascii.eqlIgnoreCase(provider_id, "radius") or radius_configured) {
        var fresh = try radius_oauth.refreshWithOptions(ctx.gpa, ctx.io, radiusGateway(ctx, selection), credential.refresh, ctx.bootstrapOptions());
        defer fresh.deinit(ctx.gpa);
        const store = ctx.store orelse return error.MissingAgentDir;
        try store.setOAuth(provider_id, .{ .refresh = fresh.refresh, .access = fresh.access, .expires = fresh.expires_ms, .scope = fresh.scope });
        return try ctx.gpa.dupe(u8, fresh.access);
    }
    // OpenRouter's OAuth exchange produces a non-expiring API token stored in
    // OAuth form. It never needs a refresh request.
    if (std.ascii.eqlIgnoreCase(provider_id, "openrouter")) return try ctx.gpa.dupe(u8, credential.access);
    return error.UnsupportedOAuthRefresh;
}

fn resolveBearer(ctx: *Context, selection: Selection, min_validity_ms: i64, refresh: bool) !?[]u8 {
    const stored_value = (try readStored(ctx, selection.provider_id)) orelse return null;
    var stored = stored_value;
    defer stored.deinit(ctx.gpa);
    return switch (stored) {
        .api_key => error.ProviderUsesApiKey,
        .oauth => |oauth_credential| blk: {
            if (!refresh) break :blk try ctx.gpa.dupe(u8, oauth_credential.access);
            const now_ms = std.Io.Clock.real.now(ctx.io).toMilliseconds();
            const remaining = std.math.sub(i64, oauth_credential.expires, now_ms) catch std.math.minInt(i64);
            if (remaining >= min_validity_ms) break :blk try ctx.gpa.dupe(u8, oauth_credential.access);
            break :blk try refreshOAuth(ctx, selection, &oauth_credential);
        },
    };
}

const CheckStatus = enum { ready, not_ready, invalid };
const CheckReason = enum { provider_not_found, credentials_not_configured, credential_not_available, invalid_state };

const CheckResult = struct {
    status: CheckStatus,
    provider: []const u8,
    reason: ?CheckReason = null,
    auth_type: ?auth_storage.CredentialType = null,
    credential: ?[]u8 = null,

    fn deinit(self: *CheckResult, gpa: std.mem.Allocator) void {
        if (self.credential) |value| gpa.free(value);
        self.* = undefined;
    }
};

fn check(ctx: *Context, parsed: Parsed) !CheckResult {
    const selection = selectionForCheck(ctx, parsed) catch |err| switch (err) {
        error.UnknownProvider => return .{ .status = .not_ready, .provider = parsed.provider orelse parsed.model.?, .reason = .provider_not_found },
        else => return err,
    };
    if (!ctx.providerKnown(selection.provider_id)) return .{ .status = .not_ready, .provider = selection.provider_id, .reason = .provider_not_found };
    const kind = ctx.configuredType(selection.provider_id) orelse return .{ .status = .not_ready, .provider = selection.provider_id, .reason = .credentials_not_configured };

    var credential: ?[]u8 = null;
    switch (kind) {
        .api_key => {
            credential = resolveApiKey(ctx, selection.provider_id) catch return .{ .status = .invalid, .provider = selection.provider_id, .reason = .invalid_state };
            if (credential == null) return .{ .status = .not_ready, .provider = selection.provider_id, .reason = .credentials_not_configured };
        },
        .oauth => {
            credential = resolveBearer(ctx, selection, NORMAL_REFRESH_SKEW_MS, !parsed.no_refresh) catch return .{ .status = .invalid, .provider = selection.provider_id, .reason = .invalid_state };
            if (credential == null) return .{ .status = .not_ready, .provider = selection.provider_id, .reason = .credentials_not_configured };
        },
    }
    if (!parsed.credentials) {
        if (credential) |value| ctx.gpa.free(value);
        credential = null;
    }
    return .{ .status = .ready, .provider = selection.provider_id, .auth_type = kind, .credential = credential };
}

fn jsonString(writer: *std.Io.Writer, value: []const u8) !void {
    try std.json.Stringify.value(value, .{}, writer);
}

fn formatCheck(gpa: std.mem.Allocator, result: CheckResult, as_json: bool) ![]u8 {
    if (!as_json) return try gpa.dupe(u8, result.credential orelse @tagName(result.status));
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"status\":");
    try jsonString(&out.writer, @tagName(result.status));
    try out.writer.writeAll(",\"provider\":");
    try jsonString(&out.writer, result.provider);
    if (result.reason) |reason| {
        try out.writer.writeAll(",\"reason\":");
        try jsonString(&out.writer, @tagName(reason));
    }
    if (result.auth_type) |kind| {
        try out.writer.writeAll(",\"authType\":");
        try jsonString(&out.writer, @tagName(kind));
    }
    if (result.credential) |credential| {
        try out.writer.writeAll(",\"credentials\":");
        try jsonString(&out.writer, credential);
    }
    try out.writer.writeByte('}');
    return out.toOwnedSlice();
}

fn runPrint(ctx: *Context, parsed: Parsed) !Result {
    const candidates = selectPrintCandidates(ctx, parsed) catch |err| switch (err) {
        error.UnknownProvider => return fail(ctx.gpa, "Unknown provider \"{s}\". Use --list-models to see available providers.", .{parsed.provider.?}, 1),
        error.ModelNotFound => return fail(ctx.gpa, "Model \"{s}\" not found. Use --list-models to see available models.", .{parsed.model orelse ""}, 1),
        else => return err,
    };
    defer ctx.gpa.free(candidates);

    var found: std.ArrayList(struct { provider_id: []const u8, value: []u8 }) = .empty;
    defer {
        for (found.items) |item| ctx.gpa.free(item.value);
        found.deinit(ctx.gpa);
    }

    for (candidates) |selection| {
        const kind = ctx.configuredType(selection.provider_id);
        if (parsed.kind == .api_key) {
            if (kind == .oauth) continue;
            const value = resolveApiKey(ctx, selection.provider_id) catch |err| switch (err) {
                error.ProviderUsesOAuth => continue,
                else => return err,
            };
            if (value) |key| try found.append(ctx.gpa, .{ .provider_id = selection.provider_id, .value = key });
        } else {
            if (kind != .oauth) continue;
            const value = resolveBearer(ctx, selection, parsed.min_expiry_ms orelse DEFAULT_BEARER_TOKEN_MIN_EXPIRY_MS, true) catch |err| switch (err) {
                error.ProviderUsesApiKey => continue,
                else => return err,
            };
            if (value) |token| try found.append(ctx.gpa, .{ .provider_id = selection.provider_id, .value = token });
        }
    }

    if (found.items.len == 1) return owned(ctx.gpa, found.items[0].value, 0, false);
    if (found.items.len == 0) {
        const provider_id = if (candidates.len > 0) candidates[0].provider_id else parsed.provider orelse "";
        const kind = ctx.configuredType(provider_id);
        if (parsed.provider != null and parsed.kind == .api_key and kind == .oauth)
            return fail(ctx.gpa, "Provider \"{s}\" is configured with OAuth, not an API key", .{provider_id}, 1);
        if (parsed.provider != null and parsed.kind == .bearer_token and kind != .oauth)
            return fail(ctx.gpa, "Provider \"{s}\" is not configured with an OAuth bearer token", .{provider_id}, 1);
        return fail(ctx.gpa, "No usable {s} is configured", .{if (parsed.kind == .api_key) "API key" else "OAuth bearer token"}, 1);
    }

    var names: std.Io.Writer.Allocating = .init(ctx.gpa);
    defer names.deinit();
    for (found.items, 0..) |item, index| {
        if (index > 0) try names.writer.writeAll(", ");
        try names.writer.writeAll(item.provider_id);
    }
    return fail(ctx.gpa, "Multiple configured providers matched ({s}). Specify --provider.", .{names.written()}, 1);
}

pub fn execute(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    args: []const []const u8,
) !Result {
    var parsed_outcome = try parse(gpa, args);
    defer parsed_outcome.deinit(gpa);
    switch (parsed_outcome) {
        .help => return owned(gpa, HELP, 0, false),
        .failure => |message| return fail(gpa, "{s}", .{message}, 1),
        .command => |parsed| {
            var ctx = Context.init(gpa, io, environ, agent_dir) catch |err| {
                return fail(gpa, "Failed to resolve credential ({s})", .{@errorName(err)}, if (parsed.kind == .check) 2 else 1);
            };
            defer ctx.deinit();
            if (parsed.kind != .check) return runPrint(&ctx, parsed) catch |err| {
                return fail(gpa, "Failed to resolve credential ({s})", .{@errorName(err)}, 1);
            };

            var result = check(&ctx, parsed) catch {
                const provider = parsed.provider orelse parsed.model.?;
                const fallback: CheckResult = .{ .status = .invalid, .provider = provider, .reason = .invalid_state };
                return .{ .output = try formatCheck(gpa, fallback, parsed.json), .exit_code = 2 };
            };
            defer result.deinit(gpa);
            if (parsed.credentials and result.status == .ready and result.credential == null) {
                result.status = .not_ready;
                result.reason = .credential_not_available;
                result.auth_type = null;
            }
            return .{
                .output = try formatCheck(gpa, result, parsed.json),
                .exit_code = switch (result.status) {
                    .ready => 0,
                    .not_ready => 1,
                    .invalid => 2,
                },
            };
        },
    }
}

fn testAgentDir(tmp: *std.testing.TmpDir, io: Io) ![]const u8 {
    const gpa = std.testing.allocator;
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try tmp.dir.realPath(io, &path_buf);
    return try gpa.dupe(u8, path_buf[0..len]);
}

test "auth command parses duration and rejects command-specific flags" {
    try std.testing.expectEqual(@as(?i64, 1_800_000), parseDuration("30m"));
    try std.testing.expectEqual(@as(?i64, 3_600_000), parseDuration("1H"));
    try std.testing.expect(parseDuration("30") == null);
    var bad = try parse(std.testing.allocator, &.{ "print-api-key", "--json", "--provider", "openai" });
    defer bad.deinit(std.testing.allocator);
    try std.testing.expect(bad == .failure);
    try std.testing.expect(std.mem.indexOf(u8, bad.failure, "only supported by auth check") != null);
}

test "auth check reports stored API key and can emit JSON credentials" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const agent_dir = try testAgentDir(&tmp, io);
    defer gpa.free(agent_dir);
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setApiKey("openai", "secret-key");
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var result = try execute(gpa, io, &env, agent_dir, &.{ "check", "--provider", "openai", "--json", "--credentials" });
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "\"status\":\"ready\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "\"authType\":\"api_key\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.output, "\"credentials\":\"secret-key\"") != null);
}

test "auth no-refresh returns persisted expired OAuth token without network" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const agent_dir = try testAgentDir(&tmp, io);
    defer gpa.free(agent_dir);
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    try store.setOAuth("openai-codex", .{ .refresh = @constCast("refresh"), .access = @constCast("persisted-access"), .expires = 1, .account_id = @constCast("acct") });
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var result = try execute(gpa, io, &env, agent_dir, &.{ "check", "--provider", "openai-codex", "--credentials", "--no-refresh" });
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("persisted-access", result.output);
}

test "credential printers enforce API-key versus OAuth type" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const agent_dir = try testAgentDir(&tmp, io);
    defer gpa.free(agent_dir);
    var store = try auth.AuthStorage.init(gpa, io, agent_dir);
    defer store.deinit();
    const far_future = std.Io.Clock.real.now(io).toMilliseconds() + 24 * 60 * 60 * 1000;
    try store.setOAuth("openai-codex", .{ .refresh = @constCast("refresh"), .access = @constCast("bearer"), .expires = far_future, .account_id = @constCast("acct") });
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();

    var api_result = try execute(gpa, io, &env, agent_dir, &.{ "print-api-key", "--provider", "openai-codex" });
    defer api_result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 1), api_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, api_result.output, "configured with OAuth") != null);

    var bearer_result = try execute(gpa, io, &env, agent_dir, &.{ "print-bearer-token", "--provider", "openai-codex", "--min-expiry", "1m" });
    defer bearer_result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), bearer_result.exit_code);
    try std.testing.expectEqualStrings("bearer", bearer_result.output);
}

test "custom models provider API key resolves config-value environment" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const agent_dir = try testAgentDir(&tmp, io);
    defer gpa.free(agent_dir);
    const path = try std.fs.path.join(gpa, &.{ agent_dir, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{"providers":{"corp":{"baseUrl":"https://example.invalid/v1","apiKey":"$CORP_KEY","api":"openai-completions","models":[{"id":"corp-model","name":"Corp Model"}]}}}
    });
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("CORP_KEY", "corp-secret");

    var result = try execute(gpa, io, &env, agent_dir, &.{ "print-api-key", "--provider", "corp", "--model", "corp-model" });
    defer result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), result.exit_code);
    try std.testing.expectEqualStrings("corp-secret", result.output);
}

test "Anthropic OAuth token environment is classified as API-key authentication" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const agent_dir = try testAgentDir(&tmp, io);
    defer gpa.free(agent_dir);
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put(app_config.ENV_ANTHROPIC_OAUTH_TOKEN, "sk-ant-oat-test");

    var check_result = try execute(gpa, io, &env, agent_dir, &.{ "check", "--provider", "anthropic", "--json" });
    defer check_result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), check_result.exit_code);
    try std.testing.expect(std.mem.indexOf(u8, check_result.output, "\"authType\":\"api_key\"") != null);

    var print_result = try execute(gpa, io, &env, agent_dir, &.{ "print-api-key", "--provider", "anthropic" });
    defer print_result.deinit(gpa);
    try std.testing.expectEqual(@as(u8, 0), print_result.exit_code);
    try std.testing.expectEqualStrings("sk-ant-oat-test", print_result.output);
}
