//! Image/classifier extension definitions retain their full Source metadata.
//! Chat definitions continue through the existing chat transport resolver.
const std = @import("std");
const providers = @import("../ai/providers.zig");
pub const Catalog = struct {
    arena: std.heap.ArenaAllocator,
    models: []const providers.ModelInfo = &.{},
    base_url: ?[]const u8 = null,
    pub fn deinit(self: *Catalog) void {
        self.arena.deinit();
    }
    pub fn init(gpa: std.mem.Allocator, provider: []const u8, config: std.json.Value, baseline: []const providers.ModelInfo) !Catalog {
        return initWithMode(gpa, provider, config, baseline, false);
    }
    pub fn initWithMode(gpa: std.mem.Allocator, provider: []const u8, config: std.json.Value, baseline: []const providers.ModelInfo, native_mode: bool) !Catalog {
        var self: Catalog = .{ .arena = .init(gpa) };
        errdefer self.deinit();
        const a = self.arena.allocator();
        self.base_url = if (text(config, "baseUrl")) |base| try a.dupe(u8, base) else null;
        const definitions = config.object.get("models") orelse return self;
        if (definitions != .array) return error.InvalidExtensionProviderConfig;
        var models: std.ArrayList(providers.ModelInfo) = .empty;
        for (definitions.array.items) |definition| {
            if (definition != .object) return error.InvalidExtensionProviderConfig;
            const typ = text(definition, "type") orelse "chat";
            const kind = std.meta.stringToEnum(providers.ModelType, typ) orelse return error.InvalidExtensionModelType;
            if (kind == .chat) continue;
            const id = text(definition, "id") orelse return error.MissingExtensionModelId;
            var defaults: ?providers.ModelInfo = null;
            var default_score: u8 = 0;
            for (baseline) |model| if (model.kind == kind and std.mem.eql(u8, model.providerName(), provider) and std.mem.eql(u8, model.id, id)) {
                defaults = model;
                break;
            };
            if (defaults == null) for (baseline) |model| {
                if (model.kind != kind or !std.mem.eql(u8, model.providerName(), provider)) continue;
                const score: u8 = if (text(definition, "api")) |api| if (std.mem.eql(u8, model.operation_api orelse "", api)) 2 else 1 else 1;
                if (score > default_score) {
                    defaults = model;
                    default_score = score;
                }
            };
            const api = text(definition, "api") orelse (if (defaults) |value| value.operation_api else null) orelse return error.MissingExtensionModelApi;
            const base = text(definition, "baseUrl") orelse text(config, "baseUrl") orelse (if (defaults) |value| value.base_url else null) orelse return error.MissingExtensionModelBaseUrl;
            if (api.len == 0) return error.MissingExtensionModelApi;
            if (base.len == 0) return error.MissingExtensionModelBaseUrl;
            // Source spreads the definition, selects API/provider/baseUrl, and
            // explicitly clears model-scoped headers during extension composition.
            var row: std.json.Value = .{ .object = .empty };
            var entries = definition.object.iterator();
            while (entries.next()) |entry| if (native_mode or !std.mem.eql(u8, entry.key_ptr.*, "headers")) try row.object.put(a, entry.key_ptr.*, entry.value_ptr.*);
            try row.object.put(a, "api", .{ .string = api });
            try row.object.put(a, "provider", .{ .string = provider });
            try row.object.put(a, "baseUrl", .{ .string = base });
            const metadata = try std.json.Stringify.valueAlloc(a, row, .{});
            const copied = try std.json.parseFromSlice(std.json.Value, a, metadata, .{ .allocate = .alloc_always });
            const retained = copied.value;
            var model: providers.ModelInfo = .{ .kind = kind, .provider = providers.Provider.fromString(provider) orelse .openai, .provider_id = text(retained, "provider").?, .id = text(retained, "id").?, .display = text(retained, "name") orelse text(retained, "id").?, .operation_api = text(retained, "api").?, .base_url = text(retained, "baseUrl").?, .source_metadata_json = metadata, .input_text = false };
            if (native_mode) if (retained.object.get("headers")) |headers| if (headers == .object) {
                var fields = headers.object.iterator();
                var out: std.ArrayList(@import("../ai/request_metadata.zig").Header) = .empty;
                while (fields.next()) |field| {
                    if (field.value_ptr.* != .string) return error.InvalidNativeProviderModels;
                    try out.append(a, .{ .name = field.key_ptr.*, .value = field.value_ptr.string });
                }
                model.headers = try out.toOwnedSlice(a);
            };
            if (retained.object.get("input")) |input| if (input == .array) {
                for (input.array.items) |item| if (item == .string) {
                    if (std.mem.eql(u8, item.string, "text")) model.input_text = true;
                    if (std.mem.eql(u8, item.string, "image")) model.input_image = true;
                };
            };
            if (retained.object.get("cost")) |cost| if (cost == .object) {
                model.cost = .{ .input = number(cost, "input"), .output = number(cost, "output"), .cache_read = number(cost, "cacheRead"), .cache_write = number(cost, "cacheWrite") };
            };
            try models.append(a, model);
        }
        self.models = try models.toOwnedSlice(a);
        return self;
    }
};
fn text(value: std.json.Value, key: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const item = value.object.get(key) orelse return null;
    return if (item == .string) item.string else null;
}
fn number(value: std.json.Value, key: []const u8) f64 {
    const item = value.object.get(key) orelse return 0;
    return switch (item) {
        .integer => @floatFromInt(item.integer),
        .float => item.float,
        else => 0,
    };
}

/// Borrowed JSON nodes are used only until the returned document is encoded.
pub fn chatConfig(a: std.mem.Allocator, config: std.json.Value) !std.json.Value {
    var result = config;
    result.object = .empty;
    var fields = config.object.iterator();
    while (fields.next()) |field| {
        var value = field.value_ptr.*;
        if (std.mem.eql(u8, field.key_ptr.*, "models") and value == .array) {
            value.array = .init(a);
            for (field.value_ptr.array.items) |model| if (std.mem.eql(u8, text(model, "type") orelse "chat", "chat")) try value.array.append(model);
        }
        try result.object.put(a, field.key_ptr.*, value);
    }
    return result;
}
