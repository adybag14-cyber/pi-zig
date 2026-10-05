//! Native plain-schema admission: detach, optional-null cleanup and coercion.
const std = @import("std");
const json = @import("../backend/json.zig");
const validator = @import("../../agent/tools.zig");
fn matches(value: json.Value, name: []const u8) bool {
    if (std.mem.eql(u8, name, "number")) return value == .integer or value == .float;
    if (std.mem.eql(u8, name, "integer")) return (value == .integer or value == .float) and @trunc(json.asNumber(value) catch unreachable) == (json.asNumber(value) catch unreachable);
    return (std.mem.eql(u8, name, "string") and value == .string) or (std.mem.eql(u8, name, "boolean") and value == .bool) or (std.mem.eql(u8, name, "object") and value == .object) or (std.mem.eql(u8, name, "array") and value == .array) or (std.mem.eql(u8, name, "null") and value == .null);
}
fn checks(gpa: std.mem.Allocator, schema: json.Value, value: json.Value) !bool {
    if (try validator.validateSchemaValue(gpa, schema, value, "root")) |failure| {
        gpa.free(failure);
        return false;
    }
    return true;
}
fn numericString(gpa: std.mem.Allocator, number: f64) ![]const u8 {
    if (number == 0) return "0";
    const magnitude = @abs(number);
    if (magnitude >= 1e21 or magnitude < 1e-6) {
        const scientific = try std.fmt.allocPrint(gpa, "{e}", .{number});
        const at = std.mem.indexOfScalar(u8, scientific, 'e') orelse return scientific;
        const exponent = try std.fmt.parseInt(i32, scientific[at + 1 ..], 10);
        return std.fmt.allocPrint(gpa, "{s}e{s}{d}", .{ scientific[0..at], if (exponent >= 0) "+" else "", exponent });
    }
    return std.fmt.allocPrint(gpa, "{d}", .{number});
}
fn primitive(gpa: std.mem.Allocator, value: json.Value, name: []const u8) !json.Value {
    if (std.mem.eql(u8, name, "number") or std.mem.eql(u8, name, "integer")) {
        var converted: ?f64 = null;
        if (value == .null) converted = 0 else if (value == .bool) converted = if (value.bool) 1 else 0 else if (value == .string) {
            const trimmed = trimNumber(value.string);
            if (trimmed.len != 0) {
                if (trimmed.len > 2 and trimmed[0] == '0' and std.mem.indexOfScalar(u8, "xXbBoO", trimmed[1]) != null) {
                    const radix: u8 = switch (trimmed[1]) {
                        'x', 'X' => 16,
                        'b', 'B' => 2,
                        else => 8,
                    };
                    if (std.fmt.parseInt(u64, trimmed[2..], radix)) |number| converted = @floatFromInt(number) else |_| {}
                } else converted = std.fmt.parseFloat(f64, trimmed) catch null;
            }
        }
        if (converted) |number| if (std.math.isFinite(number) and (!std.mem.eql(u8, name, "integer") or @trunc(number) == number)) return .{ .float = number };
    } else if (std.mem.eql(u8, name, "boolean")) {
        if (value == .null) return .{ .bool = false };
        if (value == .string) {
            if (std.mem.eql(u8, value.string, "true")) return .{ .bool = true };
            if (std.mem.eql(u8, value.string, "false")) return .{ .bool = false };
        }
        if (value == .integer or value == .float) {
            const number = try json.asNumber(value);
            if (number == 1) return .{ .bool = true };
            if (number == 0) return .{ .bool = false };
        }
    } else if (std.mem.eql(u8, name, "string")) {
        if (value == .null) return .{ .string = "" };
        if (value == .bool) return .{ .string = if (value.bool) "true" else "false" };
        if (value == .integer or value == .float) return .{ .string = try numericString(gpa, try json.asNumber(value)) };
    } else if (std.mem.eql(u8, name, "null")) {
        if ((value == .string and value.string.len == 0) or (value == .bool and !value.bool) or ((value == .float or value == .integer) and (try json.asNumber(value)) == 0)) return .null;
    }
    return value;
}
fn numberSpace(point: u21) bool {
    return switch (point) {
        9...13, 32, 0xa0, 0x1680, 0x2000...0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000, 0xfeff => true,
        else => false,
    };
}
fn trimNumber(input: []const u8) []const u8 {
    var iterator = (std.unicode.Wtf8View.init(input) catch return input).iterator();
    var first: ?usize = null;
    var end: usize = 0;
    var offset: usize = 0;
    while (iterator.nextCodepointSlice()) |bytes| {
        const point = std.unicode.wtf8Decode(bytes) catch return input;
        if (!numberSpace(point)) {
            if (first == null) first = offset;
            end = offset + bytes.len;
        }
        offset += bytes.len;
    }
    return if (first) |start| input[start..end] else "";
}

test "durable schema coercion matches actual locked TypeBox and pi-ai b7df reference" {
    const gpa = std.testing.allocator;
    var fixture = try json.Owned.parse(gpa, @embedFile("../fixtures/session_harness_b7df.json"));
    defer fixture.deinit();
    const schema = try json.required(fixture.value, "schema");
    const cases = try json.required(fixture.value, "coerced");
    for (cases.array.items) |row| {
        var owned = try json.Owned.empty(gpa);
        defer owned.deinit();
        const input = try json.required(row, "input");
        const expected = try json.required(row, "result");
        const converted = try convert(owned.arena.allocator(), schema, input);
        if (!json.equal(converted, expected)) {
            const actual = try json.stringify(gpa, converted);
            defer gpa.free(actual);
            std.debug.print("Schema conversion mismatch {s}\n", .{actual});
            return error.SchemaOracleMismatch;
        }
        try std.testing.expect(try checks(gpa, schema, converted));
    }
}
fn optionalNulls(gpa: std.mem.Allocator, schema: json.Value, value: *json.Value) anyerror!void {
    if (schema != .object) return;
    if (value.* == .array) {
        if (json.get(schema, "items")) |items| {
            for (value.array.items, 0..) |*item, index| {
                if (items == .array) {
                    if (index < items.array.items.len) try optionalNulls(gpa, items.array.items[index], item);
                } else try optionalNulls(gpa, items, item);
            }
        }
        return;
    }
    if (value.* != .object) return;
    const properties = json.get(schema, "properties") orelse return;
    if (properties != .object) return;
    const required = json.get(schema, "required");
    var iterator = properties.object.iterator();
    while (iterator.next()) |item| {
        const child = value.object.getPtr(item.key_ptr.*) orelse continue;
        var needed = false;
        if (required) |list| if (list == .array) for (list.array.items) |name| if (name == .string and std.mem.eql(u8, name.string, item.key_ptr.*)) {
            needed = true;
            break;
        };
        if (child.* == .null and !needed and json.get(item.value_ptr.*, "$ref") == null and !try checks(gpa, item.value_ptr.*, .null)) {
            _ = value.object.orderedRemove(item.key_ptr.*);
        } else try optionalNulls(gpa, item.value_ptr.*, child);
    }
}
fn coerce(gpa: std.mem.Allocator, schema: json.Value, value: json.Value) anyerror!json.Value {
    if (schema != .object) return value;
    var next = value;
    if (json.get(schema, "allOf")) |branches| if (branches == .array) for (branches.array.items) |branch| {
        next = try coerce(gpa, branch, next);
    };
    for ([_][]const u8{ "anyOf", "oneOf" }) |union_name| if (json.get(schema, union_name)) |branches| if (branches == .array) {
        var matched = false;
        for (branches.array.items) |branch| if (try checks(gpa, branch, next)) {
            matched = true;
            break;
        };
        if (!matched) for (branches.array.items) |branch| {
            const candidate = try coerce(gpa, branch, try json.clone(gpa, next));
            if (try checks(gpa, branch, candidate)) {
                next = candidate;
                break;
            }
        };
    };
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(gpa);
    if (json.get(schema, "type")) |type_spec| {
        if (type_spec == .string) try names.append(gpa, type_spec.string) else if (type_spec == .array) for (type_spec.array.items) |name| if (name == .string) try names.append(gpa, name.string);
    }
    var union_match = false;
    if (names.items.len > 1) for (names.items) |name| if (matches(next, name)) {
        union_match = true;
        break;
    };
    if (!union_match) for (names.items) |name| {
        const converted = try primitive(gpa, next, name);
        if (!json.equal(converted, next)) {
            next = converted;
            break;
        }
    };
    var object_type = false;
    var array_type = false;
    for (names.items) |name| {
        object_type = object_type or std.mem.eql(u8, name, "object");
        array_type = array_type or std.mem.eql(u8, name, "array");
    }
    if (object_type and next == .object) {
        const properties = json.get(schema, "properties");
        if (properties) |fields| if (fields == .object) {
            var iterator = fields.object.iterator();
            while (iterator.next()) |field| if (next.object.getPtr(field.key_ptr.*)) |child| {
                child.* = try coerce(gpa, field.value_ptr.*, child.*);
            };
        };
        if (json.get(schema, "additionalProperties")) |additional| if (additional == .object) {
            var iterator = next.object.iterator();
            while (iterator.next()) |entry| {
                if (properties != null and properties.? == .object and properties.?.object.contains(entry.key_ptr.*)) continue;
                entry.value_ptr.* = try coerce(gpa, additional, entry.value_ptr.*);
            }
        };
    }
    if (array_type and next == .array) if (json.get(schema, "items")) |items| for (next.array.items, 0..) |*item, index| {
        if (items == .array) {
            if (index < items.array.items.len) item.* = try coerce(gpa, items.array.items[index], item.*);
        } else if (items == .object) item.* = try coerce(gpa, items, item.*);
    };
    return next;
}
pub fn convert(gpa: std.mem.Allocator, schema: json.Value, input: json.Value) !json.Value {
    var value = try json.clone(gpa, input);
    try optionalNulls(gpa, schema, &value);
    return coerce(gpa, schema, value);
}
/// Reject features the reused native validator does not interpret. Ordinary
/// annotations stay allowed; a schema must never silently become unconstrained.
pub fn supported(schema: json.Value) bool {
    if (schema != .object) return schema == .bool;
    for ([_][]const u8{ "$ref", "$dynamicRef", "if", "then", "else", "not", "contains", "dependentSchemas", "dependentRequired", "unevaluatedProperties", "unevaluatedItems", "uniqueItems", "multipleOf", "format" }) |keyword| if (schema.object.contains(keyword)) return false;
    for ([_][]const u8{ "properties", "patternProperties" }) |keyword| if (json.get(schema, keyword)) |children| if (children == .object) {
        var iterator = children.object.iterator();
        while (iterator.next()) |item| if (!supported(item.value_ptr.*)) return false;
    };
    for ([_][]const u8{ "items", "additionalItems", "additionalProperties", "propertyNames" }) |keyword| if (json.get(schema, keyword)) |child| {
        if (child == .array) {
            for (child.array.items) |item| if (!supported(item)) return false;
        } else if (!supported(child)) return false;
    };
    for ([_][]const u8{ "allOf", "anyOf", "oneOf", "prefixItems" }) |keyword| if (json.get(schema, keyword)) |children| if (children == .array) for (children.array.items) |child| if (!supported(child)) return false;
    return true;
}
