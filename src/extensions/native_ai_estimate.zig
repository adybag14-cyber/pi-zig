//! Original pi-ai context estimation (3.5 chars/token), distinct from SDK compaction.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
extern fn JS_GetIteratorSymbol(?*c.JSContext) c.JSValue;
const Method = enum { calculateContextTokens, estimateTextTokens, estimateTextAndImageContentTokens, estimateMessageTokens, estimateContextTokens };
pub fn create(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const exports = try scope.object();
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const method: Method = @enumFromInt(field.value);
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const input = if (args.len > 0) args[0] else c.pi_js_undefined();
                return switch (method) {
                    .calculateContextTokens => usage(host, input),
                    .estimateTextTokens => textTokens(host, input),
                    .estimateTextAndImageContentTokens => contentTokens(host, input),
                    .estimateMessageTokens => messageTokens(host, input),
                    .estimateContextTokens => contextTokens(host, input),
                };
            }
        };
        try scope.put(exports, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, 1, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, exports);
}
fn op(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
fn is(scope: *Scope, value: c.JSValue, name: []const u8) !bool {
    return scope.equal(value, try scope.text(name));
}
fn iterate(scope: *Scope, object: c.JSValue) !js.Iterator {
    return js.Iterator.init(scope.engine, object, try scope.own(try scope.engine.checked(JS_GetIteratorSymbol(scope.engine.context))));
}
fn index(scope: *Scope, object: c.JSValue, position: c.JSValue) !c.JSValue {
    return scope.own(try js.getKey(scope.engine, object, position));
}
pub fn usage(engine: *em.Engine, value: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const total = try scope.get(value, "totalTokens");
    if (scope.truthy(total)) return c.JS_DupValue(engine.context, total);
    var result = try op(&scope, .add, try scope.get(value, "input"), try scope.get(value, "output"));
    result = try op(&scope, .add, result, try scope.get(value, "cacheRead"));
    result = try op(&scope, .add, result, try scope.get(value, "cacheWrite"));
    return c.JS_DupValue(engine.context, result);
}
fn ceil(scope: *Scope, chars: c.JSValue) !c.JSValue {
    const math = try scope.global("Math");
    const function = try scope.get(math, "ceil");
    return scope.call(function, math, &.{try op(scope, .divide, chars, c.JS_NewFloat64(scope.engine.context, 3.5))});
}
pub fn textTokens(engine: *em.Engine, text: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const math = try scope.global("Math");
    const function = try scope.get(math, "ceil");
    const divided = try op(&scope, .divide, try scope.get(text, "length"), c.JS_NewFloat64(engine.context, 3.5));
    return js.call(engine, function, math, &.{divided});
}
fn contentChars(scope: *Scope, content: c.JSValue) !c.JSValue {
    if (c.JS_IsString(content)) return scope.get(content, "length");
    var chars = c.JS_NewInt32(scope.engine.context, 0);
    var iterator = try iterate(scope, content);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |block| {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        _ = try row.own(block);
        const count = if (try is(&row, try row.get(block, "type"), "text")) try row.get(try row.get(block, "text"), "length") else c.JS_NewInt32(scope.engine.context, 4800);
        chars = try op(scope, .add, chars, count);
    }
    return chars;
}
pub fn contentTokens(engine: *em.Engine, content: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const math = try scope.global("Math");
    const function = try scope.get(math, "ceil");
    const divided = try op(&scope, .divide, try contentChars(&scope, content), c.JS_NewFloat64(engine.context, 3.5));
    return js.call(engine, function, math, &.{divided});
}
fn safeJSON(scope: *Scope, value: c.JSValue) !c.JSValue {
    const generation = scope.engine.native_allocation_generation;
    const string = scope.invoke(try scope.global("JSON"), "stringify", &.{value}) catch |err| {
        const classified = scope.engine.nativeAllocationError(err, generation);
        if (classified == error.OutOfMemory) return classified;
        if (scope.engine.captured_exception) |reason| {
            scope.engine.freeValue(reason);
            scope.engine.captured_exception = null;
        }
        return scope.text("[unserializable]");
    };
    return if (temp.nullish(string)) scope.text("undefined") else string;
}
fn toolTokens(scope: *Scope, tools: c.JSValue) !c.JSValue {
    if (!scope.truthy(tools) or scope.equal(try scope.get(tools, "length"), c.JS_NewInt32(scope.engine.context, 0))) return c.JS_NewInt32(scope.engine.context, 0);
    return scope.own(try textTokens(scope.engine, try safeJSON(scope, tools)));
}
pub fn messageTokens(engine: *em.Engine, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var chars = c.JS_NewInt32(engine.context, 0);
    if (try is(&scope, try scope.get(message, "role"), "system")) {
        const text = try scope.own(try @import("native_ai_text.zig").system(engine, message, false));
        const initial = try scope.own(try textTokens(engine, text));
        const added = try toolTokens(&scope, try scope.get(message, "toolsAdded"));
        const removed = try toolTokens(&scope, try scope.get(message, "toolsRemoved"));
        return c.JS_DupValue(engine.context, try op(&scope, .add, try op(&scope, .add, initial, added), removed));
    }
    if (try is(&scope, try scope.get(message, "role"), "user")) return contentTokens(engine, try scope.get(message, "content"));
    if (try is(&scope, try scope.get(message, "role"), "toolResult")) return contentTokens(engine, try scope.get(message, "content"));
    var iterator = try iterate(&scope, try scope.get(message, "content"));
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    while (try iterator.next()) |block| {
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        _ = try row.own(block);
        const amount = if (try is(&row, try row.get(block, "type"), "text")) try row.get(try row.get(block, "text"), "length") else if (try is(&row, try row.get(block, "type"), "thinking")) try row.get(try row.get(block, "thinking"), "length") else try op(&row, .add, try row.get(try row.get(block, "name"), "length"), try row.get(try safeJSON(&row, try row.get(block, "arguments")), "length"));
        chars = try op(&scope, .add, chars, amount);
    }
    return c.JS_DupValue(engine.context, try ceil(&scope, chars));
}
fn lastUsage(scope: *Scope, messages: c.JSValue) !c.JSValue {
    var latest = try scope.get(try scope.global("Number"), "NEGATIVE_INFINITY");
    var selected = c.pi_js_undefined();
    var position = c.JS_NewInt32(scope.engine.context, 0);
    var steps: usize = 0;
    while (try arithmetic.compare(scope.engine, .less, position, try scope.get(messages, "length"))) {
        try @import("native_ai_budget.zig").step(scope.engine, &steps);
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const message = try index(&row, messages, position);
        if (try is(&row, try row.get(message, "role"), "assistant")) {
            const applies = try arithmetic.compare(scope.engine, .greater_equal, try row.get(message, "timestamp"), latest);
            if (applies and !try is(&row, try row.get(message, "stopReason"), "aborted") and !try is(&row, try row.get(message, "stopReason"), "error") and try arithmetic.compare(scope.engine, .greater, try row.own(try usage(scope.engine, try row.get(message, "usage"))), c.JS_NewInt32(scope.engine.context, 0))) {
                selected = try scope.object();
                try scope.put(selected, "usage", try row.get(message, "usage"));
                try scope.put(selected, "index", position);
            }
        }
        const math = try row.global("Math");
        const max = try row.get(math, "max");
        latest = try scope.own(try js.call(scope.engine, max, math, &.{ latest, try row.get(message, "timestamp") }));
        position = try scope.own(try scope.engine.checked(c.JS_PiIncrement(scope.engine.context, position)));
    }
    return selected;
}
pub fn contextTokens(engine: *em.Engine, context: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const messages = if (try js.hasKey(engine, context, try scope.text("messages"))) try scope.get(context, "messages") else context;
    const info = try lastUsage(&scope, messages);
    const result = try scope.object();
    if (scope.truthy(info)) {
        const used = try scope.own(try usage(engine, try scope.get(info, "usage")));
        var trailing = c.JS_NewInt32(engine.context, 0);
        var position = try op(&scope, .add, try scope.get(info, "index"), c.JS_NewInt32(engine.context, 1));
        var steps: usize = 0;
        while (try arithmetic.compare(engine, .less, position, try scope.get(messages, "length"))) {
            try @import("native_ai_budget.zig").step(engine, &steps);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            trailing = try op(&scope, .add, trailing, try row.own(try messageTokens(engine, try index(&row, messages, position))));
            position = try scope.own(try engine.checked(c.JS_PiIncrement(engine.context, position)));
        }
        try scope.put(result, "tokens", try op(&scope, .add, used, trailing));
        try scope.put(result, "usageTokens", used);
        try scope.put(result, "trailingTokens", trailing);
        try scope.put(result, "lastUsageIndex", try scope.get(info, "index"));
    } else {
        var total = c.JS_NewInt32(engine.context, 0);
        var iterator = try iterate(&scope, messages);
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |message| {
            defer engine.freeValue(message);
            var row: Scope = .{ .engine = engine };
            defer row.deinit();
            total = try op(&scope, .add, total, try row.own(try messageTokens(engine, message)));
        }
        try scope.put(result, "tokens", total);
        try scope.put(result, "usageTokens", c.JS_NewInt32(engine.context, 0));
        try scope.put(result, "trailingTokens", total);
        try scope.put(result, "lastUsageIndex", c.pi_js_null());
    }
    return c.JS_DupValue(engine.context, result);
}
