//! Pi's operation-specific model identity and legacy chat defaults.
const std = @import("std");

pub const ModelType = enum {
    chat,
    image,
    classifier,

    pub fn parse(value: []const u8) ?ModelType {
        inline for (std.meta.fields(ModelType)) |field| {
            if (std.mem.eql(u8, value, field.name)) return @enumFromInt(field.value);
        }
        return null;
    }

    pub fn name(self: ModelType) []const u8 {
        return @tagName(self);
    }
};

/// Unknown explicitly-declared model types are not treated as chat models.
pub fn parseModelType(object: std.json.ObjectMap) ?ModelType {
    const value = object.get("type") orelse return .chat;
    if (value != .string) return null;
    return ModelType.parse(value.string);
}

pub fn requireType(actual: ModelType, expected: ModelType) !void {
    if (actual != expected) return switch (expected) {
        .chat => error.NotChatModel,
        .image => error.NotImageModel,
        .classifier => error.NotClassifierModel,
    };
}

pub fn findOfType(comptime Model: type, models: []const Model, kind: ModelType, provider: []const u8, id: []const u8) ?Model {
    for (models) |model| {
        if (model.kind == kind and std.mem.eql(u8, model.providerName(), provider) and std.mem.eql(u8, model.id, id)) return model;
    }
    return null;
}

pub fn getOfType(comptime Model: type, gpa: std.mem.Allocator, models: []const Model, kind: ModelType) ![]Model {
    var selected: std.ArrayList(Model) = .empty;
    errdefer selected.deinit(gpa);
    for (models) |model| if (model.kind == kind) try selected.append(gpa, model);
    return selected.toOwnedSlice(gpa);
}

test "model type parser defaults omitted types and drops unknown types" {
    for ([_]struct { raw: []const u8, expected: ?ModelType }{
        .{ .raw = "{}", .expected = .chat },
        .{ .raw = "{\"type\":\"chat\"}", .expected = .chat },
        .{ .raw = "{\"type\":\"image\"}", .expected = .image },
        .{ .raw = "{\"type\":\"classifier\"}", .expected = .classifier },
        .{ .raw = "{\"type\":\"unknown-operation\"}", .expected = null },
        .{ .raw = "{\"type\":42}", .expected = null },
    }) |case| {
        var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, case.raw, .{});
        defer parsed.deinit();
        try std.testing.expectEqual(case.expected, parseModelType(parsed.value.object));
    }
}

test "same provider and ID remain distinct per operation" {
    const Model = struct {
        kind: ModelType = .chat,
        id: []const u8,
        provider: []const u8,
        marker: usize,
        fn providerName(self: @This()) []const u8 {
            return self.provider;
        }
    };
    const models = [_]Model{
        .{ .id = "same-model", .provider = "provider", .marker = 1 },
        .{ .kind = .image, .id = "same-model", .provider = "provider", .marker = 2 },
        .{ .kind = .classifier, .id = "same-model", .provider = "provider", .marker = 3 },
    };
    try std.testing.expectEqual(@as(usize, 1), findOfType(Model, &models, .chat, "provider", "same-model").?.marker);
    try std.testing.expectEqual(@as(usize, 2), findOfType(Model, &models, .image, "provider", "same-model").?.marker);
    try std.testing.expectEqual(@as(usize, 3), findOfType(Model, &models, .classifier, "provider", "same-model").?.marker);
    const selected = try getOfType(Model, std.testing.allocator, &models, .classifier);
    defer std.testing.allocator.free(selected);
    try std.testing.expectEqual(@as(usize, 1), selected.len);
    try std.testing.expectEqual(@as(usize, 3), selected[0].marker);
}

test "operation entry points reject a model of the wrong type" {
    try requireType(.chat, .chat);
    try std.testing.expectError(error.NotChatModel, requireType(.image, .chat));
    try std.testing.expectError(error.NotImageModel, requireType(.classifier, .image));
    try std.testing.expectError(error.NotClassifierModel, requireType(.chat, .classifier));
}
