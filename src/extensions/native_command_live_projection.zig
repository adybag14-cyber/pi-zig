//! Private live Group command metadata. Public getCommands DTOs stay separate.
//! SDK aliases come from the real Source resolver, with native observation of
//! the exact loaded extension row and stock map callback index.
const std = @import("std");
const js = @import("native_js_values.zig");
const group_mod = @import("native_group.zig");
const bindings = @import("native_bindings.zig");
const sdk_owners = @import("native_sdk_resource_owners.zig");
const owners = @import("native_command_metadata_owner.zig");
const sdk = @import("native_sdk.zig");
const c = js.c;
const Registration = struct { key: []const u8, definition: c.JSValue, anchor: c.JSValue };
pub const Observer = struct {
    group: *group_mod.Group,
    caller: *sdk_owners.Caller,
    runner: c.JSValue,
    snapshot: c.JSValue,
    captured: bindings.Bindings.SdkContext,
    registrations: std.ArrayList(c.JSValue) = .empty,
    outputs: std.ArrayList(c.JSValue) = .empty,
    resolving: bool = false,
    failed: bool = false,
};
/// This observer is installed only around the private projection's genuine
/// runner call. Direct/public resolve calls and nested getter calls cannot
/// acquire its association vector.
pub fn beginResolve(engine: *js.Engine, receiver: c.JSValue) ?*Observer {
    const raw = engine.native_command_projection_observer orelse return null;
    const self: *Observer = @ptrCast(@alignCast(raw));
    if (self.resolving or !c.JS_IsStrictEqual(engine.context, receiver, self.runner)) return null;
    self.resolving = true;
    return self;
}
pub fn endResolve(self: *Observer) void {
    self.resolving = false;
}
pub fn collected(self: *Observer, extension: c.JSValue, definition: c.JSValue) !void {
    var selected: ?*bindings.Bindings = null;
    for (self.group.entries.items) |entry| {
        if (entry.sdk_scope == null or !try self.caller.owns(entry.id)) continue;
        if (entry.binding.sdk_command_row) |row| if (c.JS_IsStrictEqual(self.group.engine.context, row, extension)) {
            selected = entry.binding;
            break;
        };
    }
    const anchor = if (selected) |binding| try owners.create(self.group.engine, c.pi_js_undefined(), .{ .binding = binding, .definition = definition, .snapshot = self.snapshot, .captured = self.captured, .publish = self.group.actions_fn, .publish_context = self.group.actions_context }) else c.pi_js_undefined();
    self.registrations.append(self.group.engine.gpa, anchor) catch |err| {
        self.group.engine.freeValue(anchor);
        return err;
    };
}
/// The association uses the real Array.map index, never a public command name,
/// source path, callback equality, guessed extension or authored JS owner ID.
pub fn projected(self: *Observer, index: c.JSValue, original: c.JSValue, result: c.JSValue) !c.JSValue {
    const engine = self.group.engine;
    if (!c.JS_IsNumber(index)) return error.UnownedNativeCommandProjection;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, index) < 0) return js.capture(engine);
    if (!std.math.isFinite(number) or number < 0 or @floor(number) != number or number >= @as(f64, @floatFromInt(self.registrations.items.len))) return error.UnownedNativeCommandProjection;
    const anchor = self.registrations.items[@intFromFloat(number)];
    if (!owners.matchesDefinition(engine, anchor, original)) return error.UnownedNativeCommandProjection;
    const owned = try owners.copyMetadata(engine, anchor, result);
    errdefer engine.freeValue(owned);
    const retained = c.JS_DupValue(engine.context, owned);
    self.outputs.append(engine.gpa, retained) catch |err| {
        engine.freeValue(retained);
        return err;
    };
    return owned;
}
const Bridge = struct { gpa: std.mem.Allocator, observer: ?*Observer };
pub const ResolveScope = struct {
    engine: *js.Engine,
    value: c.JSValue,
    bridge: ?*Bridge = null,
    pub fn deinit(self: ResolveScope) void {
        if (self.bridge) |bridge| {
            if (bridge.observer) |observer| endResolve(observer);
            // A guest map may retain the genuine C callback. Its rooted
            // bridge survives, but can never dereference this stack observer.
            bridge.observer = null;
        }
        self.engine.freeValue(self.value);
    }
};
fn finalizeBridge(runtime: ?*c.JSRuntime, value: c.JSValue) callconv(.c) void {
    _ = runtime;
    const bridge: *Bridge = @ptrCast(@alignCast(c.JS_GetOpaque(value, c.JS_GetClassID(value)) orelse return));
    bridge.gpa.destroy(bridge);
}
pub fn observe(engine: *js.Engine, receiver: c.JSValue) !ResolveScope {
    const observer = beginResolve(engine, receiver) orelse return .{ .engine = engine, .value = c.pi_js_undefined() };
    errdefer endResolve(observer);
    if (engine.native_command_projection_class == 0) {
        var class: c.JSClassID = 0;
        _ = c.JS_NewClassID(engine.runtime, &class);
        const definition: c.JSClassDef = .{ .class_name = "Native private command projection", .finalizer = finalizeBridge };
        if (c.JS_NewClass(engine.runtime, class, &definition) < 0) return error.OutOfMemory;
        engine.native_command_projection_class = class;
    }
    const bridge = try engine.gpa.create(Bridge);
    errdefer engine.gpa.destroy(bridge);
    const value = try engine.checked(c.JS_NewObjectClass(engine.context, engine.native_command_projection_class));
    bridge.* = .{ .gpa = engine.gpa, .observer = observer };
    _ = c.JS_SetOpaque(value, bridge);
    return .{ .engine = engine, .value = value, .bridge = bridge };
}
fn observerValue(engine: *js.Engine, value: c.JSValue) ?*Observer {
    if (engine.native_command_projection_class == 0) return null;
    const bridge: *Bridge = @ptrCast(@alignCast(c.JS_GetOpaque(value, engine.native_command_projection_class) orelse return null));
    return bridge.observer;
}
pub fn collectedValue(engine: *js.Engine, token: c.JSValue, extension: c.JSValue, command: c.JSValue) !void {
    if (observerValue(engine, token)) |observer| try collected(observer, extension, command);
}
pub fn projectedValue(engine: *js.Engine, token: c.JSValue, index: c.JSValue, command: c.JSValue, result: c.JSValue) !c.JSValue {
    const observer = observerValue(engine, token) orelse return c.JS_DupValue(engine.context, result);
    return projected(observer, index, command, result);
}
/// Main uses current native registrations in registration order, applying the
/// same collision suffix algorithm as the existing authoritative Group DTO.
/// SDK uses its genuine runner and private scope, never Main/sibling entries.
pub fn project(group: *group_mod.Group, caller: *bindings.Bindings, snapshot: c.JSValue) !c.JSValue {
    if (group.deinitializing or try group.selected(caller.owner_id) != caller) return error.StaleNativeExtensionOwner;
    if (caller.sdk_resource_owner and caller.sdk_context == null) return sdk_owners.uninitialized(group.engine);
    if (caller.sdk_context != null) return projectSdk(group, caller, snapshot);
    const engine = group.engine;
    var arena: std.heap.ArenaAllocator = .init(engine.gpa);
    defer arena.deinit();
    const allocator = arena.allocator();
    var registrations: std.ArrayList(Registration) = .empty;
    defer for (registrations.items) |row| {
        engine.freeValue(row.definition);
        engine.freeValue(row.anchor);
    };
    for (group.entries.items) |entry| {
        if (entry.sdk_scope != null) continue;
        for (entry.binding.command_order.items) |key| if (entry.binding.commands.get(key)) |definition| {
            const retained = c.JS_DupValue(engine.context, definition);
            errdefer engine.freeValue(retained);
            const owned_key = try allocator.dupe(u8, key);
            const anchor = try owners.create(engine, c.pi_js_undefined(), .{ .binding = entry.binding, .definition = definition, .snapshot = snapshot, .registration_key = key, .publish = group.actions_fn, .publish_context = group.actions_context });
            registrations.append(allocator, .{ .key = owned_key, .definition = retained, .anchor = anchor }) catch |err| {
                engine.freeValue(anchor);
                return err;
            };
        };
    }
    var counts: std.StringHashMapUnmanaged(usize) = .empty;
    var seen: std.StringHashMapUnmanaged(usize) = .empty;
    var taken: std.StringHashMapUnmanaged(void) = .empty;
    for (registrations.items) |row| {
        const count = try counts.getOrPut(allocator, row.key);
        if (!count.found_existing) count.value_ptr.* = 0;
        count.value_ptr.* += 1;
    }
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    for (registrations.items) |row| {
        const occurrence = try seen.getOrPut(allocator, row.key);
        if (!occurrence.found_existing) occurrence.value_ptr.* = 0;
        occurrence.value_ptr.* += 1;
        var suffix = occurrence.value_ptr.*;
        var invocation = if (counts.get(row.key).? > 1) try std.fmt.allocPrint(allocator, "{s}:{d}", .{ row.key, suffix }) else row.key;
        while (taken.contains(invocation)) {
            suffix += 1;
            invocation = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ row.key, suffix });
        }
        try taken.put(allocator, invocation, {});
        const metadata = try js.spread(engine, row.definition);
        defer engine.freeValue(metadata);
        try js.define(engine, metadata, "name", try sdk.text(engine, invocation));
        const owned = try owners.copyMetadata(engine, row.anchor, metadata);
        defer engine.freeValue(owned);
        try js.push(engine, result, owned);
    }
    return result;
}
fn projectSdk(group: *group_mod.Group, caller: *bindings.Bindings, snapshot: c.JSValue) !c.JSValue {
    const engine = group.engine;
    var retained = try sdk_owners.retainCaller(caller);
    defer retained.deinit();
    const captured = caller.sdk_context.?;
    const runner = try js.get(engine, retained.owner.data, "_sdkCommandRunner");
    defer engine.freeValue(runner);
    var observer: Observer = .{ .group = group, .caller = &retained, .runner = runner, .snapshot = snapshot, .captured = captured };
    defer {
        for (observer.registrations.items) |anchor| engine.freeValue(anchor);
        observer.registrations.deinit(engine.gpa);
        for (observer.outputs.items) |row| engine.freeValue(row);
        observer.outputs.deinit(engine.gpa);
    }
    const previous = engine.native_command_projection_observer;
    engine.native_command_projection_observer = &observer;
    defer engine.native_command_projection_observer = previous;
    const resolved = try @import("native_sdk_commands.zig").resolve(retained.owner);
    defer engine.freeValue(resolved);
    const result = try js.array(engine);
    errdefer engine.freeValue(result);
    const count = try @import("native_values.zig").length(engine, resolved);
    for (0..count) |index| {
        const row = try engine.checked(c.JS_GetPropertyUint32(engine.context, resolved, @intCast(index)));
        defer engine.freeValue(row);
        // A custom resolver must not mint owner authority by copying names or
        // functions. Only rows tagged during the exact observed resolution
        // can become a private command metadata provider row.
        var observed = false;
        for (observer.outputs.items) |output| if (c.JS_IsStrictEqual(engine.context, output, row)) {
            observed = true;
            break;
        };
        if (!observed or !owners.isOwned(engine, row)) return error.UnownedNativeCommandProjection;
        const metadata = try js.spread(engine, row);
        defer engine.freeValue(metadata);
        const invocation = try js.get(engine, row, "invocationName");
        try js.define(engine, metadata, "name", invocation);
        const owned_row = try owners.copyMetadata(engine, row, metadata);
        defer engine.freeValue(owned_row);
        try js.push(engine, result, owned_row);
    }
    return result;
}
