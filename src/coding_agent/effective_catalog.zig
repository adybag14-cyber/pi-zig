//! Compose the effective model catalog from built-ins plus models.json.
//! This is credential-blind and mirrors upstream's composition order:
//! built-ins -> custom model upserts -> modelOverrides.
const std = @import("std");
const providers = @import("../ai/providers.zig");
const models_file_mod = @import("models_file.zig");

fn sameIdentity(a: providers.ModelInfo, b: providers.ModelInfo) bool {
    return std.ascii.eqlIgnoreCase(a.providerName(), b.providerName()) and std.mem.eql(u8, a.id, b.id);
}

fn hasIdentity(list: []const providers.ModelInfo, target: providers.ModelInfo) bool {
    for (list) |item| if (sameIdentity(item, target)) return true;
    return false;
}

fn applyOverride(model: providers.ModelInfo, provider_config: ?*const models_file_mod.ProviderConfig) providers.ModelInfo {
    var merged = model;
    if (provider_config) |provider| {
        if (provider.findOverride(model.id)) |model_override| {
            if (model_override.name) |name| merged.display = name;
            if (model_override.reasoning) |reasoning| merged.reasoning = reasoning;
            if (model_override.thinking_level_map) |map| merged.thinking_level_map = map;
            if (model_override.input_text) |value| merged.input_text = value;
            if (model_override.input_image) |value| merged.input_image = value;
            if (model_override.cost) |value| merged.cost = value;
            if (model_override.context_window) |value| merged.context_window = value;
            if (model_override.max_tokens) |value| merged.max_tokens = value;
        }
    }
    return merged;
}

fn staticHasIdentity(models_file: *const models_file_mod.ModelsFile, target: providers.ModelInfo) bool {
    const provider = models_file.findProvider(target.providerName()) orelse return false;
    for (provider.models) |configured| if (std.mem.eql(u8, configured.info.id, target.id)) return true;
    return false;
}

/// Compose built-ins, offline dynamic provider models, then static models.json definitions.
/// Static definitions win identity collisions; dynamic Radius entries replace built-ins and
/// still receive modelOverrides from models.json.
pub fn buildWithExtras(gpa: std.mem.Allocator, models_file: *const models_file_mod.ModelsFile, extras: []const providers.ModelInfo) ![]providers.ModelInfo {
    var out: std.ArrayList(providers.ModelInfo) = .empty;
    errdefer out.deinit(gpa);

    for (providers.known_models) |known| {
        if (staticHasIdentity(models_file, known) or hasIdentity(extras, known)) continue;
        try out.append(gpa, applyOverride(known, models_file.findProvider(known.providerName())));
    }

    for (extras) |extra| {
        if (!extra.apiKind().runtimeSupported()) continue;
        if (staticHasIdentity(models_file, extra)) continue;
        // Deduplicate malformed/repeated stores by first identity, just like a provider map.
        if (hasIdentity(out.items, extra)) continue;
        try out.append(gpa, applyOverride(extra, models_file.findProvider(extra.providerName())));
    }

    for (models_file.providers) |provider_config| {
        for (provider_config.models) |configured_model| {
            if (!configured_model.api.runtimeSupported()) continue;
            try out.append(gpa, configured_model.info);
        }
    }
    return try out.toOwnedSlice(gpa);
}

pub fn build(gpa: std.mem.Allocator, models_file: *const models_file_mod.ModelsFile) ![]providers.ModelInfo {
    return buildWithExtras(gpa, models_file, &.{});
}

test "effective catalog upserts custom models and applies overrides" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data =
        \\{
        \\  "providers": {
        \\    "openai": {
        \\      "models": [{"id":"corp-extra","name":"Corp Extra","api":"openai-completions","baseUrl":"http://127.0.0.1:9999"}],
        \\      "modelOverrides": {"gpt-4o":{"name":"Overridden GPT-4o","reasoning":true}}
        \\    }
        \\  }
        \\}
    });

    var file = try models_file_mod.load(gpa, io, root);
    defer file.deinit();
    const catalog = try build(gpa, &file);
    defer gpa.free(catalog);

    var saw_override = false;
    var saw_custom = false;
    var saw_other_builtin = false;
    for (catalog) |model| {
        if (std.mem.eql(u8, model.providerName(), "openai") and std.mem.eql(u8, model.id, "gpt-4o")) {
            saw_override = std.mem.eql(u8, model.display, "Overridden GPT-4o") and model.reasoning;
        }
        if (std.mem.eql(u8, model.providerName(), "openai") and std.mem.eql(u8, model.id, "corp-extra")) {
            saw_custom = std.mem.eql(u8, model.base_url orelse "", "http://127.0.0.1:9999");
        }
        if (std.mem.eql(u8, model.providerName(), "openai") and std.mem.eql(u8, model.id, "gpt-4.1")) saw_other_builtin = true;
    }
    try std.testing.expect(saw_override);
    try std.testing.expect(saw_custom);
    try std.testing.expect(saw_other_builtin);
}

test "effective catalog upserts cached Radius extras and applies model override" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try tmp.dir.realPath(io, &buf);
    const root = buf[0..n];
    const path = try std.fs.path.join(gpa, &.{ root, "models.json" });
    defer gpa.free(path);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = "{\"providers\":{\"radius\":{\"modelOverrides\":{\"auto\":{\"name\":\"Cached Override\",\"maxTokens\":777}}},\"radius-dev\":{\"baseUrl\":\"http://dev\",\"oauth\":\"radius\"}}}" });
    var file = try models_file_mod.load(gpa, io, root);
    defer file.deinit();
    const extras = [_]providers.ModelInfo{
        .{ .provider = .radius, .api = .pi_messages, .id = "auto", .display = "Dynamic Radius", .context_window = 9000, .max_tokens = 900 },
        .{ .provider = .radius, .provider_id = "radius-dev", .api = .pi_messages, .id = "dev", .display = "Dev", .context_window = 8000, .max_tokens = 800 },
    };
    const catalog = try buildWithExtras(gpa, &file, &extras);
    defer gpa.free(catalog);
    var auto_count: usize = 0;
    var saw_dev = false;
    for (catalog) |model| {
        if (std.mem.eql(u8, model.providerName(), "radius") and std.mem.eql(u8, model.id, "auto")) {
            auto_count += 1;
            try std.testing.expectEqualStrings("Cached Override", model.display);
            try std.testing.expectEqual(@as(u64, 777), model.max_tokens);
            try std.testing.expectEqual(@as(u64, 9000), model.context_window);
        }
        if (std.mem.eql(u8, model.providerName(), "radius-dev") and std.mem.eql(u8, model.id, "dev")) saw_dev = true;
    }
    try std.testing.expectEqual(@as(usize, 1), auto_count);
    try std.testing.expect(saw_dev);
}
