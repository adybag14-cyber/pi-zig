//! Ordinary session billed statistics and post-compaction context usage.
//! Preserve live receiver fields, collection calls and VM arithmetic values.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
pub fn install(engine: *em.Engine, prototype: c.JSValue) !void {
    inline for (.{ "getSessionStats", "getContextUsage" }, 0..) |name, index| {
        const function = try engine.checked(c.pi_js_function_magic(engine.context, dispatch, name, 0, index));
        if (c.JS_DefinePropertyValueStr(engine.context, prototype, name, function, c.JS_PROP_WRITABLE | c.JS_PROP_CONFIGURABLE) < 0) return js.capture(engine);
    }
}
fn dispatch(context: ?*c.JSContext, session: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return (if (magic == 0) stats(engine, session) else contextUsage(engine, session)) catch |err| sdk.fail(engine, err);
}
fn is(scope: *Scope, value: c.JSValue, name: []const u8) !bool {
    return scope.equal(value, try scope.text(name));
}
fn increment(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    return engine.checked(c.JS_PiIncrement(engine.context, value));
}
fn addUsage(scope: *Scope, totals: c.JSValue, usage: c.JSValue) !void {
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "cost" }) |name| {
        const previous = try scope.get(totals, name);
        const value = if (comptime @import("std").mem.eql(u8, name, "cost")) try scope.get(try scope.get(usage, "cost"), "total") else try scope.get(usage, name);
        try scope.set(totals, name, try scope.concat(previous, value));
    }
}
fn stats(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const totals = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "cost" }) |name| try scope.put(totals, name, c.JS_NewInt32(engine.context, 0));
    var users = c.JS_NewInt32(engine.context, 0);
    var assistants = c.JS_NewInt32(engine.context, 0);
    var tool_results = c.JS_NewInt32(engine.context, 0);
    var messages = c.JS_NewInt32(engine.context, 0);
    var tool_calls = c.JS_NewInt32(engine.context, 0);
    const entries = try scope.invoke(try scope.get(session, "sessionManager"), "getEntries", &.{});
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, entries, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |entry| {
        defer engine.freeValue(entry);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        if (try is(&iteration, try iteration.get(entry, "type"), "usage")) {
            try addUsage(&iteration, totals, try iteration.get(entry, "usage"));
        } else if ((try is(&iteration, try iteration.get(entry, "type"), "branch_summary") or try is(&iteration, try iteration.get(entry, "type"), "compaction")) and iteration.truthy(try iteration.get(entry, "usage"))) {
            try addUsage(&iteration, totals, try iteration.get(entry, "usage"));
        }
        if (!try is(&iteration, try iteration.get(entry, "type"), "message")) continue;
        messages = try scope.own(try increment(engine, messages));
        const message = try iteration.get(entry, "message");
        if (try is(&iteration, try iteration.get(message, "role"), "user")) {
            users = try scope.own(try increment(engine, users));
        } else if (try is(&iteration, try iteration.get(message, "role"), "toolResult")) {
            tool_results = try scope.own(try increment(engine, tool_results));
            if (iteration.truthy(try iteration.get(message, "usage"))) try addUsage(&iteration, totals, try iteration.get(message, "usage"));
        } else if (try is(&iteration, try iteration.get(message, "role"), "assistant")) {
            assistants = try scope.own(try increment(engine, assistants));
            const array = try iteration.global("Array");
            const predicate = try iteration.get(array, "isArray");
            if (iteration.truthy(try iteration.call(predicate, array, &.{try iteration.get(message, "content")}))) {
                const content = try iteration.get(message, "content");
                const filter = try iteration.get(content, "filter");
                const callback = try iteration.own(try engine.checked(c.JS_NewCFunction(engine.context, toolCall, "", 1)));
                const filtered = try iteration.call(filter, content, &.{callback});
                tool_calls = try scope.own(try arithmetic.binary(engine, .add, tool_calls, try iteration.get(filtered, "length")));
            }
            try addUsage(&iteration, totals, try iteration.get(message, "usage"));
        }
    }
    const result = try scope.object();
    try scope.put(result, "sessionFile", try scope.get(session, "sessionFile"));
    try scope.put(result, "sessionId", try scope.get(session, "sessionId"));
    inline for (.{ .{ "userMessages", users }, .{ "assistantMessages", assistants }, .{ "toolCalls", tool_calls }, .{ "toolResults", tool_results }, .{ "totalMessages", messages } }) |pair| try scope.put(result, pair[0], pair[1]);
    const tokens = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite" }) |name| try scope.put(tokens, name, try scope.get(totals, name));
    var total = try scope.concat(try scope.get(totals, "input"), try scope.get(totals, "output"));
    total = try scope.concat(total, try scope.get(totals, "cacheRead"));
    total = try scope.concat(total, try scope.get(totals, "cacheWrite"));
    try scope.put(tokens, "total", total);
    try scope.put(result, "tokens", tokens);
    try scope.put(result, "cost", try scope.get(totals, "cost"));
    try scope.put(result, "contextUsage", try scope.invoke(session, "getContextUsage", &.{}));
    return c.JS_DupValue(engine.context, result);
}
fn toolCall(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const value = is(&scope, scope.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err), "toolCall") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(value));
}
pub fn latestCompaction(engine: *em.Engine, branch: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var cursor = try arithmetic.binary(engine, .subtract, try scope.get(branch, "length"), c.JS_NewInt32(engine.context, 1));
    defer engine.freeValue(cursor);
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .greater_equal, cursor, c.JS_NewInt32(engine.context, 0))) {
        steps +|= 1;
        try budget(engine, steps);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const entry = try iteration.own(try js.getKey(engine, branch, cursor));
        if (try is(&iteration, try iteration.get(entry, "type"), "compaction")) return js.getKey(engine, branch, cursor);
        const next = try arithmetic.binary(engine, .subtract, cursor, c.JS_NewInt32(engine.context, 1));
        engine.freeValue(cursor);
        cursor = next;
    }
    return c.pi_js_null();
}
fn budget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and block: {
        engine.interrupts +|= 1;
        break :block engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}
fn contextUsage(engine: *em.Engine, session: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const model = try scope.invoke(session, "_limitsModel", &.{});
    if (!scope.truthy(model)) return c.pi_js_undefined();
    const raw_window = try scope.get(model, "contextWindow");
    const window = if (temp.nullish(raw_window)) c.JS_NewInt32(engine.context, 0) else raw_window;
    if (try arithmetic.compare(engine, .less_equal, window, c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    const projection = try scope.invoke(try scope.get(session, "sessionManager"), "buildSessionProjection", &.{});
    const branch = try scope.invoke(try scope.get(session, "sessionManager"), "getBranch", &.{});
    const compact = try scope.own(try latestCompaction(engine, branch));
    if (scope.truthy(compact)) {
        const constructor = try scope.global("Set");
        const entries = try scope.get(projection, "entries");
        const flat_map = try scope.get(entries, "flatMap");
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, projectedEntry, "", 1, 0, 0, null)));
        const ids = try scope.call(flat_map, entries, &.{callback});
        const assistants = try scope.own(try engine.checked(c.JS_CallConstructor(engine.context, constructor, 1, @constCast(&[_]c.JSValue{ids}))));
        var compaction_roots = [_]c.JSValue{compact};
        const find = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findCompaction, "", 1, 0, compaction_roots.len, &compaction_roots)));
        const index = try scope.invoke(branch, "findIndex", &.{find});
        const start = try scope.own(try arithmetic.binary(engine, .add, index, c.JS_NewInt32(engine.context, 1)));
        const after = try scope.invoke(branch, "slice", &.{start});
        var assistant_roots = [_]c.JSValue{assistants};
        const has = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, hasAssistant, "", 1, 0, assistant_roots.len, &assistant_roots)));
        if (!scope.truthy(try scope.invoke(after, "some", &.{has}))) {
            const result = try scope.object();
            try scope.put(result, "tokens", c.pi_js_null());
            try scope.put(result, "contextWindow", window);
            try scope.put(result, "percent", c.pi_js_null());
            return c.JS_DupValue(engine.context, result);
        }
    }
    const estimate = try scope.own(try @import("native_sdk_session_estimate.zig").estimate(engine, projection, branch));
    const ratio = try scope.own(try arithmetic.binary(engine, .divide, try scope.get(estimate, "tokens"), window));
    const percent = try scope.own(try arithmetic.binary(engine, .multiply, ratio, c.JS_NewInt32(engine.context, 100)));
    const result = try scope.object();
    try scope.put(result, "tokens", try scope.get(estimate, "tokens"));
    try scope.put(result, "contextWindow", window);
    try scope.put(result, "percent", percent);
    return c.JS_DupValue(engine.context, result);
}
fn projectedEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, _: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return projected(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn projected(engine: *em.Engine, entry: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.get(entry, "messages");
    const some = try scope.get(messages, "some");
    const predicate = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, usableUsage, "", 1)));
    const eligible = try scope.call(some, messages, &.{predicate});
    const result = try scope.array();
    if (scope.truthy(eligible)) try scope.index(result, 0, try scope.get(try scope.get(entry, "sourceEntry"), "id"));
    return c.JS_DupValue(engine.context, result);
}
fn usableUsage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return usable(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn usable(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const answer = try is(&scope, try scope.get(message, "role"), "assistant") and !try is(&scope, try scope.get(message, "stopReason"), "aborted") and !try is(&scope, try scope.get(message, "stopReason"), "error") and try scope.positive(try @import("native_sdk_session_estimate.zig").calculateContextTokens(&scope, try scope.get(message, "usage")));
    return c.pi_js_bool(engine.context, @intFromBool(answer));
}
fn findCompaction(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const entry = if (argc > 0) argv[0] else c.pi_js_undefined();
    const left = scope.get(entry, "id") catch |err| return sdk.fail(engine, err);
    const right = scope.get(roots[0], "id") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(scope.equal(left, right)));
}
fn hasAssistant(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const entry = if (argc > 0) argv[0] else c.pi_js_undefined();
    const has = sdk.get(engine, roots[0], "has") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(has);
    const id = sdk.get(engine, entry, "id") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(id);
    return js.call(engine, has, roots[0], &.{id}) catch |err| sdk.fail(engine, err);
}
