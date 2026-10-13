//! Actual SDK factory converter wrapper. Settings and collection methods are
//! observed at each call, including replacement and consecutive placeholders.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const disabled = "Image reading is disabled.";

pub fn create(engine: *em.Engine, settings: c.JSValue) !c.JSValue {
    const converter = try @import("native_sdk_messages.zig").create(engine);
    defer engine.freeValue(converter);
    var roots = [_]c.JSValue{ settings, converter };
    return engine.checked(c.JS_NewCFunctionData2(engine.context, convert, "convertToLlmWithBlockImages", 1, 0, roots.len, &roots));
}
fn convert(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return run(engine, roots[0], roots[1], if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn callback(scope: *Scope, comptime function: anytype, length: c_int) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_NewCFunction(scope.engine.context, function, "", length)));
}
fn run(engine: *em.Engine, settings: c.JSValue, converter: c.JSValue, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const converted = try scope.call(converter, c.pi_js_undefined(), &.{messages});
    if (!scope.truthy(try scope.invoke(settings, "getBlockImages", &.{}))) return c.JS_DupValue(engine.context, converted);
    const mapped = try scope.invoke(converted, "map", &.{try callback(&scope, blockMessage, 1)});
    return c.JS_DupValue(engine.context, mapped);
}
fn blockMessage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return block(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn block(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.equal(try scope.get(message, "role"), try scope.text("user")) and !scope.equal(try scope.get(message, "role"), try scope.text("toolResult"))) return c.JS_DupValue(engine.context, message);
    const content = try scope.get(message, "content");
    if (!scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{content}))) return c.JS_DupValue(engine.context, message);
    if (!scope.truthy(try scope.invoke(content, "some", &.{try callback(&scope, isImage, 1)}))) return c.JS_DupValue(engine.context, message);
    const mapped = try scope.invoke(content, "map", &.{try callback(&scope, replaceImage, 1)});
    const filtered = try scope.invoke(mapped, "filter", &.{try callback(&scope, keepBlock, 3)});
    const result = try scope.own(try js.spread(engine, message));
    try scope.put(result, "content", filtered);
    return c.JS_DupValue(engine.context, result);
}
fn isImage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = image(&scope, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(result));
}
fn image(scope: *Scope, value: c.JSValue) !bool {
    return scope.equal(try scope.get(value, "type"), try scope.text("image"));
}
fn replaceImage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return replacement(engine, if (argc > 0) args[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn replacement(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try image(&scope, value)) return c.JS_DupValue(engine.context, value);
    const result = try scope.object();
    try scope.put(result, "type", try scope.text("text"));
    try scope.put(result, "text", try scope.text(disabled));
    return c.JS_DupValue(engine.context, result);
}
fn keepBlock(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const result = keep(engine, if (argc > 0) args[0] else c.pi_js_undefined(), if (argc > 1) args[1] else c.pi_js_undefined(), if (argc > 2) args[2] else c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(context, @intFromBool(result));
}
fn previous(scope: *Scope, array: c.JSValue, index: c.JSValue) !c.JSValue {
    const key = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, index, c.JS_NewInt32(scope.engine.context, 1))));
    return scope.own(try js.getKey(scope.engine, array, key));
}
fn keep(engine: *em.Engine, value: c.JSValue, index: c.JSValue, array: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!scope.equal(try scope.get(value, "type"), try scope.text("text"))) return true;
    if (!scope.equal(try scope.get(value, "text"), try scope.text(disabled))) return true;
    if (!try scope.positive(index)) return true;
    if (!scope.equal(try scope.get(try previous(&scope, array, index), "type"), try scope.text("text"))) return true;
    return !scope.equal(try scope.get(try previous(&scope, array, index), "text"), try scope.text(disabled));
}
