//! Generation-safe dynamic model refresh for extension-defined providers.
//!
//! Each provider owns an independent generation and publication lock. A newer
//! refresh aborts the previous invocation; persistence and catalog publication
//! re-check the generation while holding that same lock, so stale callbacks
//! cannot mutate `models-store.json` or the live registry. JavaScript executes
//! provider-private `publication.update` only after native persistence commits.
const std = @import("std");
const Io = std.Io;
const live_state = @import("../coding_agent/live_state.zig");
const js_runtime = @import("js_runtime.zig");
const models_store = @import("models_store.zig");
const provider_oauth = @import("provider_oauth.zig");
const provider_registry = @import("provider_registry.zig");

const max_safe_generation: u64 = 9_007_199_254_740_991;

fn aborted(flag: ?*const bool) bool {
    return if (flag) |value| @atomicLoad(bool, value, .acquire) else false;
}

fn setAborted(flag: ?*bool) void {
    if (flag) |value| @atomicStore(bool, value, true, .release);
}

fn ensureActive(flag: ?*const bool) !void {
    if (aborted(flag)) return error.Canceled;
}

const ProviderState = struct {
    gpa: std.mem.Allocator,
    name: []u8,
    mutex: Io.Mutex = .init,
    generation: u64 = 0,
    active_abort: ?*bool = null,
    registered: bool = true,
    last_error: ?[]u8 = null,

    fn deinit(self: *ProviderState) void {
        setAborted(self.active_abort);
        if (self.last_error) |message| self.gpa.free(message);
        self.gpa.free(self.name);
        const gpa = self.gpa;
        self.* = undefined;
        gpa.destroy(self);
    }

    fn nextGeneration(self: *ProviderState) u64 {
        self.generation = if (self.generation >= max_safe_generation) 1 else self.generation + 1;
        return self.generation;
    }

    fn setError(self: *ProviderState, message: []const u8) !void {
        const owned = try self.gpa.dupe(u8, message);
        if (self.last_error) |previous| self.gpa.free(previous);
        self.last_error = owned;
    }

    fn clearError(self: *ProviderState) void {
        if (self.last_error) |previous| self.gpa.free(previous);
        self.last_error = null;
    }
};

pub const RefreshOptions = struct {
    allow_network: bool = true,
    force: ?bool = null,
    providers: ?[]const []const u8 = null,
    abort_flag: ?*bool = null,
};

pub const RefreshError = struct {
    provider_id: []u8,
    message: []u8,

    fn deinit(self: *RefreshError, gpa: std.mem.Allocator) void {
        gpa.free(self.provider_id);
        gpa.free(self.message);
        self.* = undefined;
    }
};

pub const RefreshResult = struct {
    gpa: std.mem.Allocator,
    aborted: bool,
    errors: []RefreshError,

    pub fn deinit(self: *RefreshResult) void {
        for (self.errors) |*entry| entry.deinit(self.gpa);
        if (self.errors.len > 0) self.gpa.free(self.errors);
        self.* = undefined;
    }
};

/// Allocation-bearing reload preparation. Once this succeeds, committing the
/// replacement registry is infallible and cannot strand the reload after its
/// old resources have been moved out of the stable stack locations.
pub const RegistryPreparation = struct {
    gpa: std.mem.Allocator,
    names: [][]u8,

    pub fn deinit(self: *RegistryPreparation) void {
        for (self.names) |name| self.gpa.free(name);
        if (self.names.len > 0) self.gpa.free(self.names);
        self.* = undefined;
    }
};

const PublishContext = struct {
    runtime: *Runtime,
    state: *ProviderState,
    provider_id: []const u8,
    generation: u64,
    abort_flag: *bool,
    last_sequence: u64 = 0,
};

pub const Runtime = struct {
    gpa: std.mem.Allocator,
    io: Io,
    agent_dir: ?[]const u8,
    registry: *provider_registry.Registry,
    oauth: *provider_oauth.Runtime,
    store: ?models_store.Store = null,
    memory_entries: std.StringHashMap([]u8),
    memory_mutex: Io.Mutex = .init,
    /// Registry publication is globally serialized because separate extension
    /// workers may refresh concurrently while Registry snapshots are replaced.
    refresh_mutex: Io.Mutex = .init,
    states: std.StringHashMap(*ProviderState),
    states_mutex: Io.Mutex = .init,
    client_pool: ?*live_state.ClientPool = null,
    live: ?*live_state.LiveState = null,

    pub fn init(
        gpa: std.mem.Allocator,
        io: Io,
        agent_dir: ?[]const u8,
        registry: *provider_registry.Registry,
        oauth: *provider_oauth.Runtime,
    ) !Runtime {
        return .{
            .gpa = gpa,
            .io = io,
            .agent_dir = agent_dir,
            .registry = registry,
            .oauth = oauth,
            .store = if (agent_dir) |root| try models_store.Store.init(gpa, io, root) else null,
            .memory_entries = std.StringHashMap([]u8).init(gpa),
            .states = std.StringHashMap(*ProviderState).init(gpa),
        };
    }

    pub fn deinit(self: *Runtime) void {
        self.supersedeAll();
        var iterator = self.states.iterator();
        while (iterator.next()) |entry| entry.value_ptr.*.deinit();
        self.states.deinit();
        var memory_iterator = self.memory_entries.iterator();
        while (memory_iterator.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.memory_entries.deinit();
        if (self.store) |*store| store.deinit();
        self.* = undefined;
    }

    pub fn bindClientPool(self: *Runtime, pool: *live_state.ClientPool) void {
        self.client_pool = pool;
    }

    pub fn bindLiveState(self: *Runtime, live: *live_state.LiveState) void {
        self.live = live;
    }

    /// Abort every active generation before an extension reload swaps workers or
    /// callback ownership. Persisted catalogs intentionally survive reload.
    pub fn supersedeAll(self: *Runtime) void {
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        var iterator = self.states.iterator();
        while (iterator.next()) |entry| {
            const state = entry.value_ptr.*;
            state.mutex.lockUncancelable(self.io);
            setAborted(state.active_abort);
            state.active_abort = null;
            _ = state.nextGeneration();
            state.mutex.unlock(self.io);
        }
    }

    /// Allocate provider names and any new stable state objects before reload
    /// ownership moves. `commitPreparedRegistry` then performs no allocation.
    pub fn prepareRegistry(self: *Runtime, registry: *const provider_registry.Registry) !RegistryPreparation {
        const names = try registry.refreshProviderNames(self.gpa);
        errdefer {
            for (names) |name| self.gpa.free(name);
            if (names.len > 0) self.gpa.free(names);
        }
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        for (names) |name| _ = try self.getOrCreateStateLocked(name);
        return .{ .gpa = self.gpa, .names = names };
    }

    /// Commit a registry prepared before the reload ownership boundary. Active
    /// generations are aborted and fully unwound before the pointer changes.
    pub fn commitPreparedRegistry(
        self: *Runtime,
        registry: *provider_registry.Registry,
        preparation: *const RegistryPreparation,
    ) void {
        self.supersedeAll();
        self.refresh_mutex.lockUncancelable(self.io);
        defer self.refresh_mutex.unlock(self.io);
        self.registry = registry;
        self.oauth.registry = registry;
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        self.applyRegistrationNamesLocked(preparation.names);
    }

    /// Repoint the coordinator after a transactional registry reload. Existing
    /// state objects remain stable, while removed providers are superseded and
    /// newly dynamic providers become refreshable.
    pub fn setRegistry(self: *Runtime, registry: *provider_registry.Registry) !void {
        self.supersedeAll();
        // Wait until any invocation that observed the previous registry has
        // unwound before replacing callback ownership and snapshots.
        self.refresh_mutex.lockUncancelable(self.io);
        defer self.refresh_mutex.unlock(self.io);
        self.registry = registry;
        self.oauth.registry = registry;
        try self.synchronizeRegistrationsLocked();
    }

    pub fn synchronizeRegistrations(self: *Runtime) !void {
        self.refresh_mutex.lockUncancelable(self.io);
        defer self.refresh_mutex.unlock(self.io);
        return self.synchronizeRegistrationsLocked();
    }

    fn synchronizeRegistrationsLocked(self: *Runtime) !void {
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        const names = try self.registry.refreshProviderNames(self.gpa);
        defer {
            for (names) |name| self.gpa.free(name);
            if (names.len > 0) self.gpa.free(names);
        }
        for (names) |name| _ = try self.getOrCreateStateLocked(name);
        self.applyRegistrationNamesLocked(names);
    }

    fn applyRegistrationNamesLocked(self: *Runtime, names: []const []const u8) void {
        var iterator = self.states.iterator();
        while (iterator.next()) |entry| entry.value_ptr.*.registered = false;
        for (names) |name| self.states.get(name).?.registered = true;
        iterator = self.states.iterator();
        while (iterator.next()) |entry| {
            const state = entry.value_ptr.*;
            if (state.registered) continue;
            state.mutex.lockUncancelable(self.io);
            setAborted(state.active_abort);
            state.active_abort = null;
            _ = state.nextGeneration();
            state.mutex.unlock(self.io);
        }
    }

    pub fn registerProvider(self: *Runtime, provider_id: []const u8, abort_flag: ?*bool) !RefreshResult {
        try self.synchronizeRegistrations();
        const selected = [_][]const u8{provider_id};
        return self.refresh(.{ .allow_network = false, .providers = &selected, .abort_flag = abort_flag });
    }

    /// Explicit unregister removes provider-owned persisted catalog state. A
    /// reload uses `setRegistry` instead and therefore preserves cache entries.
    pub fn unregisterProvider(self: *Runtime, provider_id: []const u8) !void {
        const state = try self.getOrCreateState(provider_id);
        state.mutex.lockUncancelable(self.io);
        defer state.mutex.unlock(self.io);
        setAborted(state.active_abort);
        state.active_abort = null;
        state.registered = false;
        _ = state.nextGeneration();
        try self.deleteStored(provider_id, null);
    }

    pub fn lastError(self: *Runtime, provider_id: []const u8) ?[]const u8 {
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        const state = self.states.get(provider_id) orelse return null;
        return state.last_error;
    }

    pub fn refresh(self: *Runtime, options: RefreshOptions) !RefreshResult {
        try self.synchronizeRegistrations();
        var errors: std.ArrayList(RefreshError) = .empty;
        errdefer {
            for (errors.items) |*entry| entry.deinit(self.gpa);
            errors.deinit(self.gpa);
        }
        if (aborted(options.abort_flag)) return .{
            .gpa = self.gpa,
            .aborted = true,
            .errors = try self.gpa.alloc(RefreshError, 0),
        };

        self.refresh_mutex.lockUncancelable(self.io);
        const names = self.registry.refreshProviderNames(self.gpa) catch |err| {
            self.refresh_mutex.unlock(self.io);
            return err;
        };
        self.refresh_mutex.unlock(self.io);
        defer {
            for (names) |name| self.gpa.free(name);
            if (names.len > 0) self.gpa.free(names);
        }
        for (names) |provider_id| {
            if (!isSelected(provider_id, options.providers)) continue;
            self.refreshOne(provider_id, options) catch |err| {
                if (err == error.Canceled or err == error.StaleProviderRefresh or aborted(options.abort_flag)) break;
                const state = try self.getOrCreateState(provider_id);
                const detail = self.registry.providerMethodLastError(provider_id, "refreshModels") orelse @errorName(err);
                state.mutex.lockUncancelable(self.io);
                state.setError(detail) catch {};
                state.mutex.unlock(self.io);
                try errors.append(self.gpa, .{
                    .provider_id = try self.gpa.dupe(u8, provider_id),
                    .message = try self.gpa.dupe(u8, detail),
                });
            };
        }
        return .{
            .gpa = self.gpa,
            .aborted = aborted(options.abort_flag),
            .errors = try errors.toOwnedSlice(self.gpa),
        };
    }

    fn refreshOne(self: *Runtime, provider_id: []const u8, options: RefreshOptions) !void {
        const state = try self.getOrCreateState(provider_id);
        var invocation_abort = false;
        const generation = self.begin(state, &invocation_abort);
        defer self.finish(state, generation, &invocation_abort);

        var mirror_done = false;
        var mirror_group: Io.Group = .init;
        const mirrors_caller = options.abort_flag != null;
        if (options.abort_flag) |caller| {
            if (aborted(caller)) @atomicStore(bool, &invocation_abort, true, .release);
            mirror_group.async(self.io, mirrorAbortTask, .{ self.io, caller, &invocation_abort, &mirror_done });
        }
        defer if (mirrors_caller) {
            @atomicStore(bool, &mirror_done, true, .release);
            mirror_group.cancel(self.io);
            mirror_group.await(self.io) catch {};
        };

        // All Registry reads and transactional snapshot replacements run under
        // one coordinator lock. A newer same-provider generation is started
        // before waiting here, so it still aborts and collapses the older call.
        self.refresh_mutex.lockUncancelable(self.io);
        defer self.refresh_mutex.unlock(self.io);
        try ensureActive(&invocation_abort);

        var credential_error: ?anyerror = null;
        const now_ms = std.Io.Clock.real.now(self.io).toMilliseconds();
        const offline_credential = self.oauth.credentialForModelRefresh(self.gpa, provider_id, now_ms, false, &invocation_abort) catch |err| blk: {
            credential_error = err;
            break :blk null;
        };
        defer if (offline_credential) |value| self.gpa.free(value);
        try self.runPhase(state, generation, &invocation_abort, provider_id, offline_credential, false, null);
        if (credential_error) |err| return err;
        try ensureActive(&invocation_abort);
        if (!options.allow_network) {
            state.mutex.lockUncancelable(self.io);
            state.clearError();
            state.mutex.unlock(self.io);
            return;
        }

        const online_credential = try self.oauth.credentialForModelRefresh(self.gpa, provider_id, now_ms, true, &invocation_abort);
        defer if (online_credential) |value| self.gpa.free(value);
        if (online_credential == null) {
            state.mutex.lockUncancelable(self.io);
            state.clearError();
            state.mutex.unlock(self.io);
            return;
        }
        try self.runPhase(state, generation, &invocation_abort, provider_id, online_credential, true, options.force);
        state.mutex.lockUncancelable(self.io);
        state.clearError();
        state.mutex.unlock(self.io);
    }

    fn runPhase(
        self: *Runtime,
        state: *ProviderState,
        generation: u64,
        invocation_abort: *bool,
        provider_id: []const u8,
        credential_json: ?[]const u8,
        allow_network: bool,
        force: ?bool,
    ) !void {
        try ensureActive(invocation_abort);
        const stored_json = try self.readStored(provider_id);
        defer if (stored_json) |value| self.gpa.free(value);
        const context_json = try self.buildContextJson(generation, credential_json, stored_json, allow_network, force);
        defer self.gpa.free(context_json);
        var publish_context = PublishContext{
            .runtime = self,
            .state = state,
            .provider_id = provider_id,
            .generation = generation,
            .abort_flag = invocation_abort,
        };
        const models_json = try self.registry.refreshModels(provider_id, context_json, invocation_abort, .{
            .context = &publish_context,
            .request_fn = publishRequest,
            .action_fn = publishAction,
        });
        defer self.gpa.free(models_json);
        if (!(try self.commitModels(state, generation, invocation_abort, provider_id, models_json))) return error.StaleProviderRefresh;

        // Legacy OAuth projection executes only after the worker invocation has
        // released its mutex, avoiding recursive entry into the same worker.
        if (credential_json) |credential| {
            state.mutex.lockUncancelable(self.io);
            defer state.mutex.unlock(self.io);
            if (!self.isCurrentLocked(state, generation, invocation_abort)) return error.StaleProviderRefresh;
            try self.oauth.applyModelsForCredential(provider_id, credential, invocation_abort);
            self.publishSnapshots();
        }
    }

    fn buildContextJson(
        self: *Runtime,
        generation: u64,
        credential_json: ?[]const u8,
        stored_json: ?[]const u8,
        allow_network: bool,
        force: ?bool,
    ) ![]u8 {
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        errdefer out.deinit();
        try out.writer.print("{{\"generation\":{d},\"allowNetwork\":{s}", .{ generation, if (allow_network) "true" else "false" });
        if (credential_json) |credential| {
            try out.writer.writeAll(",\"credential\":");
            try out.writer.writeAll(credential);
        }
        if (stored_json) |stored| {
            try out.writer.writeAll(",\"stored\":");
            try out.writer.writeAll(stored);
        }
        if (allow_network and force != null) try out.writer.print(",\"force\":{s}", .{if (force.?) "true" else "false"});
        try out.writer.writeByte('}');
        return out.toOwnedSlice();
    }

    fn begin(self: *Runtime, state: *ProviderState, invocation_abort: *bool) u64 {
        state.mutex.lockUncancelable(self.io);
        defer state.mutex.unlock(self.io);
        setAborted(state.active_abort);
        const generation = state.nextGeneration();
        state.active_abort = invocation_abort;
        return generation;
    }

    fn finish(self: *Runtime, state: *ProviderState, generation: u64, invocation_abort: *bool) void {
        state.mutex.lockUncancelable(self.io);
        defer state.mutex.unlock(self.io);
        if (state.generation == generation and state.active_abort == invocation_abort) state.active_abort = null;
    }

    fn isCurrentLocked(self: *Runtime, state: *const ProviderState, generation: u64, invocation_abort: *const bool) bool {
        _ = self;
        return state.registered and state.generation == generation and state.active_abort == invocation_abort and !aborted(invocation_abort);
    }

    fn commitModels(
        self: *Runtime,
        state: *ProviderState,
        generation: u64,
        invocation_abort: *bool,
        provider_id: []const u8,
        models_json: []const u8,
    ) !bool {
        state.mutex.lockUncancelable(self.io);
        defer state.mutex.unlock(self.io);
        if (!self.isCurrentLocked(state, generation, invocation_abort)) return false;
        try self.registry.validateDynamicModels(provider_id, models_json);
        if (!self.isCurrentLocked(state, generation, invocation_abort)) return false;
        try self.registry.applyDynamicModels(provider_id, models_json);
        self.publishSnapshots();
        return true;
    }

    fn publishSnapshots(self: *Runtime) void {
        if (self.client_pool) |pool| pool.setRuntimeProviders(self.registry.runtimes());
        if (self.live) |state| state.model_catalog = self.registry.catalog();
    }

    fn readStored(self: *Runtime, provider_id: []const u8) !?[]u8 {
        if (self.store) |*store| return store.read(provider_id);
        self.memory_mutex.lockUncancelable(self.io);
        defer self.memory_mutex.unlock(self.io);
        const entry = self.memory_entries.get(provider_id) orelse return null;
        return @as(?[]u8, try self.gpa.dupe(u8, entry));
    }

    fn writeStored(
        self: *Runtime,
        provider_id: []const u8,
        entry_json: []const u8,
        abort_flag: ?*const bool,
    ) !void {
        try ensureActive(abort_flag);
        try models_store.validateEntryJson(self.gpa, entry_json);
        if (self.store) |*store| return store.writeAbortable(provider_id, entry_json, abort_flag);
        const owned = try self.gpa.dupe(u8, entry_json);
        errdefer self.gpa.free(owned);
        self.memory_mutex.lockUncancelable(self.io);
        defer self.memory_mutex.unlock(self.io);
        try ensureActive(abort_flag);
        if (self.memory_entries.getPtr(provider_id)) |existing| {
            self.gpa.free(existing.*);
            existing.* = owned;
            return;
        }
        const key = try self.gpa.dupe(u8, provider_id);
        errdefer self.gpa.free(key);
        try self.memory_entries.put(key, owned);
    }

    fn deleteStored(self: *Runtime, provider_id: []const u8, abort_flag: ?*const bool) !void {
        try ensureActive(abort_flag);
        if (self.store) |*store| return store.deleteAbortable(provider_id, abort_flag);
        self.memory_mutex.lockUncancelable(self.io);
        defer self.memory_mutex.unlock(self.io);
        try ensureActive(abort_flag);
        if (self.memory_entries.fetchRemove(provider_id)) |removed| {
            self.gpa.free(removed.key);
            self.gpa.free(removed.value);
        }
    }

    fn getOrCreateState(self: *Runtime, provider_id: []const u8) !*ProviderState {
        self.states_mutex.lockUncancelable(self.io);
        defer self.states_mutex.unlock(self.io);
        return self.getOrCreateStateLocked(provider_id);
    }

    fn getOrCreateStateLocked(self: *Runtime, provider_id: []const u8) !*ProviderState {
        if (self.states.get(provider_id)) |state| return state;
        const state = try self.gpa.create(ProviderState);
        errdefer self.gpa.destroy(state);
        const name = try self.gpa.dupe(u8, provider_id);
        errdefer self.gpa.free(name);
        state.* = .{ .gpa = self.gpa, .name = name };
        try self.states.put(name, state);
        return state;
    }

    fn publishRequest(
        raw: ?*anyopaque,
        allocator: std.mem.Allocator,
        method: []const u8,
        args_json: []const u8,
    ) ![]u8 {
        const context: *PublishContext = @ptrCast(@alignCast(raw orelse return error.MissingProviderPublishContext));
        if (std.mem.eql(u8, method, "provider_models_publish")) {
            const accepted = try context.runtime.applyPersistencePublication(context, args_json);
            return allocator.dupe(u8, if (accepted) "true" else "false");
        }
        if (std.mem.eql(u8, method, "provider_models_catalog")) {
            const accepted = try context.runtime.applyCatalogPublication(context, args_json);
            return allocator.dupe(u8, if (accepted) "true" else "false");
        }
        return error.UnexpectedProviderModelsRequest;
    }

    fn publishAction(
        raw: ?*anyopaque,
        allocator: std.mem.Allocator,
        method: []const u8,
        args_json: []const u8,
    ) !void {
        _ = raw;
        _ = allocator;
        _ = method;
        _ = args_json;
        return error.UnexpectedProviderModelsAction;
    }

    fn validatePublishEnvelope(self: *Runtime, context: *PublishContext, object: std.json.ObjectMap) !u64 {
        _ = self;
        const provider = object.get("provider") orelse return error.InvalidProviderModelsPublication;
        const generation = object.get("generation") orelse return error.InvalidProviderModelsPublication;
        const sequence = object.get("sequence") orelse return error.InvalidProviderModelsPublication;
        if (provider != .string or !std.mem.eql(u8, provider.string, context.provider_id)) return error.InvalidProviderModelsPublication;
        if (generation != .integer or generation.integer < 1 or @as(u64, @intCast(generation.integer)) != context.generation) return error.InvalidProviderModelsPublication;
        if (sequence != .integer or sequence.integer < 1) return error.InvalidProviderModelsPublication;
        const value: u64 = @intCast(sequence.integer);
        if (value <= context.last_sequence) return error.InvalidProviderModelsPublicationOrder;
        context.last_sequence = value;
        return value;
    }

    fn applyPersistencePublication(self: *Runtime, context: *PublishContext, args_json: []const u8) !bool {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, args_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidProviderModelsPublication;
        _ = try self.validatePublishEnvelope(context, parsed.value.object);
        const has_persist = parsed.value.object.get("hasPersist") orelse return error.InvalidProviderModelsPublication;
        if (has_persist != .bool) return error.InvalidProviderModelsPublication;

        context.state.mutex.lockUncancelable(self.io);
        defer context.state.mutex.unlock(self.io);
        if (!self.isCurrentLocked(context.state, context.generation, context.abort_flag)) return false;
        if (!has_persist.bool) return true;
        const persist = parsed.value.object.get("persist") orelse return error.InvalidProviderModelsPublication;
        switch (persist) {
            .null => try self.deleteStored(context.provider_id, context.abort_flag),
            .object => {
                try models_store.validateEntryValue(persist);
                const models = persist.object.get("models").?;
                var models_out: std.Io.Writer.Allocating = .init(self.gpa);
                defer models_out.deinit();
                try std.json.Stringify.value(models, .{}, &models_out.writer);
                try self.registry.validateDynamicModels(context.provider_id, models_out.written());
                var entry_out: std.Io.Writer.Allocating = .init(self.gpa);
                defer entry_out.deinit();
                try std.json.Stringify.value(persist, .{}, &entry_out.writer);
                try self.writeStored(context.provider_id, entry_out.written(), context.abort_flag);
            },
            else => return error.InvalidProviderModelsPublication,
        }
        return self.isCurrentLocked(context.state, context.generation, context.abort_flag);
    }

    fn applyCatalogPublication(self: *Runtime, context: *PublishContext, args_json: []const u8) !bool {
        var parsed = try std.json.parseFromSlice(std.json.Value, self.gpa, args_json, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidProviderModelsPublication;
        _ = try self.validatePublishEnvelope(context, parsed.value.object);
        const models = parsed.value.object.get("models") orelse return error.InvalidProviderModelsPublication;
        if (models != .array) return error.InvalidProviderModelsPublication;
        var out: std.Io.Writer.Allocating = .init(self.gpa);
        defer out.deinit();
        try std.json.Stringify.value(models, .{}, &out.writer);
        return self.commitModels(context.state, context.generation, context.abort_flag, context.provider_id, out.written());
    }
};

fn isSelected(provider_id: []const u8, selected: ?[]const []const u8) bool {
    const list = selected orelse return true;
    for (list) |candidate| if (std.ascii.eqlIgnoreCase(provider_id, candidate)) return true;
    return false;
}

fn mirrorAbortTask(io: Io, source: *const bool, target: *bool, done: *bool) Io.Cancelable!void {
    while (!@atomicLoad(bool, done, .acquire)) {
        if (@atomicLoad(bool, source, .acquire)) {
            @atomicStore(bool, target, true, .release);
            return;
        }
        const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(5), .clock = .awake } };
        pause.sleep(io) catch return;
    }
}

fn testProviderConfigFromManifest(gpa: std.mem.Allocator, manifest_json: []const u8, name: []const u8) ![]u8 {
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

fn testCatalogModel(registry: *const provider_registry.Registry, provider_id: []const u8, model_id: []const u8) ?@import("../ai/providers.zig").ModelInfo {
    for (registry.catalog()) |model| {
        if (std.ascii.eqlIgnoreCase(model.providerName(), provider_id) and std.mem.eql(u8, model.id, model_id)) return model;
    }
    return null;
}

test "extension provider models restore cache refresh credentials persist and survive reload" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const model = (id, name = id) => ({ id, name, reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 });
        \\  const config = {
        \\    name: 'Dynamic 183', baseUrl: 'https://dynamic.invalid/v1', api: 'openai-completions', apiKey: 'unused', models: [model('initial', 'Initial')],
        \\    async refreshModels(context) {
        \\      if (!(context.signal instanceof AbortSignal)) throw new Error('missing-refresh-signal-183');
        \\      if (!context.allowNetwork) return context.stored?.models ?? config.models;
        \\      if (context.force !== true) throw new Error('missing-force-183');
        \\      if (context.credential?.access !== 'fresh-access-183' || context.credential?.tenant !== 'corp') throw new Error('credential-not-refreshed-183');
        \\      const fresh = [model('fresh-183', 'Fresh 183')];
        \\      const accepted = await context.publish({
        \\        persist: { models: fresh, checkedAt: 183, etag: '\"etag-183\"' },
        \\        update: () => { config.models = fresh; },
        \\      });
        \\      if (!accepted) throw new Error('publication-rejected-183');
        \\      return fresh;
        \\    },
        \\    oauth: {
        \\      async refreshToken(credentials, signal) {
        \\        if (!(signal instanceof AbortSignal)) throw new Error('missing-oauth-signal-183');
        \\        return { ...credentials, access: 'fresh-access-183', expires: 9999999999999, refreshCount: (credentials.refreshCount ?? 0) + 1 };
        \\      },
        \\      getApiKey(credentials) { return `key:${credentials.access}`; },
        \\      modifyModels(models, credentials) { return models.map((entry) => ({ ...entry, name: `${entry.name}:${credentials.access}` })); },
        \\    },
        \\  };
        \\  pi.registerProvider('dynamic-183', config);
        \\  pi.registerProvider('reject-183', {
        \\    name: 'Reject 183', baseUrl: 'https://reject.invalid/v1', api: 'openai-completions', apiKey: 'configured', models: [model('reject-initial')],
        \\    async refreshModels() { throw new Error('refresh-rejection-stack-183'); },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "provider-models.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const source_path = try std.fs.path.join(gpa, &.{ root, "provider-models.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    const dynamic_config = try testProviderConfigFromManifest(gpa, started.manifest_json, "dynamic-183");
    defer gpa.free(dynamic_config);
    const reject_config = try testProviderConfigFromManifest(gpa, started.manifest_json, "reject-183");
    defer gpa.free(reject_config);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry_a = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry_a.deinit();
    try registry_a.registerJsonWithRuntime("dynamic-183", dynamic_config, started.runtime);
    try registry_a.registerJsonWithRuntime("reject-183", reject_config, started.runtime);
    var registry_b = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry_b.deinit();
    try registry_b.registerJsonWithRuntime("dynamic-183", dynamic_config, started.runtime);
    try registry_b.registerJsonWithRuntime("reject-183", reject_config, started.runtime);

    const auth_storage = @import("../auth/storage.zig");
    var auth = try auth_storage.AuthStorage.init(gpa, io, root);
    defer auth.deinit();
    try auth.setOAuthJson("dynamic-183", "{\"type\":\"oauth\",\"refresh\":\"refresh-183\",\"access\":\"old-access-183\",\"expires\":1,\"tenant\":\"corp\",\"custom\":{\"keep\":true}}");

    var cache = try models_store.Store.init(gpa, io, root);
    defer cache.deinit();
    try cache.write("dynamic-183", "{\"models\":[{\"id\":\"cached-183\",\"name\":\"Cached 183\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":4096,\"maxTokens\":512}],\"checkedAt\":1}");

    var oauth = provider_oauth.Runtime.init(gpa, io, root, &registry_a);
    var runtime = try Runtime.init(gpa, io, root, &registry_a, &oauth);
    defer runtime.deinit();

    const dynamic_only = [_][]const u8{"dynamic-183"};
    var refreshed = try runtime.refresh(.{
        .allow_network = true,
        .force = true,
        .providers = &dynamic_only,
    });
    defer refreshed.deinit();
    try std.testing.expect(!refreshed.aborted);
    try std.testing.expectEqual(@as(usize, 0), refreshed.errors.len);
    const fresh = testCatalogModel(&registry_a, "dynamic-183", "fresh-183") orelse return error.TestModelMissing;
    try std.testing.expectEqualStrings("Fresh 183:fresh-access-183", fresh.display);

    const persisted = (try cache.read("dynamic-183")).?;
    defer gpa.free(persisted);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "fresh-183") != null);
    try std.testing.expect(std.mem.indexOf(u8, persisted, "\"checkedAt\":183") != null);
    const credential = (try auth.readOAuthJson("dynamic-183")).?;
    defer gpa.free(credential);
    try std.testing.expect(std.mem.indexOf(u8, credential, "fresh-access-183") != null);
    try std.testing.expect(std.mem.indexOf(u8, credential, "\"refreshCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, credential, "\"custom\":{\"keep\":true}") != null);

    // A registry reload supersedes the old generation but deliberately retains
    // provider-owned persisted catalogs. Offline restoration uses that cache.
    var preparation = try runtime.prepareRegistry(&registry_b);
    defer preparation.deinit();
    runtime.commitPreparedRegistry(&registry_b, &preparation);
    var restored = try runtime.refresh(.{ .allow_network = false, .providers = &dynamic_only });
    defer restored.deinit();
    try std.testing.expectEqual(@as(usize, 0), restored.errors.len);
    const restored_model = testCatalogModel(&registry_b, "dynamic-183", "fresh-183") orelse return error.TestModelMissing;
    try std.testing.expectEqualStrings("Fresh 183:fresh-access-183", restored_model.display);

    const reject_only = [_][]const u8{"reject-183"};
    var rejected = try runtime.refresh(.{ .allow_network = false, .providers = &reject_only });
    defer rejected.deinit();
    try std.testing.expectEqual(@as(usize, 1), rejected.errors.len);
    try std.testing.expect(std.mem.indexOf(u8, rejected.errors[0].message, "refresh-rejection-stack-183") != null);
    try std.testing.expect(runtime.lastError("reject-183") != null);

    try runtime.unregisterProvider("dynamic-183");
    try std.testing.expect((try cache.read("dynamic-183")) == null);
}

test "extension provider models reject stale publication generations transactionally" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, null, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJson("guard-183",
        \\{"name":"Guard 183","baseUrl":"https://guard.invalid/v1","api":"openai-completions","apiKey":"guard","models":[{"id":"initial","name":"Initial","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":4096,"maxTokens":512}]}
    );
    var oauth = provider_oauth.Runtime.init(gpa, io, null, &registry);
    var runtime = try Runtime.init(gpa, io, null, &registry, &oauth);
    defer runtime.deinit();
    const state = try runtime.getOrCreateState("guard-183");
    var first_abort = false;
    var second_abort = false;
    const first_generation = runtime.begin(state, &first_abort);
    const second_generation = runtime.begin(state, &second_abort);
    try std.testing.expect(first_generation < second_generation);
    try std.testing.expect(@atomicLoad(bool, &first_abort, .acquire));

    var stale_context = PublishContext{
        .runtime = &runtime,
        .state = state,
        .provider_id = "guard-183",
        .generation = first_generation,
        .abort_flag = &first_abort,
    };
    const stale_json = try std.fmt.allocPrint(
        gpa,
        "{{\"provider\":\"guard-183\",\"generation\":{d},\"sequence\":1,\"hasPersist\":true,\"persist\":{{\"models\":[{{\"id\":\"stale\",\"name\":\"Stale\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}},\"contextWindow\":4096,\"maxTokens\":512}}]}}}}",
        .{first_generation},
    );
    defer gpa.free(stale_json);
    try std.testing.expect(!(try runtime.applyPersistencePublication(&stale_context, stale_json)));
    try std.testing.expect((try runtime.readStored("guard-183")) == null);

    var current_context = PublishContext{
        .runtime = &runtime,
        .state = state,
        .provider_id = "guard-183",
        .generation = second_generation,
        .abort_flag = &second_abort,
    };
    const current_json = try std.fmt.allocPrint(
        gpa,
        "{{\"provider\":\"guard-183\",\"generation\":{d},\"sequence\":1,\"hasPersist\":true,\"persist\":{{\"models\":[{{\"id\":\"current\",\"name\":\"Current\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}},\"contextWindow\":4096,\"maxTokens\":512}}]}}}}",
        .{second_generation},
    );
    defer gpa.free(current_json);
    try std.testing.expect(try runtime.applyPersistencePublication(&current_context, current_json));
    const stored = (try runtime.readStored("guard-183")).?;
    defer gpa.free(stored);
    try std.testing.expect(std.mem.indexOf(u8, stored, "current") != null);

    const catalog_json = try std.fmt.allocPrint(
        gpa,
        "{{\"provider\":\"guard-183\",\"generation\":{d},\"sequence\":2,\"models\":[{{\"id\":\"current\",\"name\":\"Current\",\"reasoning\":false,\"input\":[\"text\"],\"cost\":{{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0}},\"contextWindow\":4096,\"maxTokens\":512}}]}}",
        .{second_generation},
    );
    defer gpa.free(catalog_json);
    try std.testing.expect(try runtime.applyCatalogPublication(&current_context, catalog_json));
    try std.testing.expect(testCatalogModel(&registry, "guard-183", "current") != null);

    const invalid_persist = try std.fmt.allocPrint(
        gpa,
        "{{\"provider\":\"guard-183\",\"generation\":{d},\"sequence\":3,\"hasPersist\":true,\"persist\":{{\"models\":{{}}}}}}",
        .{second_generation},
    );
    defer gpa.free(invalid_persist);
    try std.testing.expectError(error.InvalidModelsStoreEntry, runtime.applyPersistencePublication(&current_context, invalid_persist));
    const after_invalid = (try runtime.readStored("guard-183")).?;
    defer gpa.free(after_invalid);
    try std.testing.expect(std.mem.indexOf(u8, after_invalid, "current") != null);

    const delete_persisted = try std.fmt.allocPrint(
        gpa,
        "{{\"provider\":\"guard-183\",\"generation\":{d},\"sequence\":4,\"hasPersist\":true,\"persist\":null}}",
        .{second_generation},
    );
    defer gpa.free(delete_persisted);
    try std.testing.expect(try runtime.applyPersistencePublication(&current_context, delete_persisted));
    try std.testing.expect((try runtime.readStored("guard-183")) == null);
    try std.testing.expectError(error.InvalidProviderModelsPublicationOrder, runtime.applyPersistencePublication(&current_context, delete_persisted));
    runtime.finish(state, second_generation, &second_abort);
}

test "extension provider model refresh abort leaves catalog and persistence unchanged" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    if (!js_runtime.nodeAvailable(gpa, io)) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const source =
        \\export default function(pi) {
        \\  const model = (id) => ({ id, name: id, reasoning: false, input: ['text'], cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, contextWindow: 4096, maxTokens: 512 });
        \\  pi.registerProvider('abort-models-183', {
        \\    name: 'Abort Models 183', baseUrl: 'https://abort.invalid/v1', api: 'openai-completions', apiKey: 'configured', models: [model('initial-183')],
        \\    async refreshModels(context) {
        \\      if (!context.allowNetwork) return context.stored?.models ?? [model('initial-183')];
        \\      await new Promise((resolve, reject) => {
        \\        if (context.signal.aborted) { reject(context.signal.reason); return; }
        \\        const timer = setTimeout(() => reject(new Error('model refresh abort was not delivered')), 2000);
        \\        context.signal.addEventListener('abort', () => { clearTimeout(timer); reject(context.signal.reason); }, { once: true });
        \\      });
        \\      await context.publish({ persist: { models: [model('must-not-persist-183')] } });
        \\      return [model('must-not-publish-183')];
        \\    },
        \\  });
        \\}
    ;
    try tmp.dir.writeFile(io, .{ .sub_path = "abort-models.mjs", .data = source });
    var root_buf: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try tmp.dir.realPath(io, &root_buf);
    const root = root_buf[0..root_len];
    const source_path = try std.fs.path.join(gpa, &.{ root, "abort-models.mjs" });
    defer gpa.free(source_path);

    var started = try js_runtime.Runtime.start(gpa, io, source_path, "node");
    defer started.runtime.deinit();
    defer gpa.free(started.manifest_json);
    started.runtime.models_refresh_timeout_ms = 5000;
    const config = try testProviderConfigFromManifest(gpa, started.manifest_json, "abort-models-183");
    defer gpa.free(config);

    var env = std.process.Environ.Map.init(gpa);
    defer env.deinit();
    var registry = provider_registry.Registry.init(gpa, io, &env, root, &.{}, &.{});
    defer registry.deinit();
    try registry.registerJsonWithRuntime("abort-models-183", config, started.runtime);
    var oauth = provider_oauth.Runtime.init(gpa, io, root, &registry);
    var runtime = try Runtime.init(gpa, io, root, &registry, &oauth);
    defer runtime.deinit();

    const AbortTask = struct {
        fn run(task_io: Io, flag: *bool) Io.Cancelable!void {
            const pause: Io.Timeout = .{ .duration = .{ .raw = .fromMilliseconds(100), .clock = .awake } };
            try pause.sleep(task_io);
            @atomicStore(bool, flag, true, .release);
        }
    };
    var abort_flag = false;
    var group: Io.Group = .init;
    group.async(io, AbortTask.run, .{ io, &abort_flag });
    const only = [_][]const u8{"abort-models-183"};
    var result = try runtime.refresh(.{ .allow_network = true, .providers = &only, .abort_flag = &abort_flag });
    defer result.deinit();
    try group.await(io);
    try std.testing.expect(result.aborted);
    try std.testing.expectEqual(@as(usize, 0), result.errors.len);
    try std.testing.expect(testCatalogModel(&registry, "abort-models-183", "initial-183") != null);

    var cache = try models_store.Store.init(gpa, io, root);
    defer cache.deinit();
    try std.testing.expect((try cache.read("abort-models-183")) == null);
    try std.testing.expect(runtime.lastError("abort-models-183") == null or
        std.mem.indexOf(u8, runtime.lastError("abort-models-183").?, "Operation aborted") != null);

    // Cancellation must not poison the persistent worker or provider owner.
    @atomicStore(bool, &abort_flag, false, .release);
    var reused = try runtime.refresh(.{ .allow_network = false, .providers = &only, .abort_flag = &abort_flag });
    defer reused.deinit();
    try std.testing.expect(!reused.aborted);
    try std.testing.expectEqual(@as(usize, 0), reused.errors.len);
    try std.testing.expect(testCatalogModel(&registry, "abort-models-183", "initial-183") != null);
}
