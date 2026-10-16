//! Source spread-call argument construction over real iterators.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn call(scope: *Scope, function: c.JSValue, receiver: c.JSValue, iterable: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var args: std.ArrayList(c.JSValue) = .empty;
    defer {
        for (args.items) |value| engine.freeValue(value);
        args.deinit(engine.gpa);
    }
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var it = try js.Iterator.init(engine, iterable, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |value| {
        args.append(engine.gpa, value) catch |err| {
            engine.freeValue(value);
            return err;
        };
    }
    return scope.call(function, receiver, args.items);
}
pub fn literal(scope: *Scope, target: c.JSValue, iterable: c.JSValue, index: *u32) !void {
    const engine = scope.engine;
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var it = try js.Iterator.init(engine, iterable, symbol);
    defer it.deinit();
    errdefer it.closePreserving();
    while (try it.next()) |value| {
        defer engine.freeValue(value);
        try scope.index(target, index.*, value);
        index.* += 1;
    }
}
