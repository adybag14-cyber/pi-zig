//! Original public AgentSession user-message normalization and prompt boundary.
//! The receiver's prompt stays live and errors reject the returned Promise.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const flow = @import("native_agent_async.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;

pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, send, "sendUserMessage", 2));
    defer engine.freeValue(callback);
    const parent = try engine.checked(c.JS_GetAsyncFunctionPrototype(engine.context));
    defer engine.freeValue(parent);
    if (c.JS_SetPrototype(engine.context, callback, parent) < 0) return js.capture(engine);
    if (c.JS_DefinePropertyValueStr(engine.context, prototype, "sendUserMessage", c.JS_DupValue(engine.context, callback), c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
}

fn send(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const pending = flow.create(engine, receiver) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(pending.owner);
    begin(engine, pending.owner, receiver, if (argc > 0) argv[0] else c.pi_js_undefined(), if (argc > 1) argv[1] else c.pi_js_undefined()) catch |err| {
        flow.rejectError(engine, pending.owner, err) catch |failure| {
            engine.freeValue(pending.promise);
            return sdk.fail(engine, failure);
        };
    };
    return pending.promise;
}

fn begin(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, content: c.JSValue, options: c.JSValue) !void {
    var scope: temp.Scope = .{ .engine = engine };
    defer scope.deinit();
    var normalized = content;
    var images = c.pi_js_undefined();
    if (!c.JS_IsString(content)) {
        const texts = try scope.array();
        images = try scope.array();
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, content, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        const text_type = try scope.text("text");
        while (try iterator.next()) |part| {
            defer engine.freeValue(part);
            const kind = try sdk.get(engine, part, "type");
            defer engine.freeValue(kind);
            if (scope.equal(kind, text_type)) {
                const value = try sdk.get(engine, part, "text");
                defer engine.freeValue(value);
                _ = try scope.invoke(texts, "push", &.{value});
            } else _ = try scope.invoke(images, "push", &.{part});
        }
        normalized = try scope.invoke(texts, "join", &.{try scope.text("\n")});
        if (!try scope.positive(try scope.get(images, "length"))) images = c.pi_js_undefined();
    }
    // The callee is evaluated before the option getters in the call expression.
    const prompt = try scope.get(receiver, "prompt");
    const arguments = try scope.object();
    const expand = if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "expandPromptTemplates");
    try scope.put(arguments, "expandPromptTemplates", if (temp.nullish(expand)) c.pi_js_bool(engine.context, 0) else expand);
    try scope.put(arguments, "streamingBehavior", if (temp.nullish(options)) c.pi_js_undefined() else try scope.get(options, "deliverAs"));
    try scope.put(arguments, "images", images);
    try scope.put(arguments, "source", try scope.text("extension"));
    const result = try scope.call(prompt, receiver, &.{ normalized, arguments });
    try flow.wait(finish, engine, owner, result, 0);
}

fn finish(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) !void {
    try flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
}
