//! Original AgentSession prompt-image normalization using the actual native
//! image processor. Unsupported images become hints, as in upstream Source.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const processor = try @import("native_sdk_image_process.zig").create(engine);
    defer engine.freeValue(processor);
    var roots = [_]c.JSValue{processor};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, "_normalizePromptImages", 1, 0, roots.len, &roots));
    defer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "_normalizePromptImages", c.JS_DupValue(engine.context, function), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}
fn call(context: ?*c.JSContext, session: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, session, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, session: c.JSValue, images: c.JSValue, processor: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, session);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, images, processor) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn initial(engine: *em.Engine, owner: c.JSValue, images: c.JSValue, processor: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try scope.put(owner, "images", try scope.array());
    try scope.put(owner, "hints", try scope.array());
    if (!scope.truthy(images)) return finish(engine, owner);
    try scope.put(owner, "processor", processor);
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    const method = try scope.own(try js.getKey(engine, images, symbol));
    const iterator = try scope.call(method, images, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(engine, "Iterator is not an object");
    try scope.put(owner, "iterator", iterator);
    try scope.put(owner, "next", try scope.get(iterator, "next"));
    try advance(engine, owner);
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const iterator = try scope.get(owner, "iterator");
    const next = try scope.call(try scope.get(owner, "next"), iterator, &.{});
    if (!c.JS_IsObject(next)) return js.typeError(engine, "Iterator result is not an object");
    if (scope.truthy(try scope.get(next, "done"))) return finish(engine, owner);
    const image = try scope.get(next, "value");
    body(&scope, owner, image) catch |err| try rejectAndClose(engine, owner, err);
}
fn body(scope: *Scope, owner: c.JSValue, image: c.JSValue) !void {
    const engine = scope.engine;
    const processor = try scope.get(owner, "processor");
    const buffer = try scope.global("Buffer");
    const from = try scope.get(buffer, "from");
    const bytes = try scope.call(from, buffer, &.{ try scope.get(image, "data"), try scope.text("base64") });
    const mime = try scope.get(image, "mimeType");
    const session = try scope.get(owner, "agent");
    const options = try scope.object();
    try scope.put(options, "autoResizeImages", try scope.invoke(try scope.get(session, "settingsManager"), "getImageAutoResize", &.{}));
    const model = try scope.invoke(session, "_limitsModel", &.{});
    const limits = if (temp.nullish(model)) c.pi_js_undefined() else try scope.get(model, "inputLimits");
    const images = if (temp.nullish(limits)) c.pi_js_undefined() else try scope.get(limits, "images");
    const resize = if (temp.nullish(images)) c.pi_js_undefined() else try scope.get(images, "resize");
    try scope.put(options, "resizeOptions", resize);
    const pending = try scope.call(processor, c.pi_js_undefined(), &.{ bytes, mime, options });
    try flow.wait(processed, engine, owner, pending, 0);
}
fn processed(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return closeWithReason(engine, owner, value);
    consume(engine, owner, value) catch |err| return rejectAndClose(engine, owner, err);
    try advance(engine, owner);
}
fn consume(engine: *em.Engine, owner: c.JSValue, processed_image: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const hints = try scope.get(owner, "hints");
    if (!scope.truthy(try scope.get(processed_image, "ok"))) {
        const push = try scope.get(hints, "push");
        _ = try scope.call(push, hints, &.{try scope.get(processed_image, "message")});
        return;
    }
    const images = try scope.get(owner, "images");
    const push_image = try scope.get(images, "push");
    const image = try scope.object();
    try scope.put(image, "type", try scope.text("image"));
    try scope.put(image, "data", try scope.get(processed_image, "data"));
    try scope.put(image, "mimeType", try scope.get(processed_image, "mimeType"));
    _ = try scope.call(push_image, images, &.{image});
    const push_hints = try scope.get(hints, "push");
    const source_hints = try scope.get(processed_image, "hints");
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    const collected = try scope.own(try js.collect(engine, source_hints, symbol));
    const count = try sdk.length(engine, collected);
    const arguments = try engine.gpa.alloc(c.JSValue, count);
    defer engine.gpa.free(arguments);
    for (arguments, 0..) |*argument, index| argument.* = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, collected, @intCast(index))));
    _ = try scope.call(push_hints, hints, arguments);
}
fn finish(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "images", try scope.get(owner, "images"));
    try scope.put(result, "hints", try scope.get(owner, "hints"));
    try flow.settle(engine, owner, false, result);
}
fn rejectAndClose(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    try closeWithReason(engine, owner, reason);
}
fn closeWithReason(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    close(engine, owner) catch |err| {
        if (err == error.OutOfMemory) return err;
        if (err == error.JavaScriptException) {
            _ = engine.throwCaptured();
            const ignored = c.JS_GetException(engine.context);
            defer engine.freeValue(ignored);
            if (engine.native_allocation_exception) |fatal| {
                if (c.JS_IsStrictEqual(engine.context, ignored, fatal)) _ = try engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, fatal)));
            }
        } else return err;
    };
    try flow.settle(engine, owner, true, reason);
}
fn close(engine: *em.Engine, owner: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const iterator = try scope.get(owner, "iterator");
    const method = try scope.get(iterator, "return");
    if (!temp.nullish(method)) _ = try scope.call(method, iterator, &.{});
}
