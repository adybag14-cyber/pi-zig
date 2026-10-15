//! Actual Source write.ts cache algorithms. Private, awaiting real grammar engine.
//! Both required callbacks must be supplied by the full native highlight module.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const utils = @import("native_sdk_builtin_render_utils.zig");
const temporary = @import("native_sdk_prompt_scope.zig");
const Scope = temporary.Scope;
const c = em.c;

pub const Highlighter = struct {
    language: *const fn (*em.Engine, c.JSValue) anyerror!c.JSValue,
    highlight: *const fn (*em.Engine, c.JSValue, c.JSValue) anyerror!c.JSValue,
};
fn integer(scope: *Scope, number: i32) c.JSValue {
    return c.JS_NewInt32(scope.engine.context, number);
}
fn op(scope: *Scope, operation: c_int, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_PiBinaryOperator(scope.engine.context, operation, left, right)));
}
fn key(scope: *Scope, object: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, object, index));
}
fn tick(engine: *em.Engine, steps: *usize) !void {
    steps.* +|= 1;
    if (engine.cancelled.load(.acquire) or (steps.* % 256 == 0 and interrupted: {
        engine.interrupts +|= 1;
        break :interrupted engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn singleLine(scope: *Scope, api: Highlighter, line: c.JSValue, language: c.JSValue) !c.JSValue {
    const highlighted = try scope.own(try api.highlight(scope.engine, line, language));
    const first = try key(scope, highlighted, integer(scope, 0));
    return if (temporary.nullish(first)) scope.text("") else first;
}
pub fn refreshPrefix(engine: *em.Engine, api: Highlighter, cache: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const math = try scope.global("Math");
    const minimum = try scope.get(math, "min");
    const count = try scope.call(minimum, math, &.{ integer(&scope, 50), try scope.get(try scope.get(cache, "normalizedLines"), "length") });
    if (scope.equal(count, integer(&scope, 0))) return;
    const prefix = try scope.invoke(try scope.invoke(try scope.get(cache, "normalizedLines"), "slice", &.{ integer(&scope, 0), count }), "join", &.{try scope.text("\n")});
    const highlighted = try scope.own(try api.highlight(engine, prefix, try scope.get(cache, "lang")));
    var index = integer(&scope, 0);
    var native_steps: usize = 0;
    while (scope.truthy(try op(&scope, 4, index, count))) : (index = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, index)))) {
        try tick(engine, &native_steps);
        // Assignment resolves its receiver before evaluating the RHS.
        const destination = try scope.get(cache, "highlightedLines");
        const selected = try key(&scope, highlighted, index);
        const value = if (temporary.nullish(selected)) fallback: {
            const line = try key(&scope, try scope.get(cache, "normalizedLines"), index);
            break :fallback try singleLine(&scope, api, if (temporary.nullish(line)) try scope.text("") else line, try scope.get(cache, "lang"));
        } else selected;
        try js.setKey(engine, destination, index, value);
    }
}
pub fn rebuild(engine: *em.Engine, api: Highlighter, raw_path: c.JSValue, file_content: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const language = if (scope.truthy(raw_path)) try scope.own(try api.language(engine, raw_path)) else c.pi_js_undefined();
    if (!scope.truthy(language)) return c.pi_js_undefined();
    const display = try utils.normalizeDisplayText(&scope, file_content);
    const normalized = try utils.replaceTabs(&scope, display);
    const cache = try scope.object();
    try scope.put(cache, "rawPath", raw_path);
    try scope.put(cache, "lang", language);
    try scope.put(cache, "rawContent", file_content);
    try scope.put(cache, "normalizedLines", try scope.invoke(normalized, "split", &.{try scope.text("\n")}));
    try scope.put(cache, "highlightedLines", try scope.own(try api.highlight(engine, normalized, language)));
    return c.JS_DupValue(engine.context, cache);
}
pub fn update(engine: *em.Engine, api: Highlighter, cache: c.JSValue, raw_path: c.JSValue, file_content: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const language = if (scope.truthy(raw_path)) try scope.own(try api.language(engine, raw_path)) else c.pi_js_undefined();
    if (!scope.truthy(language)) return c.pi_js_undefined();
    if (!scope.truthy(cache)) return rebuild(engine, api, raw_path, file_content);
    if (!scope.equal(try scope.get(cache, "lang"), language) or !scope.equal(try scope.get(cache, "rawPath"), raw_path)) return rebuild(engine, api, raw_path, file_content);
    if (!scope.truthy(try scope.invoke(file_content, "startsWith", &.{try scope.get(cache, "rawContent")}))) return rebuild(engine, api, raw_path, file_content);
    if (scope.equal(try scope.get(file_content, "length"), try scope.get(try scope.get(cache, "rawContent"), "length"))) return c.JS_DupValue(engine.context, cache);
    const delta = try scope.invoke(file_content, "slice", &.{try scope.get(try scope.get(cache, "rawContent"), "length")});
    const display = try utils.normalizeDisplayText(&scope, delta);
    const normalized = try utils.replaceTabs(&scope, display);
    try scope.set(cache, "rawContent", file_content);
    if (scope.equal(try scope.get(try scope.get(cache, "normalizedLines"), "length"), integer(&scope, 0))) {
        _ = try scope.invoke(try scope.get(cache, "normalizedLines"), "push", &.{try scope.text("")});
        _ = try scope.invoke(try scope.get(cache, "highlightedLines"), "push", &.{try scope.text("")});
    }
    const segments = try scope.invoke(normalized, "split", &.{try scope.text("\n")});
    const last = try op(&scope, 1, try scope.get(try scope.get(cache, "normalizedLines"), "length"), integer(&scope, 1));
    const line_array = try scope.get(cache, "normalizedLines");
    const before = try key(&scope, line_array, last);
    try js.setKey(engine, line_array, last, try scope.concat(before, try key(&scope, segments, integer(&scope, 0))));
    const destination = try scope.get(cache, "highlightedLines");
    const line = try key(&scope, try scope.get(cache, "normalizedLines"), last);
    try js.setKey(engine, destination, last, try singleLine(&scope, api, line, try scope.get(cache, "lang")));
    var index = integer(&scope, 1);
    var native_steps: usize = 0;
    while (scope.truthy(try op(&scope, 4, index, try scope.get(segments, "length")))) : (index = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, index)))) {
        try tick(engine, &native_steps);
        const normalized_lines = try scope.get(cache, "normalizedLines");
        const push = try scope.get(normalized_lines, "push");
        _ = try scope.call(push, normalized_lines, &.{try key(&scope, segments, index)});
        const highlighted_lines = try scope.get(cache, "highlightedLines");
        const push_highlighted = try scope.get(highlighted_lines, "push");
        _ = try scope.call(push_highlighted, highlighted_lines, &.{try singleLine(&scope, api, try key(&scope, segments, index), try scope.get(cache, "lang"))});
    }
    try refreshPrefix(engine, api, cache);
    return c.JS_DupValue(engine.context, cache);
}
