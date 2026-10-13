//! Original ordinary session transcript and extension context utility bodies.
const std = @import("std");
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const Method = enum(c_int) { getLastAssistantText, createReplacedSessionContext, hasExtensionHandlers, getUserMessagesForForking };
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (std.meta.fields(Method)) |field| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, field.name, if (field.value == @intFromEnum(Method.hasExtensionHandlers)) 1 else 0, field.value));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, field.name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return run(engine, session, @enumFromInt(magic), if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn run(engine: *em.Engine, session: c.JSValue, method: Method, argument: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return switch (method) {
        .getLastAssistantText => lastText(&scope, session),
        .createReplacedSessionContext => replaced(&scope, session),
        .hasExtensionHandlers => js.invoke(engine, try scope.get(session, "_extensionRunner"), "hasHandlers", &.{argument}),
        .getUserMessagesForForking => @import("native_sdk_session_queries.zig").forkMessages(&scope, session),
    };
}
fn findAssistant(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return assistant(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn assistant(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const answer = scope.equal(try scope.get(message, "role"), try scope.text("assistant")) and
        !(scope.equal(try scope.get(message, "stopReason"), try scope.text("aborted")) and
            scope.equal(try scope.get(try scope.get(message, "content"), "length"), c.JS_NewInt32(engine.context, 0)));
    return c.pi_js_bool(engine.context, @intFromBool(answer));
}
fn lastText(scope: *Scope, session: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const sliced = try scope.invoke(try scope.get(session, "messages"), "slice", &.{});
    const reversed = try scope.invoke(sliced, "reverse", &.{});
    const find = try scope.get(reversed, "find");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, findAssistant, "", 1)));
    const last = try scope.call(find, reversed, &.{predicate});
    if (!scope.truthy(last)) return c.pi_js_undefined();
    const content = try scope.get(last, "content");
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, content, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var text = try scope.text("");
    while (try iterator.next()) |item| {
        defer engine.freeValue(item);
        if (scope.equal(try scope.get(item, "type"), try scope.text("text"))) text = try scope.concat(text, try scope.get(item, "text"));
    }
    const trimmed = try scope.invoke(text, "trim", &.{});
    return if (scope.truthy(trimmed)) c.JS_DupValue(engine.context, trimmed) else c.pi_js_undefined();
}
fn replaced(scope: *Scope, session: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const object = try scope.global("Object");
    const define = try scope.get(object, "defineProperties");
    const target = try scope.object();
    const descriptor_object = try scope.global("Object");
    const descriptors_function = try scope.get(descriptor_object, "getOwnPropertyDescriptors");
    const context = try scope.invoke(try scope.get(session, "_extensionRunner"), "createCommandContext", &.{});
    const descriptors = try scope.call(descriptors_function, descriptor_object, &.{context});
    const result = try scope.call(define, object, &.{ target, descriptors });
    var roots = [_]c.JSValue{session};
    inline for (.{ "sendMessage", "sendUserMessage" }, 0..) |name, index| {
        const function = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, send, "", 2, index, roots.len, &roots)));
        try scope.set(result, name, function);
    }
    return c.JS_DupValue(engine.context, result);
}
fn send(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return sendValue(engine, roots[0], magic, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn sendValue(engine: *em.Engine, session: c.JSValue, magic: c_int, message: c.JSValue, options: c.JSValue) !c.JSValue {
    return js.invoke(engine, session, if (magic == 0) "sendCustomMessage" else "sendUserMessage", &.{ message, options });
}
