//! Parent-owned catalog DTOs for the private worker control channel.
//! Build a fresh snapshot, discard it on failure, and release native catalog
//! locks before sending it to a worker or executing any guest callback.
const std = @import("std");
const json = @import("../durable/backend/json.zig");
const configured = @import("../mcp/configured.zig");
const identifier = @import("component_protocol.zig").identifier;
pub const Scope = struct { key: u64, generation: u64 };

pub fn init(gpa: std.mem.Allocator) !json.Owned {
    var owned = try json.Owned.empty(gpa);
    errdefer owned.deinit();
    const a = owned.arena.allocator();
    owned.value = .{ .object = .empty };
    try owned.value.object.put(a, "owners", .{ .array = .init(a) });
    return owned;
}
fn putId(a: std.mem.Allocator, object: *std.json.ObjectMap, name: []const u8, value: u64) !void {
    if (value == 0) return error.InvalidNativeCatalogIdentity;
    try object.put(a, name, .{ .string = try std.fmt.allocPrint(a, "{d}", .{value}) });
}
pub fn owner(owned: *json.Owned, scope: Scope) !*std.json.Value {
    if (scope.key == 0 or scope.generation == 0) return error.InvalidNativeCatalogIdentity;
    const a = owned.arena.allocator();
    const owners = owned.value.object.getPtr("owners") orelse return error.InvalidNativeCatalogSnapshot;
    if (owners.* != .array) return error.InvalidNativeCatalogSnapshot;
    for (owners.array.items) |*entry| {
        if (try identifier(try json.required(entry.*, "key")) != scope.key) continue;
        if (try identifier(try json.required(entry.*, "generation")) != scope.generation) return error.InvalidNativeCatalogIdentity;
        return entry;
    }
    var entry: std.json.Value = .{ .object = .empty };
    try putId(a, &entry.object, "key", scope.key);
    try putId(a, &entry.object, "generation", scope.generation);
    try entry.object.put(a, "records", .{ .array = .init(a) });
    try owners.array.append(entry);
    return &owners.array.items[owners.array.items.len - 1];
}
fn copyField(a: std.mem.Allocator, target: *std.json.ObjectMap, value: std.json.Value, name: []const u8) !void {
    if (json.get(value, name)) |field| try target.put(a, name, try json.clone(a, field));
}
pub fn appendMcp(owned: *json.Owned, service: *configured.Service, scope: Scope, source_scope: Scope) !void {
    try service.promoteReady();
    _ = try owner(owned, source_scope);
    const destination = try owner(owned, scope);
    const a = owned.arena.allocator();
    service.catalog_mutex.lockUncancelable(service.io);
    defer service.catalog_mutex.unlock(service.io);
    if (service.closing.load(.acquire)) return error.McpConnectionClosed;
    for (service.descriptors.items) |descriptor| {
        const function = try json.required(descriptor.schema, "function");
        var metadata: std.json.Value = .{ .object = .empty };
        try copyField(a, &metadata.object, function, "name");
        try copyField(a, &metadata.object, function, "description");
        try metadata.object.put(a, "exposure", .{ .string = if (descriptor.exposure == .codemode) "deferred" else @tagName(descriptor.exposure) });
        if (descriptor.codemode_metadata) |extra| {
            inline for (.{ "namespace", "annotations", "promptGuidelines", "outputSchema" }) |field| try copyField(a, &metadata.object, extra, field);
        }
        var source_info: std.json.Value = .{ .object = .empty };
        inline for (.{ .{ "path", "builtin:mcp" }, .{ "source", "builtin" }, .{ "scope", "temporary" }, .{ "origin", "top-level" } }) |field| try source_info.object.put(a, field[0], .{ .string = field[1] });
        var record: std.json.Value = .{ .object = .empty };
        try putId(a, &record.object, "definitionId", descriptor.definition_id);
        try record.object.put(a, "parameterIdentity", .{ .string = @tagName(descriptor.parameter_identity) });
        if (descriptor.parameter_identity == .remote_json) {
            try putId(a, &record.object, "parameterId", descriptor.parameter_id);
            try putId(a, &record.object, "parameterBodyId", descriptor.parameter_body_id);
            try record.object.put(a, "rawParameters", try json.clone(a, descriptor.raw_parameters orelse return error.MissingNativeParameterBody));
            if (descriptor.namespace_id != 0) try putId(a, &record.object, "namespaceId", descriptor.namespace_id);
            if (json.get(metadata, "annotations") != null) try putId(a, &record.object, "annotationsId", descriptor.parameter_id);
        }
        try record.object.put(a, "metadata", metadata);
        try record.object.put(a, "parameters", try json.clone(a, try json.required(function, "parameters")));
        try record.object.put(a, "sourceInfo", source_info);
        try putId(a, &record.object, "sourceInfoId", 1);
        try putId(a, &record.object, "sourceOwnerKey", source_scope.key);
        try destination.object.getPtr("records").?.array.append(record);
    }
}
pub fn appendBuiltins(owned: *json.Owned, scope: Scope) !void {
    const destination = try owner(owned, scope);
    const a = owned.arena.allocator();
    const names = [_][]const u8{ "read", "bash", "powershell", "edit", "write", "grep", "find", "ls" };
    for (names, 0..) |name, index| {
        var record: std.json.Value = .{ .object = .empty };
        try putId(a, &record.object, "definitionId", index + 1);
        try record.object.put(a, "parameterIdentity", .{ .string = try std.fmt.allocPrint(a, "builtin_{s}", .{name}) });
        var metadata: std.json.Value = .{ .object = .empty };
        try metadata.object.put(a, "name", .{ .string = name });
        try metadata.object.put(a, "exposure", .{ .string = "direct" });
        try record.object.put(a, "metadata", metadata);
        // The worker selects its genuine builtin module constants/template;
        // the parent cannot replace their identity with a JSON schema copy.
        try record.object.put(a, "parameters", .null);
        var source_info: std.json.Value = .{ .object = .empty };
        try source_info.object.put(a, "path", .{ .string = try std.fmt.allocPrint(a, "builtin:{s}", .{name}) });
        inline for (.{ .{ "source", "builtin" }, .{ "scope", "temporary" }, .{ "origin", "top-level" } }) |field| try source_info.object.put(a, field[0], .{ .string = field[1] });
        try record.object.put(a, "sourceInfo", source_info);
        try putId(a, &record.object, "sourceInfoId", index + 1);
        try destination.object.getPtr("records").?.array.append(record);
    }
}
