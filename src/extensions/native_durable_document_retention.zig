//! VM boundary for Source's document-retention setting. Cache ownership, observer
//! pinning and Session-line eviction use the native index in durable/ separately.
const std = @import("std");
const engine_mod = @import("engine.zig");
const retention = @import("../durable/document_retention.zig");
const Engine = engine_mod.Engine;
const c = engine_mod.c;

/// Match typeof value === "number" && value >= 0. In particular, neither
/// boxed numbers nor arbitrary ToPrimitive methods are consulted.
pub fn duration(engine: *Engine, value: c.JSValue) f64 {
    if (!c.JS_IsNumber(value)) return retention.default_ms;
    var number: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &number, value) < 0) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    return retention.duration(number);
}

/// The Harness reads only settings.documentRetentionMs at each cache use.
/// Getter failures select the default without entering Engine.checked, which
/// would replace the operation's captured exception/diagnostic with a cache
/// bookkeeping failure. Call on the VM owner after capturing any original cause.
pub fn readSettings(engine: *Engine, options: c.JSValue) f64 {
    const settings = c.JS_GetPropertyStr(engine.context, options, "settings");
    if (c.JS_IsException(settings)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    defer engine.freeValue(settings);
    if (c.JS_IsUndefined(settings) or c.JS_IsNull(settings)) return retention.default_ms;
    const selected = c.JS_GetPropertyStr(engine.context, settings, "documentRetentionMs");
    if (c.JS_IsException(selected)) {
        engine.freeValue(c.JS_GetException(engine.context));
        return retention.default_ms;
    }
    defer engine.freeValue(selected);
    return duration(engine, selected);
}

test "native document retention reads exact numeric types without coercion" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const values = try engine.eval("globalThis.coercions=0;[undefined,NaN,-1,'0',0,1,Infinity,-Infinity,null,new Number(0),{valueOf(){coercions++;return 0}}]", "retention-values.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(values);
    const expected = [_]f64{ 600_000, 600_000, 600_000, 600_000, 0, 1, std.math.inf(f64), 600_000, 600_000, 600_000, 600_000 };
    for (expected, 0..) |want, index| {
        const value = try engine.checked(c.JS_GetPropertyUint32(engine.context, values, @intCast(index)));
        defer engine.freeValue(value);
        try std.testing.expectEqual(want, duration(engine, value));
    }
    const result = try engine.eval("if(coercions!==0)throw Error('retention coerced user value')", "retention-coercions.js", c.JS_EVAL_TYPE_GLOBAL);
    engine.freeValue(result);
}

test "native document retention reads current settings and contains getter failures" {
    const engine = try Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    const options = try engine.eval("globalThis.retentionValues={value:Infinity,reads:0,failOptions:false,failField:false};({get settings(){retentionValues.reads++;if(retentionValues.failOptions)throw {options:true};return {get documentRetentionMs(){if(retentionValues.failField)throw {field:true};return retentionValues.value}}}})", "retention-settings.js", c.JS_EVAL_TYPE_GLOBAL);
    defer engine.freeValue(options);
    try std.testing.expectEqual(std.math.inf(f64), readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.value=0", "retention-change.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(@as(f64, 0), readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.failOptions=true", "retention-options-throw.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(retention.default_ms, readSettings(engine, options));
    engine.freeValue(try engine.eval("retentionValues.failOptions=false;retentionValues.failField=true", "retention-field-throw.js", c.JS_EVAL_TYPE_GLOBAL));
    try std.testing.expectEqual(retention.default_ms, readSettings(engine, options));
    engine.freeValue(try engine.eval("if(retentionValues.reads!==4)throw Error('settings not read once at each use')", "retention-settings-count.js", c.JS_EVAL_TYPE_GLOBAL));
}
