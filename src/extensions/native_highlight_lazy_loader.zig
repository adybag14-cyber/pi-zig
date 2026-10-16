//! Actual Source cached Promise/setImmediate/import settlement control flow.
//! The private importer executes the complete real native191 index.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_highlight_scope.zig").Scope;
const ordinary = @import("native_node_function.zig");
const c = em.c;
const Kind = enum(c_int) { executor, immediate, settle };
fn callback(s: *Scope, kind: Kind, roots: []const c.JSValue, length: c_int) !c.JSValue {
    return s.own(try s.engine.checked(c.JS_NewCFunctionData2(s.engine.context, dispatch, "", length, @intFromEnum(kind), @intCast(roots.len), @constCast(roots.ptr))));
}
fn dispatch(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return run(engine, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined(), roots) catch |err| sdk.fail(engine, err);
}
fn run(engine: *em.Engine, kind: Kind, first: c.JSValue, roots: [*c]c.JSValue) !c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    switch (kind) {
        .executor => {
            const immediate = try s.global("setImmediate");
            const task = try callback(&s, .immediate, &.{ roots[0], first }, 0);
            _ = try s.call(immediate, c.pi_js_undefined(), &.{task});
        },
        .immediate => {
            const pending = try s.call(roots[0], c.pi_js_undefined(), &.{});
            const then = try s.get(pending, "then");
            const yes = try callback(&s, .settle, &.{roots[1]}, 0);
            const no = try callback(&s, .settle, &.{roots[1]}, 0);
            _ = try s.call(then, pending, &.{ yes, no });
        },
        .settle => _ = try s.call(roots[0], c.pi_js_undefined(), &.{}),
    }
    return c.pi_js_undefined();
}
fn load(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) anyerror!c.JSValue {
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = roots[0];
    var pending = try s.get(state, "allLanguagesPromise");
    if (!s.truthy(pending)) {
        const promise = try s.global("Promise");
        const executor = try callback(&s, .executor, &.{try s.get(state, "nativeImport")}, 1);
        var args = [_]c.JSValue{executor};
        pending = try s.own(try engine.checked(c.JS_CallConstructor(engine.context, promise, args.len, &args)));
        try s.set(state, "allLanguagesPromise", pending);
    }
    return c.JS_DupValue(engine.context, pending);
}
pub fn create(engine: *em.Engine, native_import: c.JSValue) !c.JSValue {
    if (!c.JS_IsFunction(engine.context, native_import)) return error.NativeFullGrammarImportRequired;
    var s: Scope = .{ .engine = engine };
    defer s.deinit();
    const state = try s.object();
    try s.put(state, "allLanguagesPromise", c.pi_js_undefined());
    try s.put(state, "nativeImport", native_import);
    return ordinary.create(engine, "loadAllHighlightLanguages", 0, load, &.{state});
}
