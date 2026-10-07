//! One directly linked VM owner with distinct extension registrations.
const std = @import("std");
const engine_mod = @import("engine.zig");
const bindings_mod = @import("native_bindings.zig");
const native_ui = @import("native_ui.zig");
const native_renderers = @import("native_renderers.zig");
const abort_signal = @import("abort_signal.zig");
const activation_mod = @import("tool_activation.zig");
const c = engine_mod.c;

pub const Entry = struct { id: u64, source: []u8, binding: *bindings_mod.Bindings };
pub const Group = struct {
    provider_catalog_clock: u64 = 0,
    engine: *engine_mod.Engine,
    ui: *native_ui.Manager,
    renderers: *native_renderers.Manager,
    broker: bindings_mod.Bindings.InvocationBroker = .{},
    entries: std.ArrayList(Entry) = .empty,
    next_id: u64 = 1,
    membership_revision: u64 = 0,
    activation: activation_mod.Tracker,
    registration_journal: std.ArrayList(activation_mod.Event) = .empty,
    published_registration_sequence: u64 = 0,
    selection_context: ?std.json.Parsed(std.json.Value) = null,
    selection_received: bool = false,
    registration_depth: usize = 0,
    registration_failure: ?anyerror = null,
    registration_baseline_ready: bool = false,
    deinitializing: bool = false,
    external_tools: std.ArrayList([]const u8) = .empty,
    actions_fn: ?*const fn (?*anyopaque, u64, []const u8) anyerror!void = null,
    actions_context: ?*anyopaque = null,

    pub fn init(engine: *engine_mod.Engine) !*Group {
        if (engine.host_data != null or engine.native_ui_manager != null) return error.NativeGroupAlreadyAttached;
        if (!engine.abort_signals_ready) try abort_signal.install(engine);
        const ui = try native_ui.Manager.init(engine);
        errdefer ui.deinit();
        const renderers = try native_renderers.Manager.init(engine);
        errdefer renderers.deinit();
        const self = try engine.gpa.create(Group);
        self.* = .{ .engine = engine, .ui = ui, .renderers = renderers, .activation = activation_mod.Tracker.init(engine.gpa, 1) };
        renderers.replay_fn = replay;
        renderers.replay_context = self;
        return self;
    }

    fn replay(context: ?*anyopaque, invocation: native_renderers.Replay) !void {
        const self: *Group = @ptrCast(@alignCast(context.?));
        const owner = try self.selected(invocation.owner_id);
        const result = try owner.replayRenderer(invocation);
        defer self.engine.gpa.free(result);
        if (self.actions_fn) |send| try send(self.actions_context, invocation.owner_id, result);
    }

    pub fn deinit(self: *Group) void {
        self.deinitializing = true;
        for (self.entries.items) |entry| {
            entry.binding.deinit();
            self.engine.gpa.free(entry.source);
        }
        self.entries.deinit(self.engine.gpa);
        self.renderers.deinit();
        self.ui.deinit();
        self.activation.deinit();
        for (self.registration_journal.items) |*event| event.deinit(self.engine.gpa);
        self.registration_journal.deinit(self.engine.gpa);
        if (self.selection_context) |*context| context.deinit();
        for (self.external_tools.items) |name| self.engine.gpa.free(name);
        self.external_tools.deinit(self.engine.gpa);
        self.engine.gpa.destroy(self);
    }

    pub fn add(self: *Group, path: []const u8) !*bindings_mod.Bindings {
        if (self.entries.items.len >= 4096 or self.next_id >= 9_007_199_254_740_991) return error.NativeGroupExtensionLimit;
        const source = try self.engine.gpa.dupe(u8, path);
        errdefer self.engine.gpa.free(source);
        const binding = try bindings_mod.Bindings.initShared(self.engine.gpa, self.engine, .{ .ui = self.ui, .renderers = self.renderers, .broker = &self.broker, .owner_id = self.next_id, .tool_lookup = lookupTool, .tool_context = self, .catalog_fn = catalog, .provider_catalog_fn = providerCatalog, .provider_catalog_clock = &self.provider_catalog_clock, .registration_fn = registration, .active_tools_fn = activeTools, .set_active_tools_fn = setActiveTools, .selection_context_fn = selectionContext });
        errdefer binding.deinit();
        try binding.setSourcePath(path);
        try self.entries.append(self.engine.gpa, .{ .id = self.next_id, .source = source, .binding = binding });
        self.next_id += 1;
        self.membership_revision +%= 1;
        return binding;
    }

    pub fn selected(self: *Group, id: u64) !*bindings_mod.Bindings {
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        for (self.entries.items) |entry| if (entry.id == id) return entry.binding;
        return error.UnknownNativeExtensionOwner;
    }

    pub fn remove(self: *Group, id: u64) !void {
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        for (self.entries.items, 0..) |entry, index| if (entry.id == id) {
            var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
            defer arena.deinit();
            var names: std.ArrayList([]const u8) = .empty;
            for (entry.binding.tool_order.items) |name| try names.append(arena.allocator(), try arena.allocator().dupe(u8, name));
            const removed = self.entries.orderedRemove(index);
            self.membership_revision +%= 1;
            removed.binding.deinit();
            self.engine.gpa.free(removed.source);
            for (names.items) |name| self.recordRegistration(name, self.selection_received) catch |err| {
                self.registration_failure = err;
                return err;
            };
            return;
        };
    }

    pub fn tool(self: *Group, name: []const u8) ?c.JSValue {
        if (self.deinitializing) return null;
        for (self.entries.items) |entry| if (entry.binding.tools.get(name)) |value| return value;
        return null;
    }

    fn lookupTool(context: ?*anyopaque, name: []const u8) ?c.JSValue {
        const self: *Group = @ptrCast(@alignCast(context.?));
        return self.tool(name);
    }

    fn patternMatches(pattern: []const u8, name: []const u8) bool {
        var p: usize = 0;
        var n: usize = 0;
        var star: ?usize = null;
        var retry: usize = 0;
        while (n < name.len) {
            if (p < pattern.len and (pattern[p] == '?' or pattern[p] == name[n])) {
                p += 1;
                n += 1;
            } else if (p < pattern.len and pattern[p] == '*') {
                star = p;
                p += 1;
                retry = n;
            } else if (star) |at| {
                p = at + 1;
                retry += 1;
                n = retry;
            } else return false;
        }
        while (p < pattern.len and pattern[p] == '*') p += 1;
        return p == pattern.len;
    }

    fn policyEnabled(context: ?*anyopaque, name: []const u8, default_active: bool) bool {
        const self: *Group = @ptrCast(@alignCast(context.?));
        const root = if (self.selection_context) |data| data.value else return default_active;
        if (root != .object) return default_active;
        if (root.object.get("noTools")) |value| if (value == .bool and value.bool) return false;
        var enabled = default_active;
        if (root.object.get("allow")) |allowed| if (allowed == .array) {
            enabled = false;
            for (allowed.array.items) |pattern| if (pattern == .string and patternMatches(pattern.string, name)) {
                enabled = true;
                break;
            };
        };
        if (root.object.get("modifiers")) |modifiers| if (modifiers == .array) {
            for (modifiers.array.items) |modifier| {
                if (modifier != .string or modifier.string.len == 0) continue;
                const negative = modifier.string[0] == '-';
                const explicit = negative or modifier.string[0] == '+';
                const candidate = if (explicit) modifier.string[1..] else modifier.string;
                if (std.mem.eql(u8, candidate, name)) enabled = !negative;
            }
        };
        if (root.object.get("exclude")) |excluded| if (excluded == .array) {
            for (excluded.array.items) |pattern| if (pattern == .string and patternMatches(pattern.string, name)) return false;
        };
        return enabled;
    }
    fn policySelected(context: ?*anyopaque, name: []const u8) bool {
        return policyEnabled(context, name, false);
    }
    fn policy(self: *Group) activation_mod.Policy {
        return .{ .context = self, .enabled_fn = policyEnabled, .selected_fn = policySelected };
    }

    fn registration(context: ?*anyopaque, caller: *bindings_mod.Bindings, name: []const u8) !void {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        // The original runtime refresh callback is unbound during initial
        // factories. Reading user default/exposure getters must wait until all
        // factories have completed and the registry is admitted.
        if (!self.registration_baseline_ready or caller.factory_active) return;
        self.recordRegistration(name, self.selection_received and !caller.factory_active) catch |err| {
            self.registration_failure = err;
            return err;
        };
        self.registration_failure = null;
    }

    pub fn initializeActivation(self: *Group) !void {
        if (self.registration_baseline_ready) return;
        self.registration_baseline_ready = true;
        try self.refreshOwnerActivation(null, false);
    }
    pub fn refreshOwnerActivation(self: *Group, owner_id: ?u64, activate: bool) !void {
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        var names: std.ArrayList([]const u8) = .empty;
        for (self.entries.items) |entry| {
            if (owner_id) |owner| if (entry.id != owner) continue;
            for (entry.binding.tool_order.items) |name| {
                var duplicate = false;
                for (names.items) |existing| if (std.mem.eql(u8, existing, name)) {
                    duplicate = true;
                    break;
                };
                if (!duplicate) try names.append(arena.allocator(), try arena.allocator().dupe(u8, name));
            }
        }
        for (names.items) |name| try self.recordRegistration(name, activate);
    }
    fn recordRegistration(self: *Group, name: []const u8, activate: bool) !void {
        if (self.registration_depth >= 64) return error.NativeRegistrationReentrancyLimit;
        self.registration_depth += 1;
        defer self.registration_depth -= 1;
        if (self.registration_journal.items.len >= 4096) return error.NativeRegistrationJournalLimit;
        for (0..64) |_| {
            const revision = self.registrationRevision();
            var winner: ?Entry = null;
            var definition: ?c.JSValue = null;
            for (self.entries.items) |entry| if (entry.binding.tools.get(name)) |value| {
                winner = entry;
                definition = c.JS_DupValue(self.engine.context, value);
                break;
            };
            defer if (definition) |value| self.engine.freeValue(value);
            var event: activation_mod.Event = .{
                .owner_generation = self.activation.owner_generation,
                .sequence = 0,
                .owner_id = if (winner) |entry| entry.id else 0,
                .source_path = try self.engine.gpa.dupe(u8, if (winner) |entry| entry.source else ""),
                .name = "",
                .registered = winner != null,
                .activate = activate,
            };
            var retained = false;
            defer if (!retained) event.deinit(self.engine.gpa);
            event.name = try self.engine.gpa.dupe(u8, name);
            if (definition) |value| {
                const raw_default = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "defaultActive"));
                defer self.engine.freeValue(raw_default);
                event.default_active = !c.JS_IsBool(raw_default) or c.JS_ToBool(self.engine.context, raw_default) != 0;
                const exposure = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, value, "exposure"));
                defer self.engine.freeValue(exposure);
                event.declarable = c.JS_IsUndefined(exposure) or c.JS_IsNull(exposure);
                if (c.JS_IsString(exposure)) {
                    const text = try self.engine.toString(exposure);
                    defer self.engine.gpa.free(text);
                    event.declarable = std.mem.eql(u8, text, "direct") or std.mem.eql(u8, text, "model-only");
                    event.hidden = std.mem.eql(u8, text, "hidden");
                }
            }
            if (revision != self.registrationRevision()) continue;
            event.sequence = std.math.add(u64, self.activation.sequence, 1) catch return error.NativeRegistrationSequenceExhausted;
            try self.registration_journal.ensureUnusedCapacity(self.engine.gpa, 1);
            var prepared = try self.activation.clone();
            errdefer prepared.deinit();
            try prepared.applyPrepared(&event, self.policy());
            self.activation.commit(&prepared);
            self.registration_journal.appendAssumeCapacity(event);
            retained = true;
            return;
        }
        return error.NativeRegistrationProjectionUnstable;
    }

    fn activeTools(context: ?*anyopaque) !c.JSValue {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        var values: std.json.Array = .init(self.engine.gpa);
        defer values.deinit();
        for (self.activation.active.items) |name| try values.append(.{ .string = name });
        return self.engine.fromJsonValue(.{ .array = values });
    }
    fn setActiveTools(context: ?*anyopaque, caller: *bindings_mod.Bindings, value: c.JSValue) !u64 {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        const raw = try self.engine.stringify(value);
        defer self.engine.gpa.free(raw);
        var parsed = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, raw, .{});
        defer parsed.deinit();
        if (parsed.value != .array) return error.InvalidNativeToolSelection;
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.engine.gpa);
        for (parsed.value.array.items) |name| {
            if (name != .string) return error.InvalidNativeToolSelection;
            if (!policyEnabled(self, name.string, true)) continue;
            // The upstream loadout ignores unknown and hidden names. Deferred
            // and codemode tools can be explicitly selected by this API.
            if (self.tool(name.string)) |definition| {
                const retained = c.JS_DupValue(self.engine.context, definition);
                defer self.engine.freeValue(retained);
                const exposure = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, retained, "exposure"));
                defer self.engine.freeValue(exposure);
                if (c.JS_IsString(exposure)) {
                    const text = try self.engine.toString(exposure);
                    defer self.engine.gpa.free(text);
                    if (std.mem.eql(u8, text, "hidden")) continue;
                }
            } else {
                var known = false;
                for (self.external_tools.items) |external| if (std.mem.eql(u8, external, name.string)) {
                    known = true;
                    break;
                };
                if (!known) continue;
            }
            try names.append(self.engine.gpa, name.string);
        }
        if (self.registration_journal.items.len >= 4096) return error.NativeRegistrationJournalLimit;
        try self.registration_journal.ensureUnusedCapacity(self.engine.gpa, 1);
        var event = try (activation_mod.Event{
            .kind = .selection,
            .owner_generation = self.activation.owner_generation,
            .sequence = self.activation.sequence + 1,
            .owner_id = caller.owner_id,
            .source_path = caller.source_path orelse "",
            .name = "",
            .active_tools = names.items,
        }).clone(self.engine.gpa);
        errdefer event.deinit(self.engine.gpa);
        var prepared = try self.activation.clone();
        errdefer prepared.deinit();
        try prepared.applyPrepared(&event, self.policy());
        self.activation.commit(&prepared);
        self.registration_journal.appendAssumeCapacity(event);
        return event.sequence;
    }
    fn selectionContext(context: ?*anyopaque, bytes: []const u8) !void {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        try self.initializeActivation();
        var parsed = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, bytes, .{});
        defer parsed.deinit();
        if (parsed.value != .object) return error.InvalidNativeToolSelection;
        const object = parsed.value.object;
        var external: std.ArrayList([]const u8) = .empty;
        var external_committed = false;
        defer if (!external_committed) {
            for (external.items) |name| self.engine.gpa.free(name);
            external.deinit(self.engine.gpa);
        };
        const registry = object.get("allTools") orelse object.get("activeTools");
        if (registry) |all| {
            if (all != .array) return error.InvalidNativeToolSelection;
            for (all.array.items) |item| {
                const name = if (item == .string) item else if (item == .object) item.object.get("name") orelse return error.InvalidNativeToolSelection else return error.InvalidNativeToolSelection;
                if (name != .string) return error.InvalidNativeToolSelection;
                if (self.tool(name.string) != null) continue;
                var duplicate = false;
                for (external.items) |existing| if (std.mem.eql(u8, existing, name.string)) {
                    duplicate = true;
                    break;
                };
                if (duplicate) continue;
                const owned = try self.engine.gpa.dupe(u8, name.string);
                errdefer self.engine.gpa.free(owned);
                try external.append(self.engine.gpa, owned);
            }
        }
        const ack = if (object.get("nativeRegistrationSequence")) |value| blk: {
            if (value == .string) break :blk try std.fmt.parseUnsigned(u64, value.string, 10);
            if (value == .integer and value.integer >= 0) break :blk @as(u64, @intCast(value.integer));
            return error.InvalidNativeToolSelection;
        } else 0;
        var new_policy: ?std.json.Parsed(std.json.Value) = null;
        errdefer if (new_policy) |*data| data.deinit();
        if (object.get("nativeToolSelection")) |policy_value| {
            if (policy_value != .object) return error.InvalidNativeToolSelection;
            const raw = try std.json.Stringify.valueAlloc(self.engine.gpa, policy_value, .{});
            defer self.engine.gpa.free(raw);
            new_policy = try std.json.parseFromSlice(std.json.Value, self.engine.gpa, raw, .{ .allocate = .alloc_always });
        }
        if (object.get("activeTools")) |active| {
            if (active != .array) return error.InvalidNativeToolSelection;
            var names: std.ArrayList([]const u8) = .empty;
            defer names.deinit(self.engine.gpa);
            for (active.array.items) |name| {
                if (name != .string) return error.InvalidNativeToolSelection;
                try names.append(self.engine.gpa, name.string);
            }
            try self.activation.reconcileContext(names.items, ack, self.registration_journal.items);
        }
        if (new_policy != null) {
            if (self.selection_context) |*old| old.deinit();
            self.selection_context = new_policy;
        }
        self.selection_received = true;
        for (self.external_tools.items) |name| self.engine.gpa.free(name);
        self.external_tools.deinit(self.engine.gpa);
        self.external_tools = external;
        external_committed = true;
        while (self.registration_journal.items.len != 0 and self.registration_journal.items[0].sequence <= ack) {
            var removed = self.registration_journal.orderedRemove(0);
            removed.deinit(self.engine.gpa);
        }
    }

    fn providerCatalog(context: ?*anyopaque) !c.JSValue {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        const result = try self.engine.checked(c.JS_NewArray(self.engine.context));
        errdefer self.engine.freeValue(result);
        var output: u32 = 0;
        for (self.entries.items) |entry| {
            const records = try entry.binding.providers.catalogSnapshot();
            defer self.engine.freeValue(records);
            const count_value = try self.engine.checked(c.JS_GetPropertyStr(self.engine.context, records, "length"));
            defer self.engine.freeValue(count_value);
            var count: u32 = 0;
            if (c.JS_ToUint32(self.engine.context, &count, count_value) < 0) return error.JavaScriptException;
            for (0..count) |index| {
                if (output >= 65536) return error.NativeModelProviderLimit;
                const item = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, records, @intCast(index)));
                if (c.JS_SetPropertyUint32(self.engine.context, result, output, item) < 0) return error.JavaScriptException;
                output += 1;
            }
        }
        return result;
    }

    const CatalogCommand = struct { owner: *bindings_mod.Bindings, name: []const u8, value: c.JSValue };
    fn catalog(context: ?*anyopaque, caller: *bindings_mod.Bindings, kind: bindings_mod.Bindings.CatalogKind) !c.JSValue {
        const self: *Group = @ptrCast(@alignCast(context.?));
        if (self.deinitializing) return error.StaleNativeExtensionOwner;
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var values: std.json.Array = .init(allocator);
        const snapshot = try caller.catalogSnapshot(allocator, kind);
        if (snapshot != .array) return error.InvalidNativeCatalogSnapshot;
        // Agent snapshots can contain older extension projections. The group
        // owns current extension entries; retain external prompt/skill/builtins.
        for (snapshot.array.items) |item| {
            if (item != .object) return error.InvalidNativeCatalogSnapshot;
            if (item.object.get("source")) |source| if (source == .string and std.mem.eql(u8, source.string, "extension")) continue;
            try values.append(item);
        }
        var registrations: std.ArrayList(CatalogCommand) = .empty;
        defer {
            for (registrations.items) |item| self.engine.freeValue(item.value);
            registrations.deinit(allocator);
        }
        for (self.entries.items) |entry| {
            const order = if (kind == .tools) entry.binding.tool_order.items else entry.binding.command_order.items;
            const table = if (kind == .tools) &entry.binding.tools else &entry.binding.commands;
            for (order) |name| if (table.get(name)) |value| {
                const copied_name = try allocator.dupe(u8, name);
                const retained = c.JS_DupValue(self.engine.context, value);
                registrations.append(allocator, .{ .owner = entry.binding, .name = copied_name, .value = retained }) catch |err| {
                    self.engine.freeValue(retained);
                    return err;
                };
            };
        }
        if (kind == .tools) {
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (registrations.items) |entry| {
                if (seen.contains(entry.name)) continue;
                try seen.put(allocator, entry.name, {});
                const projected = try entry.owner.catalogEntry(allocator, kind, entry.name, entry.value);
                var replaced = false;
                for (values.items) |*item| {
                    const existing = item.object.get("name") orelse continue;
                    if (existing == .string and std.mem.eql(u8, existing.string, entry.name)) {
                        item.* = projected;
                        replaced = true;
                        break;
                    }
                }
                if (!replaced) try values.append(projected);
            }
        } else {
            var counts: std.StringHashMapUnmanaged(usize) = .empty;
            var seen: std.StringHashMapUnmanaged(usize) = .empty;
            var taken: std.StringHashMapUnmanaged(void) = .empty;
            for (registrations.items) |entry| {
                const count = try counts.getOrPut(allocator, entry.name);
                if (!count.found_existing) count.value_ptr.* = 0;
                count.value_ptr.* += 1;
            }
            var commands: std.json.Array = .init(allocator);
            for (registrations.items) |entry| {
                const occurrence = try seen.getOrPut(allocator, entry.name);
                if (!occurrence.found_existing) occurrence.value_ptr.* = 0;
                occurrence.value_ptr.* += 1;
                var suffix = occurrence.value_ptr.*;
                var invocation = if (counts.get(entry.name).? > 1) try std.fmt.allocPrint(allocator, "{s}:{d}", .{ entry.name, suffix }) else entry.name;
                while (taken.contains(invocation)) {
                    suffix += 1;
                    invocation = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ entry.name, suffix });
                }
                try taken.put(allocator, invocation, {});
                const projected = try entry.owner.catalogEntry(allocator, kind, invocation, entry.value);
                try commands.append(projected);
            }
            try commands.appendSlice(values.items);
            values = commands;
        }
        return self.engine.fromJsonValue(.{ .array = values });
    }

    pub fn manifest(self: *Group) ![]u8 {
        try self.initializeActivation();
        for (0..64) |_| {
            const before = self.registrationRevision();
            const raw = try self.manifestSnapshot();
            if (before == self.registrationRevision()) return raw;
            self.engine.gpa.free(raw);
        }
        return error.NativeRegistrationProjectionUnstable;
    }

    fn registrationRevision(self: *Group) u64 {
        var revision = self.membership_revision;
        for (self.entries.items) |entry| revision +%= entry.binding.registration_revision;
        return revision;
    }

    fn manifestSnapshot(self: *Group) ![]u8 {
        var arena: std.heap.ArenaAllocator = .init(self.engine.gpa);
        defer arena.deinit();
        const allocator = arena.allocator();
        var entries: std.json.Array = .init(allocator);
        for (self.entries.items) |entry| {
            const raw = try entry.binding.manifestJson(entry.source);
            defer self.engine.gpa.free(raw);
            var manifest_value = try std.json.parseFromSliceLeaky(std.json.Value, allocator, raw, .{});
            try manifest_value.object.put(allocator, "extensionId", .{ .integer = @intCast(entry.id) });
            try manifest_value.object.put(allocator, "sourcePath", .{ .string = entry.source });
            try entries.append(manifest_value);
        }
        return std.json.Stringify.valueAlloc(self.engine.gpa, std.json.Value{ .array = entries }, .{});
    }
};

test "native group retains real resolver base component state identity and action origin across extension callbacks" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("group-resolver-first.mjs");
    try first.installSchemas();
    try first.loadFactory("export default pi=>{globalThis.firstApi=pi;pi.registerToolRenderer((name,next)=>{const base=next();if(!base)return base;return {...base,renderCall(args,theme,ctx){const component=base.renderCall(args,theme,ctx);if(component!==globalThis.baseComponent||ctx.state!==globalThis.baseState)throw Error('resolver identity');firstApi.appendEntry('origin-first',{identity:true});return component}}})}", "group-resolver-first.mjs");
    const second = try group.add("group-tool-second.mjs");
    try second.loadFactory("import {Text} from 'pi-tui';export default pi=>pi.registerTool({name:'second-tool',execute(){return {}},renderCall(args,theme,ctx){globalThis.baseState=ctx.state;globalThis.baseComponent=ctx.lastComponent??new Text('actual',0,0);return baseComponent}})", "group-tool-second.mjs");
    const actual = group.tool("second-tool").?;
    const first_resolved = try group.renderers.resolve("second-tool", actual);
    defer engine.freeValue(first_resolved);
    try std.testing.expect(c.JS_IsObject(first_resolved));
    try second.setContext("{\"cwd\":\"group\"}");
    const shared_tool = c.JS_DupValue(engine.context, actual);
    defer engine.freeValue(shared_tool);
    // Begin the selected extension invocation; another extension's resolver
    // records its action to this invocation while retaining its own origin.
    const signal = try abort_signal.create(engine);
    defer engine.freeValue(signal);
    try second.setInvocationOptions(signal, null, null);
    const raw = try second.invokeRenderer(.render_tool_call, "second-tool", "{\"toolCallId\":\"group-row\",\"args\":{}}");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "actual") != null);
    try std.testing.expectEqual(@as(usize, 1), second.actions.items.len);
    const origin = try engine.checked(c.JS_GetPropertyStr(engine.context, second.actions.items[0], "sourceExtensionId"));
    defer engine.freeValue(origin);
    var owner_id: i64 = 0;
    try std.testing.expect(c.JS_ToInt64(engine.context, &owner_id, origin) == 0);
    try std.testing.expectEqual(@as(i64, 1), owner_id);
    // Renderer output actions are display-only. The source still belongs to
    // firstApi and never mutates the second extension's registrations.
    try std.testing.expect(!first.tools.contains("second-tool") and second.tools.contains("second-tool"));
    c.JS_RunGC(engine.runtime);
}

test "native group retired owner callbacks cannot attribute late actions to surviving invocations" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("retired-owner.mjs");
    try first.loadFactory("export default pi=>{globalThis.retiredApi=pi;pi.registerToolRenderer((name,next)=>next())}", "retired-owner.mjs");
    const second = try group.add("surviving-owner.mjs");
    try second.loadFactory("export default pi=>pi.registerCommand('late',{handler(){let rejected=false;try{retiredApi.appendEntry('late',{spoof:true})}catch(error){rejected=true}pi.appendEntry('live',{});return {message:String(rejected)}}})", "surviving-owner.mjs");
    try group.remove(1);
    c.JS_RunGC(engine.runtime);
    const raw = try second.invokeCommand("late", "");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "\"message\":\"true\"") != null);
    try std.testing.expectEqual(@as(usize, 1), second.actions.items.len);
    const value = try engine.checked(c.JS_GetPropertyStr(engine.context, second.actions.items[0], "sourceExtensionName"));
    defer engine.freeValue(value);
    const name = try engine.toString(value);
    defer std.testing.allocator.free(name);
    try std.testing.expectEqualStrings("surviving-owner", name);
    try std.testing.expect(group.broker.active == null);
    c.JS_RunGC(engine.runtime);
}

test "native group API reads use active session while flags keep their registration owner" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("first-read.mjs");
    try first.loadFactory("export default pi=>{globalThis.firstReadApi=pi;pi.registerFlag('label',{type:'string',default:'first'})}", "first-read.mjs");
    try first.setContext("{\"settings\":{\"marker\":\"old\"},\"sessionName\":\"old\"}");
    const second = try group.add("second-read.mjs");
    try second.loadFactory("export default pi=>pi.registerCommand('read',{handler(){firstReadApi.setSessionName('changed');return {message:firstReadApi.getSettings().marker+':'+firstReadApi.getSessionName()+':'+firstReadApi.getFlag('label')}}})", "second-read.mjs");
    try second.setContext("{\"settings\":{\"marker\":\"active\"},\"sessionName\":\"before\"}");
    const raw = try second.invokeCommand("read", "");
    defer std.testing.allocator.free(raw);
    try std.testing.expect(std.mem.indexOf(u8, raw, "active:changed:first") != null);
}

test "native group catalogs match upstream ordered first tool and collision command aliases replacement unload snapshots" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const first = try group.add("first-catalog.mjs");
    try first.loadFactory("export default pi=>{globalThis.catalogFirst=pi;pi.registerTool({name:'read',description:'first',parameters:{type:'object'},execute(){return {}}});pi.registerCommand('same:1',{handler(){return {}}});pi.registerCommand('same',{handler(){return {}}});pi.registerCommand('inspect',{handler(){const tools=pi.getAllTools(),commands=pi.getCommands();return {tools:tools.map(t=>t.name+':'+t.description),commands:commands.map(c=>c.name)}}})}", "first-catalog.mjs");
    const second = try group.add("second-catalog.mjs");
    try second.loadFactory("export default pi=>{pi.registerTool({name:'read',description:'second',parameters:{type:'object'},execute(){return {}}});pi.registerTool({name:'added',description:'added',parameters:{type:'object'},execute(){return {}}});pi.registerCommand('same',{handler(){return {}}});pi.registerCommand('inspect-second',{handler(){return {tools:pi.getAllTools().map(t=>t.name+':'+t.description),commands:pi.getCommands().map(c=>c.name)}}});pi.registerCommand('replace',{handler(){catalogFirst.registerTool({name:'read',description:'first replacement',parameters:{type:'object'},execute(){return {}}});return {}}})}", "second-catalog.mjs");
    const context = "{\"allTools\":[{\"name\":\"read\",\"description\":\"builtin\",\"source\":\"builtin\"},{\"name\":\"write\",\"description\":\"builtin\",\"source\":\"builtin\"}],\"commands\":[{\"name\":\"prompt\",\"source\":\"prompt\"},{\"name\":\"obsolete\",\"source\":\"extension\"}]}";
    try first.setContext(context);
    try second.setContext(context);
    const original = try first.invokeCommand("inspect", "");
    defer gpa.free(original);
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, original, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;
    try std.testing.expectEqual(@as(usize, 3), tools.len);
    try std.testing.expectEqualStrings("read:first", tools[0].string);
    try std.testing.expectEqualStrings("write:builtin", tools[1].string);
    try std.testing.expectEqualStrings("added:added", tools[2].string);
    const commands = parsed.value.object.get("commands").?.array.items;
    try std.testing.expectEqual(@as(usize, 7), commands.len);
    for ([_][]const u8{ "same:1", "same:2", "inspect", "same:3", "inspect-second", "replace", "prompt" }, commands) |expected, actual| try std.testing.expectEqualStrings(expected, actual.string);
    const replaced = try second.invokeCommand("replace", "");
    defer gpa.free(replaced);
    const inspected = try second.invokeCommand("inspect-second", "");
    defer gpa.free(inspected);
    try std.testing.expect(std.mem.indexOf(u8, inspected, "read:first replacement") != null);
    try group.remove(1);
    c.JS_RunGC(engine.runtime);
    const unloaded = try second.invokeCommand("inspect-second", "");
    defer gpa.free(unloaded);
    try std.testing.expect(std.mem.indexOf(u8, unloaded, "read:second") != null and std.mem.indexOf(u8, unloaded, "\"same\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, unloaded, "same:3") == null and std.mem.indexOf(u8, unloaded, "obsolete") == null);
}

test "native group owner replays dirty call and final result with actual retained state components and resize fences" {
    const protocol = @import("renderer_protocol.zig");
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    defer group.deinit();
    const owner = try group.add("replay-owner.mjs");
    try owner.installSchemas();
    try owner.loadFactory("import {Text} from 'pi-tui';export default pi=>{let oldInvalidate;pi.registerTool({name:'paint',execute(){return {}},renderCall(args,theme,ctx){oldInvalidate=ctx.invalidate;ctx.state.calls=(ctx.state.calls??0)+1;const component=ctx.lastComponent??new Text('',0,0);component.setText('call:'+ctx.state.calls+':'+args.label);return component},renderResult(result,opts,theme,ctx){ctx.state.results=(ctx.state.results??0)+1;const component=ctx.lastComponent??new Text('',0,0);component.setText('result:'+ctx.state.results+':'+result.content+':'+opts.isPartial);return component}});pi.registerCommand('invalidate',{handler(){oldInvalidate();return {message:'invalidated'}}})}", "replay-owner.mjs");
    const Capture = struct {
        queue: protocol.Queue,
        fn record(context: ?*anyopaque, value: protocol.Record) !void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            try self.queue.send(value);
        }
    };
    var capture: Capture = .{ .queue = protocol.Queue.init(gpa, std.testing.io) };
    defer capture.queue.deinit();
    group.renderers.record_fn = Capture.record;
    group.renderers.record_context = &capture;
    group.renderers.owner_generation = 42;
    group.renderers.subscribe(true);
    const call = try owner.invokeRenderer(.render_tool_call, "paint", "{\"toolCallId\":\"row\",\"args\":{\"label\":\"owned\"},\"width\":80}");
    defer gpa.free(call);
    const result = try owner.invokeRenderer(.render_tool_result, "paint", "{\"toolCallId\":\"row\",\"result\":{\"content\":\"final\"},\"isPartial\":false,\"width\":80}");
    defer gpa.free(result);
    const before = group.renderers.rows.get("row").?;
    const saved_call = c.JS_DupValue(engine.context, before.call);
    defer engine.freeValue(saved_call);
    const saved_result = c.JS_DupValue(engine.context, before.result);
    defer engine.freeValue(saved_result);
    const generation = before.generation;
    const invalidated = try owner.invokeCommand("invalidate", "");
    defer gpa.free(invalidated);
    c.JS_RunGC(engine.runtime);
    try std.testing.expect(try group.renderers.pumpDirty());
    const after = group.renderers.rows.get("row").?;
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, saved_call, after.call) and c.JS_IsStrictEqual(engine.context, saved_result, after.result));
    var fence: protocol.Fence = .{ .owner_generation = 42, .extension_id = 1, .row_generation = generation, .tool_call_id = "row" };
    const stale: protocol.Control = .{ .gpa = gpa, .fence = .{ .owner_generation = 41, .extension_id = 1, .row_generation = generation, .tool_call_id = "row" }, .kind = .{ .resize = 60 } };
    try std.testing.expect(!try group.renderers.control(&stale));
    const resize: protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .{ .resize = 60 } };
    try std.testing.expect(try group.renderers.control(&resize));
    try std.testing.expect(try group.renderers.pumpDirty());
    var call_seen = false;
    var result_seen = false;
    while (capture.queue.take()) |received| {
        var record = received;
        defer record.deinit();
        if (record.kind == .frame and record.kind.frame.width == 60) {
            if (record.kind.frame.slot == .call) {
                try std.testing.expect(std.mem.indexOf(u8, record.kind.frame.frame.lines[0], "call:3:owned") != null);
                call_seen = true;
            } else {
                try std.testing.expect(std.mem.indexOf(u8, record.kind.frame.frame.lines[0], "result:3:final:false") != null);
                result_seen = true;
            }
        }
    }
    try std.testing.expect(call_seen and result_seen);
    fence.row_generation += 1;
    const late: protocol.Control = .{ .gpa = gpa, .fence = fence, .kind = .retire };
    try std.testing.expect(!try group.renderers.control(&late));
    try std.testing.expect(group.renderers.retire("row", generation));
    try std.testing.expect(!try group.renderers.control(&resize));
    c.JS_RunGC(engine.runtime);
}

test "native group shutdown retires owner APIs before observable editor disposal and fences sibling catalogs" {
    const gpa = std.testing.allocator;
    const engine = try engine_mod.Engine.init(gpa, .{});
    defer engine.deinit();
    const group = try Group.init(engine);
    var released = false;
    defer if (!released) group.deinit();
    const first = try group.add("dispose-first.mjs");
    try first.installSchemas();
    try first.loadFactory("export default pi=>{globalThis.firstDisposeApi=pi}", "dispose-first.mjs");
    const second = try group.add("dispose-second.mjs");
    try second.loadFactory("export default pi=>{globalThis.secondDisposeApi=pi}", "dispose-second.mjs");
    const factory = try engine.eval("(()=>({getText(){return ''},setText(value){},handleInput(input){},render(){return ['dispose-owned']},dispose(){globalThis.disposeRan=true;try{firstDisposeApi.registerTool({name:'late',parameters:{type:'object'},execute(){}})}catch(e){globalThis.firstDisposeFenced=true}try{secondDisposeApi.getAllTools()}catch(e){globalThis.secondDisposeFenced=true}}}))", "dispose-factory.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(factory);
    const draft = try engine.checked(c.JS_NewString(engine.context, ""));
    defer engine.freeValue(draft);
    const theme = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(theme);
    const keys = try engine.checked(c.JS_NewObject(engine.context));
    defer engine.freeValue(keys);
    try group.ui.editors.setFactory(1, factory, draft, theme, keys, 80, 24);
    group.deinit();
    released = true;
    const result = try engine.eval("globalThis.disposeRan===true&&globalThis.firstDisposeFenced===true&&globalThis.secondDisposeFenced===true", "dispose-proof.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(result);
    try std.testing.expect(c.JS_ToBool(engine.context, result) != 0);
}
