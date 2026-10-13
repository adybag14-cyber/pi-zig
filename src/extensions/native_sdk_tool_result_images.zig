//! Original async tool-result image loop with live getters, iterator closing,
//! and unchanged-array identity when processing did not modify any block.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn create(engine: *em.Engine) !c.JSValue {
    const processor = try @import("native_sdk_image_process.zig").create(engine);
    defer engine.freeValue(processor);
    var roots = [_]c.JSValue{processor};
    const function = try engine.checked(c.JS_NewCFunctionData2(engine.context, call, "normalizeToolResultImages", 2, 0, roots.len, &roots));
    errdefer engine.freeValue(function);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, function, parent) < 0) return js.capture(engine);
    return function;
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn call(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, if (argc > 0) args[0..@intCast(argc)] else &.{}, roots[0]) catch |err| sdk.fail(engine, err);
}
fn begin(engine: *em.Engine, args: []const c.JSValue, processor: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, c.pi_js_undefined());
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    initial(engine, pending.owner, args, processor) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn option(scope: *Scope, options: c.JSValue, key: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(options)) c.pi_js_undefined() else scope.get(options, key);
}
fn initial(engine: *em.Engine, owner: c.JSValue, args: []const c.JSValue, processor: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const content = arg(args, 0);
    const some = try scope.get(content, "some");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, isImage, "", 1)));
    if (!scope.truthy(try scope.call(some, content, &.{predicate}))) return flow.settle(engine, owner, false, content);
    const options = arg(args, 1);
    const automatic = try option(&scope, options, "autoResizeImages");
    try scope.put(owner, "automatic", if (temp.nullish(automatic)) c.pi_js_bool(engine.context, 1) else automatic);
    try scope.put(owner, "content", content);
    try scope.put(owner, "options", options);
    try scope.put(owner, "processor", processor);
    try scope.put(owner, "normalized", try scope.array());
    try scope.put(owner, "changed", c.pi_js_bool(engine.context, 0));
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    const method = try scope.own(try js.getKey(engine, content, symbol));
    const iterator = try scope.call(method, content, &.{});
    if (!c.JS_IsObject(iterator)) return js.typeError(engine, "Iterator is not an object");
    try scope.put(owner, "iterator", iterator);
    try scope.put(owner, "next", try scope.get(iterator, "next"));
    try advance(engine, owner);
}
fn isImage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = scope.get(if (argc > 0) args[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err);
    const image = scope.text("image") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(kind, image)));
}
fn advance(engine: *em.Engine, owner: c.JSValue) !void {
    while (true) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const iterator = try scope.get(owner, "iterator");
        const result = try scope.call(try scope.get(owner, "next"), iterator, &.{});
        if (!c.JS_IsObject(result)) return js.typeError(engine, "Iterator result is not an object");
        if (scope.truthy(try scope.get(result, "done"))) {
            const changed = scope.truthy(try scope.get(owner, "changed"));
            return flow.settle(engine, owner, false, try scope.get(owner, if (changed) "normalized" else "content"));
        }
        const block = try scope.get(result, "value");
        const awaiting = body(&scope, owner, block) catch |err| return rejectAndClose(engine, owner, err);
        if (awaiting) return;
    }
}
fn body(scope: *Scope, owner: c.JSValue, block: c.JSValue) !bool {
    if (!scope.equal(try scope.get(block, "type"), try scope.text("image"))) {
        _ = try scope.invoke(try scope.get(owner, "normalized"), "push", &.{block});
        return false;
    }
    try scope.put(owner, "block", block);
    const processor = try scope.get(owner, "processor");
    const buffer = try scope.global("Buffer");
    const from = try scope.get(buffer, "from");
    const bytes = try scope.call(from, buffer, &.{ try scope.get(block, "data"), try scope.text("base64") });
    const mime = try scope.get(block, "mimeType");
    const options = try scope.object();
    try scope.put(options, "autoResizeImages", try scope.get(owner, "automatic"));
    try scope.put(options, "resizeOptions", try option(scope, try scope.get(owner, "options"), "resizeOptions"));
    const promise = try scope.call(processor, c.pi_js_undefined(), &.{ bytes, mime, options });
    try flow.wait(processed, scope.engine, owner, promise, 0);
    return true;
}
fn processed(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    if (rejected) return closeWithReason(engine, owner, value);
    consume(engine, owner, value) catch |err| return rejectAndClose(engine, owner, err);
    try advance(engine, owner);
}
fn consume(engine: *em.Engine, owner: c.JSValue, processed_value: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const block = try scope.get(owner, "block");
    const normalized = try scope.get(owner, "normalized");
    if (!scope.truthy(try scope.get(processed_value, "ok")) or
        (scope.equal(try scope.get(processed_value, "data"), try scope.get(block, "data")) and
            scope.equal(try scope.get(processed_value, "mimeType"), try scope.get(block, "mimeType")) and
            scope.equal(try scope.get(try scope.get(processed_value, "hints"), "length"), c.JS_NewInt32(engine.context, 0))))
    {
        _ = try scope.invoke(normalized, "push", &.{block});
        return;
    }
    const image = try scope.object();
    try scope.put(image, "type", try scope.text("image"));
    try scope.put(image, "data", try scope.get(processed_value, "data"));
    try scope.put(image, "mimeType", try scope.get(processed_value, "mimeType"));
    _ = try scope.invoke(normalized, "push", &.{image});
    const hints = try scope.get(processed_value, "hints");
    if (try scope.positive(try scope.get(hints, "length"))) {
        const text = try scope.object();
        try scope.put(text, "type", try scope.text("text"));
        try scope.put(text, "text", try scope.invoke(try scope.get(processed_value, "hints"), "join", &.{try scope.text("\n")}));
        _ = try scope.invoke(normalized, "push", &.{text});
    }
    try scope.set(owner, "changed", c.pi_js_bool(engine.context, 1));
}
fn rejectAndClose(engine: *em.Engine, owner: c.JSValue, err: anyerror) !void {
    const reason = flow.reason(engine, err);
    defer engine.freeValue(reason);
    try closeWithReason(engine, owner, reason);
}
fn closeWithReason(engine: *em.Engine, owner: c.JSValue, reason: c.JSValue) !void {
    // IteratorClose preserves an existing thrown completion, even when return
    // itself throws. Native allocator failures retain their fatal provenance.
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
