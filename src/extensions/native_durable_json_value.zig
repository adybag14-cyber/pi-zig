//! Owner-only native JSON DTO construction, without formatting and reparsing
//! ordinary data through temporary host-allocator buffers.
const std = @import("std");
const em = @import("engine.zig");
const json = @import("../durable/backend/json.zig");
const js = @import("native_js_values.zig");
const c = em.c;

/// Special/deep data uses the complete existing serializer/parser path. This
/// is a fast-path bound, not a new limit or a change in error ordering.
pub fn eligible(value: json.Value, depth: usize) bool {
    if (depth > 128) return false;
    return switch (value) {
        .null, .bool, .integer => true,
        .float => |number| std.math.isFinite(number),
        .number_string => false,
        .string => |string| std.unicode.utf8ValidateSlice(string),
        .array => |array| blk: {
            if (array.items.len > std.math.maxInt(u32)) break :blk false;
            for (array.items) |item| if (!eligible(item, depth + 1)) break :blk false;
            break :blk true;
        },
        .object => |object| blk: {
            var iterator = object.iterator();
            while (iterator.next()) |item| if (!std.unicode.utf8ValidateSlice(item.key_ptr.*) or !eligible(item.value_ptr.*, depth + 1)) break :blk false;
            break :blk true;
        },
    };
}
pub fn build(engine: *em.Engine, value: json.Value) anyerror!c.JSValue {
    return switch (value) {
        .null => c.pi_js_null(),
        .bool => |boolean| c.pi_js_bool(engine.context, @intFromBool(boolean)),
        .integer => |integer| c.JS_NewInt64(engine.context, integer),
        // The existing JSON serializer maps both zeros to positive zero.
        .float => |number| c.JS_NewFloat64(engine.context, if (number == 0) @as(f64, 0) else number),
        .string => |string| engine.checked(c.JS_NewStringLen(engine.context, string.ptr, string.len)),
        .array => |array| blk: {
            const object = try engine.checked(c.JS_NewArray(engine.context));
            errdefer engine.freeValue(object);
            for (array.items, 0..) |item, index| {
                const child = try build(engine, item);
                // JSON.parse creates own data properties; inherited setters
                // must never intercept array elements or object keys.
                if (c.JS_DefinePropertyValueUint32(engine.context, object, @intCast(index), child, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            }
            break :blk object;
        },
        .object => |record| blk: {
            const object = try engine.checked(c.JS_NewObject(engine.context));
            errdefer engine.freeValue(object);
            var iterator = record.iterator();
            while (iterator.next()) |item| {
                const atom = c.JS_NewAtomLen(engine.context, item.key_ptr.*.ptr, item.key_ptr.*.len);
                if (atom == c.JS_ATOM_NULL) return js.capture(engine);
                defer c.JS_FreeAtom(engine.context, atom);
                const child = try build(engine, item.value_ptr.*);
                if (c.JS_DefinePropertyValue(engine.context, object, atom, child, c.JS_PROP_C_W_E) < 0) return js.capture(engine);
            }
            break :blk object;
        },
        .number_string => error.RawNumberRequiresJSONParser,
    };
}
