//! Actual normalizeBuildSystemPromptOptions field order, copies and callbacks.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const roots = @import("native_sdk_prompt_scope.zig");
const Scope = roots.Scope;
const c = em.c;
extern "c" fn JS_GetIteratorSymbol(context: ?*c.JSContext) c.JSValue;
fn copyCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return copyItem(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), magic) catch |err| sdk.fail(engine, err);
}
fn copyItem(engine: *em.Engine, item: c.JSValue, magic: c_int) !c.JSValue {
    if (magic == 0) return js.spread(engine, item);
    const symbol = try engine.checked(JS_GetIteratorSymbol(engine.context));
    defer engine.freeValue(symbol);
    const pair = try js.pair(engine, item, symbol);
    defer for (pair) |value| engine.freeValue(value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.array();
    try scope.index(result, 0, pair[0]);
    try scope.index(result, 1, try scope.own(try replay.arraySpread(engine, pair[1], null)));
    return c.JS_DupValue(engine.context, result);
}
fn defaultTools(scope: *Scope) !c.JSValue {
    const array = try scope.array();
    inline for (.{ "read", "bash", "edit", "write" }, 0..) |name, index| try scope.index(array, index, try scope.text(name));
    return array;
}
fn spreadCollection(scope: *Scope, input: c.JSValue, name: [*:0]const u8, defaults: bool) !c.JSValue {
    const source = try scope.get(input, name);
    const rows = if (roots.nullish(source)) if (defaults) try defaultTools(scope) else try scope.array() else source;
    return scope.own(try replay.arraySpread(scope.engine, rows, null));
}
fn spreadObject(scope: *Scope, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const raw = try scope.get(input, name);
    return scope.own(try js.spread(scope.engine, if (roots.nullish(raw)) try scope.object() else raw));
}
fn mapCopy(scope: *Scope, input: c.JSValue, name: [*:0]const u8) !c.JSValue {
    const raw = try scope.get(input, name);
    const source = if (roots.nullish(raw)) try scope.array() else raw;
    const map = try scope.get(source, "map");
    const mapper = try scope.own(try scope.engine.checked(c.pi_js_function_magic(scope.engine.context, copyCall, "", 1, 0)));
    return scope.call(map, source, &.{mapper});
}
fn guidelines(scope: *Scope, input: c.JSValue) !c.JSValue {
    // The outer fromEntries callee is evaluated before the nested entries
    // callee and before input.toolGuidelines, exactly as the original expression.
    const outer_object = try scope.global("Object");
    const from_entries = try scope.get(outer_object, "fromEntries");
    const inner_object = try scope.global("Object");
    const entries = try scope.get(inner_object, "entries");
    const raw = try scope.get(input, "toolGuidelines");
    const pairs = try scope.call(entries, inner_object, &.{if (roots.nullish(raw)) try scope.object() else raw});
    const map = try scope.get(pairs, "map");
    const mapper = try scope.own(try scope.engine.checked(c.pi_js_function_magic(scope.engine.context, copyCall, "", 1, 1)));
    const copied = try scope.call(map, pairs, &.{mapper});
    return scope.call(from_entries, outer_object, &.{copied});
}
pub fn normalize(engine: *em.Engine, input: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    try scope.put(result, "customPrompt", try scope.get(input, "customPrompt"));
    try scope.put(result, "forceSystemPrompt", try scope.get(input, "forceSystemPrompt"));
    try scope.put(result, "selectedTools", try spreadCollection(&scope, input, "selectedTools", true));
    try scope.put(result, "hiddenTools", try spreadCollection(&scope, input, "hiddenTools", false));
    try scope.put(result, "toolSnippets", try spreadObject(&scope, input, "toolSnippets"));
    try scope.put(result, "toolGuidelines", try guidelines(&scope, input));
    try scope.put(result, "promptGuidelines", try spreadCollection(&scope, input, "promptGuidelines", false));
    const append = try scope.get(input, "appendSystemPrompt");
    try scope.put(result, "appendSystemPrompt", if (roots.nullish(append)) try scope.text("") else append);
    try scope.put(result, "sections", try spreadObject(&scope, input, "sections"));
    try scope.put(result, "cwd", try scope.get(input, "cwd"));
    try scope.put(result, "contextFiles", try mapCopy(&scope, input, "contextFiles"));
    try scope.put(result, "skills", try mapCopy(&scope, input, "skills"));
    return c.JS_DupValue(engine.context, result);
}
