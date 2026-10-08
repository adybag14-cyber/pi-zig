//! Native builtin dispatch borrows the exact admitted agent configuration for
//! the complete script lifetime. Worker calls carry owned JSON, never C VM values.
const std = @import("std");
const loop = @import("../agent/loop.zig");
const tools = @import("../agent/tools.zig");
const adapter = @import("codemode_tool.zig");
const protocol = @import("protocol.zig");
const json = protocol.json;
const configured = @import("configured.zig");
const loadout = @import("codemode_loadout.zig");
pub const Runtime = struct {
    io: std.Io,
    cwd: []const u8,
    session: *@import("../agent/session.zig").Session,
    configured: ?*configured.Service = null,
    output_root: ?[]const u8 = null,
    host: ?*@import("../extensions/host.zig").Host = null,
    loadout_mode: loadout.Mode = .on,
    inline_budget: f64 = 3000,
    model_runtime: ?@import("codemode_models.zig").Runtime = null,
    pub fn exists(raw: ?*anyopaque, name: []const u8) bool {
        if (!std.mem.eql(u8, name, "codemode")) return false;
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        if (self.host) |host| if (host.hasTool(name)) return false;
        return true;
    }
    pub fn isActive(config: *const loop.AgentConfig) bool {
        return isNamedBuiltinActive(config.tool_filter, "codemode");
    }
    pub fn isNamedBuiltinActive(initial: tools.ToolFilter, tool_name: []const u8) bool {
        var filter = initial;
        if (filter.no_tools) return false;
        if (filter.allow == null) {
            filter.default_activation_ctx = null;
            filter.default_activation_fn = struct {
                fn inactive(_: ?*anyopaque, _: []const u8) bool {
                    return false;
                }
            }.inactive;
            for (filter.builtin_allow orelse &.{}) |name| if (std.mem.eql(u8, name, tool_name)) {
                filter.default_activation_fn = null;
                break;
            };
        }
        return filter.isEnabled(tool_name);
    }
    pub fn schemasForRuntime(raw: ?*anyopaque, gpa: std.mem.Allocator, config: *const loop.AgentConfig) ![]u8 {
        if (!exists(raw, "codemode") or !isActive(config)) return gpa.dupe(u8, "[]");
        return declareSchemas(raw, gpa);
    }
    pub fn prepareLoadout(raw: ?*anyopaque, gpa: std.mem.Allocator, config: *const loop.AgentConfig, schemas: []const u8) ![]u8 {
        if (!exists(raw, "codemode") or !isActive(config)) return gpa.dupe(u8, schemas);
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var registry = try self.registryFor(gpa, config, false);
        defer registry.deinit();
        var declared = try json.Owned.parse(gpa, schemas);
        defer declared.deinit();
        const a = registry.arena.allocator();
        var catalog: std.ArrayList(loadout.Tool) = .empty;
        for (registry.value.array.items) |schema| {
            const definition = try protocol.field(schema, "function");
            const name = try protocol.text(definition, "name");
            if (!self.callableName(name)) continue;
            var tool: loadout.Tool = .{ .name = name, .description = if (json.get(definition, "description")) |value| try json.asString(value) else "", .parameters = json.get(definition, "parameters") orelse .null, .output_schema = json.get(schema, "outputSchema") orelse json.get(definition, "outputSchema") };
            for (declared.value.array.items) |entry| if (std.mem.eql(u8, name, try protocol.text(try protocol.field(entry, "function"), "name"))) {
                tool.declared = true;
                break;
            };
            if (self.host) |host| for (host.extensions.items) |extension| for (extension.tools) |registered| {
                if (std.mem.eql(u8, registered.name, name)) tool.exposure = switch (registered.exposure) {
                    .direct => .direct,
                    .codemode => .codemode,
                    .deferred => .deferred,
                    else => continue,
                };
            };
            if (self.configured) |service| if (service.exposureOf(name)) |exposure| {
                tool.exposure = switch (exposure) {
                    .direct => .direct,
                    .codemode, .deferred => .deferred,
                    .hidden => continue,
                };
            };
            if (json.get(schema, "namespace") orelse json.get(definition, "namespace")) |namespace| if (namespace == .object) {
                tool.namespace = .{ .name = try protocol.text(namespace, "name"), .description = if (json.get(namespace, "description")) |v| if (v == .string) v.string else "" else "", .instructions = if (json.get(namespace, "instructions")) |v| if (v == .string) v.string else "" else "" };
            };
            var guidelines: std.ArrayList([]const u8) = .empty;
            if (json.get(schema, "promptGuidelines") orelse json.get(definition, "promptGuidelines")) |value| if (value == .array) for (value.array.items) |v| if (v == .string) try guidelines.append(a, v.string);
            tool.guidelines = guidelines.items;
            var duplicate = false;
            for (catalog.items) |existing| if (std.mem.eql(u8, existing.name, name)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try catalog.append(a, tool);
        }
        var changes = try loadout.prepare(gpa, catalog.items, self.loadout_mode, .{ .inline_budget = self.inline_budget, .models = self.model_runtime != null });
        defer changes.deinit();
        const descriptions = changes.value.object.get("descriptions").?;
        const hidden = changes.value.object.get("hiddenDeclarations").?;
        var result: json.Value = .{ .array = .init(declared.arena.allocator()) };
        for (declared.value.array.items) |entry| {
            var definition = try protocol.field(entry, "function");
            const name = try protocol.text(definition, "name");
            var omit = false;
            for (hidden.array.items) |value| if (std.mem.eql(u8, name, value.string)) {
                omit = true;
                break;
            };
            if (omit) continue;
            if (descriptions.object.get(name)) |description| try definition.object.put(declared.arena.allocator(), "description", try json.clone(declared.arena.allocator(), description));
            // Map replacement must update the parent because ObjectMap is a value.
            var updated = entry;
            try updated.object.put(declared.arena.allocator(), "function", definition);
            try result.array.append(updated);
        }
        return json.stringify(gpa, result);
    }
    pub fn declareSchemas(_: ?*anyopaque, gpa: std.mem.Allocator) ![]u8 {
        return gpa.dupe(u8, "[{\"type\":\"function\",\"function\":{\"name\":\"codemode\",\"description\":\"Run JavaScript that calls the available tools.\",\"parameters\":{\"type\":\"object\",\"properties\":{\"code\":{\"type\":\"string\",\"description\":\"Raw JavaScript source.\"}},\"required\":[\"code\"]}}}]");
    }
    pub fn execute(raw: ?*anyopaque, gpa: std.mem.Allocator, initial: *const loop.AgentConfig, id: []const u8, name: []const u8, arguments: []const u8, progress: loop.ExternalToolProgressFn, progress_context: ?*anyopaque, aborted: ?*bool) !?tools.ToolResult {
        if (!exists(raw, name)) return null;
        if (!isActive(initial)) return .{ .content = try gpa.dupe(u8, "Tool codemode is not active"), .is_error = true };
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        var input = try json.Owned.parse(gpa, arguments);
        defer input.deinit();
        const code = try protocol.text(input.value, "code");
        if (self.configured) |service| try service.awaitForScript(code, aborted);
        var registry = try self.registryFor(gpa, initial, false);
        defer registry.deinit();
        const a = registry.arena.allocator();
        var entries: std.ArrayList(adapter.Entry) = .empty;
        defer entries.deinit(gpa);
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(gpa);
        for (registry.value.array.items) |schema| {
            const definition = try protocol.field(schema, "function");
            const tool_name = try protocol.text(definition, "name");
            if (!self.callableName(tool_name)) continue;
            var duplicate = false;
            for (names.items) |existing| if (std.mem.eql(u8, existing, tool_name)) {
                duplicate = true;
                break;
            };
            if (duplicate) continue;
            try names.append(gpa, tool_name);
            var namespace: ?@import("codemode_discovery.zig").Namespace = null;
            const namespace_value = json.get(schema, "namespace") orelse json.get(definition, "namespace");
            if (namespace_value) |value| if (value == .object) {
                if (json.get(value, "name")) |name_value| if (name_value == .string) {
                    namespace = .{
                        .name = name_value.string,
                        .description = if (json.get(value, "description")) |entry| if (entry == .string) entry.string else "" else "",
                        .instructions = if (json.get(value, "instructions")) |entry| if (entry == .string) entry.string else "" else "",
                    };
                };
            };
            var guidelines: std.ArrayList([]const u8) = .empty;
            if (json.get(schema, "promptGuidelines") orelse json.get(definition, "promptGuidelines")) |value| if (value == .array) for (value.array.items) |item| if (item == .string) try guidelines.append(a, item.string);
            try entries.append(gpa, .{
                .name = tool_name,
                .description = if (json.get(definition, "description")) |value| try json.asString(value) else "",
                .structured_result = std.mem.startsWith(u8, tool_name, "mcp__"),
                .parameters = json.get(definition, "parameters") orelse .null,
                .output_schema = json.get(schema, "outputSchema") orelse json.get(definition, "outputSchema"),
                .namespace = namespace,
                .prompt_guidelines = guidelines.items,
            });
        }
        const schemas = try json.stringify(gpa, registry.value);
        defer gpa.free(schemas);
        var invocation: Invocation = .{ .runtime = self, .config = initial.*, .schemas = schemas };
        // The registry has already applied activation and exposure. Its names
        // form this invocation's literal nested allowlist, preserving hooks.
        invocation.config.tool_filter = .{ .allow = names.items, .allow_is_loadout = true };
        var store = try adapter.loadBranchStore(gpa, self.session);
        defer store.deinit();
        const Updates = struct {
            callback: loop.ExternalToolProgressFn,
            context: ?*anyopaque,
            fn emit(update_raw: ?*anyopaque, bytes: []const u8) void {
                const updates: *@This() = @ptrCast(@alignCast(update_raw.?));
                updates.callback(updates.context, .{ .content = "", .details_json = bytes });
            }
        };
        var updates: Updates = .{ .callback = progress, .context = progress_context };
        return try adapter.execute(gpa, self.io, code, .{ .model_runtime = self.model_runtime, .progress_context = &updates, .progress = Updates.emit, .enable_discovery = true, .context = &invocation, .invoke = Invocation.call, .entries = entries.items, .call_id = id, .store = store.value, .append_context = self.session, .append_store = adapter.appendBranchStore, .output_root = self.output_root }, aborted);
    }
    fn callableName(self: *@This(), name: []const u8) bool {
        if (self.host) |host| for (host.extensions.items) |extension| for (extension.tools) |tool| {
            if (std.mem.eql(u8, name, tool.name)) return tool.exposure != .model_only and tool.exposure != .hidden;
        };
        return true;
    }
    fn registryFor(self: *@This(), gpa: std.mem.Allocator, initial: *const loop.AgentConfig, wait_for_connections: bool) !json.Owned {
        var registry = try json.Owned.empty(gpa);
        errdefer registry.deinit();
        const a = registry.arena.allocator();
        registry.value = .{ .array = .init(a) };
        const builtin = if (initial.disable_builtin_tools) try gpa.dupe(u8, "[]") else try tools.toolSchemasJson(gpa, initial.tool_filter);
        defer gpa.free(builtin);
        try appendSchemas(a, &registry.value, builtin, initial.tool_filter, false);
        try appendSchemas(a, &registry.value, initial.extra_tools_json, initial.tool_filter, false);
        if (self.host) |host| for (host.extensions.items) |extension| for (extension.tools) |tool| {
            if (tool.exposure != .codemode and tool.exposure != .deferred) continue;
            var definition: json.Value = .{ .object = .empty };
            try definition.object.put(a, "name", .{ .string = tool.name });
            try definition.object.put(a, "description", .{ .string = tool.description });
            var parameters = try json.Owned.parse(a, tool.parameters_json);
            defer parameters.deinit();
            try definition.object.put(a, "parameters", try json.clone(a, parameters.value));
            var schema: json.Value = .{ .object = .empty };
            try schema.object.put(a, "type", .{ .string = "function" });
            try schema.object.put(a, "function", definition);
            try registry.value.array.append(schema);
        };
        if (self.host) |host| for (registry.value.array.items) |*schema| {
            const name_ = try protocol.text(try protocol.field(schema.*, "function"), "name");
            for (host.extensions.items) |extension| for (extension.tools) |tool| {
                if (!std.mem.eql(u8, tool.name, name_)) continue;
                if (tool.discovery_json) |bytes| {
                    var metadata = try json.Owned.parse(a, bytes);
                    defer metadata.deinit();
                    var fields = metadata.value.object.iterator();
                    while (fields.next()) |field| try schema.object.put(a, try a.dupe(u8, field.key_ptr.*), try json.clone(a, field.value_ptr.*));
                }
                break;
            };
        };
        if (self.configured) |service| {
            const snapshot = try service.codemodeSchemasJson(wait_for_connections);
            defer service.gpa.free(snapshot);
            var catalog = try json.Owned.parse(a, snapshot);
            defer catalog.deinit();
            for (catalog.value.array.items) |descriptor| {
                const exposure = try protocol.text(descriptor, "exposure");
                const original = try protocol.field(descriptor, "schema");
                const name = try protocol.text(try protocol.field(original, "function"), "name");
                if (std.mem.eql(u8, exposure, "hidden") or (std.mem.eql(u8, exposure, "direct") and !initial.tool_filter.isMcpEnabled(name))) continue;
                var schema = try json.clone(a, original);
                if (json.get(descriptor, "metadata")) |metadata| {
                    var fields = metadata.object.iterator();
                    while (fields.next()) |field| try schema.object.put(a, try a.dupe(u8, field.key_ptr.*), try json.clone(a, field.value_ptr.*));
                }
                try registry.value.array.append(schema);
            }
        }
        return registry;
    }
    fn appendSchemas(a: std.mem.Allocator, target: *json.Value, bytes: []const u8, filter: tools.ToolFilter, configured_all: bool) !void {
        var parsed = try json.Owned.parse(a, bytes);
        defer parsed.deinit();
        if (parsed.value != .array) return error.InvalidToolSchemaArray;
        for (parsed.value.array.items) |schema| {
            const name = try protocol.text(try protocol.field(schema, "function"), "name");
            if (std.mem.eql(u8, name, "codemode") or (!configured_all and !filter.isEnabled(name))) continue;
            try target.array.append(try json.clone(a, schema));
        }
    }
};
const Invocation = struct {
    runtime: *Runtime,
    config: loop.AgentConfig,
    schemas: []const u8,
    fn call(raw: ?*anyopaque, gpa: std.mem.Allocator, id: []const u8, name: []const u8, arguments: []const u8, aborted: ?*bool) !tools.ToolResult {
        const self: *@This() = @ptrCast(@alignCast(raw.?));
        return loop.executeNestedTool(gpa, self.runtime.io, self.runtime.cwd, &self.config, self.schemas, id, name, arguments, aborted);
    }
};
