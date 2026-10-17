//! Direct controls of the actual used load/finally boundary, not a fake Module
//! bootstrap or namespace. Cache records are controlled genuine VM values.
const std = @import("std");
const v = @import("native_ai_provider_values.zig");
const c = v.c;
const load = @import("native_node_commonjs_load.zig");
const lexical = @import("native_node_commonjs_state.zig");
fn fresh(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    return v.em.Engine.fromContext(context.?).throwNativeOutOfMemory();
}
fn saved(context: ?*c.JSContext, _: c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const global = c.JS_GetGlobalObject(context);
    defer c.JS_FreeValue(context, global);
    const reason = c.JS_GetPropertyStr(context, global, "ownedLoadReason");
    if (c.JS_IsException(reason)) return reason;
    return c.JS_Throw(context, reason);
}
const Mode = enum { fresh_call, fresh_getter, historical, lookalike, ordinary };
fn subject(mode: Mode) !void {
    const engine = try v.em.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    var s: v.Scope = .{ .engine = engine }; defer s.deinit();
    // Match the production ordinary callable's suppression of diagnostic
    // coercion while the actual private boundary runs.
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    defer if (engine.captured_exception) |reason| c.JS_ClearUncatchableError(engine.context, reason);
    const global = try s.own(try engine.checked(c.JS_GetGlobalObject(engine.context)));
    try s.put(global, "ownedFreshLoad", try s.own(try engine.checked(c.JS_NewCFunction(engine.context, fresh, "ownedFreshLoad", 0))));
    try s.put(global, "ownedSavedLoad", try s.own(try engine.checked(c.JS_NewCFunction(engine.context, saved, "ownedSavedLoad", 0))));
    _ = try s.own(try engine.eval(
        "globalThis.cleanupCalls=[];globalThis.cleanupReason=Object.freeze({cleanup:true});" ++
        "globalThis.cleanupStage='cache';globalThis.ownedLoadReason={ordinary:true};" ++
        "globalThis.ownedModule={load:ownedSavedLoad};globalThis.ownedChildren=[ownedModule];" ++
        "globalThis.ownedParent={get children(){cleanupCalls.push('children');if(cleanupStage==='children')throw cleanupReason;return ownedChildren}};" ++
        "globalThis.ownedCache=new Proxy({owned:ownedModule},{deleteProperty(target,key){cleanupCalls.push('delete');if(cleanupStage==='cache')throw cleanupReason;return Reflect.deleteProperty(target,key)}});" ++
        "globalThis.fixtureCacheOwner={get _cache(){cleanupCalls.push('cache');return ownedCache}};" ++
        "globalThis.ownedRelative=Object.assign(Object.create(null),{relative:'owned'});",
        "commonjs-load-boundary-fixture.js", c.JS_EVAL_TYPE_GLOBAL));
    switch (mode) {
        .fresh_call => _ = try s.own(try engine.eval("ownedModule.load=ownedFreshLoad", "commonjs-fresh-call.js", c.JS_EVAL_TYPE_GLOBAL)),
        .fresh_getter => _ = try s.own(try engine.eval("Object.defineProperty(ownedModule,'load',{get(){return ownedFreshLoad()}})", "commonjs-fresh-getter.js", c.JS_EVAL_TYPE_GLOBAL)),
        .historical => {
            _ = engine.throwNativeOutOfMemory();
            const old = try s.own(c.JS_GetException(engine.context));
            c.JS_ClearUncatchableError(engine.context, old);
            try s.put(global, "ownedLoadReason", old);
            _ = try s.own(try engine.eval("cleanupStage='children'", "commonjs-old-tag.js", c.JS_EVAL_TYPE_GLOBAL));
        },
        .lookalike => _ = try s.own(try engine.eval("ownedLoadReason=Object.assign(new Error('out of memory'),{name:'InternalError',code:'OutOfMemory',native_allocation_generation:1})", "commonjs-lookalike.js", c.JS_EVAL_TYPE_GLOBAL)),
        .ordinary => _ = try s.own(try engine.eval("cleanupStage='none'", "commonjs-ordinary.js", c.JS_EVAL_TYPE_GLOBAL)),
    }
    const roots = try s.own(try engine.checked(c.JS_NewObjectProto(engine.context, c.pi_js_null())));
    // This explicitly controlled cache owner is not presented as Module or a
    // production binding. Only the actual load/finally helper is the subject.
    try s.put(roots, "module_constructor", try s.get(global, "fixtureCacheOwner"));
    try s.put(roots, "relativeResolveCache", try s.get(global, "ownedRelative"));
    const array = try s.global("Array");
    try s.put(roots, "loadArrayIsArray", try s.get(array, "isArray"));
    const prototype = try s.get(array, "prototype");
    try s.put(roots, "loadArrayIndexOf", try s.get(prototype, "indexOf"));
    try s.put(roots, "loadArraySplice", try s.get(prototype, "splice"));
    const owner = try s.own(try lexical.create(engine, roots));
    const state = try lexical.known(engine, owner);
    const before = engine.native_allocation_generation;
    try std.testing.expectError(error.JavaScriptException, load.loadWithCleanup(engine, state, try s.get(global, "ownedModule"), try s.get(global, "ownedParent"), try s.text("owned"), try s.text("relative")));
    const actual = engine.captured_exception orelse return error.MissingBoundaryReason;
    if (mode == .fresh_call or mode == .fresh_getter) {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, engine.native_allocation_exception.?));
        try std.testing.expect(c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(before +% 1, engine.native_allocation_generation);
        const untouched = try s.own(try engine.eval("cleanupCalls.length===0&&ownedChildren.length===1&&Object.hasOwn(ownedCache,'owned')&&Object.hasOwn(ownedRelative,'relative')", "commonjs-fatal-no-cleanup.js", c.JS_EVAL_TYPE_GLOBAL));
        try std.testing.expect(c.JS_ToBool(engine.context, untouched) == 1);
    } else if (mode == .ordinary) {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, try s.get(global, "ownedLoadReason")));
        try std.testing.expectEqual(before, engine.native_allocation_generation);
        const cleaned = try s.own(try engine.eval("cleanupCalls.join(',')==='cache,delete,children'&&ownedChildren.length===0&&!Object.hasOwn(ownedCache,'owned')&&!Object.hasOwn(ownedRelative,'relative')", "commonjs-ordinary-cleanup.js", c.JS_EVAL_TYPE_GLOBAL));
        try std.testing.expect(c.JS_ToBool(engine.context, cleaned) == 1);
    } else {
        try std.testing.expect(c.JS_IsStrictEqual(engine.context, actual, try s.get(global, "cleanupReason")));
        try std.testing.expect(!c.JS_IsUncatchableError(actual));
        try std.testing.expectEqual(before, engine.native_allocation_generation);
        const observed = try s.own(try engine.eval(if (mode == .historical) "cleanupCalls.join(',')==='cache,delete,children'" else "cleanupCalls.join(',')==='cache,delete'", "commonjs-ordinary-precedence.js", c.JS_EVAL_TYPE_GLOBAL));
        try std.testing.expect(c.JS_ToBool(engine.context, observed) == 1);
    }
}
test "CommonJS load failure fresh private native reason skips guest cache and children cleanup" { try subject(.fresh_call); }
test "CommonJS load failure fresh private reason from load getter skips guest cleanup" { try subject(.fresh_getter); }
test "CommonJS load failure historical private reason follows ordinary finally precedence" { try subject(.historical); }
test "CommonJS load failure guest lookalike follows ordinary finally precedence" { try subject(.lookalike); }
test "CommonJS load failure ordinary raw reason survives successful cache and children cleanup" { try subject(.ordinary); }
