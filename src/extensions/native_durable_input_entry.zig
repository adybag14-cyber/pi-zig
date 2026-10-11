//! Shared actual upstream input-entry placement and display-only write rules.
const engine_mod = @import("engine.zig");
const vm = @import("native_values.zig");
const js = @import("native_js_values.zig");
const c = engine_mod.c;
const Engine = engine_mod.Engine;

fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try @import("native_tool_info.zig").putData(engine, object, key, c.JS_DupValue(engine.context, value));
}
pub fn check(engine: *Engine, entry: c.JSValue) !void {
    const kind = try vm.get(engine, entry, "kind");
    defer engine.freeValue(kind);
    var invalid = !c.JS_IsString(kind);
    if (!invalid) {
        invalid = try vm.length(engine, kind) == 0;
        if (!invalid) {
            const prefix = try engine.checked(c.JS_NewString(engine.context, "pi."));
            defer engine.freeValue(prefix);
            const starts = try vm.invoke(engine, kind, "startsWith", &.{prefix});
            defer engine.freeValue(starts);
            invalid = c.JS_ToBool(engine.context, starts) != 0;
        }
    }
    if (!invalid) return;
    const global = c.JS_GetGlobalObject(engine.context);
    defer engine.freeValue(global);
    // A new expression resolves its constructor before evaluating arguments.
    const constructor = try vm.get(engine, global, "TypeError");
    defer engine.freeValue(constructor);
    const stringify = try vm.get(engine, global, "String");
    defer engine.freeValue(stringify);
    var values = [_]c.JSValue{kind};
    const rendered = try engine.checked(c.JS_Call(engine.context, stringify, c.pi_js_undefined(), 1, &values));
    defer engine.freeValue(rendered);
    const prefix = try engine.checked(c.JS_NewString(engine.context, "An input entry's kind must be a non-empty string not starting with \"pi.\", got "));
    defer engine.freeValue(prefix);
    const message = try @import("native_utf16.zig").concat(engine, &.{ prefix, rendered });
    defer engine.freeValue(message);
    var args = [_]c.JSValue{message};
    const exception = try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, &args));
    _ = try engine.checked(c.JS_Throw(engine.context, exception));
}
pub fn pick(engine: *Engine, entry: c.JSValue) !c.JSValue {
    const kind = try vm.get(engine, entry, "kind");
    defer engine.freeValue(kind);
    const data = try vm.get(engine, entry, "data");
    defer engine.freeValue(data);
    const selected = try vm.object(engine);
    defer engine.freeValue(selected);
    try put(engine, selected, "kind", kind);
    if (!c.JS_IsUndefined(data)) try put(engine, selected, "data", data);
    const options = try vm.object(engine);
    defer engine.freeValue(options);
    try put(engine, options, "omitUndefinedProperties", c.pi_js_bool(engine.context, 1));
    return @import("native_chord_json.zig").copyJson(engine, selected, options);
}
pub fn append(engine: *Engine, tx: c.JSValue, conversation: c.JSValue, content: c.JSValue, entry: c.JSValue, now: c.JSValue, user: c.JSValue) !c.JSValue {
    const message = try vm.object(engine);
    defer engine.freeValue(message);
    const role = try engine.checked(c.JS_NewString(engine.context, "user"));
    defer engine.freeValue(role);
    try put(engine, message, "role", role);
    try put(engine, message, "content", content);
    try put(engine, message, "timestamp", now);
    const model = try vm.array(engine);
    defer engine.freeValue(model);
    try js.push(engine, model, message);
    const draft = if (c.JS_IsUndefined(entry)) try vm.object(engine) else try pick(engine, entry);
    defer engine.freeValue(draft);
    try put(engine, draft, "model", model);
    return vm.invoke(engine, tx, "appendEntry", if (c.JS_IsUndefined(entry)) &.{ user, conversation, draft } else &.{ conversation, draft });
}
pub fn displayOnly(engine: *Engine, entry: c.JSValue) !bool {
    inline for (.{ "model", "head", "edits" }) |name| {
        const value = try vm.get(engine, entry, name);
        defer engine.freeValue(value);
        if (!c.JS_IsUndefined(value)) return false;
    }
    return true;
}
pub fn queuedReset(engine: *Engine, items: c.JSValue) !bool {
    const callback = try engine.checked(c.JS_NewCFunction(engine.context, resetPredicate, "", 1));
    defer engine.freeValue(callback);
    const result = try vm.invoke(engine, items, "some", &.{callback});
    defer engine.freeValue(result);
    return c.JS_ToBool(engine.context, result) != 0;
}
fn resetPredicate(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return resetItem(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| @import("native_durable.zig").reject(engine, err);
}
fn resetItem(engine: *Engine, item: c.JSValue) !c.JSValue {
    const mode = try vm.get(engine, item, "mode");
    defer engine.freeValue(mode);
    const write = try engine.checked(c.JS_NewString(engine.context, "write"));
    defer engine.freeValue(write);
    if (!c.JS_IsStrictEqual(engine.context, mode, write)) return c.pi_js_bool(engine.context, 0);
    const entry = try vm.get(engine, item, "entry");
    defer engine.freeValue(entry);
    const head = try vm.get(engine, entry, "head");
    defer engine.freeValue(head);
    const self = try engine.checked(c.JS_NewString(engine.context, "self"));
    defer engine.freeValue(self);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, head, self)));
}
