//! Original compaction conversation serializer and summary failure messages.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const replay = @import("native_sdk_transcript_replay.zig");
const c = em.c;
const Export = enum { serializeConversation, getSummarizationFailure };
pub fn exports(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    inline for (@import("std").meta.fields(Export)) |field| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                host.native_exception_diagnostics_suppressed += 1;
                defer host.native_exception_diagnostics_suppressed -= 1;
                const first = if (args.len > 0) args[0] else c.pi_js_undefined();
                return if (field.value == 0) serialize(host, first) else failure(host, first, if (args.len > 1) args[1] else c.pi_js_undefined());
            }
        };
        try scope.put(result, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value == 0) 1 else 2, Adapter.call, &.{})));
    }
    return c.JS_DupValue(engine.context, result);
}
fn is(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn iterate(scope: *Scope, value: c.JSValue) !js.Iterator {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return js.Iterator.init(scope.engine, value, symbol);
}
pub fn failure(engine: *em.Engine, response: c.JSValue, label: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (try is(&scope, try scope.get(response, "stopReason"), "error")) {
        const prefix = try scope.concat(try scope.stringify(label), try scope.text(" failed: "));
        const error_message = try scope.get(response, "errorMessage");
        const message = if (scope.truthy(error_message)) error_message else try scope.text("Unknown error");
        return c.JS_DupValue(engine.context, try scope.concat(prefix, try scope.stringify(message)));
    }
    if (try is(&scope, try scope.get(response, "stopReason"), "length")) return c.JS_DupValue(engine.context, try scope.concat(try scope.stringify(label), try scope.text(" failed: generation hit the token cap and the summary is incomplete")));
    return c.pi_js_undefined();
}
fn truncate(scope: *Scope, text: c.JSValue) !c.JSValue {
    const maximum = c.JS_NewInt32(scope.engine.context, 2000);
    if (try arithmetic.compare(scope.engine, .less_equal, try scope.get(text, "length"), maximum)) return text;
    const remaining = try scope.own(try arithmetic.binary(scope.engine, .subtract, try scope.get(text, "length"), maximum));
    const sliced = try scope.invoke(text, "slice", &.{ c.JS_NewInt32(scope.engine.context, 0), maximum });
    var result = try scope.concat(try scope.stringify(sliced), try scope.text("\n\n[... "));
    result = try scope.concat(result, try scope.stringify(remaining));
    return scope.concat(result, try scope.text(" more characters truncated]"));
}
fn argumentEntry(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return formatArgument(engine, if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| sdk.fail(engine, err);
}
fn formatArgument(engine: *em.Engine, pair: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    const values = try js.pair(engine, pair, symbol);
    defer for (values) |value| engine.freeValue(value);
    // Template literals stringify the key before evaluating JSON.stringify(v).
    const prefix = try scope.concat(try scope.stringify(values[0]), try scope.text("="));
    const json = try scope.global("JSON");
    const encoded = try scope.invoke(json, "stringify", &.{values[1]});
    return c.JS_DupValue(engine.context, try scope.concat(prefix, try scope.stringify(encoded)));
}
fn textBlock(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const kind = scope.get(if (argc > 0) argv[0] else c.pi_js_undefined(), "type") catch |err| return sdk.fail(engine, err);
    const result = is(&scope, kind, "text") catch |err| return sdk.fail(engine, err);
    return c.pi_js_bool(engine.context, @intFromBool(result));
}
pub fn serialize(engine: *em.Engine, messages: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const parts = try scope.array();
    var rows = try iterate(&scope, messages);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |message| {
        defer engine.freeValue(message);
        var step: Scope = .{ .engine = engine };
        defer step.deinit();
        if (try is(&step, try step.get(message, "role"), "user")) {
            const content = try step.own(try replay.contentTextWithSeparator(engine, try step.get(message, "content"), try step.text("")));
            if (step.truthy(content)) {
                const push = try step.get(parts, "push");
                _ = try step.call(push, parts, &.{try step.concat(try step.text("[User]: "), try step.stringify(content))});
            }
        } else if (try is(&step, try step.get(message, "role"), "assistant")) {
            const calls = try step.array();
            var blocks = try iterate(&step, try step.get(message, "content"));
            defer blocks.deinit();
            errdefer blocks.closePreserving();
            while (try blocks.next()) |block| {
                defer engine.freeValue(block);
                var item: Scope = .{ .engine = engine };
                defer item.deinit();
                if (!try is(&item, try item.get(block, "type"), "toolCall")) continue;
                const args = try item.get(block, "arguments");
                const object = try item.global("Object");
                const entries = try item.invoke(object, "entries", &.{args});
                const map = try item.get(entries, "map");
                const mapper = try item.own(try engine.checked(c.JS_NewCFunction(engine.context, argumentEntry, "", 1)));
                const formatted = try item.call(map, entries, &.{mapper});
                const args_text = try item.invoke(formatted, "join", &.{try item.text(", ")});
                const push = try item.get(calls, "push");
                var text = try item.concat(try item.stringify(try item.get(block, "name")), try item.text("("));
                text = try item.concat(text, try item.stringify(args_text));
                text = try item.concat(text, try item.text(")"));
                _ = try item.call(push, calls, &.{text});
            }
            const content = try step.get(message, "content");
            const some = try step.get(content, "some");
            const predicate = try step.own(try engine.checked(c.JS_NewCFunction(engine.context, textBlock, "", 1)));
            if (step.truthy(try step.call(some, content, &.{predicate}))) {
                const push = try step.get(parts, "push");
                const text = try step.own(try replay.contentText(engine, try step.get(message, "content")));
                _ = try step.call(push, parts, &.{try step.concat(try step.text("[Assistant]: "), try step.stringify(text))});
            }
            if (try step.positive(try step.get(calls, "length"))) {
                const push = try step.get(parts, "push");
                const text = try step.invoke(calls, "join", &.{try step.text("; ")});
                _ = try step.call(push, parts, &.{try step.concat(try step.text("[Assistant tool calls]: "), try step.stringify(text))});
            }
        } else if (try is(&step, try step.get(message, "role"), "toolResult")) {
            const content = try step.own(try replay.contentTextWithSeparator(engine, try step.get(message, "content"), try step.text("")));
            if (step.truthy(content)) {
                const push = try step.get(parts, "push");
                _ = try step.call(push, parts, &.{try step.concat(try step.text("[Tool result]: "), try step.stringify(try truncate(&step, content)))});
            }
        }
    }
    return js.invoke(engine, parts, "join", &.{try scope.text("\n\n")});
}
