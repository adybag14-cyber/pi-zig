//! Actual c268 usage-totals.ts combineUsage. Optional fields are tested and
//! reread independently; every nested cost receiver is a Source temporary.
const h = @import("native_sdk_session_locals.zig");
const v = h.v;
const c = v.c;
const Engine = h.Engine;
const Scope = h.Scope;
const copy = @import("native_sdk_catalog_copy.zig");
const x = @import("native_sdk_catalog_values.zig");

pub fn combine(engine: *Engine, first: c.JSValue, second: c.JSValue) !c.JSValue {
    return h.expression(engine, combineBody, .{ first, second });
}
fn fieldSum(s: *Scope, first: c.JSValue, second: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const left = try v.get(s, first, name);
    return v.duplicate(s, try h.binary(s, .add, left, try v.get(s, second, name)));
}
fn isDefined(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return v.boolean(s, !c.JS_IsUndefined(try v.get(s, value, name)));
}
fn defined(engine: *Engine, value: c.JSValue, name: [*:0]const u8) !bool {
    return h.truthy(engine, try h.expression(engine, isDefined, .{ value, name }));
}
fn fieldOrZero(s: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const field = try v.get(s, value, name);
    return v.duplicate(s, if (v.nullish(field)) v.number(s, 0) else field);
}
fn optionalSum(s: *Scope, first: c.JSValue, second: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const left = try v.own(s, try h.expression(s.engine, fieldOrZero, .{ first, name }));
    const right = try v.own(s, try h.expression(s.engine, fieldOrZero, .{ second, name }));
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn optionalObject(s: *Scope, first: c.JSValue, second: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const present = try defined(s.engine, first, name) or try defined(s.engine, second, name);
    const result = try v.object(s);
    if (present) try v.put(s, result, name, try v.own(s, try h.expression(s.engine, optionalSum, .{ first, second, name })));
    return v.duplicate(s, result);
}
fn spreadOptional(s: *Scope, target: c.JSValue, first: c.JSValue, second: c.JSValue, name: [*:0]const u8) !void {
    const fields = try v.own(s, try h.expression(s.engine, optionalObject, .{ first, second, name }));
    var operations: x.Ops = .{ .s = s };
    try copy.into(&operations, target, fields);
}
fn nestedSum(s: *Scope, first: c.JSValue, second: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const left = try v.own(s, try h.nested(s.engine, first, "cost", name));
    const right = try v.own(s, try h.nested(s.engine, second, "cost", name));
    return v.duplicate(s, try h.binary(s, .add, left, right));
}
fn costObject(s: *Scope, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |name|
        try v.put(s, result, name, try v.own(s, try h.expression(s.engine, nestedSum, .{ first, second, @as([*:0]const u8, name) })));
    return v.duplicate(s, result);
}
fn combineBody(s: *Scope, first: c.JSValue, second: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |name|
        try v.put(s, result, name, try v.own(s, try h.expression(s.engine, fieldSum, .{ first, second, @as([*:0]const u8, name) })));
    inline for (.{ "cacheWrite1h", "reasoning" }) |name|
        try h.statement(s.engine, spreadOptional, .{ result, first, second, @as([*:0]const u8, name) });
    try v.put(s, result, "totalTokens", try v.own(s, try h.expression(s.engine, fieldSum, .{ first, second, @as([*:0]const u8, "totalTokens") })));
    try v.put(s, result, "cost", try v.own(s, try h.expression(s.engine, costObject, .{ first, second })));
    return v.duplicate(s, result);
}
