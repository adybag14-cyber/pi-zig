//! Private typed native catalog feed. Lifetime identities come from actual
//! service/lease callbacks, never a JSON context field or schema-body hash.
const std = @import("std");
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const info = @import("native_tool_info.zig");
const parameters_mod = @import("native_tool_parameters.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;
pub const OwnerScope = struct { owner: *const anyopaque, generation: u64 };
pub const ParameterIdentity = enum { remote_json, resource_list, resource_read, codemode, tool_search };
pub const Record = struct {
    scope: OwnerScope,
    definition_id: u64,
    parameter_identity: ParameterIdentity,
    /// Independent from definition_id: hiding a previously parsed remote tool
    /// retains its parameter object; a new parse gets a new parameter_id.
    parameter_id: u64 = 0,
    parameter_body_id: u64 = 0,
    raw_parameters: ?std.json.Value = null,
    metadata: std.json.Value,
    parameters: std.json.Value,
    source_info: std.json.Value,
    /// SourceInfo belongs to an extension/builtin source, not necessarily one
    /// tool definition. Tools sharing this private key retain that same object.
    source_info_id: u64 = 0,
    source_scope: ?OwnerScope = null,
    namespace_id: u64 = 0,
    prompt_guidelines_id: u64 = 0,
    annotations_id: u64 = 0,
};
const Key = struct { scope: OwnerScope, id: u64 };
const Parameter = struct { value: c.JSValue, definitions: usize = 0, body: ?Key = null };
const ReferenceKind = enum { namespace, promptGuidelines, annotations };
const ReferenceKey = struct { scope: OwnerScope, id: u64, kind: ReferenceKind };
const Definition = struct { value: c.JSValue, source_info: c.JSValue, parameter: ?Key, references: [3]?ReferenceKey = .{null} ** 3, seen: u64 };
const ScopeState = struct { completed: u64 = 0, retired: bool = false };
pub const Cache = struct {
    engine: *Engine,
    sequence: u64 = 0,
    definitions: std.AutoHashMapUnmanaged(Key, Definition) = .empty,
    parameters: std.AutoHashMapUnmanaged(Key, Parameter) = .empty,
    parameter_bodies: std.AutoHashMapUnmanaged(Key, Parameter) = .empty,
    sources: std.AutoHashMapUnmanaged(Key, c.JSValue) = .empty,
    references: std.AutoHashMapUnmanaged(ReferenceKey, Parameter) = .empty,
    scopes: std.AutoHashMapUnmanaged(OwnerScope, ScopeState) = .empty,
    active_sinks: usize = 0,
    sweeping: bool = false,
    deinitializing: bool = false,
    pub fn init(engine: *Engine) Cache {
        return .{ .engine = engine };
    }
    pub fn parameterValue(self: *Cache, scope: OwnerScope, parameter_id: u64) ?c.JSValue {
        const entry = self.parameters.get(.{ .scope = scope, .id = parameter_id }) orelse return null;
        return c.JS_DupValue(self.engine.context, entry.value);
    }
    pub fn definitionValue(self: *Cache, scope: OwnerScope, definition_id: u64) ?c.JSValue {
        const entry = self.definitions.get(.{ .scope = scope, .id = definition_id }) orelse return null;
        return c.JS_DupValue(self.engine.context, entry.value);
    }
    fn releaseDefinition(self: *Cache, entry: Definition) void {
        self.engine.freeValue(entry.value);
        self.engine.freeValue(entry.source_info);
        if (entry.parameter) |key| if (self.parameters.getPtr(key)) |parameter_entry| {
            std.debug.assert(parameter_entry.definitions > 0);
            parameter_entry.definitions -= 1;
            if (parameter_entry.definitions == 0) {
                self.releaseParameter(self.parameters.fetchRemove(key).?.value);
            }
        };
        for (entry.references) |maybe_key| if (maybe_key) |key| if (self.references.getPtr(key)) |reference| {
            std.debug.assert(reference.definitions > 0);
            reference.definitions -= 1;
            if (reference.definitions == 0) {
                self.engine.freeValue(reference.value);
                _ = self.references.remove(key);
            }
        };
    }
    pub fn deinit(self: *Cache) void {
        self.deinitializing = true;
        var definitions = self.definitions.valueIterator();
        while (definitions.next()) |entry| {
            self.engine.freeValue(entry.value);
            self.engine.freeValue(entry.source_info);
        }
        var parameters = self.parameters.valueIterator();
        while (parameters.next()) |entry| self.engine.freeValue(entry.value);
        var bodies = self.parameter_bodies.valueIterator();
        while (bodies.next()) |entry| self.engine.freeValue(entry.value);
        var sources = self.sources.valueIterator();
        while (sources.next()) |value| self.engine.freeValue(value.*);
        var reference_values = self.references.valueIterator();
        while (reference_values.next()) |reference| self.engine.freeValue(reference.value);
        self.definitions.deinit(self.engine.gpa);
        self.parameters.deinit(self.engine.gpa);
        self.parameter_bodies.deinit(self.engine.gpa);
        self.sources.deinit(self.engine.gpa);
        self.references.deinit(self.engine.gpa);
        std.debug.assert(self.active_sinks == 0);
        self.scopes.deinit(self.engine.gpa);
    }
    pub fn retire(self: *Cache, scope: OwnerScope) void {
        if (self.deinitializing) return;
        if (self.scopes.getPtr(scope)) |state| state.retired = true;
        if (self.active_sinks == 0 and !self.sweeping) self.sweepCompleted();
    }
    fn ensureScope(self: *Cache, scope: OwnerScope) !void {
        const entry = try self.scopes.getOrPut(self.engine.gpa, scope);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        if (entry.value_ptr.retired) return error.StaleNativeCatalogScope;
    }
    fn retireOwned(self: *Cache, scope: OwnerScope) void {
        _ = self.scopes.remove(scope);
        while (true) {
            var found: ?Key = null;
            var entries = self.definitions.keyIterator();
            while (entries.next()) |key| if (std.meta.eql(key.scope, scope)) {
                found = key.*;
                break;
            };
            const key = found orelse break;
            const removed = self.definitions.fetchRemove(key).?;
            self.releaseDefinition(removed.value);
        }
        while (true) {
            var found: ?Key = null;
            var entries = self.sources.keyIterator();
            while (entries.next()) |key| if (std.meta.eql(key.scope, scope)) {
                found = key.*;
                break;
            };
            const key = found orelse break;
            self.engine.freeValue(self.sources.fetchRemove(key).?.value);
        }
        // A failed materialization may have created a parameter before a
        // definition could retain it. Retire those owned values as well.
        while (true) {
            var found: ?Key = null;
            var entries = self.parameters.keyIterator();
            while (entries.next()) |key| if (std.meta.eql(key.scope, scope)) {
                found = key.*;
                break;
            };
            const key = found orelse break;
            self.releaseParameter(self.parameters.fetchRemove(key).?.value);
        }
        self.sweepParameterBodies(scope);
        self.sweepReferences(scope);
    }
    fn sweepCompleted(self: *Cache) void {
        std.debug.assert(self.active_sinks == 0);
        std.debug.assert(!self.sweeping);
        self.sweeping = true;
        defer self.sweeping = false;
        while (true) {
            var found: ?OwnerScope = null;
            var scopes = self.scopes.iterator();
            while (scopes.next()) |entry| if (entry.value_ptr.retired) {
                found = entry.key_ptr.*;
                break;
            };
            const scope = found orelse break;
            self.retireOwned(scope);
        }
        var scopes = self.scopes.iterator();
        while (scopes.next()) |scope_entry| {
            const scope = scope_entry.key_ptr.*;
            const sequence = scope_entry.value_ptr.completed;
            while (true) {
                var found: ?Key = null;
                var entries = self.definitions.iterator();
                while (entries.next()) |entry| if (std.meta.eql(entry.key_ptr.scope, scope) and entry.value_ptr.seen < sequence) {
                    found = entry.key_ptr.*;
                    break;
                };
                const key = found orelse break;
                const removed = self.definitions.fetchRemove(key).?;
                self.releaseDefinition(removed.value);
            }
            self.sweepParameters(scope);
            self.sweepParameterBodies(scope);
            self.sweepReferences(scope);
        }
        // Native finalizers may retire another owner while an old value is
        // released. Process those marks after the non-mutating scope walk.
        while (true) {
            var found: ?OwnerScope = null;
            var remaining = self.scopes.iterator();
            while (remaining.next()) |entry| if (entry.value_ptr.retired) {
                found = entry.key_ptr.*;
                break;
            };
            self.retireOwned(found orelse break);
        }
    }
    fn sweepReferences(self: *Cache, scope: OwnerScope) void {
        while (true) {
            var found: ?ReferenceKey = null;
            var entries = self.references.iterator();
            while (entries.next()) |entry| if (std.meta.eql(entry.key_ptr.scope, scope) and entry.value_ptr.definitions == 0) {
                found = entry.key_ptr.*;
                break;
            };
            const key = found orelse break;
            self.engine.freeValue(self.references.fetchRemove(key).?.value.value);
        }
    }
    fn sweepParameters(self: *Cache, scope: OwnerScope) void {
        while (true) {
            var found: ?Key = null;
            var entries = self.parameters.iterator();
            while (entries.next()) |entry| if (std.meta.eql(entry.key_ptr.scope, scope) and entry.value_ptr.definitions == 0) {
                found = entry.key_ptr.*;
                break;
            };
            const key = found orelse break;
            self.releaseParameter(self.parameters.fetchRemove(key).?.value);
        }
    }
    fn releaseParameter(self: *Cache, parameter_value: Parameter) void {
        self.engine.freeValue(parameter_value.value);
        if (parameter_value.body) |key| {
            const body = self.parameter_bodies.getPtr(key).?;
            std.debug.assert(body.definitions > 0);
            body.definitions -= 1;
        }
    }
    fn sweepParameterBodies(self: *Cache, scope: OwnerScope) void {
        while (true) {
            var found: ?Key = null;
            var iterator = self.parameter_bodies.iterator();
            while (iterator.next()) |entry| if (std.meta.eql(entry.key_ptr.scope, scope) and entry.value_ptr.definitions == 0) {
                found = entry.key_ptr.*;
                break;
            };
            const key = found orelse break;
            self.engine.freeValue(self.parameter_bodies.fetchRemove(key).?.value.value);
        }
    }
    fn source(self: *Cache, record: Record) !c.JSValue {
        const key: Key = .{ .scope = record.source_scope orelse record.scope, .id = record.source_info_id };
        if (self.sources.get(key)) |value| return value;
        try self.ensureScope(key.scope);
        try self.sources.ensureUnusedCapacity(self.engine.gpa, 1);
        const value = try self.engine.fromJsonValue(record.source_info);
        self.sources.putAssumeCapacity(key, value);
        return value;
    }
    fn parameter(self: *Cache, record: Record) !c.JSValue {
        if (record.parameter_identity != .remote_json) return parameters_mod.get(self.engine, switch (record.parameter_identity) {
            .resource_list => .resource_list,
            .resource_read => .resource_read,
            .codemode => .codemode,
            .tool_search => .tool_search,
            .remote_json => unreachable,
        }, record.parameters);
        if (record.parameter_id == 0) return error.InvalidNativeParameterIdentity;
        const key: Key = .{ .scope = record.scope, .id = record.parameter_id };
        if (self.parameters.get(key)) |entry| return c.JS_DupValue(self.engine.context, entry.value);
        try self.parameters.ensureUnusedCapacity(self.engine.gpa, 1);
        var body_key: ?Key = null;
        const value = if (record.parameter_body_id != 0) blk: {
            const body_identity: Key = .{ .scope = record.scope, .id = record.parameter_body_id };
            if (!self.parameter_bodies.contains(body_identity)) {
                try self.parameter_bodies.ensureUnusedCapacity(self.engine.gpa, 1);
                const body_value = try self.engine.fromJsonValue(record.raw_parameters orelse return error.MissingNativeParameterBody);
                self.parameter_bodies.putAssumeCapacity(body_identity, .{ .value = body_value });
            }
            const body = self.parameter_bodies.get(body_identity).?.value;
            const projected = try info.shallow(self.engine, body);
            errdefer self.engine.freeValue(projected);
            const type_value = try vm.get(self.engine, body, "type");
            defer self.engine.freeValue(type_value);
            try info.putData(self.engine, projected, "type", if (c.JS_IsUndefined(type_value) or c.JS_IsNull(type_value)) try self.engine.checked(c.JS_NewString(self.engine.context, "object")) else c.JS_DupValue(self.engine.context, type_value));
            const properties = try vm.get(self.engine, body, "properties");
            defer self.engine.freeValue(properties);
            if (c.JS_IsUndefined(properties)) try info.putData(self.engine, projected, "properties", try vm.object(self.engine));
            body_key = body_identity;
            break :blk projected;
        } else try self.engine.fromJsonValue(record.parameters);
        errdefer self.engine.freeValue(value);
        // A schema prototype getter can collect another catalog. Recheck the
        // key and capacity after returning from every possible VM callback.
        if (self.parameters.get(key)) |existing| {
            self.engine.freeValue(value);
            return c.JS_DupValue(self.engine.context, existing.value);
        }
        try self.parameters.ensureUnusedCapacity(self.engine.gpa, 1);
        self.parameters.putAssumeCapacity(key, .{ .value = value, .body = body_key });
        if (body_key) |identity| self.parameter_bodies.getPtr(identity).?.definitions += 1;
        return c.JS_DupValue(self.engine.context, value);
    }
    fn definition(self: *Cache, record: Record, sequence: u64) !*Definition {
        if (record.definition_id == 0 or record.metadata != .object) return error.InvalidNativeDefinitionIdentity;
        const key: Key = .{ .scope = record.scope, .id = record.definition_id };
        if (self.definitions.getPtr(key)) |entry| {
            entry.seen = @max(entry.seen, sequence);
            return entry;
        }
        try self.definitions.ensureUnusedCapacity(self.engine.gpa, 1);
        const value = try self.engine.fromJsonValue(record.metadata);
        errdefer self.engine.freeValue(value);
        try info.putData(self.engine, value, "parameters", try self.parameter(record));
        if (self.definitions.getPtr(key)) |existing| {
            existing.seen = @max(existing.seen, sequence);
            self.engine.freeValue(value);
            return existing;
        }
        try self.definitions.ensureUnusedCapacity(self.engine.gpa, 1);
        const source_value = try self.source(record);
        const parameter_key: ?Key = if (record.parameter_identity == .remote_json) .{ .scope = record.scope, .id = record.parameter_id } else null;
        var reference_keys: [3]?ReferenceKey = .{null} ** 3;
        inline for (.{ ReferenceKind.namespace, ReferenceKind.promptGuidelines, ReferenceKind.annotations }, .{ record.namespace_id, record.prompt_guidelines_id, record.annotations_id }, 0..) |kind, id, index| {
            if (id != 0) {
                const reference_key: ReferenceKey = .{ .scope = record.scope, .id = id, .kind = kind };
                const field = record.metadata.object.get(@tagName(kind)) orelse return error.InvalidNativeMetadataReference;
                const reference_value = if (self.references.get(reference_key)) |reference| reference.value else blk: {
                    try self.references.ensureUnusedCapacity(self.engine.gpa, 1);
                    const created = try self.engine.fromJsonValue(field);
                    self.references.putAssumeCapacity(reference_key, .{ .value = created });
                    break :blk created;
                };
                try info.putData(self.engine, value, @tagName(kind), c.JS_DupValue(self.engine.context, reference_value));
                reference_keys[index] = reference_key;
            }
        }
        if (parameter_key) |parameter_key_value| self.parameters.getPtr(parameter_key_value).?.definitions += 1;
        for (reference_keys) |maybe_key| if (maybe_key) |reference_key| {
            self.references.getPtr(reference_key).?.definitions += 1;
        };
        self.definitions.putAssumeCapacity(key, .{ .value = value, .source_info = c.JS_DupValue(self.engine.context, source_value), .parameter = parameter_key, .references = reference_keys, .seen = sequence });
        return self.definitions.getPtr(key).?;
    }
};
pub const CatalogSink = struct {
    cache: *Cache,
    rows: c.JSValue,
    sequence: u64,
    scopes: std.ArrayList(OwnerScope) = .empty,
    count: u32 = 0,
    pub fn init(cache: *Cache) !CatalogSink {
        if (cache.deinitializing or cache.sweeping) return error.StaleNativeCatalogScope;
        cache.sequence = std.math.add(u64, cache.sequence, 1) catch return error.NativeCatalogGenerationExhausted;
        const rows = try vm.array(cache.engine);
        cache.active_sinks += 1;
        return .{ .cache = cache, .rows = rows, .sequence = cache.sequence };
    }
    pub fn deinit(self: *CatalogSink) void {
        self.cache.engine.freeValue(self.rows);
        self.scopes.deinit(self.cache.engine.gpa);
        std.debug.assert(self.cache.active_sinks > 0);
        self.cache.active_sinks -= 1;
        if (self.cache.active_sinks == 0) self.cache.sweepCompleted();
    }
    /// Call even for an empty authoritative scope so removed definitions retire.
    pub fn beginScope(self: *CatalogSink, scope: OwnerScope) !void {
        for (self.scopes.items) |present| if (std.meta.eql(present, scope)) return;
        try self.cache.ensureScope(scope);
        try self.scopes.append(self.cache.engine.gpa, scope);
    }
    pub fn append(self: *CatalogSink, record: Record) !void {
        try self.beginScope(record.scope);
        const entry = try self.cache.definition(record, self.sequence);
        const definition = c.JS_DupValue(self.cache.engine.context, entry.value);
        defer self.cache.engine.freeValue(definition);
        const source_info = c.JS_DupValue(self.cache.engine.context, entry.source_info);
        defer self.cache.engine.freeValue(source_info);
        const row = try info.project(self.cache.engine, definition, source_info, null);
        if (c.JS_SetPropertyUint32(self.cache.engine.context, self.rows, self.count, row) < 0) return error.JavaScriptException;
        self.count += 1;
    }
    /// Exact private SDK definitions already live in this owner VM. Preserve
    /// them directly; never round-trip their parameters or metadata to JSON.
    pub fn appendVM(self: *CatalogSink, definition: c.JSValue, source_info: c.JSValue, exposure: ?info.Exposure) !void {
        const retained = c.JS_DupValue(self.cache.engine.context, definition);
        defer self.cache.engine.freeValue(retained);
        const retained_source = c.JS_DupValue(self.cache.engine.context, source_info);
        defer self.cache.engine.freeValue(retained_source);
        const row = try info.project(self.cache.engine, retained, retained_source, exposure);
        if (c.JS_SetPropertyUint32(self.cache.engine.context, self.rows, self.count, row) < 0) return error.JavaScriptException;
        self.count += 1;
    }
    pub fn finish(self: *CatalogSink) !c.JSValue {
        for (self.scopes.items) |scope| {
            // An outer getter may collect again. Pin old reference identities
            // until every nested/outer snapshot has finished its projection.
            const state = self.cache.scopes.getPtr(scope).?;
            state.completed = @max(state.completed, self.sequence);
        }
        return c.JS_DupValue(self.cache.engine.context, self.rows);
    }
};

fn parameterBodyExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    var cache = Cache.init(engine);
    defer cache.deinit();
    var owner: u8 = 0;
    const scope: OwnerScope = .{ .owner = &owner, .generation = 1 };
    const raw = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}},\"required\":[\"value\"]}", .{});
    defer raw.deinit();
    const metadata = try std.json.parseFromSlice(std.json.Value, gpa, "{\"name\":\"mcp__native__shared\",\"description\":\"shared\",\"namespace\":{\"name\":\"native\"},\"annotations\":{\"readOnlyHint\":true}}", .{});
    defer metadata.deinit();
    var record: Record = .{ .scope = scope, .definition_id = 1, .parameter_identity = .remote_json, .parameter_id = 10, .parameter_body_id = 80, .raw_parameters = raw.value, .parameters = raw.value, .metadata = metadata.value, .source_info = .null, .namespace_id = 90, .annotations_id = 100 };
    const initial = try collect(&cache, scope, &.{record});
    defer engine.freeValue(initial);
    const initial_parameters = try rowField(engine, initial, 0, "parameters");
    defer engine.freeValue(initial_parameters);
    const initial_properties = try vm.get(engine, initial_parameters, "properties");
    defer engine.freeValue(initial_properties);
    const initial_required = try vm.get(engine, initial_parameters, "required");
    defer engine.freeValue(initial_required);
    record.definition_id = 2;
    record.parameter_id = 11;
    record.namespace_id = 91;
    record.annotations_id = 101;
    const refreshed = try collect(&cache, scope, &.{record});
    defer engine.freeValue(refreshed);
    const refreshed_parameters = try rowField(engine, refreshed, 0, "parameters");
    defer engine.freeValue(refreshed_parameters);
    const refreshed_properties = try vm.get(engine, refreshed_parameters, "properties");
    defer engine.freeValue(refreshed_properties);
    const refreshed_required = try vm.get(engine, refreshed_parameters, "required");
    defer engine.freeValue(refreshed_required);
    const source = try std.json.parseFromSlice(std.json.Value, gpa, @embedFile("../mcp/fixtures/mcp-resource-notification-original-6fb.json"), .{});
    defer source.deinit();
    const relationships = source.value.object.get("relationships").?.object;
    try std.testing.expectEqual(relationships.get("freshParameters").?.bool, !c.JS_IsStrictEqual(engine.context, initial_parameters, refreshed_parameters));
    try std.testing.expectEqual(relationships.get("sharedProperties").?.bool, c.JS_IsStrictEqual(engine.context, initial_properties, refreshed_properties));
    try std.testing.expectEqual(relationships.get("sharedRequired").?.bool, c.JS_IsStrictEqual(engine.context, initial_required, refreshed_required));
    record.definition_id = 3;
    record.parameter_id = 12;
    record.parameter_body_id = 81;
    const parsed_again = try collect(&cache, scope, &.{record});
    defer engine.freeValue(parsed_again);
    const parsed_parameters = try rowField(engine, parsed_again, 0, "parameters");
    defer engine.freeValue(parsed_parameters);
    const parsed_properties = try vm.get(engine, parsed_parameters, "properties");
    defer engine.freeValue(parsed_properties);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, initial_properties, parsed_properties));
    const empty = try collect(&cache, scope, &.{});
    engine.freeValue(empty);
    try std.testing.expectEqual(@as(usize, 0), cache.parameters.count());
    try std.testing.expectEqual(@as(usize, 0), cache.parameter_bodies.count());
}
test "native durable VM MCP parameter bodies match Source resource refresh nested identity and fresh tool parse" {
    try parameterBodyExercise(std.testing.allocator);
}
test "native durable VM MCP parameter bodies release every failed materialization and shared body reference" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parameterBodyExercise, .{});
}
const BodyReentryProbe = struct { cache: *Cache, scope: OwnerScope, records: []const Record };
threadlocal var body_reentry_probe: ?BodyReentryProbe = null;
fn bodyReenter(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    const probe = body_reentry_probe orelse return c.pi_js_undefined();
    const result = collect(probe.cache, probe.scope, probe.records) catch |err| {
        if (err == error.OutOfMemory) return engine.throwNativeOutOfMemory();
        return engine.throwCaptured();
    };
    engine.freeValue(result);
    return c.pi_js_undefined();
}
test "native durable VM MCP parameter bodies survive prototype getter reentry growing the native catalog" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var cache = Cache.init(engine);
    defer cache.deinit();
    var owner: u8 = 0;
    const scope: OwnerScope = .{ .owner = &owner, .generation = 1 };
    const values = try std.json.parseFromSlice(std.json.Value, engine.gpa, "[{\"name\":\"outer\",\"description\":\"outer\"},{},{\"type\":\"object\"}]", .{});
    defer values.deinit();
    const outer: Record = .{ .scope = scope, .definition_id = 1, .parameter_identity = .remote_json, .parameter_id = 1, .parameter_body_id = 1, .raw_parameters = values.value.array.items[1], .parameters = values.value.array.items[1], .metadata = values.value.array.items[0], .source_info = .null };
    var nested: [6]Record = undefined;
    for (&nested, 0..) |*record, index| {
        record.* = outer;
        record.definition_id = 100 + index;
        record.parameter_id = 100 + index;
        record.parameter_body_id = 100 + index;
        record.raw_parameters = values.value.array.items[2];
    }
    body_reentry_probe = .{ .cache = &cache, .scope = scope, .records = &nested };
    defer body_reentry_probe = null;
    try engine.bindFunction("reenterParameterBody", bodyReenter, 0);
    const installed = try engine.eval("Object.defineProperty(Object.prototype,'type',{configurable:true,get(){reenterParameterBody();return 'object'}})", "parameter-body-reentry", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(installed);
    const rows = try collect(&cache, scope, &.{outer});
    defer engine.freeValue(rows);
    const removed = try engine.eval("delete Object.prototype.type", "parameter-body-reentry-cleanup", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(removed);
    try std.testing.expectEqual(@as(usize, 1), try vm.length(engine, rows));
    try std.testing.expectEqual(@as(usize, 6), cache.parameters.count());
}

fn collect(cache: *Cache, scope: OwnerScope, records: []const Record) !c.JSValue {
    var sink = try CatalogSink.init(cache);
    defer sink.deinit();
    try sink.beginScope(scope);
    for (records) |record| try sink.append(record);
    return sink.finish();
}
fn rowField(engine: *Engine, rows: c.JSValue, index: u32, field: [:0]const u8) !c.JSValue {
    const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, rows, index));
    defer engine.freeValue(row);
    return vm.get(engine, row, field);
}
fn catalogExercise(gpa: std.mem.Allocator) !void {
    const engine = try Engine.init(gpa, .{});
    defer engine.deinit();
    var cache = Cache.init(engine);
    defer cache.deinit();
    var owner: u8 = 0;
    const scope: OwnerScope = .{ .owner = &owner, .generation = 7 };
    const metadata = try std.json.parseFromSlice(std.json.Value, gpa, "{\"name\":\"first\",\"description\":\"fixture\",\"namespace\":{\"name\":\"server\"},\"promptGuidelines\":[\"one\"],\"annotations\":{\"nested\":{\"value\":1}}}", .{});
    defer metadata.deinit();
    const schema = try std.json.parseFromSlice(std.json.Value, gpa, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"number\"}}}", .{});
    defer schema.deinit();
    const source = try std.json.parseFromSlice(std.json.Value, gpa, "{\"path\":\"builtin:mcp\",\"source\":\"builtin\",\"scope\":\"temporary\",\"origin\":\"top-level\"}", .{});
    defer source.deinit();
    var first: Record = .{ .scope = scope, .definition_id = 1, .parameter_identity = .remote_json, .parameter_id = 11, .namespace_id = 101, .prompt_guidelines_id = 201, .annotations_id = 301, .metadata = metadata.value, .parameters = schema.value, .source_info = source.value };
    var second = first;
    second.definition_id = 2;
    second.parameter_id = 12;
    second.annotations_id = 302;
    const before = try collect(&cache, scope, &.{ first, second });
    defer engine.freeValue(before);
    const before_first = try rowField(engine, before, 0, "parameters");
    defer engine.freeValue(before_first);
    const before_second = try rowField(engine, before, 1, "parameters");
    defer engine.freeValue(before_second);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, before_first, before_second));
    const namespace_first = try rowField(engine, before, 0, "namespace");
    defer engine.freeValue(namespace_first);
    const namespace_second = try rowField(engine, before, 1, "namespace");
    defer engine.freeValue(namespace_second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, namespace_first, namespace_second));
    const guidelines_first = try rowField(engine, before, 0, "promptGuidelines");
    defer engine.freeValue(guidelines_first);
    const guidelines_second = try rowField(engine, before, 1, "promptGuidelines");
    defer engine.freeValue(guidelines_second);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, guidelines_first, guidelines_second));
    first.definition_id = 3; // A hidden replacement retains the parsed references.
    const hidden = try collect(&cache, scope, &.{ first, second });
    defer engine.freeValue(hidden);
    const hidden_first = try rowField(engine, hidden, 0, "parameters");
    defer engine.freeValue(hidden_first);
    try std.testing.expect(c.JS_IsStrictEqual(engine.context, before_first, hidden_first));
    first.definition_id = 4;
    first.parameter_id = 21; // Equal JSON from a new parse is a different object.
    first.namespace_id = 102;
    second.definition_id = 5;
    second.parameter_id = 22;
    second.namespace_id = 102;
    const refreshed = try collect(&cache, scope, &.{ first, second });
    defer engine.freeValue(refreshed);
    const refreshed_first = try rowField(engine, refreshed, 0, "parameters");
    defer engine.freeValue(refreshed_first);
    const refreshed_namespace = try rowField(engine, refreshed, 0, "namespace");
    defer engine.freeValue(refreshed_namespace);
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, before_first, refreshed_first));
    try std.testing.expect(!c.JS_IsStrictEqual(engine.context, namespace_first, refreshed_namespace));
    try std.testing.expectEqual(@as(usize, 2), cache.definitions.count());
    try std.testing.expectEqual(@as(usize, 2), cache.parameters.count());
    const empty = try collect(&cache, scope, &.{});
    engine.freeValue(empty);
    try std.testing.expectEqual(@as(usize, 0), cache.definitions.count());
    try std.testing.expectEqual(@as(usize, 0), cache.parameters.count());
    try std.testing.expectEqual(@as(usize, 0), cache.references.count());
    cache.retire(scope);
    try std.testing.expectEqual(@as(usize, 0), cache.sources.count());
    try std.testing.expectEqual(@as(usize, 0), cache.scopes.count());
}
test "native durable VM native catalog separates definition parameter namespace and metadata lifetimes and retires owned values" {
    try catalogExercise(std.testing.allocator);
}
test "native durable VM native catalog materialization alias sharing and retirement unwind every GPA allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, catalogExercise, .{});
}

test "native durable VM nested catalog snapshots pin older schemas until outer metadata getters finish" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var cache = Cache.init(engine);
    defer cache.deinit();
    var owner: u8 = 0;
    const scope: OwnerScope = .{ .owner = &owner, .generation = 1 };
    const metadata = try std.json.parseFromSlice(std.json.Value, engine.gpa, "{\"name\":\"fixture\",\"description\":\"fixture\"}", .{});
    defer metadata.deinit();
    const schema = try std.json.parseFromSlice(std.json.Value, engine.gpa, "{\"type\":\"object\"}", .{});
    defer schema.deinit();
    var a: Record = .{ .scope = scope, .definition_id = 1, .parameter_identity = .remote_json, .parameter_id = 11, .metadata = metadata.value, .parameters = schema.value, .source_info = metadata.value };
    var b = a;
    b.definition_id = 2;
    b.parameter_id = 12;
    const baseline = try collect(&cache, scope, &.{ a, b });
    defer engine.freeValue(baseline);
    const original_b = try rowField(engine, baseline, 1, "parameters");
    defer engine.freeValue(original_b);
    {
        var outer = try CatalogSink.init(&cache);
        defer outer.deinit();
        try outer.append(a);
        a.definition_id = 3;
        a.parameter_id = 21;
        var replacement_b = b;
        replacement_b.definition_id = 4;
        replacement_b.parameter_id = 22;
        const newer = try collect(&cache, scope, &.{ a, replacement_b });
        engine.freeValue(newer);
        try outer.append(b);
        const older = try outer.finish();
        defer engine.freeValue(older);
        const older_b = try rowField(engine, older, 1, "parameters");
        defer engine.freeValue(older_b);
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, original_b, older_b));
    }
    try std.testing.expectEqual(@as(usize, 2), cache.definitions.count());
    try std.testing.expectEqual(@as(usize, 2), cache.parameters.count());
    try std.testing.expect(cache.definitionValue(scope, 1) == null);
    try std.testing.expect(cache.definitionValue(scope, 2) == null);
}
