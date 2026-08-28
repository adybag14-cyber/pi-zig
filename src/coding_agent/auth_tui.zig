//! Retained fullscreen provider authentication selector for interactive
//! `/login` and `/logout`.
//!
//! The actual OAuth and credential operations remain authoritative in the
//! slash-command layer. This module owns the original staged authentication-
//! type/provider selection, source-aware status rows, masked API-key entry, and
//! the owned choice returned to the command layer.
const std = @import("std");
const Io = std.Io;
const app_config = @import("../config.zig");
const providers = @import("../ai/providers.zig");
const auth_storage = @import("../auth/storage.zig");
const models_file_mod = @import("models_file.zig");
const config_value = @import("config_value.zig");
const application = @import("../tui/application.zig");
const fuzzy = @import("../tui/fuzzy.zig");
const layout = @import("../tui/layout.zig");
const line_editor = @import("../tui/line_editor.zig");
const mouse = @import("../tui/mouse.zig");
const terminal = @import("../tui/terminal.zig");
const terminal_text = @import("../tui/terminal_text.zig");
const tui_render = @import("../tui/render.zig");

const accent = "\x1b[36m";
const success = "\x1b[32m";
const warning = "\x1b[33m";
const dim = "\x1b[2m";
const bold = "\x1b[1m";
const reverse = "\x1b[7m";
const reset = "\x1b[0m";

pub const Mode = enum { login, logout };
pub const LoginMethod = enum { api_key, browser, device_code };

pub const Selection = struct {
    provider_id: ?[]u8 = null,
    method: ?LoginMethod = null,
    api_key: ?[]u8 = null,
    cancelled: bool = true,

    pub fn deinit(self: *Selection, gpa: std.mem.Allocator) void {
        if (self.provider_id) |value| gpa.free(value);
        if (self.api_key) |value| {
            @memset(value, 0);
            gpa.free(value);
        }
        self.* = undefined;
    }
};

const AuthType = enum { oauth, api_key };

const AuthStatus = struct {
    credential_type: auth_storage.CredentialType,
    source: []const u8,
};

const Entry = struct {
    provider_id: []const u8,
    display_name: []const u8,
    method: LoginMethod,
    status: ?AuthStatus = null,
};

const Ranked = struct { index: usize, score: i32 };
const Phase = enum { auth_type, provider, api_key };

const Selector = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    mode: Mode,
    entries: std.ArrayList(Entry) = .empty,
    owned_strings: std.ArrayList([]u8) = .empty,
    visible: std.ArrayList(usize) = .empty,
    query: std.ArrayList(u8) = .empty,
    secret: std.ArrayList(u8) = .empty,
    selected: usize = 0,
    viewport_rows: usize = 30,
    phase: Phase = .provider,
    selected_auth_type: ?AuthType = null,
    auth_type_selected: usize = 0,
    provider_scope: ?[]const u8 = null,
    entered_from_auth_type: bool = false,
    pending_provider: ?[]const u8 = null,
    done: bool = false,
    cancelled: bool = true,
    result_provider: ?[]u8 = null,
    result_method: ?LoginMethod = null,
    result_key: ?[]u8 = null,
    status: ?[]u8 = null,
    rendered_start: usize = 0,
    rendered_count: usize = 0,
    rendered_row_offset: usize = 0,
    last_click_ms: i64 = 0,
    last_click_index: ?usize = null,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        mode: Mode,
        agent_dir: []const u8,
        catalog: []const providers.ModelInfo,
        initial_query: ?[]const u8,
    ) !Selector {
        return initWithOAuthProviders(gpa, io, environ, mode, agent_dir, catalog, initial_query, &.{});
    }

    fn initWithOAuthProviders(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        mode: Mode,
        agent_dir: []const u8,
        catalog: []const providers.ModelInfo,
        initial_query: ?[]const u8,
        oauth_provider_ids: []const []const u8,
    ) !Selector {
        var self: Selector = .{ .gpa = gpa, .io = io, .environ = environ, .mode = mode };
        errdefer self.deinit();
        try self.buildEntries(agent_dir, catalog, oauth_provider_ids);
        if (mode == .logout) {
            self.phase = .provider;
            if (initial_query) |value| try self.query.appendSlice(gpa, value);
        } else if (initial_query) |raw| {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len > 0) {
                if (self.exactProvider(value)) |provider_id| {
                    self.provider_scope = provider_id;
                    const available = self.authTypesForScope(provider_id);
                    if (available.count == 1) {
                        self.selected_auth_type = if (available.oauth) .oauth else .api_key;
                        try self.selectScopedMethod();
                    } else {
                        self.phase = .auth_type;
                        self.auth_type_selected = if (available.oauth) 0 else 1;
                    }
                } else {
                    self.phase = .provider;
                    try self.query.appendSlice(gpa, value);
                }
            } else {
                self.phase = .auth_type;
            }
        } else {
            self.phase = .auth_type;
        }
        try self.rebuildVisible();
        return self;
    }

    fn deinit(self: *Selector) void {
        if (self.result_provider) |value| self.gpa.free(value);
        if (self.result_key) |value| {
            @memset(value, 0);
            self.gpa.free(value);
        }
        if (self.status) |value| self.gpa.free(value);
        @memset(self.secret.items, 0);
        self.secret.deinit(self.gpa);
        self.query.deinit(self.gpa);
        self.visible.deinit(self.gpa);
        self.entries.deinit(self.gpa);
        for (self.owned_strings.items) |value| self.gpa.free(value);
        self.owned_strings.deinit(self.gpa);
        self.* = undefined;
    }

    fn own(self: *Selector, value: []const u8) ![]const u8 {
        const copy = try self.gpa.dupe(u8, value);
        try self.owned_strings.append(self.gpa, copy);
        return copy;
    }

    fn friendlyName(provider_id: []const u8) []const u8 {
        if (std.ascii.eqlIgnoreCase(provider_id, "openai")) return "OpenAI";
        if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex")) return "OpenAI Codex";
        if (std.ascii.eqlIgnoreCase(provider_id, "anthropic")) return "Anthropic";
        if (std.ascii.eqlIgnoreCase(provider_id, "google")) return "Google";
        if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot")) return "GitHub Copilot";
        if (std.ascii.eqlIgnoreCase(provider_id, "kimi-coding")) return "Kimi Coding";
        if (std.ascii.eqlIgnoreCase(provider_id, "openrouter")) return "OpenRouter";
        if (std.ascii.eqlIgnoreCase(provider_id, "xai")) return "xAI";
        if (std.ascii.eqlIgnoreCase(provider_id, "amazon-bedrock")) return "Amazon Bedrock";
        if (std.ascii.eqlIgnoreCase(provider_id, "qwen-token-plan")) return "Qwen Token Plan";
        if (std.ascii.eqlIgnoreCase(provider_id, "qwen-token-plan-cn")) return "Qwen Token Plan China";
        if (std.ascii.eqlIgnoreCase(provider_id, "qwen-token-plan-individual")) return "Qwen Token Plan Individual";
        return provider_id;
    }

    fn defaultOAuthMethod(provider_id: []const u8) ?LoginMethod {
        if (std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or
            std.ascii.eqlIgnoreCase(provider_id, "kimi-coding") or
            std.ascii.eqlIgnoreCase(provider_id, "xai")) return .device_code;
        if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex") or
            std.ascii.eqlIgnoreCase(provider_id, "anthropic") or
            std.ascii.eqlIgnoreCase(provider_id, "openrouter") or
            std.ascii.eqlIgnoreCase(provider_id, "radius")) return .browser;
        return null;
    }

    fn supportsApiKey(provider_id: []const u8) bool {
        if (std.ascii.eqlIgnoreCase(provider_id, "openai-codex") or
            std.ascii.eqlIgnoreCase(provider_id, "github-copilot") or
            std.ascii.eqlIgnoreCase(provider_id, "kimi-coding") or
            std.ascii.eqlIgnoreCase(provider_id, "radius") or
            std.ascii.eqlIgnoreCase(provider_id, "amazon-bedrock") or
            std.ascii.eqlIgnoreCase(provider_id, "ollama") or
            std.ascii.eqlIgnoreCase(provider_id, "lmstudio") or
            std.ascii.eqlIgnoreCase(provider_id, "vllm") or
            std.ascii.eqlIgnoreCase(provider_id, "mock")) return false;
        return true;
    }

    fn storedStatus(infos: []const auth_storage.CredentialInfo, provider_id: []const u8) ?AuthStatus {
        for (infos) |info| if (std.ascii.eqlIgnoreCase(info.provider_id, provider_id)) return .{
            .credential_type = info.credential_type,
            .source = "stored credential",
        };
        return null;
    }

    fn environmentStatus(self: *const Selector, provider_id: []const u8) ?AuthStatus {
        if (self.environ.get(app_config.ENV_API_KEY) != null) return .{ .credential_type = .api_key, .source = app_config.ENV_API_KEY };
        if (std.ascii.eqlIgnoreCase(provider_id, "anthropic")) {
            if (self.environ.get(app_config.ENV_ANTHROPIC_AUTH_TOKEN) != null) return .{ .credential_type = .api_key, .source = app_config.ENV_ANTHROPIC_AUTH_TOKEN };
            if (self.environ.get(app_config.ENV_ANTHROPIC_OAUTH_TOKEN) != null) return .{ .credential_type = .api_key, .source = app_config.ENV_ANTHROPIC_OAUTH_TOKEN };
        }
        if (providers.Provider.fromString(provider_id)) |builtin| {
            if (!std.ascii.eqlIgnoreCase(provider_id, builtin.name())) return null;
            if (providers.credentialEnvName(builtin)) |env_name| if (self.environ.get(env_name) != null) return .{
                .credential_type = .api_key,
                .source = env_name,
            };
            if (builtin == .google and self.environ.get(app_config.ENV_GEMINI_KEY) != null) return .{
                .credential_type = .api_key,
                .source = app_config.ENV_GEMINI_KEY,
            };
            if (builtin == .amazon_bedrock) {
                if (self.environ.get("AWS_PROFILE") != null) return .{ .credential_type = .api_key, .source = "AWS_PROFILE" };
                if (self.environ.get("AWS_DEFAULT_PROFILE") != null) return .{ .credential_type = .api_key, .source = "AWS_DEFAULT_PROFILE" };
                if (self.environ.get("AWS_ACCESS_KEY_ID") != null and self.environ.get("AWS_SECRET_ACCESS_KEY") != null) return .{ .credential_type = .api_key, .source = "AWS access keys" };
                if (self.environ.get("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") != null or self.environ.get("AWS_CONTAINER_CREDENTIALS_FULL_URI") != null) return .{ .credential_type = .api_key, .source = "ECS task role" };
                if (self.environ.get("AWS_WEB_IDENTITY_TOKEN_FILE") != null) return .{ .credential_type = .api_key, .source = "web identity token" };
                if (self.environ.get("AWS_BEDROCK_SKIP_AUTH")) |value| if (std.mem.eql(u8, value, "1")) return .{ .credential_type = .api_key, .source = "AWS_BEDROCK_SKIP_AUTH" };
            }
        }
        return null;
    }

    fn configuredStatus(
        self: *const Selector,
        provider_id: []const u8,
        infos: []const auth_storage.CredentialInfo,
        models_file: *const models_file_mod.ModelsFile,
    ) ?AuthStatus {
        if (storedStatus(infos, provider_id)) |status| return status;
        if (models_file.findProvider(provider_id)) |provider| if (provider.api_key) |raw| {
            if (!config_value.isCommandConfigValue(raw)) {
                const resolved = config_value.resolveTemplate(self.gpa, self.environ, raw) catch return null;
                if (resolved) |value| self.gpa.free(value) else return null;
            }
            return .{ .credential_type = .api_key, .source = "configured API key" };
        };
        return self.environmentStatus(provider_id);
    }

    fn containsEntry(self: *const Selector, provider_id: []const u8, method: LoginMethod) bool {
        for (self.entries.items) |entry| {
            if (entry.method == method and std.ascii.eqlIgnoreCase(entry.provider_id, provider_id)) return true;
        }
        return false;
    }

    fn appendEntry(
        self: *Selector,
        provider_id_raw: []const u8,
        display_raw: []const u8,
        method: LoginMethod,
        status_raw: ?AuthStatus,
    ) !void {
        if (self.containsEntry(provider_id_raw, method)) return;
        const provider_id = try self.own(provider_id_raw);
        const display_name = if (std.mem.eql(u8, display_raw, provider_id_raw)) provider_id else try self.own(display_raw);
        const status: ?AuthStatus = if (status_raw) |value| .{
            .credential_type = value.credential_type,
            .source = if (std.mem.eql(u8, value.source, "stored credential") or
                std.mem.eql(u8, value.source, "configured API key") or
                std.mem.eql(u8, value.source, "AWS access keys") or
                std.mem.eql(u8, value.source, "ECS task role") or
                std.mem.eql(u8, value.source, "web identity token")) value.source else try self.own(value.source),
        } else null;
        try self.entries.append(self.gpa, .{
            .provider_id = provider_id,
            .display_name = display_name,
            .method = method,
            .status = status,
        });
    }

    fn isOAuthProvider(provider_id: []const u8, oauth_provider_ids: []const []const u8) bool {
        for (oauth_provider_ids) |candidate| {
            if (std.ascii.eqlIgnoreCase(provider_id, candidate)) return true;
        }
        return false;
    }

    fn buildEntries(
        self: *Selector,
        agent_dir: []const u8,
        catalog: []const providers.ModelInfo,
        oauth_provider_ids: []const []const u8,
    ) !void {
        var store = try auth_storage.AuthStorage.init(self.gpa, self.io, agent_dir);
        defer store.deinit();
        const infos = try store.list();
        defer {
            for (infos) |*info| info.deinit(self.gpa);
            if (infos.len > 0) self.gpa.free(infos);
        }
        var models_file = try models_file_mod.load(self.gpa, self.io, agent_dir);
        defer models_file.deinit();

        if (self.mode == .logout) {
            for (infos) |info| {
                try self.appendEntry(
                    info.provider_id,
                    friendlyName(info.provider_id),
                    if (info.credential_type == .oauth) .browser else .api_key,
                    .{ .credential_type = info.credential_type, .source = "stored credential" },
                );
            }
        } else {
            for (catalog) |model| {
                const id = model.providerName();
                const status = self.configuredStatus(id, infos, &models_file);
                if (defaultOAuthMethod(id)) |method| {
                    try self.appendEntry(id, friendlyName(id), method, status);
                } else if (isOAuthProvider(id, oauth_provider_ids)) {
                    try self.appendEntry(id, friendlyName(id), .browser, status);
                }
                if (supportsApiKey(id)) try self.appendEntry(id, friendlyName(id), .api_key, status);
            }
            for (models_file.providers) |provider| {
                const status = self.configuredStatus(provider.id, infos, &models_file);
                if (provider.oauth != null or isOAuthProvider(provider.id, oauth_provider_ids))
                    try self.appendEntry(provider.id, provider.name, .browser, status);
                if (provider.api_key != null or provider.oauth == null) try self.appendEntry(provider.id, provider.name, .api_key, status);
            }
            // An extension may register OAuth before publishing any models. Keep
            // its account flow reachable instead of requiring a catalog entry.
            for (oauth_provider_ids) |provider_id| {
                const status = self.configuredStatus(provider_id, infos, &models_file);
                const display = if (models_file.findProvider(provider_id)) |provider| provider.name else friendlyName(provider_id);
                try self.appendEntry(provider_id, display, .browser, status);
            }
        }

        std.mem.sort(Entry, self.entries.items, {}, struct {
            fn lessThan(_: void, lhs: Entry, rhs: Entry) bool {
                const name_order = std.ascii.orderIgnoreCase(lhs.display_name, rhs.display_name);
                if (name_order != .eq) return name_order == .lt;
                if (lhs.method != rhs.method) return lhs.method == .browser or lhs.method == .device_code;
                return std.ascii.orderIgnoreCase(lhs.provider_id, rhs.provider_id) == .lt;
            }
        }.lessThan);
    }

    fn authTypeForMethod(method: LoginMethod) AuthType {
        return if (method == .api_key) .api_key else .oauth;
    }

    const AuthTypeAvailability = struct {
        oauth: bool = false,
        api_key: bool = false,
        count: usize = 0,
    };

    fn authTypesForScope(self: *const Selector, provider_id: ?[]const u8) AuthTypeAvailability {
        var result: AuthTypeAvailability = .{};
        for (self.entries.items) |entry| {
            if (provider_id) |scope| if (!std.ascii.eqlIgnoreCase(entry.provider_id, scope)) continue;
            switch (authTypeForMethod(entry.method)) {
                .oauth => if (!result.oauth) {
                    result.oauth = true;
                    result.count += 1;
                },
                .api_key => if (!result.api_key) {
                    result.api_key = true;
                    result.count += 1;
                },
            }
        }
        return result;
    }

    fn exactProvider(self: *const Selector, raw: []const u8) ?[]const u8 {
        var found: ?[]const u8 = null;
        for (self.entries.items) |entry| {
            if (!std.ascii.eqlIgnoreCase(entry.provider_id, raw) and !std.ascii.eqlIgnoreCase(entry.display_name, raw)) continue;
            if (found) |existing| {
                if (!std.ascii.eqlIgnoreCase(existing, entry.provider_id)) return null;
            } else found = entry.provider_id;
        }
        return found;
    }

    fn findScopedEntry(self: *const Selector, auth_type: AuthType) ?Entry {
        const scope = self.provider_scope orelse return null;
        for (self.entries.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.provider_id, scope) and authTypeForMethod(entry.method) == auth_type) return entry;
        }
        return null;
    }

    fn selectEntry(self: *Selector, entry: Entry) !void {
        if (self.mode == .login and entry.method == .api_key) {
            self.pending_provider = entry.provider_id;
            self.phase = .api_key;
            self.secret.clearRetainingCapacity();
            return;
        }
        self.result_provider = try self.gpa.dupe(u8, entry.provider_id);
        self.result_method = entry.method;
        self.cancelled = false;
        self.done = true;
    }

    fn selectScopedMethod(self: *Selector) !void {
        const auth_type = self.selected_auth_type orelse return;
        const entry = self.findScopedEntry(auth_type) orelse return error.AuthenticationMethodUnavailable;
        try self.selectEntry(entry);
    }

    fn component(self: *Selector) layout.Component {
        return .{ .context = self, .vtable = &vtable };
    }

    const vtable: layout.Component.VTable = .{
        .render = renderCallback,
        .handle_input = inputCallback,
        .handle_mouse = mouseCallback,
        .set_focus = focusCallback,
    };

    fn renderCallback(context: *anyopaque, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.render(gpa, width);
    }

    fn inputCallback(context: *anyopaque, data: []const u8) !void {
        const self: *Selector = @ptrCast(@alignCast(context));
        try self.handleInput(data);
    }

    fn mouseCallback(context: *anyopaque, event: mouse.Event) !bool {
        const self: *Selector = @ptrCast(@alignCast(context));
        return self.handleMouse(event);
    }

    fn focusCallback(_: *anyopaque, _: bool) void {}

    fn methodLabel(method: LoginMethod) []const u8 {
        return switch (method) {
            .api_key => "API key",
            .browser => "subscription",
            .device_code => "device code",
        };
    }

    fn authTypeLabel(auth_type: AuthType) []const u8 {
        return switch (auth_type) {
            .oauth => "Sign in with an account",
            .api_key => "Sign in with an API key",
        };
    }

    fn authTypeDetail(auth_type: AuthType) []const u8 {
        return switch (auth_type) {
            .oauth => "OAuth, subscription, or device-code authentication",
            .api_key => "Store an API key in auth.json with private permissions",
        };
    }

    fn authTypeAt(self: *const Selector, logical_index: usize) ?AuthType {
        const available = self.authTypesForScope(self.provider_scope);
        var index: usize = 0;
        if (available.oauth) {
            if (logical_index == index) return .oauth;
            index += 1;
        }
        if (available.api_key and logical_index == index) return .api_key;
        return null;
    }

    fn authTypeCount(self: *const Selector) usize {
        return self.authTypesForScope(self.provider_scope).count;
    }

    fn selectAuthType(self: *Selector) !void {
        const selected_type = self.authTypeAt(self.auth_type_selected) orelse return;
        self.selected_auth_type = selected_type;
        if (self.provider_scope != null) {
            try self.selectScopedMethod();
            return;
        }
        self.entered_from_auth_type = true;
        self.phase = .provider;
        self.query.clearRetainingCapacity();
        self.selected = 0;
        try self.rebuildVisible();
    }

    fn scoreEntry(self: *const Selector, entry: Entry) ?i32 {
        if (self.query.items.len == 0) return 0;
        const source = if (entry.status) |status| status.source else "unconfigured";
        const fields = [_][]const u8{ entry.display_name, entry.provider_id, methodLabel(entry.method), source };
        var tokens = std.mem.tokenizeAny(u8, self.query.items, " \t\r\n");
        var total: i32 = 0;
        var matched = false;
        while (tokens.next()) |token| {
            total += fuzzy.bestScore(&fields, token) orelse return null;
            matched = true;
        }
        return if (matched) total else 0;
    }

    fn rebuildVisible(self: *Selector) !void {
        self.visible.clearRetainingCapacity();
        var ranked: std.ArrayList(Ranked) = .empty;
        defer ranked.deinit(self.gpa);
        for (self.entries.items, 0..) |entry, index| {
            if (self.phase == .provider) if (self.selected_auth_type) |auth_type| {
                if (authTypeForMethod(entry.method) != auth_type) continue;
            };
            const score = self.scoreEntry(entry) orelse continue;
            try ranked.append(self.gpa, .{ .index = index, .score = score });
        }
        if (self.query.items.len > 0) std.mem.sort(Ranked, ranked.items, {}, struct {
            fn lessThan(_: void, lhs: Ranked, rhs: Ranked) bool {
                if (lhs.score != rhs.score) return lhs.score > rhs.score;
                return lhs.index < rhs.index;
            }
        }.lessThan);
        for (ranked.items) |entry| try self.visible.append(self.gpa, entry.index);
        self.selected = if (self.visible.items.len == 0) 0 else @min(self.selected, self.visible.items.len - 1);
    }

    fn current(self: *const Selector) ?Entry {
        if (self.selected >= self.visible.items.len) return null;
        return self.entries.items[self.visible.items[self.selected]];
    }

    fn move(self: *Selector, delta: isize) void {
        const count = self.visible.items.len;
        if (count == 0) return;
        if (delta < 0) self.selected = if (self.selected == 0) count - 1 else self.selected - 1 else if (delta > 0) self.selected = if (self.selected + 1 >= count) 0 else self.selected + 1;
    }

    fn pageSize(self: *const Selector) usize {
        return @max(@as(usize, 1), self.viewport_rows -| 9);
    }

    fn selectCurrent(self: *Selector) !void {
        const entry = self.current() orelse return;
        try self.selectEntry(entry);
    }

    fn finishSecret(self: *Selector) !void {
        if (self.secret.items.len == 0) {
            try self.setStatus("API key cannot be empty");
            return;
        }
        self.result_provider = try self.gpa.dupe(u8, self.pending_provider.?);
        self.result_method = .api_key;
        self.result_key = try self.gpa.dupe(u8, self.secret.items);
        self.cancelled = false;
        self.done = true;
    }

    fn setStatus(self: *Selector, message: []const u8) !void {
        if (self.status) |old| self.gpa.free(old);
        self.status = try self.gpa.dupe(u8, message);
    }

    fn popUtf8(list: *std.ArrayList(u8)) void {
        if (list.items.len == 0) return;
        var index = list.items.len - 1;
        while (index > 0 and (list.items[index] & 0xc0) == 0x80) : (index -= 1) {}
        list.shrinkRetainingCapacity(index);
    }

    fn returnFromSecret(self: *Selector) !void {
        @memset(self.secret.items, 0);
        self.secret.clearRetainingCapacity();
        self.pending_provider = null;
        if (self.provider_scope != null) {
            self.phase = .auth_type;
        } else {
            self.phase = .provider;
            try self.rebuildVisible();
        }
    }

    fn backFromProvider(self: *Selector) !void {
        if (self.query.items.len > 0) {
            self.query.clearRetainingCapacity();
            try self.rebuildVisible();
            return;
        }
        if (self.mode == .login and self.entered_from_auth_type) {
            self.phase = .auth_type;
            self.selected_auth_type = null;
            self.entered_from_auth_type = false;
            self.selected = 0;
            return;
        }
        self.cancelled = true;
        self.done = true;
    }

    fn handleDecodedKey(self: *Selector, key: terminal.Key) !void {
        if (self.phase == .api_key) {
            switch (key) {
                .enter => try self.finishSecret(),
                .backspace => popUtf8(&self.secret),
                .delete => {
                    @memset(self.secret.items, 0);
                    self.secret.clearRetainingCapacity();
                },
                .escape => try self.returnFromSecret(),
                .ctrl_c, .ctrl_d => {
                    self.cancelled = true;
                    self.done = true;
                },
                .text => |byte| if (byte >= 0x20 and self.secret.items.len < 64 * 1024) try self.secret.append(self.gpa, byte),
                else => {},
            }
            return;
        }
        if (self.phase == .auth_type) {
            const count = self.authTypeCount();
            switch (key) {
                .up, .left => {
                    if (count > 0) self.auth_type_selected = if (self.auth_type_selected == 0) count - 1 else self.auth_type_selected - 1;
                },
                .down, .right => {
                    if (count > 0) self.auth_type_selected = if (self.auth_type_selected + 1 >= count) 0 else self.auth_type_selected + 1;
                },
                .home => self.auth_type_selected = 0,
                .end => {
                    if (count > 0) self.auth_type_selected = count - 1;
                },
                .enter => try self.selectAuthType(),
                .escape, .ctrl_c, .ctrl_d => {
                    self.cancelled = true;
                    self.done = true;
                },
                else => {},
            }
            return;
        }
        switch (key) {
            .up => self.move(-1),
            .down => self.move(1),
            .home => self.selected = 0,
            .end => {
                if (self.visible.items.len > 0) self.selected = self.visible.items.len - 1;
            },
            .left => self.selected -|= @min(self.selected, self.pageSize()),
            .right => {
                if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            },
            .enter => try self.selectCurrent(),
            .backspace => if (self.query.items.len > 0) {
                popUtf8(&self.query);
                try self.rebuildVisible();
            },
            .delete => if (self.query.items.len > 0) {
                self.query.clearRetainingCapacity();
                try self.rebuildVisible();
            },
            .escape => try self.backFromProvider(),
            .ctrl_c, .ctrl_d => {
                self.cancelled = true;
                self.done = true;
            },
            .text => |byte| if (byte >= 0x20) {
                try self.query.append(self.gpa, byte);
                try self.rebuildVisible();
            },
            else => {},
        }
    }

    fn handleInput(self: *Selector, data: []const u8) !void {
        // A lone Escape is intentionally incomplete according to the generic
        // CSI decoder, but fullscreen selectors receive it as a complete input
        // chunk after the terminal escape timeout. Handle it explicitly so
        // search-clear, back-navigation, and cancellation remain usable.
        if (std.mem.eql(u8, data, "\x1b")) {
            try self.handleDecodedKey(.escape);
            return;
        }
        if (self.phase == .provider and std.mem.eql(u8, data, "\x1b[5~")) {
            self.selected -|= @min(self.selected, self.pageSize());
            return;
        }
        if (self.phase == .provider and std.mem.eql(u8, data, "\x1b[6~")) {
            if (self.visible.items.len > 0) self.selected = @min(self.visible.items.len - 1, self.selected + self.pageSize());
            return;
        }
        var offset: usize = 0;
        while (offset < data.len) {
            const decoded = terminal.decodeKey(data[offset..]) orelse {
                const byte = data[offset];
                if (byte >= 0x20) {
                    if (self.phase == .api_key) {
                        if (self.secret.items.len < 64 * 1024) try self.secret.append(self.gpa, byte);
                    } else if (self.phase == .provider) {
                        try self.query.append(self.gpa, byte);
                        try self.rebuildVisible();
                    }
                }
                offset += 1;
                continue;
            };
            try self.handleDecodedKey(decoded.key);
            offset += decoded.consumed;
        }
    }

    fn handleMouse(self: *Selector, event: mouse.Event) !bool {
        if (self.phase == .api_key) return false;
        if (event.kind == .scroll) {
            switch (event.button) {
                .wheel_up => if (self.phase == .auth_type) try self.handleDecodedKey(.up) else self.move(-3),
                .wheel_down => if (self.phase == .auth_type) try self.handleDecodedKey(.down) else self.move(3),
                else => return false,
            }
            return true;
        }
        if (event.kind != .press or event.button != .left) return false;
        if (event.y < self.rendered_row_offset or event.y >= self.rendered_row_offset + self.rendered_count) return false;
        const local_index = event.y - self.rendered_row_offset;
        if (self.phase == .auth_type) {
            if (local_index >= self.authTypeCount()) return false;
            self.auth_type_selected = local_index;
            const now_ms = std.Io.Clock.awake.now(self.io).toMilliseconds();
            if (self.last_click_index != null and self.last_click_index.? == local_index and now_ms >= self.last_click_ms and now_ms - self.last_click_ms <= 500) {
                self.last_click_index = null;
                self.last_click_ms = 0;
                try self.selectAuthType();
            } else {
                self.last_click_index = local_index;
                self.last_click_ms = now_ms;
            }
            return true;
        }
        const visible_index = self.rendered_start + local_index;
        if (visible_index >= self.visible.items.len) return false;
        self.selected = visible_index;
        const now_ms = std.Io.Clock.awake.now(self.io).toMilliseconds();
        if (self.last_click_index != null and self.last_click_index.? == visible_index and now_ms >= self.last_click_ms and now_ms - self.last_click_ms <= 500) {
            self.last_click_index = null;
            self.last_click_ms = 0;
            try self.selectCurrent();
        } else {
            self.last_click_index = visible_index;
            self.last_click_ms = now_ms;
        }
        return true;
    }

    fn appendClipped(gpa: std.mem.Allocator, lines: *std.ArrayList([]u8), width: usize, owned: []u8) !void {
        defer gpa.free(owned);
        try lines.append(gpa, try terminal_text.truncateAlloc(gpa, owned, width, .{ .ellipsis = "…", .reset_style = true }));
    }

    fn isEnvironmentSource(source: []const u8) bool {
        if (source.len == 0) return false;
        for (source) |byte| {
            if (!(std.ascii.isUpper(byte) or std.ascii.isDigit(byte) or byte == '_')) return false;
        }
        return true;
    }

    fn statusText(self: *const Selector, gpa: std.mem.Allocator, entry: Entry) ![]u8 {
        _ = self;
        const status = entry.status orelse return gpa.dupe(u8, "unconfigured");
        const wanted: auth_storage.CredentialType = if (authTypeForMethod(entry.method) == .oauth) .oauth else .api_key;
        if (status.credential_type != wanted) return gpa.dupe(u8, if (status.credential_type == .oauth) "subscription configured" else "API key configured");
        if (std.mem.eql(u8, status.source, "stored credential")) return gpa.dupe(u8, "configured");
        if (isEnvironmentSource(status.source)) return std.fmt.allocPrint(gpa, "env: {s}", .{status.source});
        return gpa.dupe(u8, status.source);
    }

    fn render(self: *Selector, gpa: std.mem.Allocator, width: usize) !layout.RenderedLines {
        var lines: std.ArrayList([]u8) = .empty;
        errdefer {
            for (lines.items) |line| gpa.free(line);
            lines.deinit(gpa);
        }
        self.rendered_start = 0;
        self.rendered_count = 0;
        self.rendered_row_offset = 0;

        if (self.phase == .api_key) {
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}Configure API key{s}  {s}Enter{s} save  {s}Esc{s} back", .{ bold, reset, dim, reset, dim, reset }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Provider: {s}{s}{s}", .{ accent, self.pending_provider.?, reset }));
            try lines.append(gpa, try gpa.dupe(u8, ""));
            const stars_len = @min(self.secret.items.len, @max(@as(usize, 1), width -| 6));
            const stars = try gpa.alloc(u8, stars_len);
            defer gpa.free(stars);
            @memset(stars, '*');
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Key: {s}_{s}", .{ stars, reset }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}The key is stored in auth.json with private permissions and is never rendered.{s}", .{ dim, reset }));
            if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }));
            return .{ .items = try lines.toOwnedSlice(gpa) };
        }

        if (self.phase == .auth_type) {
            const title = if (self.provider_scope) |provider_id|
                try std.fmt.allocPrint(gpa, "Select authentication method for {s}:", .{provider_id})
            else
                try gpa.dupe(u8, "Select authentication method:");
            defer gpa.free(title);
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}  {s}Enter{s} select  {s}Esc{s} cancel", .{ bold, title, reset, dim, reset, dim, reset }));
            try lines.append(gpa, try gpa.dupe(u8, ""));
            self.rendered_row_offset = 2;
            const count = self.authTypeCount();
            self.rendered_count = count;
            for (0..count) |index| {
                const auth_type = self.authTypeAt(index).?;
                const selected = index == self.auth_type_selected;
                try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s} {s}{s}{s}  {s}{s}{s}", .{
                    if (selected) reverse else "",
                    if (selected) ">" else " ",
                    if (selected) accent else "",
                    authTypeLabel(auth_type),
                    if (selected) reset else "",
                    dim,
                    authTypeDetail(auth_type),
                    reset,
                }));
            }
            if (self.provider_scope) |provider_id| {
                if (self.findScopedEntry(self.authTypeAt(self.auth_type_selected) orelse .oauth)) |entry| {
                    const status = try self.statusText(gpa, entry);
                    defer gpa.free(status);
                    try lines.append(gpa, try gpa.dupe(u8, ""));
                    try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s} · {s}{s}", .{ dim, provider_id, status, reset }));
                }
            }
            return .{ .items = try lines.toOwnedSlice(gpa) };
        }

        const title = if (self.mode == .logout)
            "Select provider to logout:"
        else if (self.selected_auth_type == .oauth)
            "Select subscription provider to configure:"
        else if (self.selected_auth_type == .api_key)
            "Select API key provider to configure:"
        else
            "Select provider to configure:";
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}  {s}Enter{s} select  {s}Esc{s} clear/back", .{ bold, title, reset, dim, reset, dim, reset }));
        try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "Search: {s}{s}_{s}", .{ accent, self.query.items, reset }));
        try lines.append(gpa, try gpa.dupe(u8, ""));
        self.rendered_row_offset = 3;

        if (self.visible.items.len == 0) {
            const empty = if (self.mode == .logout) "No stored credentials to remove" else "No matching authentication providers";
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {s}{s}", .{ dim, empty, reset }));
        } else {
            const count = self.pageSize();
            const half = count / 2;
            var start = self.selected -| half;
            if (start + count > self.visible.items.len) start = self.visible.items.len -| count;
            const end = @min(self.visible.items.len, start + count);
            self.rendered_start = start;
            self.rendered_count = end - start;
            for (self.visible.items[start..end], start..) |entry_index, visible_index| {
                const entry = self.entries.items[entry_index];
                const selected = visible_index == self.selected;
                const status = try self.statusText(gpa, entry);
                defer gpa.free(status);
                const configured = entry.status != null;
                const matching = if (entry.status) |value| value.credential_type == (if (authTypeForMethod(entry.method) == .oauth) auth_storage.CredentialType.oauth else auth_storage.CredentialType.api_key) else false;
                const indicator = if (configured) try std.fmt.allocPrint(gpa, "✓ {s}", .{status}) else try gpa.dupe(u8, status);
                defer gpa.free(indicator);
                try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s} {s}{s}{s} {s}[{s}]{s}  {s}{s}{s}", .{
                    if (selected) reverse else "",
                    if (selected) ">" else " ",
                    if (selected) accent else "",
                    entry.display_name,
                    if (selected) reset else "",
                    dim,
                    methodLabel(entry.method),
                    reset,
                    if (configured and matching) success else if (configured) warning else dim,
                    indicator,
                    reset,
                }));
            }
            try lines.append(gpa, try gpa.dupe(u8, ""));
            const current_entry = self.current().?;
            const current_status = try self.statusText(gpa, current_entry);
            defer gpa.free(current_status);
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {s} · {s} · {s}{s}", .{ dim, current_entry.provider_id, methodLabel(current_entry.method), current_status, reset }));
            try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}  {d}/{d} options · mouse selects · double-click confirms{s}", .{ dim, self.selected + 1, self.visible.items.len, reset }));
        }
        if (self.status) |status| try appendClipped(gpa, &lines, width, try std.fmt.allocPrint(gpa, "{s}{s}{s}", .{ warning, status, reset }));
        return .{ .items = try lines.toOwnedSlice(gpa) };
    }
};

fn readInputChunk(io: Io, reader: ?*Io.File.Reader, buffer: []u8) !usize {
    if (reader) |buffered| {
        const available = buffered.interface.bufferedLen();
        if (available > 0) {
            const count = @min(available, buffer.len);
            const source = try buffered.interface.take(count);
            @memcpy(buffer[0..count], source);
            return count;
        }
    }
    var slices = [_][]u8{buffer};
    return Io.File.stdin().readStreaming(io, &slices);
}

pub fn run(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    agent_dir: []const u8,
    catalog: []const providers.ModelInfo,
    mode: Mode,
    initial_query: ?[]const u8,
    already_fullscreen: bool,
) !Selection {
    return runWithOAuthProviders(
        gpa,
        io,
        environ,
        reader,
        agent_dir,
        catalog,
        &.{},
        mode,
        initial_query,
        already_fullscreen,
    );
}

pub fn runWithOAuthProviders(
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    reader: ?*Io.File.Reader,
    agent_dir: []const u8,
    catalog: []const providers.ModelInfo,
    oauth_provider_ids: []const []const u8,
    mode: Mode,
    initial_query: ?[]const u8,
    already_fullscreen: bool,
) !Selection {
    if (!terminal.supportsFullscreen(io)) return error.UnsupportedTerminal;
    var selector = try Selector.initWithOAuthProviders(gpa, io, environ, mode, agent_dir, catalog, initial_query, oauth_provider_ids);
    defer selector.deinit();
    var app = application.Application.init(gpa, selector.component());
    defer app.deinit();
    app.setFocus(selector.component());

    var raw = try line_editor.RawMode.enter();
    defer raw.leave();
    if (already_fullscreen) {
        try tui_render.writeAll(io, terminal.clear_screen ++ terminal.hide_cursor ++ terminal.bracketed_paste_enable ++ application.mouse_enable);
        defer tui_render.writeAll(io, application.mouse_disable ++ terminal.bracketed_paste_disable ++ terminal.show_cursor ++ terminal.clear_screen) catch {};
    } else {
        try app.start(io);
        defer app.stop(io) catch {};
    }

    var input_buffer: [4096]u8 = undefined;
    while (!selector.done) {
        const dimensions = terminal.terminalDimensions(environ, .{ .columns = 100, .rows = 30 });
        selector.viewport_rows = dimensions.rows;
        try app.paint(io, dimensions.columns, dimensions.rows);
        const count = readInputChunk(io, reader, input_buffer[0..]) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (count == 0) break;
        try app.handleInput(input_buffer[0..count]);
    }

    return .{
        .provider_id = if (selector.result_provider) |value| try gpa.dupe(u8, value) else null,
        .method = selector.result_method,
        .api_key = if (selector.result_key) |value| try gpa.dupe(u8, value) else null,
        .cancelled = selector.cancelled,
    };
}

fn testCatalog() [5]providers.ModelInfo {
    return .{
        .{ .provider = .openai, .id = "gpt-test", .display = "GPT Test" },
        .{ .provider = .anthropic, .id = "claude-test", .display = "Claude Test" },
        .{ .provider = .github_copilot, .id = "copilot-test", .display = "Copilot Test" },
        .{ .provider = .ollama, .id = "local-test", .display = "Local Test" },
        .{ .provider = .xai, .id = "grok-test", .display = "Grok Test" },
    };
}

fn createAgentDir(gpa: std.mem.Allocator, io: Io, tmp: *std.testing.TmpDir) ![]u8 {
    var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buffer);
    return gpa.dupe(u8, buffer[0..n]);
}

test "auth selector exposes subscription and API-key choices without local providers" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const catalog = testCatalog();
    var selector = try Selector.init(gpa, io, &env, .login, dir, &catalog, null);
    defer selector.deinit();
    try std.testing.expect(selector.containsEntry("anthropic", .browser));
    try std.testing.expect(selector.containsEntry("anthropic", .api_key));
    try std.testing.expect(selector.containsEntry("github-copilot", .device_code));
    try std.testing.expect(!selector.containsEntry("github-copilot", .api_key));
    try std.testing.expect(!selector.containsEntry("ollama", .api_key));
    try std.testing.expectEqual(Phase.auth_type, selector.phase);
    selector.selected_auth_type = null;
    selector.phase = .provider;
    try selector.query.appendSlice(gpa, "openai api key");
    try selector.rebuildVisible();
    try std.testing.expect(selector.visible.items.len > 0);
    const matched = selector.entries.items[selector.visible.items[0]];
    try std.testing.expectEqualStrings("openai", matched.provider_id);
    try std.testing.expectEqual(LoginMethod.api_key, matched.method);
}

test "auth selector exposes extension OAuth providers without catalog models" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const catalog = testCatalog();
    const oauth_providers = [_][]const u8{ "extension-account", "anthropic" };
    var selector = try Selector.initWithOAuthProviders(gpa, io, &env, .login, dir, &catalog, null, &oauth_providers);
    defer selector.deinit();
    try std.testing.expect(selector.containsEntry("extension-account", .browser));
    try std.testing.expect(selector.containsEntry("anthropic", .browser));
    try std.testing.expect(!selector.containsEntry("extension-account", .device_code));
}

test "auth selector masks API key and returns owned choice" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const catalog = testCatalog();
    var selector = try Selector.init(gpa, io, &env, .login, dir, &catalog, null);
    defer selector.deinit();
    selector.auth_type_selected = 1;
    try selector.selectAuthType();
    try std.testing.expectEqual(Phase.provider, selector.phase);
    for (selector.visible.items, 0..) |entry_index, visible_index| {
        const entry = selector.entries.items[entry_index];
        if (entry.method == .api_key and std.ascii.eqlIgnoreCase(entry.provider_id, "openai")) {
            selector.selected = visible_index;
            break;
        }
    }
    try selector.selectCurrent();
    try std.testing.expectEqual(Phase.api_key, selector.phase);
    try selector.handleInput("secret-177");
    var rendered = try selector.render(gpa, 100);
    defer rendered.deinit(gpa);
    for (rendered.items) |line| try std.testing.expect(std.mem.indexOf(u8, line, "secret-177") == null);
    try selector.handleInput("\r");
    try std.testing.expect(!selector.cancelled);
    try std.testing.expectEqualStrings("openai", selector.result_provider.?);
    try std.testing.expectEqualStrings("secret-177", selector.result_key.?);
}

test "logout selector contains only persisted credentials" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    var store = try auth_storage.AuthStorage.init(gpa, io, dir);
    defer store.deinit();
    try store.setApiKey("openai", "secret");
    const catalog = testCatalog();
    var selector = try Selector.init(gpa, io, &env, .logout, dir, &catalog, null);
    defer selector.deinit();
    try std.testing.expectEqual(@as(usize, 1), selector.entries.items.len);
    try std.testing.expectEqualStrings("openai", selector.entries.items[0].provider_id);
    try std.testing.expectEqual(LoginMethod.api_key, selector.entries.items[0].method);
}

test "auth selector uses separate authentication type and provider stages" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const catalog = testCatalog();

    var selector = try Selector.init(gpa, io, &env, .login, dir, &catalog, null);
    defer selector.deinit();
    try std.testing.expectEqual(Phase.auth_type, selector.phase);
    try std.testing.expectEqual(@as(usize, 2), selector.authTypeCount());
    selector.auth_type_selected = 0;
    try selector.selectAuthType();
    try std.testing.expectEqual(Phase.provider, selector.phase);
    try std.testing.expectEqual(AuthType.oauth, selector.selected_auth_type.?);
    for (selector.visible.items) |entry_index| try std.testing.expect(Selector.authTypeForMethod(selector.entries.items[entry_index].method) == .oauth);
    try selector.backFromProvider();
    try std.testing.expectEqual(Phase.auth_type, selector.phase);
    try selector.handleInput("\x1b");
    try std.testing.expect(selector.done and selector.cancelled);
}

test "explicit provider with multiple methods opens scoped authentication type stage" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const catalog = testCatalog();

    var selector = try Selector.init(gpa, io, &env, .login, dir, &catalog, "anthropic");
    defer selector.deinit();
    try std.testing.expectEqual(Phase.auth_type, selector.phase);
    try std.testing.expectEqualStrings("anthropic", selector.provider_scope.?);
    try std.testing.expectEqual(@as(usize, 2), selector.authTypeCount());
    selector.auth_type_selected = 1;
    try selector.selectAuthType();
    try std.testing.expectEqual(Phase.api_key, selector.phase);
    try std.testing.expectEqualStrings("anthropic", selector.pending_provider.?);
}

test "auth selector reports stored models and environment credential sources" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("OPENAI_API_KEY", "env-secret");
    try env.put("CORP_API_KEY", "corp-secret");
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try createAgentDir(gpa, io, &tmp);
    defer gpa.free(dir);
    const models_path = try std.fs.path.join(gpa, &.{ dir, "models.json" });
    defer gpa.free(models_path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = models_path, .data =
        \\{"providers":{"corp":{"name":"Corp","baseUrl":"https://corp.example/v1","api":"openai-completions","apiKey":"$CORP_API_KEY","models":[{"id":"fast"}]}}}
    });
    var store = try auth_storage.AuthStorage.init(gpa, io, dir);
    defer store.deinit();
    try store.setApiKey("anthropic", "stored-secret");
    const catalog = testCatalog();

    var selector = try Selector.init(gpa, io, &env, .login, dir, &catalog, null);
    defer selector.deinit();
    var saw_openai = false;
    var saw_anthropic = false;
    var saw_corp = false;
    for (selector.entries.items) |entry| {
        if (std.ascii.eqlIgnoreCase(entry.provider_id, "openai") and entry.method == .api_key) {
            try std.testing.expectEqualStrings("OPENAI_API_KEY", entry.status.?.source);
            saw_openai = true;
        }
        if (std.ascii.eqlIgnoreCase(entry.provider_id, "anthropic") and entry.method == .browser) {
            try std.testing.expectEqualStrings("stored credential", entry.status.?.source);
            try std.testing.expectEqual(auth_storage.CredentialType.api_key, entry.status.?.credential_type);
            saw_anthropic = true;
        }
        if (std.ascii.eqlIgnoreCase(entry.provider_id, "corp") and entry.method == .api_key) {
            try std.testing.expectEqualStrings("configured API key", entry.status.?.source);
            saw_corp = true;
        }
    }
    try std.testing.expect(saw_openai and saw_anthropic and saw_corp);
}
