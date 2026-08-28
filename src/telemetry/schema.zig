//! Serializable telemetry schema metadata and runtime validation.
const std = @import("std");
const types = @import("types.zig");

pub const AttributeType = enum { string, number, boolean, string_array, number_array, boolean_array };
pub const Cardinality = enum { low, high };

pub const AttributeDefinition = struct {
    name: []const u8,
    description: []const u8,
    attribute_type: AttributeType,
    required: bool = false,
    sensitive: bool = false,
    cardinality: ?Cardinality = null,
    string_values: []const []const u8 = &.{},
    number_values: []const f64 = &.{},
    boolean_values: []const bool = &.{},
};

pub const EventDefinition = struct {
    name: []const u8,
    description: []const u8,
    attributes: []const AttributeDefinition = &.{},
};

pub const ParentDefinition = union(enum) {
    any,
    root_or_external,
    spans: []const []const u8,
};

pub const SpanDefinition = struct {
    name: []const u8,
    description: []const u8,
    parents: ParentDefinition = .any,
    start_attributes: []const AttributeDefinition = &.{},
    end_attributes: []const AttributeDefinition = &.{},
    events: []const EventDefinition = &.{},
    error_when: []const u8,
};

pub const Schema = struct {
    version: u32,
    spans: []const SpanDefinition,
};

pub const ValidationError = error{
    InvalidVersion,
    EmptyName,
    DuplicateSpan,
    DuplicateAttribute,
    DuplicateEvent,
    UnknownParentSpan,
    MissingRequiredAttribute,
    UnknownAttribute,
    WrongAttributeType,
    DisallowedAttributeValue,
    UnknownSpan,
    UnknownEvent,
};

pub fn validateSchema(schema: Schema) ValidationError!void {
    if (schema.version == 0) return ValidationError.InvalidVersion;
    for (schema.spans, 0..) |span, index| {
        if (span.name.len == 0 or span.description.len == 0 or span.error_when.len == 0) return ValidationError.EmptyName;
        for (schema.spans[0..index]) |previous| if (std.mem.eql(u8, previous.name, span.name)) return ValidationError.DuplicateSpan;
        try validateAttributeDefinitions(span.start_attributes);
        try validateAttributeDefinitions(span.end_attributes);
        for (span.events, 0..) |event, event_index| {
            if (event.name.len == 0 or event.description.len == 0) return ValidationError.EmptyName;
            for (span.events[0..event_index]) |previous| if (std.mem.eql(u8, previous.name, event.name)) return ValidationError.DuplicateEvent;
            try validateAttributeDefinitions(event.attributes);
        }
        switch (span.parents) {
            .any, .root_or_external => {},
            .spans => |parents| for (parents) |parent_name| {
                if (findSpan(schema, parent_name) == null) return ValidationError.UnknownParentSpan;
            },
        }
    }
}

fn validateAttributeDefinitions(definitions: []const AttributeDefinition) ValidationError!void {
    for (definitions, 0..) |definition, index| {
        if (definition.name.len == 0 or definition.description.len == 0) return ValidationError.EmptyName;
        for (definitions[0..index]) |previous| if (std.mem.eql(u8, previous.name, definition.name)) return ValidationError.DuplicateAttribute;
    }
}

pub fn validateStartAttributes(schema: Schema, span_name: []const u8, attributes: []const types.Attribute) ValidationError!void {
    const span = findSpan(schema, span_name) orelse return ValidationError.UnknownSpan;
    try validateAttributes(span.start_attributes, attributes);
}

pub fn validateEndAttributes(schema: Schema, span_name: []const u8, attributes: []const types.Attribute) ValidationError!void {
    const span = findSpan(schema, span_name) orelse return ValidationError.UnknownSpan;
    try validateAttributes(span.end_attributes, attributes);
}

pub fn validateEventAttributes(schema: Schema, span_name: []const u8, event_name: []const u8, attributes: []const types.Attribute) ValidationError!void {
    const span = findSpan(schema, span_name) orelse return ValidationError.UnknownSpan;
    const event = findEvent(span.*, event_name) orelse return ValidationError.UnknownEvent;
    try validateAttributes(event.attributes, attributes);
}

pub fn parentAllowed(schema: Schema, span_name: []const u8, parent_name: ?[]const u8) ValidationError!bool {
    const span = findSpan(schema, span_name) orelse return ValidationError.UnknownSpan;
    return switch (span.parents) {
        .any => true,
        .root_or_external => parent_name == null,
        .spans => |parents| blk: {
            const parent = parent_name orelse break :blk false;
            for (parents) |candidate| if (std.mem.eql(u8, candidate, parent)) break :blk true;
            break :blk false;
        },
    };
}

fn validateAttributes(definitions: []const AttributeDefinition, attributes: []const types.Attribute) ValidationError!void {
    for (attributes, 0..) |attribute, index| {
        for (attributes[0..index]) |previous| if (std.mem.eql(u8, previous.name, attribute.name)) return ValidationError.DuplicateAttribute;
        const definition = findDefinition(definitions, attribute.name) orelse return ValidationError.UnknownAttribute;
        if (!typeMatches(definition.attribute_type, attribute.value)) return ValidationError.WrongAttributeType;
        if (!valueAllowed(definition.*, attribute.value)) return ValidationError.DisallowedAttributeValue;
    }
    for (definitions) |definition| {
        if (!definition.required) continue;
        var found = false;
        for (attributes) |attribute| if (std.mem.eql(u8, definition.name, attribute.name)) {
            found = true;
            break;
        };
        if (!found) return ValidationError.MissingRequiredAttribute;
    }
}

fn findSpan(schema: Schema, name: []const u8) ?*const SpanDefinition {
    for (schema.spans) |*span| if (std.mem.eql(u8, span.name, name)) return span;
    return null;
}

fn findEvent(span: SpanDefinition, name: []const u8) ?*const EventDefinition {
    for (span.events) |*event| if (std.mem.eql(u8, event.name, name)) return event;
    return null;
}

fn findDefinition(definitions: []const AttributeDefinition, name: []const u8) ?*const AttributeDefinition {
    for (definitions) |*definition| if (std.mem.eql(u8, definition.name, name)) return definition;
    return null;
}

fn typeMatches(expected: AttributeType, value: types.AttributeValue) bool {
    return switch (expected) {
        .string => value == .string,
        .number => value == .number,
        .boolean => value == .boolean,
        .string_array => value == .strings,
        .number_array => value == .numbers,
        .boolean_array => value == .booleans,
    };
}

fn valueAllowed(definition: AttributeDefinition, value: types.AttributeValue) bool {
    return switch (value) {
        .string => |actual| definition.string_values.len == 0 or containsString(definition.string_values, actual),
        .number => |actual| definition.number_values.len == 0 or containsNumber(definition.number_values, actual),
        .boolean => |actual| definition.boolean_values.len == 0 or containsBool(definition.boolean_values, actual),
        .strings => |actuals| definition.string_values.len == 0 or allStringsAllowed(definition.string_values, actuals),
        .numbers => |actuals| definition.number_values.len == 0 or allNumbersAllowed(definition.number_values, actuals),
        .booleans => |actuals| definition.boolean_values.len == 0 or allBoolsAllowed(definition.boolean_values, actuals),
    };
}

fn containsString(values: []const []const u8, actual: []const u8) bool {
    for (values) |value| if (std.mem.eql(u8, value, actual)) return true;
    return false;
}
fn containsNumber(values: []const f64, actual: f64) bool {
    for (values) |value| if (value == actual) return true;
    return false;
}
fn containsBool(values: []const bool, actual: bool) bool {
    for (values) |value| if (value == actual) return true;
    return false;
}
fn allStringsAllowed(values: []const []const u8, actuals: []const []const u8) bool {
    for (actuals) |actual| if (!containsString(values, actual)) return false;
    return true;
}
fn allNumbersAllowed(values: []const f64, actuals: []const f64) bool {
    for (actuals) |actual| if (!containsNumber(values, actual)) return false;
    return true;
}
fn allBoolsAllowed(values: []const bool, actuals: []const bool) bool {
    for (actuals) |actual| if (!containsBool(values, actual)) return false;
    return true;
}

const test_schema = Schema{
    .version = 1,
    .spans = &.{
        .{
            .name = "request",
            .description = "request",
            .parents = .root_or_external,
            .start_attributes = &.{.{
                .name = "provider",
                .description = "provider",
                .attribute_type = .string,
                .required = true,
                .string_values = &.{ "openai", "anthropic" },
            }},
            .end_attributes = &.{.{
                .name = "tokens",
                .description = "tokens",
                .attribute_type = .number,
            }},
            .events = &.{.{
                .name = "retry",
                .description = "retry",
                .attributes = &.{.{
                    .name = "attempt",
                    .description = "attempt",
                    .attribute_type = .number,
                    .required = true,
                }},
            }},
            .error_when = "request fails",
        },
        .{
            .name = "tool",
            .description = "tool",
            .parents = .{ .spans = &.{"request"} },
            .error_when = "tool fails",
        },
    },
};

test "schema validates required, closed and enumerated attributes" {
    try validateSchema(test_schema);
    try validateStartAttributes(test_schema, "request", &.{.{ .name = "provider", .value = .{ .string = "openai" } }});
    try std.testing.expectError(ValidationError.MissingRequiredAttribute, validateStartAttributes(test_schema, "request", &.{}));
    try std.testing.expectError(ValidationError.DisallowedAttributeValue, validateStartAttributes(test_schema, "request", &.{.{ .name = "provider", .value = .{ .string = "other" } }}));
    try std.testing.expectError(ValidationError.UnknownAttribute, validateStartAttributes(test_schema, "request", &.{
        .{ .name = "provider", .value = .{ .string = "openai" } },
        .{ .name = "extra", .value = .{ .boolean = true } },
    }));
    try validateEventAttributes(test_schema, "request", "retry", &.{.{ .name = "attempt", .value = .{ .number = 2 } }});
    try std.testing.expect(try parentAllowed(test_schema, "tool", "request"));
    try std.testing.expect(!(try parentAllowed(test_schema, "tool", null)));
}
