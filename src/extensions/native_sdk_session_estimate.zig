//! Native imported compaction utilities shared by Source session hooks.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const temp = @import("native_sdk_prompt_scope.zig");
const js = @import("native_js_values.zig");
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
pub fn install(engine: *em.Engine, dependencies: c.JSValue) !void {
    inline for (.{ "shouldCompact", "estimateProjectedContextTokens", "getVirtualModelState" }, 0..) |name, index| {
        const Adapter = struct {
            fn invoke(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                var input = [_]c.JSValue{c.pi_js_undefined()} ** 3;
                for (args[0..@min(input.len, args.len)], 0..) |value, position| input[position] = value;
                return dispatch(host, &input, index);
            }
        };
        try sdk.put(engine, dependencies, name, try @import("native_node_function.zig").create(engine, name, if (index == 1) 2 else 3, Adapter.invoke, &.{}));
    }
}
fn dispatch(engine: *em.Engine, args: []const c.JSValue, magic: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (magic == 0) {
        if (!scope.truthy(try scope.get(args[2], "enabled"))) return c.pi_js_bool(engine.context, 0);
        const threshold = try scope.own(try engine.checked(c.JS_PiBinaryOperator(engine.context, 1, args[1], try scope.get(args[2], "reserveTokens"))));
        return engine.checked(c.JS_PiBinaryOperator(engine.context, 6, args[0], threshold));
    }
    if (magic == 1) return estimate(engine, args[0], args[1]);
    var index = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(args[0], "length"), c.JS_NewInt32(engine.context, 1)));
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .greater_equal, index, c.JS_NewInt32(engine.context, 0))) {
        steps +|= 1;
        try estimateBudget(engine, steps);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const entry = try keyAt(&iteration, args[0], index);
        if (try is(&iteration, try iteration.get(entry, "type"), "custom") and try is(&iteration, try iteration.get(entry, "customType"), "pi.virtual-model-state")) {
            const data = try iteration.get(entry, "data");
            const provider = if (temp.nullish(data)) c.pi_js_undefined() else try iteration.get(data, "provider");
            if (iteration.equal(provider, args[1]) and iteration.equal(try iteration.get(data, "modelId"), args[2])) return c.JS_DupValue(engine.context, try iteration.get(data, "state"));
        }
        index = try scope.own(try arithmetic.binary(engine, .subtract, index, c.JS_NewInt32(engine.context, 1)));
    }
    return c.pi_js_undefined();
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
pub fn estimate(engine: *em.Engine, projection: c.JSValue, branch: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.get(projection, "messages");
    const info = try lastUsage(&scope, messages);
    var last_index = if (info) |item| item.index else c.pi_js_null();
    var usage_tokens = c.JS_NewInt32(engine.context, 0);
    var trailing = c.JS_NewInt32(engine.context, 0);
    var tokens = c.JS_NewInt32(engine.context, 0);
    if (info) |item| {
        usage_tokens = try calculateContextTokens(&scope, item.report);
        var cursor = try scope.own(try arithmetic.binary(engine, .add, item.index, c.JS_NewInt32(engine.context, 1)));
        var steps: usize = 0;
        while (try arithmetic.compare(engine, .less, cursor, try scope.get(messages, "length"))) {
            steps +|= 1;
            try estimateBudget(engine, steps);
            var iteration: Scope = .{ .engine = engine };
            defer iteration.deinit();
            const message = try keyAt(&iteration, messages, cursor);
            trailing = try scope.concat(trailing, try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message)));
            cursor = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, cursor)));
        }
        tokens = try scope.concat(usage_tokens, trailing);
    } else {
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var estimate_iterator = try js.Iterator.init(engine, messages, symbol);
        defer estimate_iterator.deinit();
        errdefer estimate_iterator.closePreserving();
        while (try estimate_iterator.next()) |message| {
            defer engine.freeValue(message);
            tokens = try scope.concat(tokens, try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message)));
        }
        trailing = tokens;
    }
    if (info) |item| {
        var offset = c.JS_NewInt32(engine.context, 0);
        var entry_id = c.pi_js_undefined();
        const entries = try scope.get(projection, "entries");
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var entry_iterator = try js.Iterator.init(engine, entries, symbol);
        defer entry_iterator.deinit();
        errdefer entry_iterator.closePreserving();
        while (try entry_iterator.next()) |entry| {
            defer engine.freeValue(entry);
            var iteration: Scope = .{ .engine = engine };
            defer iteration.deinit();
            const next = try scope.concat(offset, try iteration.get(try iteration.get(entry, "messages"), "length"));
            if (try arithmetic.compare(engine, .less, item.index, next)) {
                entry_id = try scope.get(try iteration.get(entry, "sourceEntry"), "id");
                try entry_iterator.close();
                break;
            }
            offset = next;
        }
        var usage_index = c.JS_NewInt32(engine.context, -1);
        if (scope.truthy(entry_id)) {
            var roots = [_]c.JSValue{entry_id};
            const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findUsageEntry, "", 1, 0, roots.len, &roots)));
            usage_index = try scope.invoke(branch, "findIndex", &.{predicate});
        }
        var invalidating = c.JS_NewInt32(engine.context, -1);
        var cursor = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(branch, "length"), c.JS_NewInt32(engine.context, 1)));
        var steps: usize = 0;
        while (try arithmetic.compare(engine, .greater_equal, cursor, c.JS_NewInt32(engine.context, 0))) {
            steps +|= 1;
            try estimateBudget(engine, steps);
            var iteration: Scope = .{ .engine = engine };
            defer iteration.deinit();
            const entry = try keyAt(&iteration, branch, cursor);
            if (try is(&iteration, try iteration.get(entry, "type"), "context_edit") or try is(&iteration, try iteration.get(entry, "type"), "compaction")) {
                invalidating = cursor;
                break;
            }
            cursor = try scope.own(try arithmetic.binary(engine, .subtract, cursor, c.JS_NewInt32(engine.context, 1)));
        }
        if (try arithmetic.compare(engine, .greater, usage_index, invalidating)) return estimateResult(&scope, tokens, usage_tokens, trailing, last_index);
    }
    const projected_messages = try scope.get(projection, "messages");
    const system = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(engine, projected_messages));
    tokens = if (scope.truthy(system)) try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, system)) else c.JS_NewInt32(engine.context, 0);
    const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
    var message_iterator = try js.Iterator.init(engine, try scope.get(projection, "messages"), symbol);
    defer message_iterator.deinit();
    errdefer message_iterator.closePreserving();
    while (try message_iterator.next()) |message| {
        defer engine.freeValue(message);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        if (!try is(&iteration, try iteration.get(message, "role"), "system")) tokens = try scope.concat(tokens, try scope.own(try @import("native_sdk_compaction_estimate.zig").estimateTokens(engine, message)));
    }
    last_index = c.pi_js_null();
    return estimateResult(&scope, tokens, c.JS_NewInt32(engine.context, 0), tokens, last_index);
}
const LastUsage = struct { index: c.JSValue, report: c.JSValue };
fn lastUsage(scope: *Scope, messages: c.JSValue) !?LastUsage {
    const engine = scope.engine;
    var cursor = try scope.own(try arithmetic.binary(engine, .subtract, try scope.get(messages, "length"), c.JS_NewInt32(engine.context, 1)));
    var steps: usize = 0;
    while (try arithmetic.compare(engine, .greater_equal, cursor, c.JS_NewInt32(engine.context, 0))) {
        steps +|= 1;
        try estimateBudget(engine, steps);
        var iteration: Scope = .{ .engine = engine };
        defer iteration.deinit();
        const message = try keyAt(&iteration, messages, cursor);
        const report = try assistantUsage(&iteration, message);
        if (iteration.truthy(report)) return .{ .index = cursor, .report = try scope.own(c.JS_DupValue(engine.context, report)) };
        cursor = try scope.own(try arithmetic.binary(engine, .subtract, cursor, c.JS_NewInt32(engine.context, 1)));
    }
    return null;
}
fn keyAt(scope: *Scope, array: c.JSValue, index: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, array, index));
}
fn estimateResult(scope: *Scope, tokens: c.JSValue, reported: c.JSValue, trailing: c.JSValue, index: c.JSValue) !c.JSValue {
    const result = try scope.object();
    try scope.put(result, "tokens", tokens);
    try scope.put(result, "usageTokens", reported);
    try scope.put(result, "trailingTokens", trailing);
    try scope.put(result, "lastUsageIndex", index);
    return c.JS_DupValue(scope.engine.context, result);
}
fn estimateBudget(engine: *em.Engine, steps: usize) !void {
    if (engine.cancelled.load(.acquire) or (steps % 256 == 0 and block: {
        engine.interrupts +|= 1;
        break :block engine.interrupts > engine.options.interrupt_budget;
    })) {
        _ = try engine.checked(c.JS_ThrowInternalError(engine.context, "interrupted"));
        unreachable;
    }
}

fn findUsageEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    const entry = if (argc > 0) args[0] else c.pi_js_undefined();
    const id = sdk.get(engine, entry, "id") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(id);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, id, roots[0])));
}
pub fn calculateContextTokens(scope: *Scope, report: c.JSValue) !c.JSValue {
    const total = try scope.get(report, "totalTokens");
    if (scope.truthy(total)) return total;
    var sum = try scope.concat(try scope.get(report, "input"), try scope.get(report, "output"));
    sum = try scope.concat(sum, try scope.get(report, "cacheRead"));
    return scope.concat(sum, try scope.get(report, "cacheWrite"));
}
fn assistantUsage(scope: *Scope, message: c.JSValue) !c.JSValue {
    if (!try is(scope, try scope.get(message, "role"), "assistant") or !try js.hasKey(scope.engine, message, try scope.text("usage"))) return c.pi_js_undefined();
    if (try is(scope, try scope.get(message, "stopReason"), "aborted") or try is(scope, try scope.get(message, "stopReason"), "error") or !scope.truthy(try scope.get(message, "usage"))) return c.pi_js_undefined();
    const tokens = try calculateContextTokens(scope, try scope.get(message, "usage"));
    if (try scope.positive(tokens)) return scope.get(message, "usage");
    return c.pi_js_undefined();
}
