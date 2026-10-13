//! Native imported compaction utilities shared by Source session hooks.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const temp = @import("native_sdk_prompt_scope.zig");
const usage = @import("native_sdk_session_usage.zig");
const js = @import("native_js_values.zig");
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
    var index = try sdk.length(engine, args[0]);
    while (index > 0) {
        index -= 1;
        const entry = try at(&scope, args[0], index);
        if (!try is(&scope, try scope.get(entry, "type"), "custom") or !try is(&scope, try scope.get(entry, "customType"), "pi.virtual-model-state")) continue;
        const data = try scope.get(entry, "data");
        const provider = if (temp.nullish(data)) c.pi_js_undefined() else try scope.get(data, "provider");
        if (scope.equal(provider, args[1]) and scope.equal(try scope.get(data, "modelId"), args[2])) return c.JS_DupValue(engine.context, try scope.get(data, "state"));
    }
    return c.pi_js_undefined();
}
fn at(scope: *Scope, array: c.JSValue, index: usize) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, array, @intCast(index))));
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
pub fn estimate(engine: *em.Engine, projection: c.JSValue, branch: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = try scope.get(projection, "messages");
    var last_usage: ?usize = null;
    var last_usage_object = c.pi_js_undefined();
    var cursor = try sdk.length(engine, messages);
    while (cursor > 0) {
        cursor -= 1;
        const message = try at(&scope, messages, cursor);
        const reported = try assistantUsage(&scope, message);
        if (scope.truthy(reported)) {
            last_usage = cursor;
            last_usage_object = reported;
            break;
        }
    }
    var usage_tokens = c.JS_NewInt32(engine.context, 0);
    var tokens = c.JS_NewInt32(engine.context, 0);
    var trailing = c.JS_NewInt32(engine.context, 0);
    // Source calls estimateContextTokens before deciding whether the recorded
    // usage is trustworthy, including its estimates on the invalidated path.
    if (last_usage) |index| {
        usage_tokens = try calculateContextTokens(&scope, last_usage_object);
        var next = index + 1;
        while (next < try sdk.length(engine, messages)) : (next += 1) trailing = try scope.concat(trailing, c.JS_NewFloat64(engine.context, try usage.estimateTokens(engine, try at(&scope, messages, next))));
        tokens = try scope.concat(usage_tokens, trailing);
    } else {
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, messages, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |message| {
            defer engine.freeValue(message);
            tokens = try scope.concat(tokens, c.JS_NewFloat64(engine.context, try usage.estimateTokens(engine, message)));
        }
        trailing = tokens;
    }
    var trusted = false;
    if (last_usage) |usage_index| {
        var offset: usize = 0;
        var usage_entry_id = c.pi_js_undefined();
        const projected = try scope.get(projection, "entries");
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, projected, symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |row| {
            defer engine.freeValue(row);
            const next = offset + try sdk.length(engine, try scope.get(row, "messages"));
            if (usage_index < next) {
                usage_entry_id = try scope.get(try scope.get(row, "sourceEntry"), "id");
                try iterator.close();
                break;
            }
            offset = next;
        }
        var usage_entry_index: i64 = -1;
        if (scope.truthy(usage_entry_id)) {
            var roots = [_]c.JSValue{usage_entry_id};
            const predicate = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, findUsageEntry, "", 1, 0, roots.len, &roots)));
            const found = try scope.invoke(branch, "findIndex", &.{predicate});
            var numeric: i64 = undefined;
            if (c.JS_ToInt64(engine.context, &numeric, found) < 0) return js.capture(engine);
            usage_entry_index = numeric;
        }
        var invalidating_index: i64 = -1;
        cursor = try sdk.length(engine, branch);
        while (cursor > 0) {
            cursor -= 1;
            const typ = try scope.get(try at(&scope, branch, cursor), "type");
            if (try is(&scope, typ, "context_edit") or try is(&scope, typ, "compaction")) {
                invalidating_index = @intCast(cursor);
                break;
            }
        }
        trusted = usage_entry_index > invalidating_index;
    }
    if (!trusted) {
        const projected_messages = try scope.get(projection, "messages");
        const system = try scope.own(try @import("native_sdk_transcript_replay.zig").currentSystemMessage(engine, projected_messages));
        tokens = if (scope.truthy(system)) c.JS_NewFloat64(engine.context, try usage.estimateTokens(engine, system)) else c.JS_NewInt32(engine.context, 0);
        const symbol = try scope.own(try engine.checked(JS_GetIteratorSymbol(engine.context)));
        var iterator = try js.Iterator.init(engine, try scope.get(projection, "messages"), symbol);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |message| {
            defer engine.freeValue(message);
            if (!try is(&scope, try scope.get(message, "role"), "system")) tokens = try scope.concat(tokens, c.JS_NewFloat64(engine.context, try usage.estimateTokens(engine, message)));
        }
        usage_tokens = c.JS_NewInt32(engine.context, 0);
        trailing = tokens;
        last_usage = null;
    }
    const result = try scope.object();
    try scope.put(result, "tokens", tokens);
    try scope.put(result, "usageTokens", usage_tokens);
    try scope.put(result, "trailingTokens", trailing);
    try scope.put(result, "lastUsageIndex", if (last_usage) |index| c.JS_NewUint32(engine.context, @intCast(index)) else c.pi_js_null());
    return c.JS_DupValue(engine.context, result);
}
fn findUsageEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const entry = if (argc > 0) args[0] else c.pi_js_undefined();
    const id = sdk.get(engine, entry, "id") catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(id);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_IsStrictEqual(engine.context, id, roots[0])));
}
fn calculateContextTokens(scope: *Scope, report: c.JSValue) !c.JSValue {
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
