//! Deterministic native catalog projection. Unknown metadata fails explicitly.
const std = @import("std");

pub fn zigString(writer: *std.Io.Writer, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |byte| switch (byte) {
        '"' => try writer.writeAll("\\\""),
        '\\' => try writer.writeAll("\\\\"),
        '\n' => try writer.writeAll("\\n"),
        '\r' => try writer.writeAll("\\r"),
        '\t' => try writer.writeAll("\\t"),
        0...8, 11...12, 14...31 => try writer.print("\\x{x:0>2}", .{byte}),
        else => try writer.writeByte(byte),
    };
    try writer.writeByte('"');
}

fn snake(writer: *std.Io.Writer, value: []const u8) !void {
    if (std.mem.eql(u8, value, "supportsOpenAIGrammarTools")) return writer.writeAll("supports_openai_grammar_tools");
    for (value, 0..) |byte, index| {
        if (byte == '-') {
            try writer.writeByte('_');
        } else if (std.ascii.isUpper(byte)) {
            if (index > 0) try writer.writeByte('_');
            try writer.writeByte(std.ascii.toLower(byte));
        } else try writer.writeByte(byte);
    }
}

fn renderValue(writer: *std.Io.Writer, input: std.json.Value) anyerror!void {
    switch (input) {
        .null => try writer.writeAll("null"),
        .bool => |boolean| try writer.writeAll(if (boolean) "true" else "false"),
        .integer => |integer| try writer.print("{d}", .{integer}),
        .float => |number| {
            if (!std.math.isFinite(number)) return error.NonFiniteCatalogNumber;
            try writer.print("{d}", .{number});
        },
        .number_string => |number| {
            _ = std.fmt.parseFloat(f64, number) catch return error.InvalidCatalogNumber;
            try writer.writeAll(number);
        },
        .string => |string| try zigString(writer, string),
        .array => |array| {
            try writer.writeAll("&.{ ");
            for (array.items, 0..) |item, index| {
                if (index > 0) try writer.writeAll(", ");
                try renderValue(writer, item);
            }
            try writer.writeAll(" }");
        },
        .object => |object| {
            try writer.writeAll(".{ ");
            var entries = object.iterator();
            var index: usize = 0;
            while (entries.next()) |entry| : (index += 1) {
                if (index > 0) try writer.writeAll(", ");
                try writer.writeByte('.');
                try snake(writer, entry.key_ptr.*);
                try writer.writeAll(" = ");
                try renderValue(writer, entry.value_ptr.*);
            }
            try writer.writeAll(" }");
        },
    }
}

fn field(object: std.json.ObjectMap, name: []const u8) !std.json.Value {
    return object.get(name) orelse error.MissingCatalogField;
}

fn getString(object: std.json.ObjectMap, name: []const u8) ![]const u8 {
    const item = try field(object, name);
    if (item != .string) return error.InvalidCatalogString;
    return item.string;
}

fn transport(api: []const u8) ![]const u8 {
    if (std.mem.eql(u8, api, "anthropic-messages")) return "anthropic";
    if (std.mem.eql(u8, api, "google-generative-ai") or std.mem.eql(u8, api, "google-vertex")) return "google";
    if (std.mem.eql(u8, api, "bedrock-converse-stream")) return "amazon_bedrock";
    if (std.mem.eql(u8, api, "mistral-conversations")) return "mistral";
    if (std.mem.eql(u8, api, "pi-messages")) return "radius";
    for ([_][]const u8{ "openai-completions", "openai-responses", "openai-codex-responses", "azure-openai-responses" }) |known| {
        if (std.mem.eql(u8, api, known)) return "openai";
    }
    return error.UnsupportedCatalogChatApi;
}

fn contains(options: []const []const u8, needle: []const u8) bool {
    for (options) |option| if (std.mem.eql(u8, option, needle)) return true;
    return false;
}

fn renderThinking(writer: *std.Io.Writer, map: std.json.Value, force_off_unsupported: bool) !void {
    if (map != .object) return error.InvalidCatalogThinking;
    try writer.writeAll(".{ ");
    const levels = [_][]const u8{ "off", "minimal", "low", "medium", "high", "xhigh", "max" };
    for (map.object.keys()) |key| if (!contains(&levels, key)) return error.UnknownCatalogThinkingLevel;
    var index: usize = 0;
    for (levels) |level| {
        const item = map.object.get(level) orelse if (force_off_unsupported and std.mem.eql(u8, level, "off")) std.json.Value.null else continue;
        if (index > 0) try writer.writeAll(", ");
        index += 1;
        try writer.print(".{s} = ", .{level});
        if (item == .null or (force_off_unsupported and std.mem.eql(u8, level, "off"))) {
            try writer.writeAll(".unsupported");
        } else if (item == .string) {
            try writer.writeAll(".{ .mapped = ");
            try zigString(writer, item.string);
            try writer.writeAll(" }");
        } else return error.InvalidCatalogThinking;
    }
    try writer.writeAll(" }");
}

const compat_fields = [_][]const u8{
    "allowEmptySignature",         "cacheControlFormat",               "deferredToolsMode",                           "forceAdaptiveThinking",
    "maxTokensField",              "requiresAssistantAfterToolResult", "requiresReasoningContentOnAssistantMessages", "requiresThinkingAsText",
    "requiresToolResultName",      "sendSessionAffinityHeaders",       "sessionAffinityFormat",                       "supportsAdditionalTools",
    "supportsCacheControlOnTools", "supportsDeveloperRole",            "supportsEagerToolInputStreaming",             "supportsExplicitPromptCacheMode",
    "supportsFinishReason",        "supportsLongCacheRetention",       "supportsOpenAIGrammarTools",                  "supportsReasoningEffort",
    "supportsStore",               "supportsStrictMode",               "supportsStrictTools",                         "supportsTemperature",
    "supportsThinkingTokenBudget", "thinkingTokenBudgetField",         "supportsToolReferences",                      "supportsToolSearch",
    "supportsUsageInStreaming",    "thinkingFormat",                   "zaiToolStream",                               "allowedFallbackModels",
    "chatTemplateArgs",
};

fn renderCompat(writer: *std.Io.Writer, compat: std.json.Value) !void {
    if (compat != .object) return error.InvalidCatalogCompat;
    try writer.writeAll(".{ ");
    var entries = compat.object.iterator();
    var index: usize = 0;
    while (entries.next()) |entry| : (index += 1) {
        if (!contains(&compat_fields, entry.key_ptr.*)) return error.UnknownCatalogCompatField;
        if (index > 0) try writer.writeAll(", ");
        if (std.mem.eql(u8, entry.key_ptr.*, "chatTemplateArgs")) {
            if (entry.value_ptr.* != .object) return error.UnsupportedCatalogTemplate;
            const enable = entry.value_ptr.object.get("enable_thinking") orelse return error.UnsupportedCatalogTemplate;
            if (enable != .object or enable.object.count() != 1 or entry.value_ptr.object.count() != 1) return error.UnsupportedCatalogTemplate;
            const variable = enable.object.get("$var") orelse return error.UnsupportedCatalogTemplate;
            if (variable != .string or !std.mem.eql(u8, variable.string, "thinking.enabled")) return error.UnsupportedCatalogTemplate;
            try writer.writeAll(".chat_template_args_enable_thinking = true");
            continue;
        }
        try writer.writeByte('.');
        try snake(writer, entry.key_ptr.*);
        try writer.writeAll(" = ");
        if (entry.value_ptr.* == .string) {
            try writer.writeByte('.');
            try snake(writer, entry.value_ptr.string);
        } else try renderValue(writer, entry.value_ptr.*);
    }
    try writer.writeAll(" }");
}

fn renderModel(writer: *std.Io.Writer, model: std.json.ObjectMap) !void {
    const allowed = [_][]const u8{ "api", "baseUrl", "compat", "contextWindow", "cost", "headers", "id", "input", "maxTokens", "name", "provider", "reasoning", "samplingParams", "thinkingLevelMap" };
    for (model.keys()) |key| if (!contains(&allowed, key)) return error.UnknownCatalogModelField;
    const api = try getString(model, "api");
    try writer.print("        .{{ .provider = .{s}, .provider_id = ", .{try transport(api)});
    try zigString(writer, try getString(model, "provider"));
    for ([_][2][]const u8{ .{ "id", "id" }, .{ "name", "display" }, .{ "baseUrl", "base_url" } }) |pair| {
        try writer.print(", .{s} = ", .{pair[1]});
        try zigString(writer, try getString(model, pair[0]));
    }
    const input = try field(model, "input");
    if (input != .array) return error.InvalidCatalogInput;
    var image = false;
    var text_input = false;
    for (input.array.items) |item| {
        if (item != .string) return error.InvalidCatalogInput;
        if (std.mem.eql(u8, item.string, "image")) image = true else if (std.mem.eql(u8, item.string, "text")) text_input = true else return error.InvalidCatalogInput;
    }
    if (!text_input) return error.InvalidCatalogInput;
    const reasoning = model.get("reasoning") orelse std.json.Value{ .bool = false };
    try writer.writeAll(", .reasoning = ");
    try renderValue(writer, reasoning);
    try writer.print(", .input_image = {s}", .{if (image) "true" else "false"});
    for ([_][2][]const u8{ .{ "contextWindow", "context_window" }, .{ "maxTokens", "max_tokens" }, .{ "cost", "cost" } }) |pair| {
        try writer.print(", .{s} = ", .{pair[1]});
        try renderValue(writer, try field(model, pair[0]));
    }
    try writer.writeAll(", .api = .");
    try snake(writer, api);
    const free_model = std.mem.eql(u8, try getString(model, "provider"), "openrouter") and std.mem.eql(u8, try getString(model, "id"), "openrouter/free");
    if (model.get("thinkingLevelMap")) |thinking| {
        try writer.writeAll(", .thinking_level_map = ");
        try renderThinking(writer, thinking, free_model);
    } else if (free_model) {
        try writer.writeAll(", .thinking_level_map = .{ .off = .unsupported }");
    }
    if (model.get("headers")) |headers| {
        if (headers != .object) return error.InvalidCatalogHeaders;
        try writer.writeAll(", .headers = &.{ ");
        var entries = headers.object.iterator();
        var index: usize = 0;
        while (entries.next()) |entry| : (index += 1) {
            if (index > 0) try writer.writeAll(", ");
            try writer.writeAll(".{ .name = ");
            try zigString(writer, entry.key_ptr.*);
            try writer.writeAll(", .value = ");
            try renderValue(writer, entry.value_ptr.*);
            try writer.writeAll(" }");
        }
        try writer.writeAll(" }");
    }
    if (model.get("samplingParams")) |sampling| {
        if (sampling != .object) return error.InvalidCatalogSampling;
        try writer.writeAll(", .sampling_params = &.{ ");
        var entries = sampling.object.iterator();
        var index: usize = 0;
        while (entries.next()) |entry| : (index += 1) {
            if (index > 0) try writer.writeAll(", ");
            try writer.writeAll(".{ .name = ");
            try zigString(writer, entry.key_ptr.*);
            try writer.writeAll(", .value_json = ");
            var encoded: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
            defer encoded.deinit();
            try std.json.Stringify.value(entry.value_ptr.*, .{}, &encoded.writer);
            try zigString(writer, encoded.written());
            try writer.writeAll(" }");
        }
        try writer.writeAll(" }");
    }
    if (model.get("compat")) |compat| {
        try writer.writeAll(", .compat = ");
        try renderCompat(writer, compat);
    }
    try writer.writeAll(" },\n");
}

pub fn render(gpa: std.mem.Allocator, source: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, source, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidCatalogSource;
    const root = parsed.value.object;
    const schema = try field(root, "schemaVersion");
    if (schema != .integer or schema.integer != 1) return error.UnsupportedCatalogSourceSchema;
    if (!std.mem.eql(u8, try getString(root, "upstreamPackage"), "@earendil-works/pi-ai")) return error.InvalidCatalogProvenance;
    const models = try field(root, "models");
    if (models != .array) return error.InvalidCatalogSource;
    const declared_count = try field(root, "modelCount");
    if (declared_count != .integer or declared_count.integer < 1 or declared_count.integer != models.array.items.len) return error.InvalidCatalogCardinality;
    var identities: std.StringHashMapUnmanaged(void) = .empty;
    defer {
        var keys = identities.keyIterator();
        while (keys.next()) |key| gpa.free(key.*);
        identities.deinit(gpa);
    }
    var provider_ids: std.StringHashMapUnmanaged(void) = .empty;
    defer provider_ids.deinit(gpa);
    for (models.array.items) |model| {
        if (model != .object) return error.InvalidCatalogModel;
        const provider = try getString(model.object, "provider");
        const id = try getString(model.object, "id");
        const identity = try std.fmt.allocPrint(gpa, "{s}\x00{s}", .{ provider, id });
        if (identities.contains(identity)) {
            gpa.free(identity);
            return error.DuplicateCatalogIdentity;
        }
        identities.put(gpa, identity, {}) catch |err| {
            gpa.free(identity);
            return err;
        };
        try provider_ids.put(gpa, provider, {});
    }
    const declared_providers = try field(root, "providerCount");
    if (declared_providers != .integer or declared_providers.integer < 1 or declared_providers.integer != provider_ids.count()) return error.InvalidCatalogCardinality;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();
    const writer = &output.writer;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(source, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    try writer.print("//! Generated from catalog_source.json. Do not edit manually.\n//! Source SHA-256: {s}\n\npub const source_sha256 = \"{s}\";\n", .{ hex, hex });
    for ([_][2][]const u8{
        .{ "upstreamVersion", "upstream_version" },                             .{ "upstreamCommit", "upstream_commit" },
        .{ "upstreamReleaseArchiveSha256", "upstream_release_archive_sha256" }, .{ "upstreamModelDataStructureHash", "upstream_model_data_structure_hash" },
    }) |pair| {
        try writer.print("pub const {s} = ", .{pair[1]});
        try zigString(writer, try getString(root, pair[0]));
        try writer.writeAll(";\n");
    }
    try writer.print("pub const model_count: usize = {d};\npub const provider_count: usize = ", .{models.array.items.len});
    try renderValue(writer, try field(root, "providerCount"));
    try writer.writeAll(";\n\npub fn rows(comptime ModelInfo: type) [model_count]ModelInfo {\n    return .{\n");
    for (models.array.items) |model| {
        if (model != .object) return error.InvalidCatalogModel;
        try renderModel(writer, model.object);
    }
    try writer.writeAll("    };\n}\n");
    const terminated = try gpa.dupeZ(u8, output.written());
    defer gpa.free(terminated);
    var tree = try std.zig.Ast.parse(gpa, terminated, .zig);
    defer tree.deinit(gpa);
    if (tree.errors.len > 0) return error.InvalidGeneratedCatalog;
    return tree.renderAlloc(gpa);
}

test "Zig source strings escape control bytes without JavaScript Unicode escapes" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try zigString(&output.writer, "hi\x00\n🌍\"\\");
    try std.testing.expectEqualStrings("\"hi\\x00\\n🌍\\\"\\\\\"", output.written());
}
