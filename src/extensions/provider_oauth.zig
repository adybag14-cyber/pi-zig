//! End-to-end lifecycle for OAuth providers registered by JavaScript extensions.
//!
//! The provider registry owns callback descriptors and workers; AuthStorage owns
//! serialized credential transactions; ClientPool consumes only the cycle-free
//! bridge declared by live_state. This keeps arbitrary extension credential
//! fields intact without introducing a provider-registry/live-state import loop.
const std = @import("std");
const Io = std.Io;
const auth_storage = @import("../auth/storage.zig");
const live_state = @import("../coding_agent/live_state.zig");
const js_runtime = @import("js_runtime.zig");
const provider_registry = @import("provider_registry.zig");

fn abortRequested(abort_flag: ?*const bool) bool {
    return if (abort_flag) |flag| @atomicLoad(bool, flag, .acquire) else false;
}

fn ensureLoginActive(abort_flag: ?*const bool) !void {
    if (abortRequested(abort_flag)) return error.LoginCancelled;
}

fn ensureOperationActive(abort_flag: ?*const bool) !void {
    if (abortRequested(abort_flag)) return error.Canceled;
}

pub const Runtime = struct {
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    registry: *provider_registry.Registry,
    client_pool: ?*live_state.ClientPool = null,
    live: ?*live_state.LiveState = null,

    pub fn init(
        gpa: std.mem.Allocator,
        io: Io,
        agent_dir: ?[]const u8,
        registry: *provider_registry.Registry,
    ) Runtime {
        return .{
            .gpa = gpa,
            .io = io,
            .agent_dir = agent_dir,
            .registry = registry,
        };
    }

    pub fn bindClientPool(self: *Runtime, pool: *live_state.ClientPool) void {
        self.client_pool = pool;
    }

    pub fn bindLiveState(self: *Runtime, live: *live_state.LiveState) void {
        self.live = live;
    }

    pub fn bridge(self: *Runtime) live_state.ExtensionOAuthBridge {
        return .{
            .context = self,
            .supports_fn = supportsThunk,
            .resolve_fn = resolveThunk,
        };
    }

    pub fn supports(self: *const Runtime, provider_id: []const u8) bool {
        return self.registry.hasProviderMethod(provider_id, "oauth.getApiKey");
    }

    pub fn canLogin(self: *const Runtime, provider_id: []const u8) bool {
        return self.supports(provider_id) and self.registry.hasProviderMethod(provider_id, "oauth.login");
    }

    pub fn loginProviderNames(self: *const Runtime, allocator: std.mem.Allocator) ![][]const u8 {
        return self.registry.oauthProviderNames(allocator);
    }

    pub fn lastLoginError(self: *const Runtime, provider_id: []const u8) ?[]const u8 {
        return self.registry.providerMethodLastError(provider_id, "oauth.login");
    }

    /// Execute the interactive extension callback, validate and atomically
    /// persist its complete credential object, then publish credential-specific
    /// models. No auth file is modified until the callback has completed.
    pub fn loginAndPersist(
        self: *Runtime,
        provider_id: []const u8,
        abort_flag: ?*bool,
        ui_bridge: ?js_runtime.UiBridge,
    ) ![]u8 {
        const agent_dir = self.agent_dir orelse return error.MissingAgentDir;
        try ensureLoginActive(abort_flag);
        const credential = self.registry.loginOAuth(provider_id, abort_flag, ui_bridge) catch |err| {
            if (abortRequested(abort_flag)) return error.LoginCancelled;
            return err;
        };
        defer self.gpa.free(credential);
        try ensureLoginActive(abort_flag);

        var store = try auth_storage.AuthStorage.init(self.gpa, self.io, agent_dir);
        defer store.deinit();
        store.setOAuthJsonAbortable(provider_id, credential, abort_flag) catch |err| switch (err) {
            error.Canceled => return error.LoginCancelled,
            else => return err,
        };
        const persisted = (try store.readOAuthJson(provider_id)) orelse return error.MissingExtensionOAuthCredential;
        errdefer self.gpa.free(persisted);
        // Once the atomic credential write has committed, complete publication
        // without reinterpreting a later UI abort as a failed login.
        try self.applyCredentialModels(provider_id, persisted, null);
        return persisted;
    }

    pub fn resolve(
        self: *Runtime,
        allocator: std.mem.Allocator,
        provider_id: []const u8,
        now_ms: i64,
        abort_flag: ?*bool,
        apply_models: bool,
    ) !?live_state.ExtensionOAuthResolution {
        if (!self.supports(provider_id)) return null;
        const agent_dir = self.agent_dir orelse return null;
        var store = try auth_storage.AuthStorage.init(self.gpa, self.io, agent_dir);
        defer store.deinit();

        var refresh_context = RefreshContext{
            .runtime = self,
            .provider_id = provider_id,
            .now_ms = now_ms,
            .abort_flag = abort_flag,
        };
        const credential = (try store.modifyOAuthJsonAbortable(provider_id, &refresh_context, refreshUnderLock, abort_flag)) orelse return null;
        defer self.gpa.free(credential);

        try ensureOperationActive(abort_flag);
        const api_key = try self.registry.oauthApiKey(provider_id, credential);
        errdefer self.gpa.free(api_key);
        try ensureOperationActive(abort_flag);
        const expires_ms = try credentialExpiration(self.gpa, credential);
        if (apply_models) try self.applyCredentialModels(provider_id, credential, abort_flag);

        const owned_key = if (allocator.ptr == self.gpa.ptr and allocator.vtable == self.gpa.vtable)
            api_key
        else blk: {
            const copy = try allocator.dupe(u8, api_key);
            self.gpa.free(api_key);
            break :blk copy;
        };
        return .{ .api_key = owned_key, .expires_ms = expires_ms };
    }

    /// Resolve the complete credential object passed to extension
    /// `refreshModels(context)`. Offline phases never refresh OAuth. Online
    /// phases serialize refresh under the canonical auth lock and preserve all
    /// provider-defined fields. Configured API keys are used when no stored
    /// credential exists.
    pub fn credentialForModelRefresh(
        self: *Runtime,
        allocator: std.mem.Allocator,
        provider_id: []const u8,
        now_ms: i64,
        allow_network: bool,
        abort_flag: ?*bool,
    ) !?[]u8 {
        try ensureOperationActive(abort_flag);
        var credential: ?[]u8 = null;
        if (self.agent_dir) |agent_dir| {
            var store = try auth_storage.AuthStorage.init(self.gpa, self.io, agent_dir);
            defer store.deinit();
            credential = try store.readCredentialJson(provider_id);
            if (credential) |current| {
                var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, current, .{});
                defer parsed.deinit();
                const type_value = if (parsed.value == .object) parsed.value.object.get("type") else null;
                const is_oauth = type_value != null and type_value.? == .string and std.mem.eql(u8, type_value.?.string, "oauth");
                if (allow_network and is_oauth) {
                    self.gpa.free(current);
                    credential = null;
                    var refresh_context = RefreshContext{
                        .runtime = self,
                        .provider_id = provider_id,
                        .now_ms = now_ms,
                        .abort_flag = abort_flag,
                    };
                    credential = try store.modifyOAuthJsonAbortable(provider_id, &refresh_context, refreshUnderLock, abort_flag);
                }
            }
        }
        if (credential == null) credential = try self.registry.configuredApiKeyCredentialJson(provider_id);
        const value = credential orelse return null;
        defer self.gpa.free(value);
        try ensureOperationActive(abort_flag);
        return @as(?[]u8, try allocator.dupe(u8, value));
    }

    /// Apply legacy credential-dependent model projection after a dynamic model
    /// list has committed. This remains a compatibility layer above the
    /// extension-owned refresh result.
    pub fn applyModelsForCredential(
        self: *Runtime,
        provider_id: []const u8,
        credential_json: []const u8,
        abort_flag: ?*const bool,
    ) !void {
        return self.applyCredentialModels(provider_id, credential_json, abort_flag);
    }

    fn applyCredentialModels(
        self: *Runtime,
        provider_id: []const u8,
        credential_json: []const u8,
        abort_flag: ?*const bool,
    ) !void {
        const has_modify = self.registry.hasProviderMethod(provider_id, "oauth.modifyModels");
        const has_filter = self.registry.hasProviderMethod(provider_id, "filterModels");
        if (!has_modify and !has_filter) return;
        try ensureOperationActive(abort_flag);
        const current_models = try self.registry.providerModelsJson(provider_id);
        defer self.gpa.free(current_models);
        const modified = if (has_modify)
            try self.registry.modifyOAuthModels(provider_id, current_models, credential_json)
        else
            try self.gpa.dupe(u8, current_models);
        defer self.gpa.free(modified);
        const projected = if (has_filter)
            try self.registry.filterModels(provider_id, modified, credential_json)
        else
            try self.gpa.dupe(u8, modified);
        defer self.gpa.free(projected);
        try ensureOperationActive(abort_flag);
        try self.registry.applyOAuthModels(provider_id, projected);

        // Registry publication replaces borrowed snapshots. Repoint every live
        // consumer before subsequent client/model resolution can observe them.
        if (self.client_pool) |pool| pool.setRuntimeProviders(self.registry.runtimes());
        if (self.live) |state| state.model_catalog = self.registry.catalog();
    }

    fn supportsThunk(raw: ?*anyopaque, provider_id: []const u8) bool {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return false));
        return self.supports(provider_id);
    }

    fn resolveThunk(
        raw: ?*anyopaque,
        allocator: std.mem.Allocator,
        provider_id: []const u8,
        now_ms: i64,
        abort_flag: ?*bool,
        apply_models: bool,
    ) anyerror!?live_state.ExtensionOAuthResolution {
        const self: *Runtime = @ptrCast(@alignCast(raw orelse return null));
        return self.resolve(allocator, provider_id, now_ms, abort_flag, apply_models);
    }
};

const RefreshContext = struct {
    runtime: *Runtime,
    provider_id: []const u8,
    now_ms: i64,
    abort_flag: ?*bool,
};

fn refreshUnderLock(
    raw: ?*anyopaque,
    allocator: std.mem.Allocator,
    current_json: ?[]const u8,
) anyerror!?[]u8 {
    const context: *RefreshContext = @ptrCast(@alignCast(raw orelse return null));
    const current = current_json orelse return null;
    const expires_ms = try credentialExpiration(context.runtime.gpa, current);
    // Match the concrete clients' one-minute early-refresh window. Rechecking
    // while the exclusive auth lock is held collapses concurrent refreshes.
    if (expires_ms > context.now_ms + 60_000) return null;
    if (!context.runtime.registry.hasProviderMethod(context.provider_id, "oauth.refreshToken")) {
        return error.ExtensionOAuthCredentialExpired;
    }
    try ensureOperationActive(context.abort_flag);
    const refreshed = context.runtime.registry.refreshOAuth(context.provider_id, current, context.abort_flag) catch |err| {
        if (abortRequested(context.abort_flag)) return error.Canceled;
        return err;
    };
    defer context.runtime.gpa.free(refreshed);
    try ensureOperationActive(context.abort_flag);
    return @as(?[]u8, try allocator.dupe(u8, refreshed));
}

fn credentialExpiration(gpa: std.mem.Allocator, credential_json: []const u8) !i64 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, credential_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionProviderCredential;
    const expires = parsed.value.object.get("expires") orelse return error.InvalidExtensionProviderCredential;
    if (expires != .integer) return error.InvalidExtensionProviderCredential;
    return expires.integer;
}

test "extension OAuth login refresh key derivation and model projection are end to end" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    const FakeUi = struct {
        auth_actions: usize = 0,
        device_actions: usize = 0,
        progress_actions: usize = 0,
        prompt_requests: usize = 0,
        select_requests: usize = 0,

        fn request(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args_json: []const u8) ![]u8 {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
            defer parsed.deinit();
            try std.testing.expect(parsed.value == .object);
            if (std.mem.eql(u8, method, "oauth_prompt")) {
                self.prompt_requests += 1;
                return allocator.dupe(u8, "\"prompt-answer\"");
            }
            if (std.mem.eql(u8, method, "oauth_manual_code")) return allocator.dupe(u8, "\"manual-code\"");
            if (std.mem.eql(u8, method, "oauth_select")) {
                self.select_requests += 1;
                return allocator.dupe(u8, "\"team-b\"");
            }
            return error.UnexpectedOAuthUiRequest;
        }

        fn action(raw: ?*anyopaque, allocator: std.mem.Allocator, method: []const u8, args_json: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            var parsed = try std.json.parseFromSlice(std.json.Value, allocator, args_json, .{});
            defer parsed.deinit();
            try std.testing.expect(parsed.value == .object);
            if (std.mem.eql(u8, method, "oauth_auth")) self.auth_actions += 1;
            if (std.mem.eql(u8, method, "oauth_device_code")) {
                self.device_actions += 1;
                try std.testing.expectEqual(@as(i64, 7), parsed.value.object.get("intervalSeconds").?.integer);
                try std.testing.expectEqual(@as(i64, 600), parsed.value.object.get("expiresInSeconds").?.integer);
            }
            if (std.mem.eql(u8, method, "oauth_progress")) self.progress_actions += 1;
        }
    };

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const closure = 'oauth-182';
        \\  pi.registerProvider('extension-oauth', {
        \\    name: 'Extension OAuth', baseUrl: 'https://oauth.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'oauth-model', name: 'Before Login', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      async login(callbacks) {
        \\        callbacks.onAuth({ url: 'https://login.invalid', instructions: 'Open it' });
        \\        callbacks.onDeviceCode({ verificationUri: 'https://device.invalid', userCode: 'DEVICE-182', intervalSeconds: 7, expiresInSeconds: 600, instructions: 'Enter the code' });
        \\        callbacks.onProgress('working');
        \\        const prompt = await callbacks.onPrompt({ message: 'Tenant?' });
        \\        const manual = await callbacks.onManualCodeInput();
        \\        const team = await callbacks.onSelect({ message: 'Team?', options: [{ value: 'team-a', label: 'A' }, { value: 'team-b', label: 'B' }] });
        \\        if (!(callbacks.signal instanceof AbortSignal)) throw new Error('missing login signal');
        \\        return { refresh: 'refresh-login', access: 'access-login', expires: 9999999999999, tenant: { prompt, manual, team }, closure };
        \\      },
        \\      async refreshToken(credentials, signal) {
        \\        if (!(signal instanceof AbortSignal)) throw new Error('missing refresh signal');
        \\        return { ...credentials, access: `refreshed:${credentials.refresh}`, expires: 9999999999999, refreshCount: (credentials.refreshCount ?? 0) + 1 };
        \\      },
        \\      getApiKey(credentials) { return `key:${credentials.access}:${credentials.tenant.team}`; },
        \\      modifyModels(models, credentials) { return models.map((model) => ({ ...model, name: `${model.name}:${credentials.access}` })); },
        \\    },
        \\  });
        \\  pi.registerProvider('incomplete-oauth', {
        \\    name: 'Incomplete OAuth', baseUrl: 'https://incomplete.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'incomplete-model', name: 'Incomplete Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      async login() { return { refresh: 'r', access: 'a', expires: 9999999999999 }; },
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "oauth.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const source_path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "oauth.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config_json = try providerConfigFromManifest(gpa, started.manifest_json, "extension-oauth");
    defer gpa.free(config_json);
    const incomplete_config_json = try providerConfigFromManifest(gpa, started.manifest_json, "incomplete-oauth");
    defer gpa.free(incomplete_config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, root_buf[0..root_len], &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("extension-oauth", config_json, started.runtime);
    try registry.registerJsonWithRuntime("incomplete-oauth", incomplete_config_json, started.runtime);

    var lifecycle = Runtime.init(gpa, io, root_buf[0..root_len], &registry);
    const login_names = try lifecycle.loginProviderNames(gpa);
    defer if (login_names.len > 0) gpa.free(login_names);
    try std.testing.expectEqual(@as(usize, 1), login_names.len);
    try std.testing.expectEqualStrings("extension-oauth", login_names[0]);
    var fake = FakeUi{};
    const persisted = try lifecycle.loginAndPersist("extension-oauth", null, .{
        .context = &fake,
        .request_fn = FakeUi.request,
        .action_fn = FakeUi.action,
    });
    defer gpa.free(persisted);
    try std.testing.expectEqual(@as(usize, 1), fake.auth_actions);
    try std.testing.expectEqual(@as(usize, 1), fake.device_actions);
    try std.testing.expectEqual(@as(usize, 1), fake.progress_actions);
    try std.testing.expectEqual(@as(usize, 1), fake.prompt_requests);
    try std.testing.expectEqual(@as(usize, 1), fake.select_requests);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "prompt-answer") != null);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "manual-code") != null);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "team-b") != null);
    try std.testing.expect(std.mem.indexOf(u8, registry.catalog()[0].display, "access-login") != null);

    var store = try auth_storage.AuthStorage.init(gpa, io, root_buf[0..root_len]);
    defer store.deinit();
    try store.setOAuthJson("extension-oauth", "{\"refresh\":\"refresh-expired\",\"access\":\"old\",\"expires\":1,\"tenant\":{\"team\":\"team-b\"},\"custom\":{\"keep\":true}}");
    const resolved = (try lifecycle.resolve(gpa, "extension-oauth", 1_000_000, null, true)).?;
    defer {
        var owned = resolved;
        owned.deinit(gpa);
    }
    try std.testing.expectEqualStrings("key:refreshed:refresh-expired:team-b", resolved.api_key);
    const refreshed = (try store.readOAuthJson("extension-oauth")).?;
    defer gpa.free(refreshed);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "\"keep\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "\"refreshCount\":1") != null);
}

test "extension OAuth login cancellation aborts the callback without persisting partial credentials" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerProvider('cancel-oauth', {
        \\    name: 'Cancel OAuth', baseUrl: 'https://cancel.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'cancel-model', name: 'Cancel Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      async login(callbacks) {
        \\        await new Promise((resolve, reject) => {
        \\          if (callbacks.signal.aborted) { reject(callbacks.signal.reason); return; }
        \\          const timer = setTimeout(() => reject(new Error('oauth login abort was not delivered')), 1500);
        \\          callbacks.signal.addEventListener('abort', () => { clearTimeout(timer); reject(callbacks.signal.reason); }, { once: true });
        \\        });
        \\        return { refresh: 'must-not-persist', access: 'must-not-persist', expires: 9999999999999 };
        \\      },
        \\      getApiKey(credentials) { return `worker-reused:${credentials.access}`; },
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "cancel-oauth.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const source_path = try std.fs.path.join(gpa, &.{ root_buf[0..root_len], "cancel-oauth.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.timeout_ms = 5000;
    const config_json = try providerConfigFromManifest(gpa, started.manifest_json, "cancel-oauth");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, root_buf[0..root_len], &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("cancel-oauth", config_json, started.runtime);

    var lifecycle = Runtime.init(gpa, io, root_buf[0..root_len], &registry);
    const AbortTask = struct {
        fn run(task_io: Io, flag: *bool) Io.Cancelable!void {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(40), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var aborted = false;
    var group: Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &aborted });
    try std.testing.expectError(
        error.LoginCancelled,
        lifecycle.loginAndPersist("cancel-oauth", &aborted, null),
    );
    try group.await(io);
    try std.testing.expect(lifecycle.lastLoginError("cancel-oauth") != null);
    try std.testing.expect(std.mem.indexOf(u8, lifecycle.lastLoginError("cancel-oauth").?, "Operation aborted") != null);

    var store = try auth_storage.AuthStorage.init(gpa, io, root_buf[0..root_len]);
    defer store.deinit();
    const persisted = try store.readOAuthJson("cancel-oauth");
    defer if (persisted) |value| gpa.free(value);
    try std.testing.expect(persisted == null);

    // The aborted invocation must not poison or replace the persistent worker.
    const key = try registry.oauthApiKey("cancel-oauth", "{\"refresh\":\"r\",\"access\":\"after-abort\",\"expires\":9999999999999}");
    defer gpa.free(key);
    try std.testing.expectEqualStrings("worker-reused:after-abort", key);
}

test "extension OAuth ignores a late noncooperative login result after native cancellation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerProvider('late-oauth', {
        \\    name: 'Late OAuth', baseUrl: 'https://late.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'late-model', name: 'Late Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      async login(_callbacks) {
        \\        await new Promise((resolve) => setTimeout(resolve, 90));
        \\        return { refresh: 'late-refresh', access: 'late-access', expires: 9999999999999, shouldNeverPersist: true };
        \\      },
        \\      getApiKey(credentials) { return `late-worker:${credentials.access}`; },
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "late-oauth.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const source_path = try std.fs.path.join(gpa, &.{ root, "late-oauth.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.oauth_login_timeout_ms = 5000;
    const config_json = try providerConfigFromManifest(gpa, started.manifest_json, "late-oauth");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("late-oauth", config_json, started.runtime);

    var lifecycle = Runtime.init(gpa, io, root, &registry);
    const AbortTask = struct {
        fn run(task_io: Io, flag: *bool) Io.Cancelable!void {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(20), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var aborted = false;
    var group: Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &aborted });
    try std.testing.expectError(error.LoginCancelled, lifecycle.loginAndPersist("late-oauth", &aborted, null));
    try group.await(io);

    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    const persisted = try store.readOAuthJson("late-oauth");
    defer if (persisted) |value| gpa.free(value);
    try std.testing.expect(persisted == null);

    const key = try registry.oauthApiKey("late-oauth", "{\"refresh\":\"r\",\"access\":\"after-late-abort\",\"expires\":9999999999999}");
    defer gpa.free(key);
    try std.testing.expectEqualStrings("late-worker:after-late-abort", key);
}

fn providerConfigFromManifest(gpa: std.mem.Allocator, manifest_json: []const u8, name: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest_json, .{});
    defer parsed.deinit();
    const registrations = parsed.value.object.get("providers") orelse return error.TestProviderNotFound;
    if (registrations != .array) return error.TestProviderNotFound;
    for (registrations.array.items) |entry| {
        if (entry != .object) continue;
        const provider_name = entry.object.get("name") orelse continue;
        const config = entry.object.get("config") orelse continue;
        if (provider_name != .string or !std.mem.eql(u8, provider_name.string, name)) continue;
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(config, .{}, &out.writer);
        return out.toOwnedSlice();
    }
    return error.TestProviderNotFound;
}

test "extension OAuth reload routing follows the replacement registry and unregister removes ownership" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source_a =
        \\export default function(pi) {
        \\  pi.registerProvider('swap-oauth', {
        \\    name: 'Swap OAuth A', baseUrl: 'https://swap.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'swap-model', name: 'Swap Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: { getApiKey(credentials) { return `worker-a:${credentials.access}`; } },
        \\  });
        \\}
    ;
    const source_b =
        \\export default function(pi) {
        \\  pi.registerProvider('swap-oauth', {
        \\    name: 'Swap OAuth B', baseUrl: 'https://swap.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'swap-model', name: 'Swap Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: { getApiKey(credentials) { return `worker-b:${credentials.access}`; } },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "swap-a.mjs", .data = source_a });
    try tmp.dir.writeFile(io, .{ .sub_path = "swap-b.mjs", .data = source_b });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const path_a = try std.fs.path.join(gpa, &.{ root, "swap-a.mjs" });
    defer gpa.free(path_a);
    const path_b = try std.fs.path.join(gpa, &.{ root, "swap-b.mjs" });
    defer gpa.free(path_b);

    var started_a = try js_runtime.Runtime.start(gpa, io, path_a, "node");
    defer started_a.runtime.deinit();
    defer gpa.free(started_a.manifest_json);
    var started_b = try js_runtime.Runtime.start(gpa, io, path_b, "node");
    defer started_b.runtime.deinit();
    defer gpa.free(started_b.manifest_json);
    const config_a = try providerConfigFromManifest(gpa, started_a.manifest_json, "swap-oauth");
    defer gpa.free(config_a);
    const config_b = try providerConfigFromManifest(gpa, started_b.manifest_json, "swap-oauth");
    defer gpa.free(config_b);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry_a = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry_a.deinit();
    var registry_b = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry_b.deinit();
    try registry_a.registerJsonWithRuntime("swap-oauth", config_a, started_a.runtime);
    try registry_b.registerJsonWithRuntime("swap-oauth", config_b, started_b.runtime);

    var store = try auth_storage.AuthStorage.init(gpa, io, root);
    defer store.deinit();
    try store.setOAuthJson("swap-oauth", "{\"refresh\":\"refresh\",\"access\":\"access\",\"expires\":9999999999999}");

    var lifecycle = Runtime.init(gpa, io, root, &registry_a);
    var from_a = (try lifecycle.resolve(gpa, "swap-oauth", 1, null, false)).?;
    defer from_a.deinit(gpa);
    try std.testing.expectEqualStrings("worker-a:access", from_a.api_key);

    lifecycle.registry = &registry_b;
    var from_b = (try lifecycle.resolve(gpa, "swap-oauth", 1, null, false)).?;
    defer from_b.deinit(gpa);
    try std.testing.expectEqualStrings("worker-b:access", from_b.api_key);

    try std.testing.expect(try registry_b.unregister("swap-oauth"));
    try std.testing.expect(!lifecycle.supports("swap-oauth"));
    try std.testing.expect((try lifecycle.resolve(gpa, "swap-oauth", 1, null, false)) == null);
}
