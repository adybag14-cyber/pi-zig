//! Shared constrained-sampling validation for OpenAI-compatible tool schemas.
const std = @import("std");

pub const Grammar = struct {
    syntax: []const u8,
    definition: []const u8,
    input_property: []const u8,
};

fn constrainedConfig(tool: std.json.Value) ?std.json.Value {
    if (tool != .object) return null;
    if (tool.object.get("constrainedSampling")) |value| return value;
    if (tool.object.get("function")) |fn_value| {
        if (fn_value == .object) return fn_value.object.get("constrainedSampling");
    }
    return null;
}

fn functionObject(tool: std.json.Value) ?std.json.ObjectMap {
    if (tool != .object) return null;
    const fn_value = tool.object.get("function") orelse return null;
    return if (fn_value == .object) fn_value.object else null;
}

fn inferInputProperty(tool: std.json.Value) ![]const u8 {
    const fn_obj = functionObject(tool) orelse return error.InvalidGrammarTool;
    const parameters = fn_obj.get("parameters") orelse return error.GrammarRequiresObjectSchema;
    if (parameters != .object) return error.GrammarRequiresObjectSchema;
    const type_value = parameters.object.get("type") orelse return error.GrammarRequiresObjectSchema;
    if (type_value != .string or !std.mem.eql(u8, type_value.string, "object")) return error.GrammarRequiresObjectSchema;
    const required = parameters.object.get("required") orelse return error.GrammarRequiresExactlyOneRequiredString;
    if (required != .array or required.array.items.len != 1 or required.array.items[0] != .string)
        return error.GrammarRequiresExactlyOneRequiredString;
    const input_property = required.array.items[0].string;
    const properties = parameters.object.get("properties") orelse return error.GrammarMissingInputProperty;
    if (properties != .object) return error.GrammarMissingInputProperty;
    const property = properties.object.get(input_property) orelse return error.GrammarMissingInputProperty;
    if (property != .object) return error.GrammarInputMustBeString;
    const property_type = property.object.get("type") orelse return error.GrammarInputMustBeString;
    if (property_type != .string or !std.mem.eql(u8, property_type.string, "string")) return error.GrammarInputMustBeString;
    return input_property;
}

pub fn resolveGrammar(tool: std.json.Value, supported: bool) !?Grammar {
    const config = constrainedConfig(tool) orelse return null;
    if (config != .object) return error.InvalidConstrainedSampling;
    const kind = config.object.get("type") orelse return error.InvalidConstrainedSampling;
    if (kind != .string or !std.mem.eql(u8, kind.string, "grammar")) return null;
    if (!supported) return null;
    const variants = config.object.get("variants") orelse return error.MissingGrammarVariant;
    if (variants != .object) return error.MissingGrammarVariant;
    const lark = if (variants.object.get("openai_lark")) |v| if (v == .string and std.mem.trim(u8, v.string, " \t\r\n").len > 0) v.string else null else null;
    const regex = if (variants.object.get("openai_regex")) |v| if (v == .string and std.mem.trim(u8, v.string, " \t\r\n").len > 0) v.string else null else null;
    const definition = lark orelse regex orelse return error.MissingGrammarVariant;
    return .{
        .syntax = if (lark != null) "lark" else "regex",
        .definition = definition,
        .input_property = try inferInputProperty(tool),
    };
}

/// Returns true when strict JSON-schema sampling should be emitted, null when
/// the tool did not request JSON-schema constrained sampling.
pub fn resolveJsonSchemaStrict(tool: std.json.Value, supports_strict: bool) !?bool {
    const config = constrainedConfig(tool) orelse return null;
    if (config != .object) return error.InvalidConstrainedSampling;
    const kind = config.object.get("type") orelse return error.InvalidConstrainedSampling;
    if (kind != .string or !std.mem.eql(u8, kind.string, "json_schema")) return null;
    if (supports_strict) return true;
    if (config.object.get("strict")) |strict| {
        if (strict == .string and std.mem.eql(u8, strict.string, "require")) return error.StrictToolsUnsupported;
    }
    return null;
}

pub fn toolName(tool: std.json.Value) ?[]const u8 {
    const fn_obj = functionObject(tool) orelse return null;
    const name = fn_obj.get("name") orelse return null;
    return if (name == .string) name.string else null;
}

pub fn functionSpec(tool: std.json.Value) ?std.json.ObjectMap {
    return functionObject(tool);
}

/// Find the single string argument property for a grammar tool by name.
/// Returned memory is allocator-owned because the parsed tool document is temporary.
pub fn findGrammarInputProperty(
    gpa: std.mem.Allocator,
    tools_json: []const u8,
    name: []const u8,
    supported: bool,
) !?[]u8 {
    if (!supported or tools_json.len <= 2) return null;
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, tools_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .array) return null;
    for (parsed.value.array.items) |tool| {
        const tool_name = toolName(tool) orelse continue;
        if (!std.mem.eql(u8, tool_name, name)) continue;
        const grammar = (try resolveGrammar(tool, true)) orelse return null;
        return try gpa.dupe(u8, grammar.input_property);
    }
    return null;
}

pub fn wrapGrammarInput(gpa: std.mem.Allocator, property: []const u8, input: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    errdefer out.deinit();
    try out.writer.writeAll("{");
    try std.json.Stringify.value(property, .{}, &out.writer);
    try out.writer.writeAll(":");
    try std.json.Stringify.value(input, .{}, &out.writer);
    try out.writer.writeAll("}");
    return out.toOwnedSlice();
}

pub fn normalizeGrammarArguments(
    gpa: std.mem.Allocator,
    tools_json: []const u8,
    supported: bool,
    name: []const u8,
    raw_input: []const u8,
) !?[]u8 {
    const property = (try findGrammarInputProperty(gpa, tools_json, name, supported)) orelse return null;
    defer gpa.free(property);
    return @as(?[]u8, try wrapGrammarInput(gpa, property, raw_input));
}

/// Extract the raw custom-tool input from persisted ordinary JSON arguments.
/// Returns allocator-owned memory when `name` is a supported grammar tool.
pub fn extractGrammarInput(
    gpa: std.mem.Allocator,
    tools_json: []const u8,
    supported: bool,
    name: []const u8,
    arguments_json: []const u8,
) !?[]u8 {
    const property = (try findGrammarInputProperty(gpa, tools_json, name, supported)) orelse return null;
    defer gpa.free(property);
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, arguments_json, .{}) catch return error.InvalidGrammarArguments;
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidGrammarArguments;
    const input = parsed.value.object.get(property) orelse return error.InvalidGrammarArguments;
    if (input != .string) return error.InvalidGrammarArguments;
    return @as(?[]u8, try gpa.dupe(u8, input.string));
}

test "grammar prefers lark and validates one required string property" {
    const raw =
        \\{"type":"function","function":{"name":"sample","parameters":{"type":"object","properties":{"payload":{"type":"string"}},"required":["payload"]}},"constrainedSampling":{"type":"grammar","variants":{"openai_regex":"[a-z]+","openai_lark":"start: /[a-z]+/"}}}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, raw, .{});
    defer parsed.deinit();
    const grammar = (try resolveGrammar(parsed.value, true)).?;
    try std.testing.expectEqualStrings("lark", grammar.syntax);
    try std.testing.expectEqualStrings("start: /[a-z]+/", grammar.definition);
    try std.testing.expectEqualStrings("payload", grammar.input_property);
}

test "grammar falls back when unsupported and strict require fails" {
    const grammar_raw =
        \\{"type":"function","function":{"name":"sample","parameters":{"type":"object","properties":{"payload":{"type":"string"}},"required":["payload"]}},"constrainedSampling":{"type":"grammar","variants":{"openai_regex":".+"}}}
    ;
    var grammar_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, grammar_raw, .{});
    defer grammar_parsed.deinit();
    try std.testing.expect((try resolveGrammar(grammar_parsed.value, false)) == null);

    const strict_raw =
        \\{"type":"function","function":{"name":"sample","parameters":{"type":"object"}},"constrainedSampling":{"type":"json_schema","strict":"require"}}
    ;
    var strict_parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, strict_raw, .{});
    defer strict_parsed.deinit();
    try std.testing.expectError(error.StrictToolsUnsupported, resolveJsonSchemaStrict(strict_parsed.value, false));
}

test "grammar input normalizes to ordinary JSON arguments" {
    const tools =
        \\[{"type":"function","function":{"name":"sample","parameters":{"type":"object","properties":{"payload":{"type":"string"}},"required":["payload"]}},"constrainedSampling":{"type":"grammar","variants":{"openai_regex":".+"}}}]
    ;
    const got = (try normalizeGrammarArguments(std.testing.allocator, tools, true, "sample", "a\nb")).?;
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("{\"payload\":\"a\\nb\"}", got);
}
