//! SDK ToolInfo comes from the actual retained SDK session, never Main context
//! JSON. Native registry keys and VM definitions have independent lifetimes.
const std = @import("std");
const engine_mod = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const bindings_mod = @import("native_bindings.zig");
const group_mod = @import("native_group.zig");
const vm = @import("native_values.zig");
const catalog = @import("native_tool_catalog.zig");
const info = @import("native_tool_info.zig");
const selection = @import("../coding_agent/tool_selection.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
const Version = struct { id: u64, revision: ?u64 };
const Record = struct { name: []u8, definition: c.JSValue, source: c.JSValue, agent_tool: ?c.JSValue = null };
const Retained = struct { definition: c.JSValue, source: c.JSValue };

pub const State = struct {
    engine: *Engine,
    records: std.ArrayList(Record) = .empty,
    versions: std.ArrayList(Version) = .empty,
    arena: std.heap.ArenaAllocator,
    allowed: ?[]const []const u8 = null,
    denied: []const []const u8 = &.{},
    filters_mcp: bool = false,
    initialized: bool = false,
    refreshing: bool = false,
    scope_generation: u64 = 0,
    fn release(self: *State, runtime: ?*c.JSRuntime, records: *std.ArrayList(Record)) void {
        for (records.items) |record| {
            self.engine.gpa.free(record.name);
            c.JS_FreeValueRT(runtime, record.definition);
            c.JS_FreeValueRT(runtime, record.source);
            if (record.agent_tool) |tool| c.JS_FreeValueRT(runtime, tool);
        }
        records.deinit(self.engine.gpa);
    }
    pub fn deinit(self: *State, runtime: ?*c.JSRuntime) void {
        self.retire();
        self.release(runtime, &self.records);
        self.versions.deinit(self.engine.gpa);
        self.arena.deinit();
        self.engine.gpa.destroy(self);
    }
    pub fn mark(self: *State, runtime: ?*c.JSRuntime, marker: ?*const c.JS_MarkFunc) void {
        for (self.records.items) |record| {
            c.JS_MarkValue(runtime, record.definition, marker);
            c.JS_MarkValue(runtime, record.source, marker);
            if (record.agent_tool) |tool| c.JS_MarkValue(runtime, tool, marker);
        }
    }
    pub fn retire(self: *State) void {
        if (self.scope_generation == 0) return;
        if (self.engine.native_sdk_extension_group) |raw| {
            const group: *group_mod.Group = @ptrCast(@alignCast(raw));
            group.retireNativeToolCatalog(.{ .owner = self, .generation = self.scope_generation });
        }
        self.scope_generation = 0;
    }
    fn permits(self: *State, name: []const u8) bool {
        for (self.denied) |pattern| if (@import("../mcp/config.zig").matches(pattern, name)) return false;
        const allowed = self.allowed orelse return true;
        for (allowed) |pattern| if (@import("../mcp/config.zig").matches(pattern, name)) return true;
        return !self.filters_mcp and isMcp(name);
    }
    fn put(self: *State, records: *std.ArrayList(Record), name: []const u8, definition: c.JSValue, source: c.JSValue) !void {
        if (!self.permits(name)) return;
        for (records.items) |*record| if (std.mem.eql(u8, record.name, name)) {
            self.engine.freeValue(record.definition);
            self.engine.freeValue(record.source);
            if (record.agent_tool) |tool| self.engine.freeValue(tool);
            record.agent_tool = null;
            record.definition = c.JS_DupValue(self.engine.context, definition);
            record.source = c.JS_DupValue(self.engine.context, source);
            return;
        };
        const owned = try self.engine.gpa.dupe(u8, name);
        errdefer self.engine.gpa.free(owned);
        try records.ensureUnusedCapacity(self.engine.gpa, 1);
        records.appendAssumeCapacity(.{ .name = owned, .definition = c.JS_DupValue(self.engine.context, definition), .source = c.JS_DupValue(self.engine.context, source) });
    }
    fn refresh(self: *State, owner: *sdk.State) !void {
        if (self.refreshing or (owner.disposed and self.initialized)) return;
        if (self.initialized and try @import("native_sdk_resource_owners.zig").sessionScopeRetired(owner)) return;
        self.refreshing = true;
        defer self.refreshing = false;
        var versions = try ownerVersions(owner);
        defer versions.deinit(self.engine.gpa);
        if (self.initialized and equalVersions(self.versions.items, versions.items)) return;
        var next: std.ArrayList(Record) = .empty;
        errdefer self.release(self.engine.runtime, &next);
        // Native factory-owned builtin definitions, when installed, are real
        // executable VM definitions with canonical parameter constants.
        const base = try vm.get(self.engine, owner.data, "_sdkBuiltinDefinitions");
        defer self.engine.freeValue(base);
        if (c.JS_IsArray(base)) try self.appendDefinitions(&next, base, "builtin");
        if (self.engine.native_sdk_extension_group) |raw| {
            const group: *group_mod.Group = @ptrCast(@alignCast(raw));
            for (versions.items) |version| {
                const binding = group.selected(version.id) catch |err| switch (err) {
                    error.UnknownNativeExtensionOwner => continue,
                    else => return err,
                };
                const source = try binding.sourceInfoValue();
                for (binding.tool_order.items) |name| if (binding.tools.get(name)) |definition| try self.put(&next, name, definition, source);
            }
        }
        // SDK custom definitions win over same-named extension definitions,
        // preserving the first Map position just as Source Map.set does.
        const custom = try vm.get(self.engine, owner.data, "customTools");
        defer self.engine.freeValue(custom);
        try self.appendDefinitions(&next, custom, "sdk");
        var previous = self.records;
        self.records = next;
        next = .empty;
        self.release(self.engine.runtime, &previous);
        self.versions.deinit(self.engine.gpa);
        self.versions = versions;
        versions = .empty;
        self.initialized = true;
    }
    fn appendDefinitions(self: *State, next: *std.ArrayList(Record), definitions: c.JSValue, source_kind: []const u8) !void {
        if (!c.JS_IsArray(definitions)) return;
        for (0..try vm.length(self.engine, definitions)) |index| {
            const definition = try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, definitions, @intCast(index)));
            defer self.engine.freeValue(definition);
            const name_value = try vm.get(self.engine, definition, "name");
            defer self.engine.freeValue(name_value);
            if (!c.JS_IsString(name_value)) return error.InvalidNativeSDKToolName;
            const name = try self.engine.toString(name_value);
            defer self.engine.gpa.free(name);
            const path = if (std.mem.eql(u8, source_kind, "sdk")) try std.fmt.allocPrint(self.engine.gpa, "<sdk:{s}>", .{name}) else try std.fmt.allocPrint(self.engine.gpa, "builtin:{s}", .{name});
            defer self.engine.gpa.free(path);
            const source = try synthetic(self.engine, path, source_kind);
            defer self.engine.freeValue(source);
            try self.put(next, name, definition, source);
        }
    }
};
fn isMcp(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "mcp__") or std.mem.eql(u8, name, "list_mcp_resources") or std.mem.eql(u8, name, "list_mcp_resource_templates") or std.mem.eql(u8, name, "read_mcp_resource");
}
fn strings(engine: *Engine, allocator: std.mem.Allocator, value: c.JSValue) !?[]const []const u8 {
    if (!c.JS_IsArray(value)) return null;
    const result = try allocator.alloc([]const u8, try vm.length(engine, value));
    for (result, 0..) |*item, index| {
        const entry = try engine.checked(c.JS_GetPropertyUint32(engine.context, value, @intCast(index)));
        defer engine.freeValue(entry);
        const text = try engine.toString(entry);
        defer engine.gpa.free(text);
        item.* = try allocator.dupe(u8, text);
    }
    return result;
}
pub fn initialize(owner: *sdk.State, options: c.JSValue) !void {
    if (owner.tool_catalog != null) return;
    const engine = owner.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const self = try engine.gpa.create(State);
    self.* = .{ .engine = engine, .arena = .init(engine.gpa) };
    errdefer self.deinit(engine.runtime);
    const a = self.arena.allocator();
    const tools = try vm.get(engine, options, "tools");
    defer engine.freeValue(tools);
    const entries = try strings(engine, a, tools);
    const no_tools = try vm.get(engine, options, "noTools");
    defer engine.freeValue(no_tools);
    const mode = if (c.JS_IsString(no_tools)) try engine.toString(no_tools) else try engine.gpa.dupe(u8, "");
    defer engine.gpa.free(mode);
    if (entries) |names| {
        if (try selection.listError(a, names)) |message| {
            const text = try std.fmt.allocPrint(a, "Invalid tools option: {s}", .{message});
            const global = c.JS_GetGlobalObject(engine.context);
            defer engine.freeValue(global);
            const constructor = try vm.get(engine, global, "Error");
            defer engine.freeValue(constructor);
            const argument = try engine.checked(c.JS_NewStringLen(engine.context, text.ptr, text.len));
            defer engine.freeValue(argument);
            var arguments = [_]c.JSValue{argument};
            const failure = try engine.checked(c.JS_CallConstructor(engine.context, constructor, arguments.len, &arguments));
            _ = try engine.checked(c.JS_Throw(engine.context, failure));
            unreachable;
        }
        self.allowed = if (selection.usesModifiers(names)) if (std.mem.eql(u8, mode, "all")) try selection.apply(a, &.{}, names) else null else names;
    } else if (std.mem.eql(u8, mode, "all")) self.allowed = &.{};
    if (self.allowed) |names| {
        self.filters_mcp = names.len == 0;
        for (names) |name| if (std.mem.startsWith(u8, name, "mcp__")) {
            self.filters_mcp = true;
        };
    }
    const exclude = try vm.get(engine, options, "excludeTools");
    defer engine.freeValue(exclude);
    self.denied = (try strings(engine, a, exclude)) orelse &.{};
    owner.tool_catalog = self;
    errdefer owner.tool_catalog = null;
    try self.refresh(owner);
}
fn equalVersions(left: []const Version, right: []const Version) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (a.id != b.id or a.revision != b.revision) return false;
    return true;
}
fn ownerVersions(owner: *sdk.State) !std.ArrayList(Version) {
    const engine = owner.engine;
    var result: std.ArrayList(Version) = .empty;
    errdefer result.deinit(engine.gpa);
    const ids = try @import("native_sdk_resource_owners.zig").sessionOwnerIds(engine, owner.data);
    defer engine.freeValue(ids);
    if (!c.JS_IsArray(ids)) return result;
    const group: ?*group_mod.Group = if (engine.native_sdk_extension_group) |raw| @ptrCast(@alignCast(raw)) else null;
    for (0..try vm.length(engine, ids)) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, ids, @intCast(index)));
        defer engine.freeValue(value);
        var id: i64 = 0;
        if (c.JS_ToInt64(engine.context, &id, value) < 0 or id <= 0) return error.InvalidNativeSDKToolOwner;
        const binding = if (group) |actual| actual.selected(@intCast(id)) catch |err| switch (err) {
            error.UnknownNativeExtensionOwner => null,
            else => return err,
        } else null;
        try result.append(engine.gpa, .{ .id = @intCast(id), .revision = if (binding) |actual| actual.registration_revision else null });
    }
    return result;
}
fn synthetic(engine: *Engine, path: []const u8, source_kind: []const u8) !c.JSValue {
    const result = try vm.object(engine);
    errdefer engine.freeValue(result);
    try info.putData(engine, result, "path", try engine.checked(c.JS_NewStringLen(engine.context, path.ptr, path.len)));
    try info.putData(engine, result, "source", try engine.checked(c.JS_NewStringLen(engine.context, source_kind.ptr, source_kind.len)));
    try info.putData(engine, result, "scope", try engine.checked(c.JS_NewString(engine.context, "temporary")));
    try info.putData(engine, result, "origin", try engine.checked(c.JS_NewString(engine.context, "top-level")));
    try info.putData(engine, result, "baseDir", c.pi_js_undefined());
    return result;
}
fn current(owner: *sdk.State) !*State {
    const self = owner.tool_catalog orelse return error.NativeSDKToolCatalogUnavailable;
    try self.refresh(owner);
    return self;
}
pub fn getDefinition(owner: *sdk.State, name: c.JSValue) !c.JSValue {
    owner.engine.native_exception_diagnostics_suppressed += 1;
    defer owner.engine.native_exception_diagnostics_suppressed -= 1;
    const self = try current(owner);
    if (!c.JS_IsString(name)) return c.pi_js_undefined();
    const text = try self.engine.toString(name);
    defer self.engine.gpa.free(text);
    for (self.records.items) |record| if (std.mem.eql(u8, record.name, text)) return c.JS_DupValue(self.engine.context, record.definition);
    return c.pi_js_undefined();
}
fn declarable(engine: *Engine, definition: c.JSValue) !bool {
    const value = try vm.get(engine, definition, "exposure");
    defer engine.freeValue(value);
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return true;
    const text = try engine.toString(value);
    defer engine.gpa.free(text);
    return std.mem.eql(u8, text, "direct") or std.mem.eql(u8, text, "model-only");
}
fn activatable(self: *State, record: Record) !bool {
    const value = try vm.get(self.engine, record.definition, "exposure");
    defer self.engine.freeValue(value);
    const text = if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) try self.engine.gpa.dupe(u8, "direct") else try self.engine.toString(value);
    defer self.engine.gpa.free(text);
    if (std.mem.eql(u8, text, "hidden")) return false;
    if (!isMcp(record.name)) return true;
    const allowed = self.allowed orelse return true;
    for (allowed) |pattern| if (@import("../mcp/config.zig").matches(pattern, record.name)) return true;
    if (std.mem.eql(u8, text, "direct")) return false;
    for (self.records.items) |entry| if (std.mem.eql(u8, entry.name, "tool_search")) return true;
    return false;
}
fn agentTool(owner: *sdk.State, record: *Record) !c.JSValue {
    if (record.agent_tool) |tool| return c.JS_DupValue(owner.engine.context, tool);
    const tool = try @import("native_sdk_agent_tool.zig").wrap(owner, record.definition);
    record.agent_tool = tool;
    return c.JS_DupValue(owner.engine.context, tool);
}
pub fn setActive(owner: *sdk.State, requested: c.JSValue) !void {
    const self = try current(owner);
    const engine = self.engine;
    const names = try vm.array(engine);
    defer engine.freeValue(names);
    const definitions = try vm.array(engine);
    defer engine.freeValue(definitions);
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    defer seen.deinit(engine.gpa);
    if (c.JS_IsArray(requested)) for (0..try vm.length(engine, requested)) |index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, requested, @intCast(index)));
        defer engine.freeValue(value);
        if (!c.JS_IsString(value)) continue;
        const name = try engine.toString(value);
        defer engine.gpa.free(name);
        for (self.records.items) |*record| if (std.mem.eql(u8, record.name, name)) {
            if (seen.contains(record.name) or !try activatable(self, record.*)) break;
            try seen.put(engine.gpa, record.name, {});
            const output: u32 = @intCast(try vm.length(engine, names));
            if (c.JS_SetPropertyUint32(engine.context, names, output, c.JS_DupValue(engine.context, value)) < 0 or c.JS_SetPropertyUint32(engine.context, definitions, output, try agentTool(owner, record)) < 0) return error.JavaScriptException;
            break;
        };
    };
    try vm.put(engine, owner.data, "activeTools", c.JS_DupValue(engine.context, names));
    try sdk.setAgentField(owner, "tools", definitions);
}
pub fn initializeActive(owner: *sdk.State, options: c.JSValue) !void {
    const self = try current(owner);
    const engine = self.engine;
    var arena: std.heap.ArenaAllocator = .init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    const configured = try vm.get(engine, options, "tools");
    defer engine.freeValue(configured);
    const entries = try strings(engine, allocator, configured);
    const no_tools = try vm.get(engine, options, "noTools");
    defer engine.freeValue(no_tools);
    const settings = try sdk.publicField(owner, "settingsManager");
    defer engine.freeValue(settings);
    const default_value = try vm.invoke(engine, settings, "getDefaultTools", &.{});
    defer engine.freeValue(default_value);
    const defaults = if (c.JS_ToBool(engine.context, no_tools) == 1) &.{} else (try strings(engine, allocator, default_value)) orelse &selection.default_tool_names;
    const selected = if (entries) |values| if (selection.usesModifiers(values)) try selection.apply(allocator, defaults, values) else values else defaults;
    const requested = try vm.array(engine);
    defer engine.freeValue(requested);
    for (selected, 0..) |name, index| if (c.JS_SetPropertyUint32(engine.context, requested, @intCast(index), try sdk.text(engine, name)) < 0) return error.JavaScriptException;
    for (self.records.items) |record| {
        var activate = false;
        if (self.allowed) |allowed| {
            for (allowed) |pattern| if (@import("../mcp/config.zig").matches(pattern, record.name)) {
                activate = true;
                break;
            };
        } else {
            const source_kind = try vm.get(engine, record.source, "source");
            defer engine.freeValue(source_kind);
            const kind = try engine.toString(source_kind);
            defer engine.gpa.free(kind);
            if (!std.mem.eql(u8, kind, "builtin")) {
                const default_active = try vm.get(engine, record.definition, "defaultActive");
                defer engine.freeValue(default_active);
                activate = !c.JS_IsBool(default_active) or c.JS_ToBool(engine.context, default_active) != 0;
            }
        }
        if (activate and try declarable(engine, record.definition)) if (c.JS_SetPropertyUint32(engine.context, requested, @intCast(try vm.length(engine, requested)), try sdk.text(engine, record.name)) < 0) return error.JavaScriptException;
    }
    try setActive(owner, requested);
}
pub fn activeDefinitions(owner: *sdk.State) !c.JSValue {
    return sdk.agentField(owner, "tools");
}
pub fn callableDefinitions(owner: *sdk.State) !c.JSValue {
    const self = try current(owner);
    const engine = owner.engine;
    const active = try activeNames(owner);
    defer engine.freeValue(active);
    const result = try vm.array(engine);
    errdefer engine.freeValue(result);
    for (self.records.items) |*record| {
        const exposure_value = try vm.get(engine, record.definition, "exposure");
        defer engine.freeValue(exposure_value);
        const exposure_text = if (c.JS_IsUndefined(exposure_value) or c.JS_IsNull(exposure_value)) try engine.gpa.dupe(u8, "direct") else try engine.toString(exposure_value);
        defer engine.gpa.free(exposure_text);
        var callable = std.mem.eql(u8, exposure_text, "codemode") or std.mem.eql(u8, exposure_text, "deferred");
        if (std.mem.eql(u8, exposure_text, "direct")) for (0..try vm.length(engine, active)) |index| {
            const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, active, @intCast(index)));
            defer engine.freeValue(value);
            const name = try engine.toString(value);
            defer engine.gpa.free(name);
            if (std.mem.eql(u8, record.name, name)) {
                callable = true;
                break;
            }
        };
        if (callable and c.JS_SetPropertyUint32(engine.context, result, @intCast(try vm.length(engine, result)), try agentTool(owner, record)) < 0) return error.JavaScriptException;
    }
    return result;
}
pub fn activeNames(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    const definitions = try activeDefinitions(owner);
    defer engine.freeValue(definitions);
    const names = try vm.array(engine);
    errdefer engine.freeValue(names);
    for (0..try vm.length(engine, definitions)) |index| {
        const definition = try engine.checked(c.JS_GetPropertyUint32(engine.context, definitions, @intCast(index)));
        defer engine.freeValue(definition);
        if (c.JS_SetPropertyUint32(engine.context, names, @intCast(index), try vm.get(engine, definition, "name")) < 0) return error.JavaScriptException;
    }
    return names;
}
fn exposure(raw: ?*anyopaque, name: c.JSValue) !c.JSValue {
    const owner: *sdk.State = @ptrCast(@alignCast(raw.?));
    const value = try getDefinition(owner, name);
    defer owner.engine.freeValue(value);
    return if (c.JS_IsUndefined(value)) c.pi_js_undefined() else vm.get(owner.engine, value, "exposure");
}
fn append(owner: *sdk.State, sink: *catalog.CatalogSink) !void {
    const self = try current(owner);
    var snapshot: std.ArrayList(Retained) = .empty;
    defer {
        for (snapshot.items) |record| {
            self.engine.freeValue(record.definition);
            self.engine.freeValue(record.source);
        }
        snapshot.deinit(self.engine.gpa);
    }
    try snapshot.ensureTotalCapacity(self.engine.gpa, self.records.items.len);
    for (self.records.items) |record| snapshot.appendAssumeCapacity(.{ .definition = c.JS_DupValue(self.engine.context, record.definition), .source = c.JS_DupValue(self.engine.context, record.source) });
    for (snapshot.items) |record| try sink.appendVM(record.definition, record.source, .{ .context = owner, .read = exposure });
}
pub fn sessionRows(owner: *sdk.State) !c.JSValue {
    const engine = owner.engine;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var cache = catalog.Cache.init(engine);
    defer cache.deinit();
    var sink = try catalog.CatalogSink.init(&cache);
    defer sink.deinit();
    try append(owner, &sink);
    return sink.finish();
}
/// Group and Main's private router may call this. Retain the actual SDK roots
/// before any metadata getter can unload the caller or enter another session.
pub fn feed(caller: *bindings_mod.Bindings, sink: *catalog.CatalogSink) !void {
    const engine = caller.engine;
    const scope = caller.sdk_context orelse return error.NativeSDKContextUnavailable;
    const session = c.JS_DupValue(engine.context, scope.session);
    defer engine.freeValue(session);
    const registry = c.JS_DupValue(engine.context, scope.registry);
    defer engine.freeValue(registry);
    const manager = c.JS_DupValue(engine.context, scope.manager);
    defer engine.freeValue(manager);
    const group: *group_mod.Group = @ptrCast(@alignCast(engine.native_sdk_extension_group orelse return error.NativeSDKExtensionGroupUnavailable));
    if (try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    const owner = try sdk.state(engine, session);
    try @import("native_sdk_resource_owners.zig").assertSessionScope(owner, group);
    const actual = try sdk.sessionModelLease(owner);
    if (actual.runtime_id != scope.lease.runtime_id or actual.generation != scope.lease.generation) return error.InvalidNativeSDKModelLease;
    const actual_registry = try vm.get(engine, owner.data, "modelRegistry");
    defer engine.freeValue(actual_registry);
    const actual_manager = try sdk.publicField(owner, "sessionManager");
    defer engine.freeValue(actual_manager);
    const registry_lease = try sdk.modelRegistryLease(engine, registry);
    if (!c.JS_IsStrictEqual(engine.context, registry, actual_registry) or !c.JS_IsStrictEqual(engine.context, manager, actual_manager) or registry_lease.runtime_id != actual.runtime_id) return error.InvalidNativeSDKContext;
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const self = owner.tool_catalog orelse return error.NativeSDKToolCatalogUnavailable;
    if (self.scope_generation != 0 and self.scope_generation != actual.generation) self.retire();
    self.scope_generation = actual.generation;
    try sink.beginScope(.{ .owner = self, .generation = actual.generation });
    try append(owner, sink);
}
