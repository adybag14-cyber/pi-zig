//! c268 resolveCliModel: actual public ordinary body over the live ModelRuntime.
const r = @import("native_sdk_model_reference_live.zig");
const h = @import("native_sdk_session_locals.zig");
const v = r.v;
const c = v.c;
const Scope = v.Scope;
const Frame = h.Frame(enum {
    cli_provider, cli_model, cli_thinking, inline_key, runtime, models, provider,
    result, matches, auth_hint, target, model_id, fallback_thinking, fallback_model, requested_thinking,
});
pub fn resolve(engine: *r.Engine, inputs: r.Inputs, options: c.JSValue) !c.JSValue {
    var frame = Frame.init(engine);
    return frame.finish(source(&frame, inputs, options));
}
fn source(f: *Frame, inputs: r.Inputs, options: c.JSValue) !c.JSValue {
    const e = f.engine;
    try h.statement(e, destructureOptions, .{ f, options });
    if (!h.truthy(e, f.get(.cli_model))) return h.expression(e, emptyResult, .{});
    try f.set(.models, h.expression(e, modelsSnapshot, .{f.get(.runtime)}));
    if (try r.exactLength(e, f.get(.models), 0))
        return h.expression(e, fixedError, .{@as([]const u8, "No models available. Check your installation or add models to models.json.")});
    try f.set(.provider, if (h.truthy(e, f.get(.cli_provider)))
        h.expression(e, findProvider, .{f.get(.models), f.get(.cli_provider)}) else c.pi_js_undefined());
    if (h.truthy(e, f.get(.cli_provider)) and !h.truthy(e, f.get(.provider)))
        return h.expression(e, unknownProvider, .{f.get(.cli_provider)});
    try f.set(.result, h.expression(e, reference, .{inputs, f}));
    if (try h.fieldEqual(e, f.get(.result), "status", "resolved"))
        return h.expression(e, resolvedResult, .{f.get(.result)});
    if (try h.fieldEqual(e, f.get(.result), "status", "ambiguous")) {
        try f.set(.matches, h.expression(e, joinMatches, .{collectionIncoming(e,
            collectionIncoming(e, h.get(e, f.get(.result), "candidates"), "map", .model_label),
            "sort", .ascending)}));
        try f.set(.auth_hint, if (h.truthy(e, f.get(.inline_key)))
            h.text(e, "--api-key does not choose a provider.")
        else if (try zeroUsable(e, f.get(.result)))
            h.text(e, "No matching provider is authenticated.")
        else h.text(e, "More than one matching provider is authenticated."));
        return h.expression(e, ambiguousError, .{f.get(.cli_model), f.get(.matches), f.get(.auth_hint)});
    }
    try f.set(.target, h.get(e, f.get(.result), "target"));
    if (!h.truthy(e, f.get(.target))) return h.expression(e, missingModel, .{f.get(.cli_model)});
    try f.set(.model_id, h.get(e, f.get(.target), if (h.truthy(e, f.get(.cli_thinking))) "modelText" else "modelId"));
    try f.set(.fallback_thinking, if (h.truthy(e, f.get(.cli_thinking))) c.pi_js_undefined() else h.get(e, f.get(.target), "thinkingLevel"));
    try f.set(.fallback_model, h.expression(e, fallback, .{inputs.defaults, f.get(.target), f.get(.model_id)}));
    try f.set(.requested_thinking, h.duplicate(e, if (v.nullish(f.get(.cli_thinking))) f.get(.fallback_thinking) else f.get(.cli_thinking)));
    return h.expression(e, customResult, .{f});
}
fn destructureOptions(s: *Scope, f: *Frame, options: c.JSValue) !void {
    // BindingPattern performs ToObject once. This temporary receiver survives
    // all five ordered getters and retires before the following statement.
    const object = try v.guest.toObject(s, options);
    try f.set(.cli_provider, h.get(s.engine, object, "cliProvider"));
    try f.set(.cli_model, h.get(s.engine, object, "cliModel"));
    try f.set(.cli_thinking, h.get(s.engine, object, "cliThinking"));
    try f.set(.inline_key, h.get(s.engine, object, "inlineApiKey"));
    try f.set(.runtime, h.get(s.engine, object, "modelRuntime"));
}
fn emptyResult(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "model", c.pi_js_undefined());
    try v.put(s, result, "warning", c.pi_js_undefined());
    try v.put(s, result, "error", c.pi_js_undefined());
    return v.duplicate(s, result);
}
fn errorStart(s: *Scope) !c.JSValue {
    const result = try v.object(s);
    try v.put(s, result, "model", c.pi_js_undefined());
    try v.put(s, result, "warning", c.pi_js_undefined());
    return result;
}
fn fixedError(s: *Scope, message: []const u8) !c.JSValue {
    const result = try errorStart(s);
    try v.put(s, result, "error", try v.text(s, message));
    return v.duplicate(s, result);
}
fn modelsSnapshot(s: *Scope, runtime: c.JSValue) !c.JSValue {
    const result = try v.array(s); var position: u32 = 0;
    try r.appendIterable(s.engine, result, v.invokeOwned(s.engine, runtime, "getModels", &.{}), &position);
    return v.duplicate(s, result);
}
fn findProvider(s: *Scope, models: c.JSValue, requested: c.JSValue) !c.JSValue {
    const model = try v.own(s, try r.collection(s.engine, models, "find", .provider_cli, &.{requested}));
    return if (v.nullish(model)) c.pi_js_undefined() else v.duplicate(s, try v.get(s, model, "provider"));
}
fn unknownProvider(s: *Scope, provider: c.JSValue) !c.JSValue {
    const result = try errorStart(s);
    var message = try h.binary(s, .add, try v.text(s, "Unknown provider \""), try v.stringify(s, provider));
    message = try h.binary(s, .add, message, try v.text(s, "\". Use --list-models to see available providers/models."));
    try v.put(s, result, "error", message);
    return v.duplicate(s, result);
}
fn reference(s: *Scope, inputs: r.Inputs, f: *Frame) !c.JSValue {
    const request = try v.object(s);
    try v.put(s, request, "text", f.get(.cli_model));
    try v.put(s, request, "provider", f.get(.provider));
    try v.put(s, request, "thinkingSuffix", try v.text(s, "strict"));
    try v.put(s, request, "fuzzy", v.boolean(s, true));
    const usable = if (h.truthy(s.engine, f.get(.inline_key)))
        try v.arrow(s, "", 0, neverUsable, &.{})
    else try v.arrow(s, "", 1, configured, &.{f.get(.runtime)});
    return r.resolve(s.engine, inputs, request, f.get(.models), usable);
}
fn neverUsable(engine: *r.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.JS_NewBool(engine.context, false);
}
fn configured(engine: *r.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return v.invokeOwned(engine, roots[0], "hasConfiguredAuth", &.{v.arg(args, 0)});
}
fn resolvedResult(s: *Scope, value: c.JSValue) !c.JSValue {
    const result = try v.object(s);
    try r.fieldInto(s.engine, result, "model", value, "model");
    try r.fieldInto(s.engine, result, "thinkingLevel", value, "thinkingLevel");
    try r.fieldInto(s.engine, result, "warning", value, "warning");
    try v.put(s, result, "error", c.pi_js_undefined());
    return v.duplicate(s, result);
}
fn collectionIncoming(engine: *r.Engine, incoming: anyerror!c.JSValue, name: [*:0]const u8, comptime kind: r.Callback) !c.JSValue {
    return h.expression(engine, collectionIncomingBody, .{incoming, name, kind});
}
fn collectionIncomingBody(s: *Scope, incoming: anyerror!c.JSValue, name: [*:0]const u8, comptime kind: r.Callback) !c.JSValue {
    return r.collection(s.engine, try v.own(s, try incoming), name, kind, &.{});
}
fn joinMatches(s: *Scope, incoming: anyerror!c.JSValue) !c.JSValue {
    const receiver = try v.own(s, try incoming);
    const callable = try v.get(s, receiver, "join");
    return v.duplicate(s, try v.call(s, callable, receiver, &.{try v.text(s, ", ")}));
}
fn zeroUsable(engine: *r.Engine, result: c.JSValue) !bool {
    return h.truthy(engine, try h.expression(engine, zeroUsableBody, .{result}));
}
fn zeroUsableBody(s: *Scope, result: c.JSValue) !c.JSValue {
    return v.boolean(s, v.equal(s, try v.get(s, result, "usableCount"), v.number(s, 0)));
}
fn ambiguousError(s: *Scope, model: c.JSValue, matches: c.JSValue, hint: c.JSValue) !c.JSValue {
    const result = try errorStart(s);
    var message = try h.binary(s, .add, try v.text(s, "Model \""), try v.stringify(s, model));
    message = try h.binary(s, .add, message, try v.text(s, "\" is ambiguous across providers: "));
    message = try h.binary(s, .add, message, try v.stringify(s, matches));
    message = try h.binary(s, .add, message, try v.text(s, ". "));
    message = try h.binary(s, .add, message, try v.stringify(s, hint));
    message = try h.binary(s, .add, message, try v.text(s, " Use --provider or provider/model."));
    try v.put(s, result, "error", message);
    return v.duplicate(s, result);
}
fn missingModel(s: *Scope, model: c.JSValue) !c.JSValue {
    const result = try errorStart(s);
    var message = try h.binary(s, .add, try v.text(s, "Model \""), try v.stringify(s, model));
    message = try h.binary(s, .add, message, try v.text(s, "\" not found. Use --list-models to see available models."));
    try v.put(s, result, "error", message);
    return v.duplicate(s, result);
}
fn fallback(s: *Scope, defaults: c.JSValue, target: c.JSValue, id: c.JSValue) !c.JSValue {
    return r.fallback(s.engine, defaults, try v.get(s, target, "providerModels"), id);
}
fn customResult(s: *Scope, f: *Frame) !c.JSValue {
    const result = try v.object(s);
    const requested = f.get(.requested_thinking);
    const model = if (v.truthy(s, requested) and !try v.eq(s, requested, "off"))
        try v.own(s, try h.expression(s.engine, reasoningCopy, .{f.get(.fallback_model)}))
    else f.get(.fallback_model);
    try v.put(s, result, "model", model);
    try v.put(s, result, "thinkingLevel", f.get(.fallback_thinking));
    try h.statement(s.engine, customWarning, .{result, f.get(.model_id), f.get(.target)});
    try v.put(s, result, "error", c.pi_js_undefined());
    return v.duplicate(s, result);
}
fn reasoningCopy(s: *Scope, model: c.JSValue) !c.JSValue {
    const result = try r.copied(s, model);
    try v.put(s, result, "reasoning", v.boolean(s, true));
    return v.duplicate(s, result);
}
fn customWarning(s: *Scope, result: c.JSValue, id: c.JSValue, target: c.JSValue) !void {
    var warning = try h.binary(s, .add, try v.text(s, "Model \""), try v.stringify(s, id));
    warning = try h.binary(s, .add, warning, try v.text(s, "\" not found for provider \""));
    warning = try h.binary(s, .add, warning, try v.own(s, try r.fieldString(s.engine, target, "provider")));
    warning = try h.binary(s, .add, warning, try v.text(s, "\". Using custom model id."));
    try v.put(s, result, "warning", warning);
}
