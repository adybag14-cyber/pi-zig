//! The Source VisualLinePreview algorithm, using the actual native Text renderer.
//! Private tool-renderer dependency; no session or public SDK activation.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;
const module_name = "pi-native:tool-visual-line-preview";

fn tui(scope: *Scope) !c.JSValue {
    try @import("native_tui.zig").install(scope.engine);
    return scope.engine.native_module_values.get("@earendil-works/pi-tui").?;
}
fn component(scope: *Scope, text: c.JSValue, padding: c.JSValue) !c.JSValue {
    const text_type = try scope.get(try tui(scope), "Text");
    var args = [_]c.JSValue{ text, padding, c.JS_NewInt32(scope.engine.context, 0) };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, text_type, args.len, &args)));
}
pub fn truncate(scope: *Scope, text: c.JSValue, maximum: c.JSValue, width: c.JSValue, padding: c.JSValue, keep: c.JSValue) !c.JSValue {
    const result = try scope.object();
    if (!scope.truthy(text)) {
        try scope.put(result, "visualLines", try scope.array());
        try scope.put(result, "skippedCount", c.JS_NewInt32(scope.engine.context, 0));
        return result;
    }
    const temporary = try component(scope, text, padding);
    const lines = try scope.invoke(temporary, "render", &.{width});
    const length = try scope.get(lines, "length");
    const fits = try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 5, length, maximum)));
    if (scope.truthy(fits)) {
        try scope.put(result, "visualLines", lines);
        try scope.put(result, "skippedCount", c.JS_NewInt32(scope.engine.context, 0));
    } else {
        const slice = try scope.get(lines, "slice");
        const start = scope.equal(keep, try scope.text("start"));
        const selected = if (start)
            try scope.call(slice, lines, &.{ c.JS_NewInt32(scope.engine.context, 0), maximum })
        else
            try scope.call(slice, lines, &.{try negate(scope, maximum)});
        try scope.put(result, "visualLines", selected);
        try scope.put(result, "skippedCount", try scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 1, length, maximum))));
    }
    return result;
}
fn render(engine: *em.Engine, receiver: c.JSValue, width: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (c.JS_IsUndefined(try scope.get(receiver, "cachedLines")) or !scope.equal(try scope.get(receiver, "cachedWidth"), width)) {
        const options = try scope.get(receiver, "options");
        const text = try scope.get(options, "text");
        const maximum = try scope.get(options, "maxVisualLines");
        const keep = try scope.get(options, "keep");
        const hint_function = try scope.get(options, "formatHint");
        const preview = try truncate(&scope, text, maximum, width, c.JS_NewInt32(engine.context, 0), keep);
        const lines = try scope.get(preview, "visualLines");
        if (try scope.positive(try scope.get(preview, "skippedCount"))) {
            const truncate_function = try scope.get(try tui(&scope), "truncateToWidth");
            const hint = try scope.call(truncate_function, c.pi_js_undefined(), &.{ try scope.call(hint_function, c.pi_js_undefined(), &.{try scope.get(preview, "skippedCount")}), width, try scope.text("...") });
            const spread = try scope.own(try @import("native_sdk_transcript_replay.zig").arraySpread(engine, lines, null));
            if (scope.equal(keep, try scope.text("start"))) {
                try scope.index(spread, try sdk.length(engine, spread), hint);
                try scope.set(receiver, "cachedLines", spread);
            } else {
                const combined = try scope.array();
                try scope.index(combined, 0, hint);
                for (0..try sdk.length(engine, spread)) |index| {
                    const item = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, spread, @intCast(index))));
                    try scope.index(combined, @intCast(index + 1), item);
                }
                try scope.set(receiver, "cachedLines", combined);
            }
        } else try scope.set(receiver, "cachedLines", lines);
        try scope.set(receiver, "cachedWidth", width);
    }
    return c.JS_DupValue(engine.context, try scope.get(receiver, "cachedLines"));
}
fn negate(scope: *Scope, value: c.JSValue) !c.JSValue {
    const numeric = try scope.own(try scope.engine.checked(c.JS_PiToNumeric(scope.engine.context, value)));
    const minus_one = if (c.JS_IsBigInt(numeric)) try scope.own(try scope.engine.checked(c.JS_NewBigInt64(scope.engine.context, -1))) else c.JS_NewInt32(scope.engine.context, -1);
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, 2, numeric, minus_one)));
}
fn method(context: ?*c.JSContext, receiver: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    if (magic == 0) return render(engine, receiver, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    scope.set(receiver, "cachedWidth", c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    scope.set(receiver, "cachedLines", c.pi_js_undefined()) catch |err| return sdk.fail(engine, err);
    return c.pi_js_undefined();
}
fn construct(context: ?*c.JSContext, target: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return instance(engine, target, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn instance(engine: *em.Engine, target: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.own(try engine.checked(c.JS_NewObjectProto(engine.context, try scope.get(target, "prototype"))));
    try scope.put(result, "options", c.pi_js_undefined());
    try scope.put(result, "cachedWidth", c.pi_js_undefined());
    try scope.put(result, "cachedLines", c.pi_js_undefined());
    try scope.set(result, "options", options);
    return c.JS_DupValue(engine.context, result);
}
pub fn constructor(engine: *em.Engine) !c.JSValue {
    if (!engine.native_module_values.contains(module_name)) {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const exports = try scope.object();
        const prototype = try scope.object();
        const preview_type = try scope.own(try engine.checked(c.JS_NewCFunction2(engine.context, construct, "VisualLinePreview", 1, c.JS_CFUNC_constructor, 0)));
        if (c.JS_SetConstructor(engine.context, preview_type, prototype) < 0) return js.capture(engine);
        inline for (.{ "render", "invalidate" }, 0..) |name, index| {
            const function = try engine.checked(c.pi_js_function_magic(engine.context, method, name, if (index == 0) 1 else 0, @intCast(index)));
            if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
        }
        try scope.put(exports, "VisualLinePreview", preview_type);
        try engine.registerValueModule(module_name, exports);
    }
    return sdk.get(engine, engine.native_module_values.get(module_name).?, "VisualLinePreview");
}
pub fn create(engine: *em.Engine, options: c.JSValue) !c.JSValue {
    const selected = try constructor(engine);
    defer engine.freeValue(selected);
    var args = [_]c.JSValue{options};
    return engine.checked(c.JS_CallConstructor(engine.context, selected, args.len, &args));
}
