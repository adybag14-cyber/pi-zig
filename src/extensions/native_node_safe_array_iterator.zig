// Copyright Joyent, Inc. and other Node contributors. MIT; retained Node LICENSE.
//! The genuine primordials SafeArrayIterator class. The existing complete
//! createSafeIterator producer receives actual early-bound Array iterator and
//! next functions, never guest-replaced globals or a substitute iterator.
const a = @import("native_node_argument_values.zig");
const collections = @import("native_node_fs_collections.zig");
const publication = @import("native_node_fs_private_publication.zig");
const c = a.c;
const key = "\x00native.internal.SafeArrayIterator";

/// One real frozen SafeIterator class per Engine, shared by its native modules.
pub fn acquire(engine: *a.v.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_module_values.get(key)) |known| return a.duplicate(engine, known);
    const candidate = try a.expression(engine, createBody, .{});
    if (engine.native_module_values.get(key)) |known| {
        var completion = a.owned.Completion.initValue(engine, a.duplicate(engine, known));
        completion.release(candidate);
        return completion.finishValue();
    }
    return publication.publish(engine, key, candidate);
}
fn createBody(s: *a.Scope) !c.JSValue {
    const captured = s.engine.intrinsic_clone_operations;
    const factory = try s.get(captured, "Array.iterate.uncurried");
    const next = try s.get(captured, "Array.next.uncurried");
    const symbol = try s.get(captured, "Symbol.iterator");
    if (!c.JS_IsFunction(s.engine.context, factory) or
        !c.JS_IsFunction(s.engine.context, next) or !c.JS_IsSymbol(symbol))
        return error.RequiredPristineActualArrayIteratorFunctions;
    return collections.createSafeIterator(s.engine, factory, next, symbol);
}
