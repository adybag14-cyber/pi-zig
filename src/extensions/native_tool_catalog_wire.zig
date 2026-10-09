//! Private parent-control admission of native catalog data. Public context
//! snapshots cannot select native owner, definition, or parameter lifetimes.
const std = @import("std");
const engine_mod = @import("engine.zig");
const group_mod = @import("native_group.zig");
const bindings_mod = @import("native_bindings.zig");
const catalog = @import("native_tool_catalog.zig");
const json = @import("../durable/backend/json.zig");
const identifier = @import("component_protocol.zig").identifier;
pub const SdkFeed = *const fn (*bindings_mod.Bindings, *catalog.CatalogSink) anyerror!void;
const Owner = struct { key: u64, generation: u64 = 0, highest_generation: u64 = 0, present: bool = false };
const State = struct {
    engine: *engine_mod.Engine,
    group: *group_mod.Group,
    snapshot: ?json.Owned = null,
    owners: std.AutoHashMapUnmanaged(u64, *Owner) = .empty,
    sdk_feed: ?SdkFeed = null,
    fn owner(self: *State, key: u64) !*Owner {
        if (self.owners.get(key)) |value| return value;
        if (self.owners.count() == 4096) return error.NativeToolCatalogOwnerLimit;
        const value = try self.engine.gpa.create(Owner);
        errdefer self.engine.gpa.destroy(value);
        value.* = .{ .key = key };
        try self.owners.put(self.engine.gpa, key, value);
        return value;
    }
    fn feed(raw: ?*anyopaque, caller: *bindings_mod.Bindings, sink: *catalog.CatalogSink) !void {
        const self: *State = @ptrCast(@alignCast(raw.?));
        if (caller.sdk_context != null) {
            const sdk = self.sdk_feed orelse return error.NativeSDKToolCatalogProducerUnbound;
            return sdk(caller, sink);
        }
        // Pin the current DTO before any VM getter can reenter the control pump.
        var pinned = try json.Owned.empty(self.engine.gpa);
        defer pinned.deinit();
        const snapshot = self.snapshot orelse return error.NativeToolCatalogNotAdmitted;
        pinned.value = try json.clone(pinned.arena.allocator(), snapshot.value);
        for ((try json.required(pinned.value, "owners")).array.items) |entry| {
            const key = try identifier(try json.required(entry, "key"));
            const native_owner = self.owners.get(key) orelse return error.StaleNativeToolCatalogOwner;
            const generation = try identifier(try json.required(entry, "generation"));
            const scope: catalog.OwnerScope = .{ .owner = native_owner, .generation = generation };
            try sink.beginScope(scope);
            for ((try json.required(entry, "records")).array.items) |record| {
                var admitted: catalog.Record = .{
                    .scope = scope,
                    .definition_id = try positive(record, "definitionId"),
                    .parameter_identity = try parameterKind(record),
                    .parameter_id = try optionalId(record, "parameterId"),
                    .parameter_body_id = try optionalId(record, "parameterBodyId"),
                    .raw_parameters = json.get(record, "rawParameters"),
                    .metadata = try json.required(record, "metadata"),
                    .parameters = try json.required(record, "parameters"),
                    .source_info = json.get(record, "sourceInfo") orelse .null,
                    .source_info_id = try optionalId(record, "sourceInfoId"),
                    .namespace_id = try optionalId(record, "namespaceId"),
                    .prompt_guidelines_id = try optionalId(record, "promptGuidelinesId"),
                    .annotations_id = try optionalId(record, "annotationsId"),
                };
                if (json.get(record, "sourceOwnerKey")) |source_key| {
                    const source_owner = self.owners.get(try identifier(source_key)) orelse return error.StaleNativeToolCatalogOwner;
                    var source_generation: ?u64 = null;
                    for ((try json.required(pinned.value, "owners")).array.items) |source_entry| if (try identifier(try json.required(source_entry, "key")) == source_owner.key) {
                        source_generation = try identifier(try json.required(source_entry, "generation"));
                        break;
                    };
                    admitted.source_scope = .{ .owner = source_owner, .generation = source_generation orelse return error.StaleNativeToolCatalogOwner };
                }
                try sink.append(admitted);
            }
        }
    }
};
fn positive(value: std.json.Value, key: []const u8) !u64 {
    const result = try identifier(try json.required(value, key));
    if (result == 0) return error.InvalidNativeToolCatalogIdentity;
    return result;
}
fn optionalId(value: std.json.Value, key: []const u8) !u64 {
    return if (json.get(value, key)) |id| identifier(id) else 0;
}
fn parameterKind(record: std.json.Value) !catalog.ParameterIdentity {
    const text = try json.asString(try json.required(record, "parameterIdentity"));
    return std.meta.stringToEnum(catalog.ParameterIdentity, text) orelse error.InvalidNativeToolCatalogIdentity;
}
fn state(engine: *engine_mod.Engine, group: *group_mod.Group) !*State {
    if (group.native_wire_catalog_state) |value| return @ptrCast(@alignCast(value));
    const created = try engine.gpa.create(State);
    created.* = .{ .engine = engine, .group = group };
    group.native_wire_catalog_state = created;
    return created;
}
pub fn bindSdkProducer(group: *group_mod.Group, feed: SdkFeed) !void {
    (try state(group.engine, group)).sdk_feed = feed;
}
pub fn apply(engine: *engine_mod.Engine, group: *group_mod.Group, object: std.json.ObjectMap) anyerror!void {
    if (try identifier(object.get("version") orelse return error.InvalidNativeToolCatalogFrame) != 1) return error.InvalidNativeToolCatalogFrame;
    if (try identifier(object.get("ownerGeneration") orelse return error.InvalidNativeToolCatalogFrame) != group.ui.widgets.owner_generation) return error.StaleNativeToolCatalogOwner;
    const value = object.get("catalog") orelse return error.InvalidNativeToolCatalogFrame;
    const owners = try json.required(value, "owners");
    if (owners != .array or owners.array.items.len > 4096) return error.InvalidNativeToolCatalogFrame;
    var candidate = try json.Owned.empty(engine.gpa);
    errdefer candidate.deinit();
    candidate.value = try json.clone(candidate.arena.allocator(), value);
    var unique: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer unique.deinit(engine.gpa);
    for (owners.array.items) |entry| {
        const key = try positive(entry, "key");
        const inserted = try unique.getOrPut(engine.gpa, key);
        if (inserted.found_existing) return error.InvalidNativeToolCatalogIdentity;
        _ = try positive(entry, "generation");
        const records = try json.required(entry, "records");
        if (records != .array) return error.InvalidNativeToolCatalogFrame;
        var definitions: std.AutoHashMapUnmanaged(u64, void) = .empty;
        defer definitions.deinit(engine.gpa);
        for (records.array.items) |record| {
            const definition = try definitions.getOrPut(engine.gpa, try positive(record, "definitionId"));
            if (definition.found_existing) return error.InvalidNativeToolCatalogIdentity;
            const kind = try parameterKind(record);
            if (kind == .remote_json) _ = try positive(record, "parameterId");
            if (try json.required(record, "metadata") != .object) return error.InvalidNativeToolCatalogFrame;
            const parameters = try json.required(record, "parameters");
            if (kind == .remote_json and parameters != .object) return error.InvalidNativeToolCatalogFrame;
            if (kind != .remote_json and parameters != .object and parameters != .null) return error.InvalidNativeToolCatalogFrame;
            if (try optionalId(record, "parameterBodyId") != 0) {
                if (kind != .remote_json or (json.get(record, "rawParameters") orelse return error.InvalidNativeToolCatalogFrame) != .object) return error.InvalidNativeToolCatalogFrame;
            }
            inline for (.{ "namespaceId", "promptGuidelinesId", "annotationsId", "sourceInfoId", "sourceOwnerKey" }) |name| _ = try optionalId(record, name);
        }
    }
    const self = try state(engine, group);
    for (owners.array.items) |entry| {
        if (self.owners.get(try positive(entry, "key"))) |old| {
            const generation = try positive(entry, "generation");
            if (generation < old.highest_generation or (!old.present and generation == old.highest_generation)) return error.StaleNativeToolCatalogOwner;
        }
        for ((try json.required(entry, "records")).array.items) |record| if (json.get(record, "sourceOwnerKey")) |source_key| {
            if (!unique.contains(try identifier(source_key))) return error.InvalidNativeToolCatalogIdentity;
        };
    }
    for (owners.array.items) |entry| _ = try self.owner(try positive(entry, "key"));
    try group.setNativeToolCatalog(self, State.feed);
    var iterator = self.owners.valueIterator();
    while (iterator.next()) |owner_ptr| {
        const old = owner_ptr.*;
        old.present = false;
        var next_generation: u64 = 0;
        for (owners.array.items) |entry| if (try positive(entry, "key") == old.key) {
            next_generation = try positive(entry, "generation");
            break;
        };
        if (old.generation != 0 and old.generation != next_generation) group.retireNativeToolCatalog(.{ .owner = old, .generation = old.generation });
        old.generation = next_generation;
        old.highest_generation = @max(old.highest_generation, next_generation);
        old.present = next_generation != 0;
    }
    if (self.snapshot) |*old| old.deinit();
    self.snapshot = candidate;
}
pub fn deinit(group: *group_mod.Group) void {
    const raw = group.native_wire_catalog_state orelse return;
    const self: *State = @ptrCast(@alignCast(raw));
    if (self.snapshot) |*snapshot| snapshot.deinit();
    var owners = self.owners.valueIterator();
    while (owners.next()) |owner_ptr| self.engine.gpa.destroy(owner_ptr.*);
    self.owners.deinit(self.engine.gpa);
    self.engine.gpa.destroy(self);
    group.native_wire_catalog_state = null;
}

fn fixtureFrame(engine: *engine_mod.Engine, group: *group_mod.Group, owners: []const u8) !std.json.Parsed(std.json.Value) {
    const text = try std.fmt.allocPrint(engine.gpa, "{{\"version\":1,\"ownerGeneration\":{d},\"catalog\":{{\"owners\":{s}}}}}", .{ group.ui.widgets.owner_generation, owners });
    defer engine.gpa.free(text);
    return std.json.parseFromSlice(std.json.Value, engine.gpa, text, .{});
}
fn fixtureCollect(engine: *engine_mod.Engine, group: *group_mod.Group, binding: *bindings_mod.Bindings) !engine_mod.c.JSValue {
    _ = engine;
    var sink = try catalog.CatalogSink.init(&group.native_tool_catalog_cache);
    defer sink.deinit();
    try State.feed(group.native_wire_catalog_state, binding, &sink);
    return sink.finish();
}
fn fixtureSchema(engine: *engine_mod.Engine, rows: engine_mod.c.JSValue) !engine_mod.c.JSValue {
    const row = try engine.checked(engine_mod.c.JS_GetPropertyUint32(engine.context, rows, 0));
    defer engine.freeValue(row);
    return @import("native_values.zig").get(engine, row, "parameters");
}
const fixtureOwners =
    \\[{"key":"91","generation":"1","records":[{"definitionId":"10","parameterId":"20","parameterIdentity":"remote_json","metadata":{"name":"remote","description":"remote fixture"},"parameters":{"type":"object","properties":{"value":{"type":"string"}}},"sourceInfo":{"path":"builtin:mcp"},"sourceInfoId":"1"}]}]
;
test "private native catalog control owns identities and rejects public context forgery and retired generation reuse" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("private-catalog-fixture.mjs");
    try binding.installSchemas();
    try binding.setContext("{\"nativeRuntimeBound\":true,\"catalog\":{\"owners\":[{\"key\":91,\"generation\":999}]}}");
    try std.testing.expect(group.native_wire_catalog_state == null);
    var frame = try fixtureFrame(engine, group, fixtureOwners);
    defer frame.deinit();
    try apply(engine, group, frame.value.object);
    const first = try fixtureCollect(engine, group, binding);
    defer engine.freeValue(first);
    const first_schema = try fixtureSchema(engine, first);
    defer engine.freeValue(first_schema);
    try apply(engine, group, frame.value.object);
    const second = try fixtureCollect(engine, group, binding);
    defer engine.freeValue(second);
    const second_schema = try fixtureSchema(engine, second);
    defer engine.freeValue(second_schema);
    try std.testing.expect(engine_mod.c.JS_IsStrictEqual(engine.context, first_schema, second_schema));
    var empty = try fixtureFrame(engine, group, "[]");
    defer empty.deinit();
    try apply(engine, group, empty.value.object);
    try std.testing.expectError(error.StaleNativeToolCatalogOwner, apply(engine, group, frame.value.object));
    try std.testing.expectEqual(@as(usize, 0), group.native_tool_catalog_cache.definitions.count());
    frame.value.object.getPtr("catalog").?.object.getPtr("owners").?.array.items[0].object.getPtr("generation").?.* = .{ .string = "2" };
    try apply(engine, group, frame.value.object);
    const next = try fixtureCollect(engine, group, binding);
    defer engine.freeValue(next);
    const next_schema = try fixtureSchema(engine, next);
    defer engine.freeValue(next_schema);
    try std.testing.expect(!engine_mod.c.JS_IsStrictEqual(engine.context, first_schema, next_schema));
}
test "private native catalog invalid transaction retains prior native snapshot" {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("private-catalog-invalid.mjs");
    try binding.installSchemas();
    var frame = try fixtureFrame(engine, group, fixtureOwners);
    defer frame.deinit();
    try apply(engine, group, frame.value.object);
    const first = try fixtureCollect(engine, group, binding);
    defer engine.freeValue(first);
    const first_schema = try fixtureSchema(engine, first);
    defer engine.freeValue(first_schema);
    frame.value.object.getPtr("catalog").?.object.getPtr("owners").?.array.items[0].object.getPtr("records").?.array.items[0].object.getPtr("parameterIdentity").?.* = .{ .string = "forged" };
    try std.testing.expectError(error.InvalidNativeToolCatalogIdentity, apply(engine, group, frame.value.object));
    const second = try fixtureCollect(engine, group, binding);
    defer engine.freeValue(second);
    const second_schema = try fixtureSchema(engine, second);
    defer engine.freeValue(second_schema);
    try std.testing.expect(engine_mod.c.JS_IsStrictEqual(engine.context, first_schema, second_schema));
}

fn fixtureAllocationTransaction(gpa: std.mem.Allocator) !void {
    const engine = try engine_mod.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const group = try group_mod.Group.init(engine);
    defer group.deinit();
    const binding = try group.add("private-catalog-allocation.mjs");
    try binding.installSchemas();
    var frame = try fixtureFrame(engine, group, fixtureOwners);
    defer frame.deinit();
    try apply(engine, group, frame.value.object);
    const previous = (try state(engine, group)).snapshot.?.value;
    const old_bytes = try std.json.Stringify.valueAlloc(std.testing.allocator, previous, .{});
    defer std.testing.allocator.free(old_bytes);
    frame.value.object.getPtr("catalog").?.object.getPtr("owners").?.array.items[0].object.getPtr("key").?.* = .{ .string = "92" };
    const original = engine.gpa;
    engine.gpa = gpa;
    apply(engine, group, frame.value.object) catch |err| {
        engine.gpa = original;
        if (err != error.OutOfMemory) return err;
        const current = try std.json.Stringify.valueAlloc(std.testing.allocator, (try state(engine, group)).snapshot.?.value, .{});
        defer std.testing.allocator.free(current);
        try std.testing.expectEqualStrings(old_bytes, current);
        return err;
    };
    engine.gpa = original;
}
test "private native catalog every allocation failure preserves committed snapshot and owned cleanup" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, fixtureAllocationTransaction, .{});
}
