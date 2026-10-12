//! Draft: native internal CodeMode model tools, over the actual api.models
//! service. Script-supplied addresses/headers never select provider credentials.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const awaiting = @import("native_durable_await.zig");
const c = em.c;
const classifier_shape = "{ state: { ... }, images?: [{ type: \"image\", data: <base64>, mimeType }], questions: { <id>: { type: \"choice\", instructions, criteria: { <label>: <meaning> } } | { type: \"score\", instructions, criteria: [<lowest level>, ..., <highest level>] } | { type: \"bool\", instructions, criteria: { true: <meaning>, false: <meaning> } } } }";
const image_shape = "{ input: [{ type: \"text\", text: <prompt> }, ...optional { type: \"image\", data: <base64>, mimeType } references] }";
fn item(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn record(value: c.JSValue) bool {
    return c.JS_IsObject(value) and !c.JS_IsNull(value) and !c.JS_IsArray(value);
}
fn concat(scope: *Scope, parts: []const c.JSValue) !c.JSValue {
    var result = try scope.text("");
    for (parts) |part| result = try scope.concat(result, part);
    return result;
}
fn fail(scope: *Scope, message: c.JSValue) anyerror {
    const reason = js.builtin(scope.engine, "Error", &.{message}) catch |err| return err;
    _ = scope.engine.checked(c.JS_Throw(scope.engine.context, reason)) catch |err| return err;
    unreachable;
}
fn describe(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (c.JS_IsUndefined(value) or c.JS_IsNull(value)) return scope.stringify(value);
    if (c.JS_IsArray(value)) return scope.text(if (try vm.length(scope.engine, value) == 0) "an empty array" else "an array");
    if (c.JS_IsFunction(scope.engine.context, value)) return scope.text("a function");
    if (c.JS_IsObject(value)) {
        const keys = try scope.invoke(try scope.global("Object"), "keys", &.{value});
        const count = try vm.length(scope.engine, keys);
        if (count == 0) return scope.text("{}");
        return concat(scope, &.{ try scope.text("{ "), try scope.invoke(try scope.invoke(keys, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), c.JS_NewInt32(scope.engine.context, 6) }), "join", &.{try scope.text(", ")}), try scope.text(if (count > 6) ", ... }" else " }") });
    }
    return scope.text(if (c.JS_IsString(value)) "a string" else if (c.JS_IsBool(value)) "a boolean" else if (c.JS_IsNumber(value)) "a number" else if (c.JS_IsBigInt(value)) "a bigint" else "a symbol");
}
fn article(scope: *Scope, kind: []const u8) !c.JSValue {
    return scope.text(if (kind[0] == 'i') "an image" else if (kind[0] == 'c' and kind.len == 4) "a chat" else "a classifier");
}
fn resolveModel(scope: *Scope, images: bool, model: c.JSValue, models: c.JSValue) !c.JSValue {
    const kind = if (images) "image" else "classifier";
    const name = if (images) "models.generateImages" else "models.classify";
    const hint = try concat(scope, &.{ try scope.text("List the "), try scope.text(kind), try scope.text(" models you can use with models.getAvailableOfType(\""), try scope.text(kind), try scope.text("\").") });
    if (!record(model) or c.JS_IsFunction(scope.engine.context, model) or !c.JS_IsString(try scope.get(model, "provider")) or !c.JS_IsString(try scope.get(model, "id"))) return fail(scope, try concat(scope, &.{ try scope.text(name), try scope.text("() expects "), try article(scope, kind), try scope.text(" model as its first argument, got "), try describe(scope, model), try scope.text(if (c.JS_IsUndefined(model) or c.JS_IsNull(model)) ". models.getModelOfType() returns undefined for an unknown provider or id. " else ". "), hint }));
    const provider = try scope.get(model, "provider");
    const id = try scope.get(model, "id");
    const resolved = try scope.invoke(models, "getModelOfType", &.{ try scope.text(kind), provider, id });
    if (!c.JS_IsUndefined(resolved)) return resolved;
    inline for (.{ "chat", "image", "classifier" }) |other| if (!@import("std").mem.eql(u8, kind, other)) {
        if (!c.JS_IsUndefined(try scope.invoke(models, "getModelOfType", &.{ try scope.text(other), provider, id }))) return fail(scope, try concat(scope, &.{ try scope.text("\""), provider, try scope.text("/"), id, try scope.text("\" is "), try article(scope, other), try scope.text(" model, not "), try article(scope, kind), try scope.text(" model. "), hint }));
    };
    return fail(scope, try concat(scope, &.{ try scope.text("Unknown "), try scope.text(kind), try scope.text(" model \""), provider, try scope.text("/"), id, try scope.text("\". "), hint }));
}
fn invalid(scope: *Scope, images: bool, problem: c.JSValue) anyerror {
    return fail(scope, concat(scope, &.{ scope.text(if (images) "models.generateImages() " else "models.classify() ") catch |err| return err, problem, scope.text(". Expected context: ") catch |err| return err, scope.text(if (images) image_shape else classifier_shape) catch |err| return err, scope.text(".") catch |err| return err }) catch |err| return err);
}
fn imageBlock(scope: *Scope, value: c.JSValue) !bool {
    return record(value) and !c.JS_IsFunction(scope.engine.context, value) and try is(scope, try scope.get(value, "type"), "image") and c.JS_IsString(try scope.get(value, "data")) and c.JS_IsString(try scope.get(value, "mimeType"));
}
fn strings(scope: *Scope, array: c.JSValue) !bool {
    const length = try vm.length(scope.engine, array);
    if (length == 0) return false;
    for (0..length) |i| if (!c.JS_IsString(try item(scope, array, i))) return false;
    return true;
}
fn checkedContext(scope: *Scope, images: bool, context: c.JSValue) !c.JSValue {
    if (!record(context) or c.JS_IsFunction(scope.engine.context, context)) return invalid(scope, images, try concat(scope, &.{ try scope.text("expects a context object as its second argument, got "), try describe(scope, context) }));
    if (images) {
        const input = try scope.get(context, "input");
        if (!c.JS_IsArray(input) or try vm.length(scope.engine, input) == 0) return invalid(scope, true, try concat(scope, &.{ try scope.text("context.input must be a non-empty array of blocks, got "), try describe(scope, input) }));
        for (0..try vm.length(scope.engine, input)) |i| {
            const block = try item(scope, input, i);
            if (record(block) and try is(scope, try scope.get(block, "type"), "text") and c.JS_IsString(try scope.get(block, "text"))) continue;
            if (try imageBlock(scope, block)) continue;
            return invalid(scope, true, try concat(scope, &.{ try scope.text("context.input["), c.JS_NewFloat64(scope.engine.context, @floatFromInt(i)), try scope.text("] must be a text or image block, got "), try describe(scope, block) }));
        }
        return context;
    }
    const state = try scope.get(context, "state");
    if (!record(state) or c.JS_IsFunction(scope.engine.context, state)) return invalid(scope, false, try concat(scope, &.{ try scope.text("context.state must be an object, got "), try describe(scope, state) }));
    const pictures = try scope.get(context, "images");
    if (!c.JS_IsUndefined(pictures)) {
        if (!c.JS_IsArray(pictures)) return invalid(scope, false, try concat(scope, &.{ try scope.text("context.images must be an array, got "), try describe(scope, pictures) }));
        for (0..try vm.length(scope.engine, pictures)) |i| if (!try imageBlock(scope, try item(scope, pictures, i))) return invalid(scope, false, try concat(scope, &.{ try scope.text("context.images["), c.JS_NewFloat64(scope.engine.context, @floatFromInt(i)), try scope.text("] must be an image block, got "), try describe(scope, try item(scope, pictures, i)) }));
    }
    const questions = try scope.get(context, "questions");
    const object = try scope.global("Object");
    if (!record(questions) or c.JS_IsFunction(scope.engine.context, questions) or try vm.length(scope.engine, try scope.invoke(object, "keys", &.{questions})) == 0) return invalid(scope, false, try concat(scope, &.{ try scope.text("context.questions must map question IDs to questions, got "), try describe(scope, questions) }));
    const entries = try scope.invoke(object, "entries", &.{questions});
    for (0..try vm.length(scope.engine, entries)) |i| {
        const pair = try item(scope, entries, i);
        const at = try scope.concat(try scope.text("context.questions."), try item(scope, pair, 0));
        const question = try item(scope, pair, 1);
        if (!record(question) or c.JS_IsFunction(scope.engine.context, question)) return invalid(scope, false, try concat(scope, &.{ at, try scope.text(" must be a question object, got "), try describe(scope, question) }));
        if (!c.JS_IsString(try scope.get(question, "instructions"))) return invalid(scope, false, try scope.concat(at, try scope.text(".instructions must be a string")));
        const criteria = try scope.get(question, "criteria");
        const kind = try scope.get(question, "type");
        if (try is(scope, kind, "choice")) {
            if (!record(criteria) or c.JS_IsFunction(scope.engine.context, criteria) or !try strings(scope, try scope.invoke(object, "values", &.{criteria}))) return invalid(scope, false, try scope.concat(at, try scope.text(" is a \"choice\" question, so criteria must map each label to its meaning")));
        } else if (try is(scope, kind, "score")) {
            if (!c.JS_IsArray(criteria) or !try strings(scope, criteria)) return invalid(scope, false, try scope.concat(at, try scope.text(" is a \"score\" question, so criteria must list the levels as strings, lowest first")));
        } else if (try is(scope, kind, "bool")) {
            if (!record(criteria) or c.JS_IsFunction(scope.engine.context, criteria) or !c.JS_IsString(try scope.get(criteria, "true")) or !c.JS_IsString(try scope.get(criteria, "false"))) return invalid(scope, false, try scope.concat(at, try scope.text(" is a \"bool\" question, so criteria must be { true: string, false: string }")));
        } else return invalid(scope, false, try concat(scope, &.{ at, try scope.text(".type must be \"choice\", \"score\", or \"bool\", got "), try scope.invoke(try scope.global("JSON"), "stringify", &.{kind}) }));
    }
    return context;
}
/// metadata is the exact Source createModelTools() JSON data; docs supplies the
/// invocation module's retained Promise intrinsics.
pub fn create(engine: *em.Engine, exports: c.JSValue, docs: c.JSValue, metadata: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const tools = try scope.array();
    for (0..2) |i| {
        const definition = try scope.own(try js.spread(engine, try item(&scope, metadata, i)));
        var captures = [_]c.JSValue{docs};
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, execute, "execute", 3, @intCast(i), captures.len, &captures)));
        try scope.put(definition, "execute", callback);
        _ = try scope.invoke(tools, "push", &.{try scope.invoke(exports, "defineTool", &.{definition})});
    }
    return c.JS_DupValue(engine.context, tools);
}
fn execute(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, magic: c_int, captures: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return begin(engine, captures[0], magic == 1, args[0..@intCast(argc)]) catch |err| @import("native_durable.zig").rejectedPromise(engine, err);
}
fn begin(engine: *em.Engine, docs: c.JSValue, images: bool, args: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const api = args[1];
    const context = args[2];
    const selected = try resolveModel(&scope, images, try scope.get(args[0], "model"), try scope.get(api, "models"));
    const checked = try checkedContext(&scope, images, try scope.get(args[0], "context"));
    const state = try scope.object();
    try scope.put(state, "docs", docs);
    try scope.put(state, "model", selected);
    try scope.put(state, "images", c.pi_js_bool(engine.context, @intFromBool(images)));
    const options = try scope.object();
    if (!c.JS_IsUndefined(try scope.get(context, "abortSignal"))) try scope.put(options, "signal", try scope.get(context, "abortSignal"));
    const pending = try scope.invoke(try scope.get(api, "models"), if (images) "generateImages" else "classify", &.{ selected, checked, options });
    var captured: awaiting.Intrinsics = .{ .constructor = try scope.get(docs, "promiseConstructor"), .resolve = try scope.get(docs, "promiseResolve"), .then_function = try scope.get(docs, "promiseThen") };
    return awaiting.continueWith(done, engine, &captured, state, pending, 0);
}
fn done(engine: *em.Engine, state: c.JSValue, value: c.JSValue, rejected: bool, _: c_int) anyerror!c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = try scope.get(state, "model");
    const reason = try scope.get(value, "stopReason");
    const ok = try is(&scope, reason, "stop");
    const label = try concat(&scope, &.{ try scope.text(if (scope.truthy(try scope.get(state, "images"))) "generateImages " else "classify "), try scope.get(model, "provider"), try scope.text("/"), try scope.get(model, "id") });
    var message = try scope.concat(label, try scope.text(" done"));
    if (!ok) {
        var error_message = try scope.get(value, "errorMessage");
        if (c.JS_IsUndefined(error_message) or c.JS_IsNull(error_message)) error_message = try scope.text("");
        message = try concat(&scope, &.{ label, try scope.text(" "), reason, try scope.text(": "), error_message });
    }
    const result = try scope.object();
    const output = try scope.array();
    const text = try scope.object();
    try scope.put(text, "type", try scope.text("text"));
    try scope.put(text, "text", message);
    _ = try scope.invoke(output, "push", &.{text});
    try scope.put(result, "output", output);
    const json = try scope.global("JSON");
    try scope.put(result, "structuredOutput", try scope.invoke(json, "parse", &.{try scope.invoke(json, "stringify", &.{value})}));
    if (!ok) try scope.put(result, "isError", c.pi_js_bool(engine.context, 1));
    const usage = try scope.get(value, "usage");
    if (!c.JS_IsUndefined(usage)) try scope.put(result, "usage", usage);
    return c.JS_DupValue(engine.context, result);
}
