//! Declarative provider registrations emitted by JavaScript/TypeScript extensions.
//!
//! The upstream extension API allows `pi.registerProvider()` at module load or
//! from a later callback. Pi Zig deliberately routes the serializable subset
//! through the same models.json parser and runtime resolver as on-disk custom
//! providers. This gives registrations identical API/base URL/header/cost/
//! thinking semantics without persisting extension-owned configuration.
const std = @import("std");
const Io = std.Io;
const providers = @import("../ai/providers.zig");
const models_file_mod = @import("../coding_agent/models_file.zig");
const runtime_config = @import("../coding_agent/runtime_config.zig");
const live_state = @import("../coding_agent/live_state.zig");
const js_runtime = @import("js_runtime.zig");
const provider_method_ref = @import("../provider_method_ref.zig");

const CallbackOwner = struct {
    callback_id: []u8,
    path: []u8,
    generation: u64,
    runtime: *js_runtime.Runtime,

    fn deinit(self: *CallbackOwner, gpa: std.mem.Allocator) void {
        gpa.free(self.callback_id);
        gpa.free(self.path);
        self.* = undefined;
    }
};

const CollectedMethodRef = struct {
    callback_id: []u8,
    path: []u8,
    generation: u64,

    fn deinit(self: *CollectedMethodRef, gpa: std.mem.Allocator) void {
        gpa.free(self.callback_id);
        gpa.free(self.path);
        self.* = undefined;
    }
};

const Registration = struct {
    gpa: std.mem.Allocator,
    name: []u8,
    config_json: []u8,
    models_file: models_file_mod.ModelsFile,
    replaces_models: bool,
    resolved: []runtime_config.ResolvedRuntime,
    runtime_configs: []live_state.RuntimeProviderConfig,
    callback_owners: []CallbackOwner,

    fn init(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        agent_dir: ?[]const u8,
        baseline_catalog: []const providers.ModelInfo,
        name: []const u8,
        incoming_json: []const u8,
        config_json: []const u8,
        incoming_runtime: ?*js_runtime.Runtime,
        previous: ?*const Registration,
    ) !Registration {
        var config = try std.json.parseFromSlice(std.json.Value, gpa, config_json, .{});
        defer config.deinit();
        if (config.value != .object) return error.InvalidExtensionProviderConfig;
        const replaces_models = config.value.object.get("models") != null;

        var incoming = try std.json.parseFromSlice(std.json.Value, gpa, incoming_json, .{});
        defer incoming.deinit();
        if (incoming.value != .object) return error.InvalidExtensionProviderConfig;
        var incoming_refs: std.ArrayList(CollectedMethodRef) = .empty;
        defer deinitCollectedRefs(gpa, &incoming_refs);
        var incoming_path: std.ArrayList(u8) = .empty;
        defer incoming_path.deinit(gpa);
        try collectMethodRefs(gpa, incoming.value, &incoming_path, &incoming_refs);

        var effective_refs: std.ArrayList(CollectedMethodRef) = .empty;
        defer deinitCollectedRefs(gpa, &effective_refs);
        var effective_path: std.ArrayList(u8) = .empty;
        defer effective_path.deinit(gpa);
        try collectMethodRefs(gpa, config.value, &effective_path, &effective_refs);

        const callback_owners = try buildCallbackOwners(gpa, effective_refs.items, incoming_refs.items, incoming_runtime, previous);
        errdefer {
            for (callback_owners) |*owner| owner.deinit(gpa);
            if (callback_owners.len > 0) gpa.free(callback_owners);
        }

        const document = try providerDocument(gpa, name, config.value);
        defer gpa.free(document);
        var models_file = try models_file_mod.parseFromSlice(gpa, document);
        errdefer models_file.deinit();
        if (models_file.findProvider(name) == null) return error.InvalidExtensionProviderConfig;

        var targets: std.ArrayList(providers.ModelInfo) = .empty;
        defer targets.deinit(gpa);
        if (replaces_models) {
            try targets.appendSlice(gpa, models_file.model_infos);
        } else {
            for (baseline_catalog) |model| {
                if (std.ascii.eqlIgnoreCase(model.providerName(), name)) try targets.append(gpa, model);
            }
        }

        var resolved_list: std.ArrayList(runtime_config.ResolvedRuntime) = .empty;
        errdefer {
            for (resolved_list.items) |*runtime| runtime.deinit();
            resolved_list.deinit(gpa);
        }
        for (targets.items) |model| {
            var resolved = try runtime_config.resolveForModel(gpa, io, environ, &models_file, model, .{
                .agent_dir = agent_dir,
                .allow_generic_api_key = false,
            });
            errdefer resolved.deinit();
            try resolved_list.append(gpa, resolved);
        }
        const resolved = try resolved_list.toOwnedSlice(gpa);
        errdefer {
            for (resolved) |*runtime| runtime.deinit();
            if (resolved.len > 0) gpa.free(resolved);
        }

        const configs = try gpa.alloc(live_state.RuntimeProviderConfig, resolved.len);
        errdefer if (configs.len > 0) gpa.free(configs);
        for (resolved, 0..) |*runtime, index| {
            configs[index] = runtimeConfig(runtime);
        }

        const owned_name = try gpa.dupe(u8, name);
        errdefer gpa.free(owned_name);
        return .{
            .gpa = gpa,
            .name = owned_name,
            .config_json = try gpa.dupe(u8, config_json),
            .models_file = models_file,
            .replaces_models = replaces_models,
            .resolved = resolved,
            .runtime_configs = configs,
            .callback_owners = callback_owners,
        };
    }

    fn deinit(self: *Registration) void {
        for (self.resolved) |*runtime| runtime.deinit();
        if (self.resolved.len > 0) self.gpa.free(self.resolved);
        if (self.runtime_configs.len > 0) self.gpa.free(self.runtime_configs);
        for (self.callback_owners) |*owner| owner.deinit(self.gpa);
        if (self.callback_owners.len > 0) self.gpa.free(self.callback_owners);
        self.models_file.deinit();
        self.gpa.free(self.name);
        self.gpa.free(self.config_json);
        self.* = undefined;
    }

    fn callbackRuntime(self: *const Registration, callback_id: []const u8, path: []const u8, generation: u64) ?*js_runtime.Runtime {
        for (self.callback_owners) |owner| {
            if (owner.generation == generation and std.mem.eql(u8, owner.callback_id, callback_id) and std.mem.eql(u8, owner.path, path)) return owner.runtime;
        }
        return null;
    }
};

pub const Registry = struct {
    gpa: std.mem.Allocator,
    io: Io,
    environ: *const std.process.Environ.Map,
    agent_dir: ?[]const u8,
    baseline_catalog: []const providers.ModelInfo,
    baseline_runtimes: []const live_state.RuntimeProviderConfig,
    registrations: std.ArrayList(Registration) = .empty,
    catalog_snapshot: []providers.ModelInfo = &.{},
    runtime_snapshot: []live_state.RuntimeProviderConfig = &.{},
    owns_snapshots: bool = false,

    pub fn init(
        gpa: std.mem.Allocator,
        io: Io,
        environ: *const std.process.Environ.Map,
        agent_dir: ?[]const u8,
        baseline_catalog: []const providers.ModelInfo,
        baseline_runtimes: []const live_state.RuntimeProviderConfig,
    ) Registry {
        return .{
            .gpa = gpa,
            .io = io,
            .environ = environ,
            .agent_dir = agent_dir,
            .baseline_catalog = baseline_catalog,
            .baseline_runtimes = baseline_runtimes,
            .catalog_snapshot = @constCast(baseline_catalog),
            .runtime_snapshot = @constCast(baseline_runtimes),
        };
    }

    pub fn deinit(self: *Registry) void {
        for (self.registrations.items) |*registration| {
            self.handoffCallbacks(registration.name, registration, null);
        }
        if (self.owns_snapshots) {
            if (self.catalog_snapshot.len > 0) self.gpa.free(self.catalog_snapshot);
            if (self.runtime_snapshot.len > 0) self.gpa.free(self.runtime_snapshot);
        }
        for (self.registrations.items) |*registration| registration.deinit();
        self.registrations.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn catalog(self: *const Registry) []const providers.ModelInfo {
        return self.catalog_snapshot;
    }

    pub fn runtimes(self: *const Registry) []const live_state.RuntimeProviderConfig {
        return self.runtime_snapshot;
    }

    pub fn count(self: *const Registry) usize {
        return self.registrations.items.len;
    }

    pub fn contains(self: *const Registry, name: []const u8) bool {
        return self.findIndex(name) != null;
    }

    /// Register a provider without JavaScript callback ownership. This remains
    /// the entry point for native manifests and tests containing only data.
    pub fn registerJson(self: *Registry, name: []const u8, config_json: []const u8) !void {
        return self.registerJsonWithRuntime(name, config_json, null);
    }

    /// Register or shallow-merge a provider and associate callback descriptors
    /// introduced by this registration with their persistent extension worker.
    /// A failed re-registration leaves the previous registration and snapshots
    /// untouched.
    pub fn registerJsonWithRuntime(
        self: *Registry,
        name: []const u8,
        config_json: []const u8,
        runtime: ?*js_runtime.Runtime,
    ) !void {
        if (name.len == 0) return error.InvalidExtensionProviderName;
        var incoming = try std.json.parseFromSlice(std.json.Value, self.gpa, config_json, .{});
        defer incoming.deinit();
        if (incoming.value != .object) return error.InvalidExtensionProviderConfig;

        const existing_index = self.findIndex(name);
        const effective_json = if (existing_index) |index|
            try mergeObjects(self.gpa, self.registrations.items[index].config_json, config_json)
        else
            try self.gpa.dupe(u8, config_json);
        defer self.gpa.free(effective_json);

        var replacement = try Registration.init(
            self.gpa,
            self.io,
            self.environ,
            self.agent_dir,
            self.baseline_catalog,
            name,
            config_json,
            effective_json,
            runtime,
            if (existing_index) |index| &self.registrations.items[index] else null,
        );

        if (existing_index) |index| {
            var old = self.registrations.items[index];
            self.registrations.items[index] = replacement;
            self.rebuild() catch |err| {
                self.registrations.items[index] = old;
                replacement.deinit();
                return err;
            };
            self.handoffCallbacks(name, &old, &self.registrations.items[index]);
            old.deinit();
        } else {
            self.registrations.append(self.gpa, replacement) catch |err| {
                replacement.deinit();
                return err;
            };
            self.rebuild() catch |err| {
                var removed = self.registrations.pop().?;
                removed.deinit();
                return err;
            };
            self.handoffCallbacks(name, null, &self.registrations.items[self.registrations.items.len - 1]);
        }
    }

    /// Invoke a JSON-safe provider callback by its descriptor path. The returned
    /// slice is the callback value itself as JSON, not the worker envelope.
    pub fn invokeProviderMethod(
        self: *Registry,
        name: []const u8,
        path: []const u8,
        args_json: []const u8,
        append_signal: bool,
        abort_flag: ?*bool,
    ) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, path);
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, path)) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        const envelope = try runtime.invokeProviderMethod(method.callback_id, args_json, append_signal, abort_flag);
        defer self.gpa.free(envelope);
        return unwrapProviderMethodValue(self.gpa, envelope);
    }

    pub fn hasProviderMethod(self: *const Registry, name: []const u8, path: []const u8) bool {
        const index = self.findIndex(name) orelse return false;
        const registration = &self.registrations.items[index];
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{}) catch return false;
        defer parsed.deinit();
        const descriptor_value = valueAtProviderPath(parsed.value, path) catch return false;
        const method = provider_method_ref.ProviderMethodRef.fromJson(descriptor_value) catch return false;
        return std.mem.eql(u8, method.path, path) and registration.callbackRuntime(method.callback_id, method.path, method.generation) != null;
    }

    /// Invoke extension-defined OAuth login with the native interaction bridge
    /// installed only for the lifetime of this call. The returned object is the
    /// credential value itself; persistence is intentionally owned by auth storage.
    pub fn loginOAuth(
        self: *Registry,
        name: []const u8,
        abort_flag: ?*bool,
        bridge: ?js_runtime.UiBridge,
    ) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, "oauth.login");
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, "oauth.login")) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        const envelope = try runtime.invokeProviderOAuthLogin(method.callback_id, abort_flag, bridge);
        defer self.gpa.free(envelope);
        const result = try unwrapProviderMethodValue(self.gpa, envelope);
        errdefer self.gpa.free(result);
        try validateOAuthCredentialJson(self.gpa, result);
        return result;
    }

    /// Invoke extension-defined dynamic model discovery on the callback's
    /// owning persistent worker. `refresh_context_json` is the host-owned
    /// credential/store/network/generation snapshot. `context.publish()` calls
    /// are routed through `bridge` before the final model array is returned.
    pub fn refreshModels(
        self: *Registry,
        name: []const u8,
        refresh_context_json: []const u8,
        abort_flag: ?*bool,
        bridge: js_runtime.UiBridge,
    ) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, "refreshModels");
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, "refreshModels")) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        const envelope = try runtime.invokeProviderRefreshModels(method.callback_id, name, refresh_context_json, abort_flag, bridge);
        defer self.gpa.free(envelope);
        return unwrapRefreshModels(self.gpa, envelope);
    }

    /// Invoke extension-defined `streamSimple(model, context, options)` through
    /// the exact callback owner retained by the registration generation. Events
    /// are acknowledged one at a time by `event_fn`; the returned object is the
    /// worker's terminal protocol summary rather than the assistant response.
    pub fn streamSimple(
        self: *Registry,
        name: []const u8,
        model_json: []const u8,
        stream_context_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
        event_fn: js_runtime.ProviderStreamEventFn,
        event_ctx: ?*anyopaque,
    ) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, "streamSimple");
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, "streamSimple")) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        return runtime.invokeProviderStreamSimple(
            name,
            method.callback_id,
            method.generation,
            model_json,
            stream_context_json,
            options_json,
            abort_flag,
            event_fn,
            event_ctx,
        );
    }

    pub fn fetchDeferred(
        self: *Registry,
        name: []const u8,
        model_json: []const u8,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
        event_fn: js_runtime.ProviderStreamEventFn,
        event_ctx: ?*anyopaque,
    ) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, "fetchDeferred");
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, "fetchDeferred")) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        return runtime.invokeProviderFetchDeferred(
            name,
            method.callback_id,
            method.generation,
            model_json,
            handle_json,
            options_json,
            abort_flag,
            event_fn,
            event_ctx,
        );
    }

    pub fn cancelDeferred(
        self: *Registry,
        name: []const u8,
        model_json: []const u8,
        handle_json: []const u8,
        options_json: []const u8,
        abort_flag: ?*bool,
    ) !void {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        const descriptor_value = try valueAtProviderPath(parsed.value, "cancelDeferred");
        const method = try provider_method_ref.ProviderMethodRef.fromJson(descriptor_value);
        if (!std.mem.eql(u8, method.path, "cancelDeferred")) return error.ProviderMethodPathMismatch;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return error.ProviderMethodRuntimeMissing;
        const result = try runtime.invokeProviderCancelDeferred(
            name,
            method.callback_id,
            method.generation,
            model_json,
            handle_json,
            options_json,
            abort_flag,
        );
        self.gpa.free(result);
    }

    /// Owned names for dynamic extension providers. Refresh publication can
    /// transactionally replace a registration while the caller is iterating,
    /// so borrowing `Registration.name` here would leave the active provider ID
    /// dangling after the first catalog commit. The caller owns every string and
    /// the outer slice.
    pub fn refreshProviderNames(self: *const Registry, gpa: std.mem.Allocator) ![][]u8 {
        var names: std.ArrayList([]u8) = .empty;
        errdefer {
            for (names.items) |name| gpa.free(name);
            names.deinit(gpa);
        }
        for (self.registrations.items) |registration| {
            if (self.hasProviderMethod(registration.name, "refreshModels")) {
                try names.append(gpa, try gpa.dupe(u8, registration.name));
            }
        }
        return names.toOwnedSlice(gpa);
    }

    /// Return the effective configured API key as a canonical credential object
    /// for `RefreshModelsContext.credential`. Runtime resolution has already
    /// expanded environment references and command substitutions.
    pub fn configuredApiKeyCredentialJson(self: *const Registry, name: []const u8) !?[]u8 {
        const index = self.findIndex(name) orelse return null;
        const registration = &self.registrations.items[index];
        for (registration.runtime_configs) |runtime| {
            const key = runtime.api_key orelse continue;
            var out: std.Io.Writer.Allocating = .init(self.gpa);
            errdefer out.deinit();
            try out.writer.writeAll("{\"type\":\"api_key\",\"key\":");
            try std.json.Stringify.value(key, .{}, &out.writer);
            try out.writer.writeByte('}');
            return @as(?[]u8, try out.toOwnedSlice());
        }
        return null;
    }

    /// Return the most recent JavaScript error for a provider callback. The
    /// slice remains owned by the persistent worker and is invalidated by its
    /// next invocation.
    pub fn providerMethodLastError(self: *const Registry, name: []const u8, path: []const u8) ?[]const u8 {
        const index = self.findIndex(name) orelse return null;
        const registration = &self.registrations.items[index];
        var parsed = std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{}) catch return null;
        defer parsed.deinit();
        const descriptor_value = valueAtProviderPath(parsed.value, path) catch return null;
        const method = provider_method_ref.ProviderMethodRef.fromJson(descriptor_value) catch return null;
        if (!std.mem.eql(u8, method.path, path)) return null;
        const runtime = registration.callbackRuntime(method.callback_id, method.path, method.generation) orelse return null;
        return runtime.lastError();
    }

    /// Return borrowed names for extension providers that expose a usable
    /// legacy OAuth login surface. A login callback without `getApiKey` cannot
    /// produce request authentication, so it must not appear as a selectable
    /// `/login` target. The caller owns only the outer slice.
    pub fn oauthProviderNames(self: *const Registry, gpa: std.mem.Allocator) ![][]const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        errdefer names.deinit(gpa);
        for (self.registrations.items) |registration| {
            if (self.hasProviderMethod(registration.name, "oauth.login") and
                self.hasProviderMethod(registration.name, "oauth.getApiKey"))
            {
                try names.append(gpa, registration.name);
            }
        }
        return names.toOwnedSlice(gpa);
    }

    /// Serialize the provider's current model array in the extension-facing
    /// shape consumed by `oauth.modifyModels`.
    pub fn providerModelsJson(self: *const Registry, name: []const u8) ![]u8 {
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        const registration = &self.registrations.items[index];
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, registration.config_json, .{});
        defer parsed.deinit();
        if (parsed.value.object.get("models")) |models| {
            if (models != .array) return error.InvalidExtensionProviderModels;
            var out: std.Io.Writer.Allocating = .init(self.gpa);
            errdefer out.deinit();
            try std.json.Stringify.value(models, .{}, &out.writer);
            return out.toOwnedSlice();
        }

        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.writeByte('[');
        var wrote = false;
        for (self.catalog_snapshot) |model| {
            if (!std.ascii.eqlIgnoreCase(model.providerName(), name)) continue;
            if (wrote) try out.writer.writeByte(',');
            wrote = true;
            try writeProviderModelJson(&out.writer, model);
        }
        try out.writer.writeByte(']');
        return out.toOwnedSlice();
    }

    /// Validate a prospective dynamic model array against the complete effective
    /// provider configuration without mutating registrations or published snapshots.
    pub fn validateDynamicModels(self: *Registry, name: []const u8, models_json: []const u8) !void {
        try validateArrayJson(self.gpa, models_json);
        const index = self.findIndex(name) orelse return error.ExtensionProviderNotRegistered;
        var patch: std.Io.Writer.Allocating = .init(self.gpa);
        defer patch.deinit();
        try patch.writer.writeAll("{\"models\":");
        try patch.writer.writeAll(models_json);
        try patch.writer.writeByte('}');
        const effective = try mergeObjects(self.gpa, self.registrations.items[index].config_json, patch.written());
        defer self.gpa.free(effective);
        var candidate = try Registration.init(
            self.gpa,
            self.io,
            self.environ,
            self.agent_dir,
            self.baseline_catalog,
            name,
            patch.written(),
            effective,
            null,
            &self.registrations.items[index],
        );
        candidate.deinit();
    }

    /// Publish a validated dynamic model array through the same transactional
    /// registration path used by extension re-registration. Callback ownership
    /// survives because this patch contains only the `models` field.
    pub fn applyDynamicModels(self: *Registry, name: []const u8, models_json: []const u8) !void {
        try validateArrayJson(self.gpa, models_json);
        var patch: std.Io.Writer.Allocating = .init(self.gpa);
        defer patch.deinit();
        try patch.writer.writeAll("{\"models\":");
        try patch.writer.writeAll(models_json);
        try patch.writer.writeByte('}');
        try self.registerJson(name, patch.written());
    }

    /// Publish credential-dependent model projection through the same
    /// transactional registration path as JavaScript re-registration. Callback
    /// descriptors and their owning worker survive because this patch is data-only.
    pub fn applyOAuthModels(self: *Registry, name: []const u8, models_json: []const u8) !void {
        return self.applyDynamicModels(name, models_json);
    }

    /// OAuth refreshToken receives `(credential, signal)` in the upstream API.
    pub fn refreshOAuth(
        self: *Registry,
        name: []const u8,
        credential_json: []const u8,
        abort_flag: ?*bool,
    ) ![]u8 {
        try validateObjectJson(self.gpa, credential_json);
        const args = try singleJsonArgument(self.gpa, credential_json);
        defer self.gpa.free(args);
        const result = try self.invokeProviderMethod(name, "oauth.refreshToken", args, true, abort_flag);
        errdefer self.gpa.free(result);
        try validateObjectJson(self.gpa, result);
        return result;
    }

    /// OAuth getApiKey receives one credential and must return a non-empty key.
    pub fn oauthApiKey(self: *Registry, name: []const u8, credential_json: []const u8) ![]u8 {
        try validateObjectJson(self.gpa, credential_json);
        const args = try singleJsonArgument(self.gpa, credential_json);
        defer self.gpa.free(args);
        const result = try self.invokeProviderMethod(name, "oauth.getApiKey", args, false, null);
        defer self.gpa.free(result);
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, result, .{});
        defer parsed.deinit();
        if (parsed.value != .string or parsed.value.string.len == 0) return error.InvalidProviderApiKey;
        return self.gpa.dupe(u8, parsed.value.string);
    }

    /// OAuth modifyModels receives the current JSON model array and credential
    /// and must synchronously or asynchronously return the replacement array.
    pub fn modifyOAuthModels(
        self: *Registry,
        name: []const u8,
        models_json: []const u8,
        credential_json: []const u8,
    ) ![]u8 {
        try validateArrayJson(self.gpa, models_json);
        try validateObjectJson(self.gpa, credential_json);
        const args = try twoJsonArguments(self.gpa, models_json, credential_json);
        defer self.gpa.free(args);
        const result = try self.invokeProviderMethod(name, "oauth.modifyModels", args, false, null);
        errdefer self.gpa.free(result);
        try validateArrayJson(self.gpa, result);
        return result;
    }

    /// Object-form providers may expose credential-aware `filterModels` even
    /// when they do not own OAuth. It receives the current model array and the
    /// complete credential (or null), and must return the available subset.
    pub fn filterModels(
        self: *Registry,
        name: []const u8,
        models_json: []const u8,
        credential_json: ?[]const u8,
    ) ![]u8 {
        try validateArrayJson(self.gpa, models_json);
        if (credential_json) |credential| try validateObjectJson(self.gpa, credential);
        var args: std.Io.Writer.Allocating = .init(self.gpa);
        defer args.deinit();
        try args.writer.writeByte('[');
        try args.writer.writeAll(models_json);
        try args.writer.writeByte(',');
        try args.writer.writeAll(credential_json orelse "null");
        try args.writer.writeByte(']');
        const result = try self.invokeProviderMethod(name, "filterModels", args.written(), false, null);
        errdefer self.gpa.free(result);
        try validateArrayJson(self.gpa, result);
        return result;
    }

    pub fn unregister(self: *Registry, name: []const u8) !bool {
        const index = self.findIndex(name) orelse return false;
        var removed = self.registrations.orderedRemove(index);
        self.rebuild() catch |err| {
            try self.registrations.insert(self.gpa, index, removed);
            return err;
        };
        self.handoffCallbacks(name, &removed, null);
        removed.deinit();
        return true;
    }

    fn handoffCallbacks(
        self: *Registry,
        provider_name: []const u8,
        previous: ?*const Registration,
        current: ?*const Registration,
    ) void {
        var callback_runtimes: std.ArrayList(*js_runtime.Runtime) = .empty;
        defer callback_runtimes.deinit(self.gpa);
        if (previous) |registration| for (registration.callback_owners) |owner| appendUniqueRuntime(self.gpa, &callback_runtimes, owner.runtime) catch return;
        if (current) |registration| for (registration.callback_owners) |owner| appendUniqueRuntime(self.gpa, &callback_runtimes, owner.runtime) catch return;

        for (callback_runtimes.items) |runtime| {
            // Dynamic model and OAuth projections re-register data while the
            // provider callback itself still owns this worker's invocation
            // mutex. An unchanged callback set needs no JavaScript handoff and
            // attempting one here would self-deadlock.
            if (runtimeCallbackSetsEqual(previous, current, runtime)) continue;
            if (previous) |registration| for (registration.callback_owners) |owner| {
                if (owner.runtime != runtime or callbackOwnerSelected(current, owner)) continue;
                _ = runtime.retireProviderGeneration(provider_name, owner.generation, 1_000);
            };

            var selected: std.ArrayList([]const u8) = .empty;
            defer selected.deinit(self.gpa);
            if (current) |registration| for (registration.callback_owners) |owner| {
                if (owner.runtime == runtime) selected.append(self.gpa, owner.callback_id) catch return;
            };
            runtime.commitProviderCallbacks(provider_name, selected.items) catch {};
        }
    }

    fn findIndex(self: *const Registry, name: []const u8) ?usize {
        for (self.registrations.items, 0..) |registration, index| {
            if (std.ascii.eqlIgnoreCase(registration.name, name)) return index;
        }
        return null;
    }

    fn providerRegistered(self: *const Registry, name: []const u8) bool {
        return self.findIndex(name) != null;
    }

    fn rebuild(self: *Registry) !void {
        if (self.registrations.items.len == 0) {
            if (self.owns_snapshots) {
                if (self.catalog_snapshot.len > 0) self.gpa.free(self.catalog_snapshot);
                if (self.runtime_snapshot.len > 0) self.gpa.free(self.runtime_snapshot);
            }
            self.catalog_snapshot = @constCast(self.baseline_catalog);
            self.runtime_snapshot = @constCast(self.baseline_runtimes);
            self.owns_snapshots = false;
            return;
        }

        var models: std.ArrayList(providers.ModelInfo) = .empty;
        errdefer models.deinit(self.gpa);
        for (self.baseline_catalog) |model| {
            const index = self.findIndex(model.providerName());
            if (index != null and self.registrations.items[index.?].replaces_models) continue;
            try models.append(self.gpa, model);
        }
        for (self.registrations.items) |registration| {
            if (registration.replaces_models) try models.appendSlice(self.gpa, registration.models_file.model_infos);
        }

        var runtime_list: std.ArrayList(live_state.RuntimeProviderConfig) = .empty;
        errdefer runtime_list.deinit(self.gpa);
        for (self.baseline_runtimes) |runtime| {
            if (!self.providerRegistered(runtime.id)) try runtime_list.append(self.gpa, runtime);
        }
        for (self.registrations.items) |registration| try runtime_list.appendSlice(self.gpa, registration.runtime_configs);

        const next_models = try models.toOwnedSlice(self.gpa);
        errdefer if (next_models.len > 0) self.gpa.free(next_models);
        const next_runtimes = try runtime_list.toOwnedSlice(self.gpa);
        errdefer if (next_runtimes.len > 0) self.gpa.free(next_runtimes);

        if (self.owns_snapshots) {
            if (self.catalog_snapshot.len > 0) self.gpa.free(self.catalog_snapshot);
            if (self.runtime_snapshot.len > 0) self.gpa.free(self.runtime_snapshot);
        }
        self.catalog_snapshot = next_models;
        self.runtime_snapshot = next_runtimes;
        self.owns_snapshots = true;
    }
};

fn deinitCollectedRefs(gpa: std.mem.Allocator, refs: *std.ArrayList(CollectedMethodRef)) void {
    for (refs.items) |*ref| ref.deinit(gpa);
    refs.deinit(gpa);
}

fn appendUniqueRuntime(
    gpa: std.mem.Allocator,
    runtimes: *std.ArrayList(*js_runtime.Runtime),
    runtime: *js_runtime.Runtime,
) !void {
    for (runtimes.items) |existing| if (existing == runtime) return;
    try runtimes.append(gpa, runtime);
}

fn callbackOwnerSelected(current: ?*const Registration, candidate: CallbackOwner) bool {
    const registration = current orelse return false;
    for (registration.callback_owners) |owner| {
        if (owner.runtime == candidate.runtime and owner.generation == candidate.generation and
            std.mem.eql(u8, owner.callback_id, candidate.callback_id) and
            std.mem.eql(u8, owner.path, candidate.path)) return true;
    }
    return false;
}

fn runtimeCallbackSetsEqual(
    previous: ?*const Registration,
    current: ?*const Registration,
    runtime: *js_runtime.Runtime,
) bool {
    var previous_count: usize = 0;
    if (previous) |registration| for (registration.callback_owners) |owner| {
        if (owner.runtime == runtime) previous_count += 1;
    };
    var current_count: usize = 0;
    if (current) |registration| for (registration.callback_owners) |owner| {
        if (owner.runtime == runtime) current_count += 1;
    };
    if (previous_count != current_count) return false;
    if (previous_count == 0) return true;
    const registration = previous.?;
    for (registration.callback_owners) |owner| {
        if (owner.runtime != runtime or !callbackOwnerSelected(current, owner)) continue;
        previous_count -= 1;
    }
    return previous_count == 0;
}

fn appendPathSegment(gpa: std.mem.Allocator, path: *std.ArrayList(u8), segment: []const u8) !usize {
    const previous_len = path.items.len;
    if (previous_len > 0) try path.append(gpa, '.');
    try path.appendSlice(gpa, segment);
    return previous_len;
}

fn collectMethodRefs(
    gpa: std.mem.Allocator,
    value: std.json.Value,
    path: *std.ArrayList(u8),
    out: *std.ArrayList(CollectedMethodRef),
) !void {
    switch (value) {
        .object => |object| {
            const has_marker = object.get(provider_method_ref.callback_id_field) != null or
                object.get(provider_method_ref.callback_kind_field) != null or
                object.get(provider_method_ref.callback_path_field) != null;
            if (has_marker) {
                const ref = try provider_method_ref.ProviderMethodRef.fromJson(value);
                if (!std.mem.eql(u8, ref.path, path.items)) return error.ProviderMethodPathMismatch;
                const callback_id = try gpa.dupe(u8, ref.callback_id);
                errdefer gpa.free(callback_id);
                const owned_path = try gpa.dupe(u8, ref.path);
                errdefer gpa.free(owned_path);
                try out.append(gpa, .{
                    .callback_id = callback_id,
                    .path = owned_path,
                    .generation = ref.generation,
                });
                return;
            }
            var it = object.iterator();
            while (it.next()) |entry| {
                const previous_len = try appendPathSegment(gpa, path, entry.key_ptr.*);
                defer path.shrinkRetainingCapacity(previous_len);
                try collectMethodRefs(gpa, entry.value_ptr.*, path, out);
            }
        },
        .array => |array| for (array.items, 0..) |item, index| {
            var index_buffer: [32]u8 = undefined;
            const segment = try std.fmt.bufPrint(&index_buffer, "{d}", .{index});
            const previous_len = try appendPathSegment(gpa, path, segment);
            defer path.shrinkRetainingCapacity(previous_len);
            try collectMethodRefs(gpa, item, path, out);
        },
        else => {},
    }
}

fn findCollected(refs: []const CollectedMethodRef, callback_id: []const u8, path: []const u8, generation: u64) bool {
    for (refs) |ref| {
        if (ref.generation == generation and std.mem.eql(u8, ref.callback_id, callback_id) and std.mem.eql(u8, ref.path, path)) return true;
    }
    return false;
}

fn buildCallbackOwners(
    gpa: std.mem.Allocator,
    effective_refs: []const CollectedMethodRef,
    incoming_refs: []const CollectedMethodRef,
    incoming_runtime: ?*js_runtime.Runtime,
    previous: ?*const Registration,
) ![]CallbackOwner {
    if (effective_refs.len == 0) return &.{};
    const owners = try gpa.alloc(CallbackOwner, effective_refs.len);
    var initialized: usize = 0;
    errdefer {
        for (owners[0..initialized]) |*owner| owner.deinit(gpa);
        gpa.free(owners);
    }
    for (effective_refs, 0..) |ref, index| {
        const runtime = if (findCollected(incoming_refs, ref.callback_id, ref.path, ref.generation))
            incoming_runtime orelse if (previous) |old| old.callbackRuntime(ref.callback_id, ref.path, ref.generation) else null
        else if (previous) |old|
            old.callbackRuntime(ref.callback_id, ref.path, ref.generation)
        else
            null;
        const resolved_runtime = runtime orelse return error.ProviderMethodRuntimeMissing;
        const callback_id = try gpa.dupe(u8, ref.callback_id);
        errdefer gpa.free(callback_id);
        const owned_path = try gpa.dupe(u8, ref.path);
        errdefer gpa.free(owned_path);
        owners[index] = .{
            .callback_id = callback_id,
            .path = owned_path,
            .generation = ref.generation,
            .runtime = resolved_runtime,
        };
        initialized += 1;
    }
    return owners;
}

fn valueAtProviderPath(root: std.json.Value, path: []const u8) !std.json.Value {
    if (path.len == 0) return error.InvalidProviderMethodPath;
    var current = root;
    var segments = std.mem.splitScalar(u8, path, '.');
    while (segments.next()) |segment| {
        if (segment.len == 0) return error.InvalidProviderMethodPath;
        current = switch (current) {
            .object => |object| object.get(segment) orelse return error.ProviderMethodNotRegistered,
            .array => |array| blk: {
                const index = std.fmt.parseInt(usize, segment, 10) catch return error.InvalidProviderMethodPath;
                if (index >= array.items.len) return error.ProviderMethodNotRegistered;
                break :blk array.items[index];
            },
            else => return error.ProviderMethodNotRegistered,
        };
    }
    return current;
}

fn unwrapProviderMethodValue(gpa: std.mem.Allocator, envelope: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, envelope, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidProviderMethodResponse;
    const value = parsed.value.object.get("value") orelse return error.InvalidProviderMethodResponse;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(value, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn unwrapRefreshModels(gpa: std.mem.Allocator, envelope: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, envelope, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidProviderRefreshResult;
    const models = parsed.value.object.get("models") orelse return error.InvalidProviderRefreshResult;
    if (models != .array) return error.InvalidProviderRefreshResult;
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try std.json.Stringify.value(models, .{}, &out.writer);
    return out.toOwnedSlice();
}

fn validateOAuthCredentialJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionProviderCredential;
    const refresh = parsed.value.object.get("refresh") orelse return error.InvalidExtensionProviderCredential;
    const access = parsed.value.object.get("access") orelse return error.InvalidExtensionProviderCredential;
    const expires = parsed.value.object.get("expires") orelse return error.InvalidExtensionProviderCredential;
    if (refresh != .string or access != .string or expires != .integer) return error.InvalidExtensionProviderCredential;
    if (parsed.value.object.get("type")) |kind| {
        if (kind != .string or !std.mem.eql(u8, kind.string, "oauth")) return error.InvalidExtensionProviderCredential;
    }
}

fn writeProviderModelJson(writer: *std.Io.Writer, model: providers.ModelInfo) !void {
    try writer.writeAll("{\"id\":");
    try std.json.Stringify.value(model.id, .{}, writer);
    try writer.writeAll(",\"name\":");
    try std.json.Stringify.value(model.display, .{}, writer);
    try writer.print(",\"reasoning\":{},\"input\":[\"text\"", .{model.reasoning});
    if (model.input_image) try writer.writeAll(",\"image\"");
    try writer.writeAll("],\"cost\":{");
    try writer.print("\"input\":{d},\"output\":{d},\"cacheRead\":{d},\"cacheWrite\":{d}", .{
        model.cost.input, model.cost.output, model.cost.cache_read, model.cost.cache_write,
    });
    try writer.writeByte('}');
    try writer.print(",\"contextWindow\":{d},\"maxTokens\":{d}", .{ model.context_window, model.max_tokens });
    if (model.api) |api| {
        try writer.writeAll(",\"api\":");
        try std.json.Stringify.value(api.name(), .{}, writer);
    }
    try writer.writeByte('}');
}

fn validateObjectJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidExtensionProviderCredential;
}

fn validateArrayJson(gpa: std.mem.Allocator, raw: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidExtensionProviderModels;
}

fn twoJsonArguments(gpa: std.mem.Allocator, first_json: []const u8, second_json: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('[');
    try out.writer.writeAll(first_json);
    try out.writer.writeByte(',');
    try out.writer.writeAll(second_json);
    try out.writer.writeByte(']');
    return out.toOwnedSlice();
}

fn singleJsonArgument(gpa: std.mem.Allocator, value_json: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('[');
    try out.writer.writeAll(value_json);
    try out.writer.writeByte(']');
    return out.toOwnedSlice();
}

fn runtimeConfig(runtime: *const runtime_config.ResolvedRuntime) live_state.RuntimeProviderConfig {
    return .{
        .id = runtime.provider_id,
        .model_id = runtime.model_id,
        .transport = runtime.transport,
        .api = runtime.api,
        .model_cost = runtime.model_cost,
        .api_key = runtime.api_key,
        .oauth_refresh = runtime.oauth_refresh,
        .oauth_expires_ms = runtime.oauth_expires_ms,
        .oauth_enterprise_url = runtime.oauth_enterprise_url,
        .base_url = runtime.base_url,
        .headers = runtime.headers,
        .sampling_params = runtime.sampling_params,
        .compat = runtime.compat,
        .reasoning = runtime.reasoning,
        .input_image = runtime.input_image,
        .thinking_level_map = runtime.thinking_level_map,
        .max_tokens = runtime.max_tokens,
        .context_window = runtime.context_window,
    };
}

fn providerDocument(gpa: std.mem.Allocator, name: []const u8, config: std.json.Value) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{\"providers\":{");
    try std.json.Stringify.value(name, .{}, &out.writer);
    try out.writer.writeByte(':');
    try std.json.Stringify.value(config, .{}, &out.writer);
    try out.writer.writeAll("}}");
    return try out.toOwnedSlice();
}

/// JavaScript object spread is shallow. Preserve prior fields omitted by a
/// later registration while replacing every field explicitly supplied later.
fn mergeObjects(gpa: std.mem.Allocator, previous_json: []const u8, next_json: []const u8) ![]u8 {
    var previous = try std.json.parseFromSlice(std.json.Value, gpa, previous_json, .{});
    defer previous.deinit();
    var next = try std.json.parseFromSlice(std.json.Value, gpa, next_json, .{});
    defer next.deinit();
    if (previous.value != .object or next.value != .object) return error.InvalidExtensionProviderConfig;

    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeByte('{');
    var wrote = false;
    var old_it = previous.value.object.iterator();
    while (old_it.next()) |entry| {
        if (next.value.object.get(entry.key_ptr.*) != null) continue;
        if (wrote) try out.writer.writeByte(',');
        wrote = true;
        try std.json.Stringify.value(entry.key_ptr.*, .{}, &out.writer);
        try out.writer.writeByte(':');
        try std.json.Stringify.value(entry.value_ptr.*, .{}, &out.writer);
    }
    var next_it = next.value.object.iterator();
    while (next_it.next()) |entry| {
        if (wrote) try out.writer.writeByte(',');
        wrote = true;
        try std.json.Stringify.value(entry.key_ptr.*, .{}, &out.writer);
        try out.writer.writeByte(':');
        try std.json.Stringify.value(entry.value_ptr.*, .{}, &out.writer);
    }
    try out.writer.writeByte('}');
    return try out.toOwnedSlice();
}

fn testManifestProviderConfig(
    gpa: std.mem.Allocator,
    manifest_json: []const u8,
    provider_name: []const u8,
) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, manifest_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidTestManifest;
    const providers_value = parsed.value.object.get("providers") orelse return error.InvalidTestManifest;
    if (providers_value != .array) return error.InvalidTestManifest;
    for (providers_value.array.items) |entry| {
        if (entry != .object) continue;
        const name = entry.object.get("name") orelse continue;
        const config = entry.object.get("config") orelse continue;
        if (name != .string or !std.mem.eql(u8, name.string, provider_name)) continue;
        var out: std.Io.Writer.Allocating = .init(gpa);
        errdefer out.deinit();
        try std.json.Stringify.value(config, .{}, &out.writer);
        return out.toOwnedSlice();
    }
    return error.TestProviderNotFound;
}

test "extension provider registration replaces models and resolves runtime metadata" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    try env.put("CORP_TOKEN", "secret");

    const baseline = [_]providers.ModelInfo{
        .{ .provider = .openai, .id = "base", .display = "Base" },
    };
    var registry = Registry.init(gpa, io, &env, null, &baseline, &.{});
    defer registry.deinit();
    try registry.registerJson("corp", "{\"name\":\"Corp\",\"baseUrl\":\"https://corp.example/v1\",\"api\":\"openai-completions\",\"apiKey\":\"$CORP_TOKEN\",\"models\":[{\"id\":\"fast\",\"name\":\"Fast\",\"reasoning\":true,\"input\":[\"text\",\"image\"],\"cost\":{\"input\":1,\"output\":2,\"cacheRead\":0.1,\"cacheWrite\":0.2},\"contextWindow\":100000,\"maxTokens\":8192}]}");
    try std.testing.expectEqual(@as(usize, 2), registry.catalog().len);
    const model = registry.catalog()[1];
    try std.testing.expectEqualStrings("corp", model.providerName());
    try std.testing.expectEqualStrings("fast", model.id);
    try std.testing.expect(model.input_image and model.reasoning);
    try std.testing.expectEqual(@as(usize, 1), registry.runtimes().len);
    try std.testing.expectEqualStrings("secret", registry.runtimes()[0].api_key.?);
    try std.testing.expectEqualStrings("https://corp.example/v1", registry.runtimes()[0].base_url.?);
}

test "extension provider partial re-registration shallow merges and unregister restores baseline" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    const baseline = [_]providers.ModelInfo{
        .{ .provider = .openai, .id = "one", .display = "One" },
        .{ .provider = .anthropic, .id = "two", .display = "Two" },
    };
    var registry = Registry.init(gpa, io, &env, null, &baseline, &.{});
    defer registry.deinit();
    try registry.registerJson("openai", "{\"baseUrl\":\"http://localhost:9988/v1\",\"apiKey\":\"local\"}");
    try std.testing.expectEqual(@as(usize, 2), registry.catalog().len);
    try std.testing.expectEqualStrings("http://localhost:9988/v1", registry.runtimes()[0].base_url.?);
    try registry.registerJson("openai", "{\"name\":\"Development OpenAI\"}");
    try std.testing.expectEqualStrings("http://localhost:9988/v1", registry.runtimes()[0].base_url.?);
    try std.testing.expect(try registry.unregister("OPENAI"));
    try std.testing.expectEqual(@as(usize, 2), registry.catalog().len);
    try std.testing.expectEqual(@as(usize, 0), registry.runtimes().len);
    try std.testing.expect(!try registry.unregister("missing"));
}

test "provider registry invokes OAuth methods through the owning persistent worker" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const closure = 'registry-181';
        \\  pi.registerProvider('oauth-worker', {
        \\    name: 'OAuth Worker', baseUrl: 'https://oauth.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'oauth-model', name: 'OAuth Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    oauth: {
        \\      owner: 'registry-owner',
        \\      async refreshToken(credentials, signal) { if (!signal || this.owner !== 'registry-owner') throw new Error('bad registry invocation'); return { ...credentials, access: `${closure}:${credentials.refresh}`, expires: 181181 }; },
        \\      getApiKey(credentials) { return `${this.owner}:${credentials.access}`; },
        \\      modifyModels(models, credentials) { return models.map((model) => ({ ...model, name: `${model.name}:${credentials.access}:${closure}` })); },
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "oauth-worker.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "oauth-worker.mjs" });
    defer gpa.free(path);

    var started = try js_runtime.Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config_json = try testManifestProviderConfig(gpa, started.manifest_json, "oauth-worker");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("oauth-worker", config_json, started.runtime);
    try std.testing.expect(registry.hasProviderMethod("oauth-worker", "oauth.refreshToken"));
    try std.testing.expect(registry.hasProviderMethod("oauth-worker", "oauth.getApiKey"));
    try std.testing.expect(registry.hasProviderMethod("oauth-worker", "oauth.modifyModels"));

    const refreshed = try registry.refreshOAuth("oauth-worker", "{\"refresh\":\"refresh-181\",\"access\":\"old\"}", null);
    defer gpa.free(refreshed);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "registry-181:refresh-181") != null);
    try std.testing.expect(std.mem.indexOf(u8, refreshed, "181181") != null);

    const api_key = try registry.oauthApiKey("oauth-worker", "{\"refresh\":\"refresh-181\",\"access\":\"fresh-access\"}");
    defer gpa.free(api_key);
    try std.testing.expectEqualStrings("registry-owner:fresh-access", api_key);

    const projected = try registry.modifyOAuthModels(
        "oauth-worker",
        "[{\"id\":\"one\",\"name\":\"One\"}]",
        "{\"access\":\"credential-access\"}",
    );
    defer gpa.free(projected);
    try std.testing.expect(std.mem.indexOf(u8, projected, "One:credential-access:registry-181") != null);

    // A data-only shallow merge must preserve the callback owner and descriptors.
    try registry.registerJson("oauth-worker", "{\"name\":\"Renamed OAuth Worker\"}");
    const after_merge = try registry.oauthApiKey("oauth-worker", "{\"access\":\"after-merge\"}");
    defer gpa.free(after_merge);
    try std.testing.expectEqualStrings("registry-owner:after-merge", after_merge);

    const before_count = registry.count();
    try std.testing.expectError(
        error.ProviderMethodRuntimeMissing,
        registry.registerJson("missing-owner", "{\"oauth\":{\"getApiKey\":{\"__pi_callback_id\":\"provider:missing-owner:1\",\"__pi_callback_kind\":\"provider_method\",\"__pi_callback_path\":\"oauth.getApiKey\",\"__pi_callback_generation\":1}}}"),
    );
    try std.testing.expectEqual(before_count, registry.count());
    try std.testing.expectError(
        error.ProviderMethodPathMismatch,
        registry.registerJsonWithRuntime("wrong-path", "{\"oauth\":{\"getApiKey\":{\"__pi_callback_id\":\"provider:wrong-path:1\",\"__pi_callback_kind\":\"provider_method\",\"__pi_callback_path\":\"oauth.refreshToken\",\"__pi_callback_generation\":1}}}", started.runtime),
    );
    try std.testing.expectEqual(before_count, registry.count());
}

test "provider callback ownership remains distinct when separate workers emit colliding IDs" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const base =
        \\export default function(pi) {
        \\  pi.registerProvider('collision-provider', {
        \\    name: 'Collision Provider', baseUrl: 'https://collision.invalid/v1', api: 'openai-completions', apiKey: 'unused',
        \\    models: [{ id: 'collision-model', name: 'Collision Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    streamSimple(value) { return `worker-one:${value}`; },
        \\  });
        \\}
    ;
    const overlay =
        \\export default function(pi) {
        \\  pi.registerProvider('collision-provider', {
        \\    refreshModels(value) { return `worker-two:${value}`; },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "worker-one.mjs", .data = base });
    try tmp.dir.writeFile(io, .{ .sub_path = "worker-two.mjs", .data = overlay });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path_one = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "worker-one.mjs" });
    defer gpa.free(path_one);
    const path_two = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "worker-two.mjs" });
    defer gpa.free(path_two);

    var first = try js_runtime.Runtime.start(gpa, io, path_one, "node");
    defer first.runtime.deinit();
    defer gpa.free(first.manifest_json);
    var second = try js_runtime.Runtime.start(gpa, io, path_two, "node");
    defer second.runtime.deinit();
    defer gpa.free(second.manifest_json);
    const first_config = try testManifestProviderConfig(gpa, first.manifest_json, "collision-provider");
    defer gpa.free(first_config);
    const second_config = try testManifestProviderConfig(gpa, second.manifest_json, "collision-provider");
    defer gpa.free(second_config);

    var first_parsed = try std.json.parseFromSlice(std.json.Value, gpa, first_config, .{});
    defer first_parsed.deinit();
    var second_parsed = try std.json.parseFromSlice(std.json.Value, gpa, second_config, .{});
    defer second_parsed.deinit();
    const first_ref = try provider_method_ref.ProviderMethodRef.fromJson(first_parsed.value.object.get("streamSimple").?);
    const second_ref = try provider_method_ref.ProviderMethodRef.fromJson(second_parsed.value.object.get("refreshModels").?);
    try std.testing.expectEqualStrings(first_ref.callback_id, second_ref.callback_id);
    try std.testing.expect(!std.mem.eql(u8, first_ref.path, second_ref.path));

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("collision-provider", first_config, first.runtime);
    try registry.registerJsonWithRuntime("collision-provider", second_config, second.runtime);

    const from_first = try registry.invokeProviderMethod("collision-provider", "streamSimple", "[\"alpha\"]", false, null);
    defer gpa.free(from_first);
    try std.testing.expectEqualStrings("\"worker-one:alpha\"", from_first);
    const from_second = try registry.invokeProviderMethod("collision-provider", "refreshModels", "[\"beta\"]", false, null);
    defer gpa.free(from_second);
    try std.testing.expectEqualStrings("\"worker-two:beta\"", from_second);
}

test "provider registry routes streamSimple to its exact persistent callback owner" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\import { createAssistantMessageEventStream } from '@mariozechner/pi-ai';
        \\const usage = { input: 1, output: 1, cacheRead: 0, cacheWrite: 0, totalTokens: 2, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } };
        \\const assistant = (content, stopReason = 'pending') => ({ role: 'assistant', content, api: 'openai-completions', provider: 'registry-stream', model: 'registry-model', usage, stopReason, timestamp: 185 });
        \\export default function(pi) {
        \\  const owner = 'registry-stream-owner-185';
        \\  pi.registerProvider('registry-stream', {
        \\    name: 'Registry Stream', baseUrl: 'https://registry-stream.invalid/v1', api: 'openai-completions', apiKey: 'local',
        \\    models: [{ id: 'registry-model', name: 'Registry Model', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 }],
        \\    streamSimple(model, context) {
        \\      if (model.id !== 'registry-model' || context.owner !== owner) throw new Error('registry stream owner mismatch');
        \\      const stream = createAssistantMessageEventStream();
        \\      const partial = assistant([]);
        \\      stream.push({ type: 'start', partial });
        \\      stream.push({ type: 'text_start', contentIndex: 0, partial });
        \\      stream.push({ type: 'text_delta', contentIndex: 0, delta: owner, partial });
        \\      stream.push({ type: 'text_end', contentIndex: 0, content: owner, partial });
        \\      stream.push({ type: 'done', reason: 'stop', message: assistant([{ type: 'text', text: owner }], 'stop') });
        \\      return stream;
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "registry-stream.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "registry-stream.mjs" });
    defer gpa.free(path);

    var started = try js_runtime.Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config_json = try testManifestProviderConfig(gpa, started.manifest_json, "registry-stream");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("registry-stream", config_json, started.runtime);
    try std.testing.expect(registry.hasProviderMethod("registry-stream", "streamSimple"));

    const Capture = struct {
        count: u64 = 0,
        saw_owner: bool = false,
        saw_done: bool = false,

        fn consume(raw_context: ?*anyopaque, sequence: u64, event_json: []const u8) !void {
            const self: *@This() = @ptrCast(@alignCast(raw_context.?));
            try std.testing.expectEqual(self.count + 1, sequence);
            self.count = sequence;
            if (std.mem.indexOf(u8, event_json, "registry-stream-owner-185") != null) self.saw_owner = true;
            if (std.mem.indexOf(u8, event_json, "\"type\":\"done\"") != null) self.saw_done = true;
        }
    };

    var capture: Capture = .{};
    const first = try registry.streamSimple(
        "registry-stream",
        "{\"id\":\"registry-model\",\"provider\":\"registry-stream\",\"api\":\"openai-completions\"}",
        "{\"owner\":\"registry-stream-owner-185\",\"messages\":[]}",
        "{}",
        null,
        Capture.consume,
        &capture,
    );
    defer gpa.free(first);
    try std.testing.expectEqual(@as(u64, 5), capture.count);
    try std.testing.expect(capture.saw_owner and capture.saw_done);

    // A data-only shallow merge must not detach the stream callback from its
    // original worker generation.
    try registry.registerJson("registry-stream", "{\"name\":\"Registry Stream Renamed\"}");
    var after_merge: Capture = .{};
    const second = try registry.streamSimple(
        "registry-stream",
        "{\"id\":\"registry-model\",\"provider\":\"registry-stream\",\"api\":\"openai-completions\"}",
        "{\"owner\":\"registry-stream-owner-185\",\"messages\":[]}",
        "{}",
        null,
        Capture.consume,
        &after_merge,
    );
    defer gpa.free(second);
    try std.testing.expectEqual(@as(u64, 5), after_merge.count);
    try std.testing.expect(after_merge.saw_owner and after_merge.saw_done);

    try std.testing.expect(try registry.unregister("registry-stream"));
    try std.testing.expectError(
        error.ExtensionProviderNotRegistered,
        registry.streamSimple(
            "registry-stream",
            "{}",
            "{}",
            "{}",
            null,
            Capture.consume,
            &after_merge,
        ),
    );
}

test "object-form provider filterModels receives credential and owns its callback generation" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  pi.registerProvider({
        \\    id: 'object-filter', name: 'Object Filter', baseUrl: 'https://filter.invalid/v1', api: 'openai-completions', apiKey: 'local',
        \\    models: [
        \\      { id: 'public', name: 'Public', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 },
        \\      { id: 'private', name: 'Private', reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 },
        \\    ],
        \\    filterModels(models, credential) {
        \\      if (this.id !== 'object-filter') throw new Error('object provider receiver lost');
        \\      return credential?.access === 'allow-private' ? models : models.filter((model) => model.id !== 'private');
        \\    },
        \\    streamSimple() { throw new Error('not used'); },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "object-filter.mjs", .data = source });
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &path_buf);
    const path = try std.fs.path.join(gpa, &.{ path_buf[0..root_len], "object-filter.mjs" });
    defer gpa.free(path);

    var started = try js_runtime.Runtime.start(gpa, io, path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const config_json = try testManifestProviderConfig(gpa, started.manifest_json, "object-filter");
    defer gpa.free(config_json);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("object-filter", config_json, started.runtime);
    try std.testing.expect(registry.hasProviderMethod("object-filter", "filterModels"));

    const models = "[{\"id\":\"public\"},{\"id\":\"private\"}]";
    const filtered = try registry.filterModels("object-filter", models, "{\"type\":\"oauth\",\"access\":\"public-only\"}");
    defer gpa.free(filtered);
    try std.testing.expect(std.mem.indexOf(u8, filtered, "public") != null);
    try std.testing.expect(std.mem.indexOf(u8, filtered, "private") == null);

    const all = try registry.filterModels("object-filter", models, "{\"type\":\"oauth\",\"access\":\"allow-private\"}");
    defer gpa.free(all);
    try std.testing.expect(std.mem.indexOf(u8, all, "private") != null);
}
