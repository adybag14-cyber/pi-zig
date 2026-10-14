//! Original UUIDv7 algorithm using live guest globals and VM numeric operators.
//! One private owner represents one module instance's timestamp and sequence.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const math = @import("native_image_arithmetic.zig");
const c = em.c;
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    try scope.put(owner, "lastOrdinaryTimestamp", c.JS_NewInt32(engine.context, -1));
    try scope.put(owner, "sequence", c.pi_js_undefined());
    return @import("native_node_function.zig").create(engine, "uuidv7", 1, dispatch, &.{owner});
}
fn dispatch(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return generate(engine, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined());
}
fn bigint(scope: *Scope, value: u64) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, value)));
}
fn binary(scope: *Scope, operation: math.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try math.binary(scope.engine, operation, left, right));
}
fn convert(scope: *Scope, name: [*:0]const u8, value: c.JSValue) !c.JSValue {
    return scope.call(try scope.global(name), c.pi_js_undefined(), &.{value});
}
fn getByte(scope: *Scope, bytes: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, bytes, index)));
}
fn setByte(scope: *Scope, bytes: c.JSValue, index: u32, value: c.JSValue) !void {
    if (c.JS_SetPropertyUint32(scope.engine.context, bytes, index, c.JS_DupValue(scope.engine.context, value)) < 0) return js.capture(scope.engine);
}
fn failRange(scope: *Scope, message: []const u8) !c.JSValue {
    const constructor = try scope.global("RangeError");
    var args = [_]c.JSValue{try scope.text(message)};
    const reason = try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, args.len, &args));
    _ = c.JS_Throw(scope.engine.context, reason);
    return js.capture(scope.engine);
}
fn hexByte(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return encodeByte(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn encodeByte(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const text = try scope.invoke(value, "toString", &.{c.JS_NewInt32(engine.context, 16)});
    const pad = try scope.get(text, "padStart");
    return js.call(engine, pad, text, &.{ c.JS_NewInt32(engine.context, 2), try scope.text("0") });
}
fn generate(engine: *em.Engine, owner: c.JSValue, supplied: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const requested = if (c.JS_IsNull(supplied) or c.JS_IsUndefined(supplied)) try scope.invoke(try scope.global("Date"), "now", &.{}) else supplied;
    const max_timestamp = c.JS_NewInt64(engine.context, 0xffffffffffff);
    if (!scope.truthy(try scope.invoke(try scope.global("Number"), "isInteger", &.{requested})) or
        try math.compare(engine, .less, requested, c.JS_NewInt32(engine.context, 0)) or
        try math.compare(engine, .greater, requested, max_timestamp))
        return failRange(&scope, "UUIDv7 timestamp must be an integer between 0 and 281474976710655");
    const timestamp_value = if (c.JS_IsUndefined(supplied)) try scope.invoke(try scope.global("Math"), "max", &.{ requested, try scope.get(owner, "lastOrdinaryTimestamp") }) else supplied;
    if (c.JS_IsUndefined(supplied)) try scope.set(owner, "lastOrdinaryTimestamp", timestamp_value);
    var args = [_]c.JSValue{c.JS_NewInt32(engine.context, 16)};
    const bytes = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, try scope.global("Uint8Array"), args.len, &args)));
    _ = try scope.invoke(try scope.get(try scope.global("globalThis"), "crypto"), "getRandomValues", &.{bytes});
    const previous = try scope.get(owner, "sequence");
    const sequence = if (c.JS_IsUndefined(previous)) initial: {
        var value = c.pi_js_undefined();
        inline for (.{ 32, 24, 16, 8, 0 }, 1..) |shift, index| {
            // Resolve the mutable BigInt function before reading the byte.
            const function = try scope.global("BigInt");
            const number = try getByte(&scope, bytes, index);
            const part = try scope.call(function, c.pi_js_undefined(), &.{number});
            const shifted = if (shift == 0) part else try binary(&scope, .shift_left, part, try bigint(&scope, shift));
            value = if (index == 1) shifted else try binary(&scope, .bit_or, value, shifted);
        }
        break :initial value;
    } else increment: {
        if (scope.equal(previous, try bigint(&scope, (1 << 41) - 1))) return failRange(&scope, "UUIDv7 generator sequence exhausted");
        break :increment try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, previous)));
    };
    try scope.set(owner, "sequence", sequence);
    const timestamp = try convert(&scope, "BigInt", timestamp_value);
    var index: u32 = 6;
    while (index > 0) {
        index -= 1;
        const number_function = try scope.global("Number");
        const count = try convert(&scope, "BigInt", c.JS_NewInt32(engine.context, @intCast((5 - index) * 8)));
        const shifted = try binary(&scope, .shift_right, timestamp, count);
        const number = try scope.call(number_function, c.pi_js_undefined(), &.{shifted});
        try setByte(&scope, bytes, index, try binary(&scope, .bit_and, number, c.JS_NewInt32(engine.context, 255)));
    }
    inline for (.{ .{ 6, 37, 15, 112 }, .{ 7, 29, 255, 0 }, .{ 8, 23, 63, 128 }, .{ 9, 15, 255, 0 }, .{ 10, 7, 255, 0 } }) |item| {
        const number_function = try scope.global("Number");
        const shifted = try binary(&scope, .shift_right, sequence, try bigint(&scope, item[1]));
        const masked = try binary(&scope, .bit_and, shifted, try bigint(&scope, item[2]));
        const number = try scope.call(number_function, c.pi_js_undefined(), &.{masked});
        const encoded = if (item[3] == 0) number else try binary(&scope, .bit_or, c.JS_NewInt32(engine.context, item[3]), number);
        try setByte(&scope, bytes, item[0], encoded);
    }
    const number_function = try scope.global("Number");
    const low = try binary(&scope, .shift_left, try binary(&scope, .bit_and, sequence, try bigint(&scope, 127)), try bigint(&scope, 1));
    const number = try scope.call(number_function, c.pi_js_undefined(), &.{low});
    const random_bit = try binary(&scope, .bit_and, try getByte(&scope, bytes, 11), c.JS_NewInt32(engine.context, 1));
    try setByte(&scope, bytes, 11, try binary(&scope, .bit_or, number, random_bit));
    const array = try scope.global("Array");
    const from = try scope.get(array, "from");
    const callback = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, hexByte, "", 1)));
    const hex = try scope.call(from, array, &.{ bytes, callback });
    var result = try scope.text("");
    inline for (.{ .{ 0, 4 }, .{ 4, 6 }, .{ 6, 8 }, .{ 8, 10 }, .{ 10, -1 } }, 0..) |range, group| {
        if (group > 0) result = try scope.concat(result, try scope.text("-"));
        const slice = try scope.get(hex, "slice");
        const part = if (range[1] == -1) try scope.call(slice, hex, &.{c.JS_NewInt32(engine.context, range[0])}) else try scope.call(slice, hex, &.{ c.JS_NewInt32(engine.context, range[0]), c.JS_NewInt32(engine.context, range[1]) });
        const joined = try scope.invoke(part, "join", &.{try scope.text("")});
        result = try scope.concat(result, try scope.stringify(joined));
    }
    return c.JS_DupValue(engine.context, result);
}
