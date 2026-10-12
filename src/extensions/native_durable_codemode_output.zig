//! Durable CodeMode's result layout and asynchronous output-file callbacks.
//! The input is the owned result DTO from the sandbox, not executable source.
const std = @import("std");
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const vm = @import("native_values.zig");
const awaiting = @import("native_durable_await.zig");
const durable = @import("native_durable.zig");
const c = em.c;
const Engine = em.Engine;
const Scope = struct {
    engine: *Engine,
    values: std.ArrayList(c.JSValue) = .empty,
    fn deinit(self: *Scope) void {
        for (self.values.items) |value| self.engine.freeValue(value);
        self.values.deinit(self.engine.gpa);
    }
    fn own(self: *Scope, value: c.JSValue) !c.JSValue {
        self.values.append(self.engine.gpa, value) catch |err| {
            self.engine.freeValue(value);
            return err;
        };
        return value;
    }
    fn get(self: *Scope, object: c.JSValue, key: [:0]const u8) !c.JSValue {
        return self.own(try vm.get(self.engine, object, key));
    }
    fn invoke(self: *Scope, object: c.JSValue, key: [:0]const u8, args: []const c.JSValue) !c.JSValue {
        return self.own(try vm.invoke(self.engine, object, key, args));
    }
    fn text(self: *Scope, bytes: []const u8) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_NewStringLen(self.engine.context, bytes.ptr, bytes.len)));
    }
    fn item(self: *Scope, array: c.JSValue, index: usize) !c.JSValue {
        return self.own(try self.engine.checked(c.JS_GetPropertyUint32(self.engine.context, array, @intCast(index))));
    }
    fn concat(self: *Scope, parts: []const c.JSValue) !c.JSValue {
        // Template interpolation uses intrinsic ToString/concatenation. Keep
        // UTF-16 units, including the lone surrogates produced by slice().
        var units: std.ArrayList(u16) = .empty;
        defer units.deinit(self.engine.gpa);
        for (parts) |part| {
            var size: usize = 0;
            const bytes = c.JS_ToCStringLen2(self.engine.context, &size, part, true) orelse return js.capture(self.engine);
            defer c.JS_FreeCString(self.engine.context, bytes);
            var points = std.unicode.Wtf8View.initUnchecked(bytes[0..size]).iterator();
            while (points.nextCodepoint()) |point| {
                if (point <= 0xffff) try units.append(self.engine.gpa, @intCast(point)) else {
                    const rest = point - 0x10000;
                    try units.appendSlice(self.engine.gpa, &.{ @intCast(0xd800 + (rest >> 10)), @intCast(0xdc00 + (rest & 1023)) });
                }
            }
        }
        return self.own(try self.engine.checked(c.JS_NewStringUTF16(self.engine.context, units.items.ptr, units.items.len)));
    }
};
fn put(engine: *Engine, object: c.JSValue, key: [:0]const u8, value: c.JSValue) !void {
    try js.define(engine, object, key, c.JS_DupValue(engine.context, value));
}
fn is(scope: *Scope, value: c.JSValue, bytes: []const u8) !bool {
    return c.JS_IsStrictEqual(scope.engine.context, value, try scope.text(bytes));
}
fn truth(engine: *Engine, value: c.JSValue) bool {
    return c.JS_ToBool(engine.context, value) != 0;
}
fn number(engine: *Engine, value: c.JSValue) !f64 {
    var result: f64 = 0;
    if (c.JS_ToFloat64(engine.context, &result, value) < 0) return js.capture(engine);
    return result;
}
fn textItem(scope: *Scope, text: c.JSValue) !c.JSValue {
    const item = try scope.own(try vm.object(scope.engine));
    try put(scope.engine, item, "type", try scope.text("text"));
    try put(scope.engine, item, "text", text);
    return item;
}
fn intrinsics(scope: *Scope, state: c.JSValue) !awaiting.Intrinsics {
    return .{ .constructor = try scope.get(state, "promiseConstructor"), .resolve = try scope.get(state, "promiseResolve"), .then_function = try scope.get(state, "promiseThen") };
}
fn wait(engine: *Engine, state: c.JSValue, pending: c.JSValue, stage: c_int) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured = try intrinsics(&scope, state);
    return awaiting.continueWith(advance, engine, &captured, state, pending, stage);
}
fn copyArray(scope: *Scope, values: c.JSValue) !c.JSValue {
    const symbol = try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context)));
    return scope.own(try js.collect(scope.engine, values, symbol));
}
pub fn format(engine: *Engine, result: c.JSValue, options: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var captured = try awaiting.Intrinsics.init(engine);
    defer captured.deinit(engine);
    const state = try scope.own(try vm.object(engine));
    inline for (.{ .{ "result", result }, .{ "options", options }, .{ "promiseConstructor", captured.constructor }, .{ "promiseResolve", captured.resolve }, .{ "promiseThen", captured.then_function } }) |field| try put(engine, state, field[0], field[1]);
    const output = try copyArray(&scope, try scope.get(result, "output"));
    const ok = truth(engine, try scope.get(result, "ok"));
    if (ok) {
        const value = try scope.get(result, "value");
        if (!c.JS_IsUndefined(value)) {
            var text = value;
            if (!c.JS_IsString(value)) {
                text = try scope.invoke(try scope.own(try js.global(engine, "JSON")), "stringify", &.{value});
                if (c.JS_IsUndefined(text)) text = try scope.own(try engine.checked(c.JS_ToString(engine.context, value)));
            }
            try js.push(engine, output, try textItem(&scope, text));
        }
    }
    const items = try formatItems(&scope, output);
    if (!ok) try js.push(engine, items, try textItem(&scope, try scope.concat(&.{ try scope.text("Script error:\n"), try errorText(&scope, result, try scope.get(options, "calls")) })));
    const generated = try scope.get(options, "generatedImages");
    if (try number(engine, generated) > 0 and !try hasImages(&scope, items)) {
        const note = try scope.concat(&.{ try scope.text("Note: models.generateImages() returned "), generated, try scope.text(if (c.JS_IsStrictEqual(engine.context, generated, c.JS_NewInt32(engine.context, 1))) " image" else " images"), try scope.text(" that the script did not show. Show each image block of result.output with image(block).") });
        try js.push(engine, items, try textItem(&scope, note));
    }
    const joined = try joinAdjacent(&scope, items);
    return truncate(engine, state, joined);
}
fn formatItems(scope: *Scope, output: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    var total: usize = 0;
    for (0..try vm.length(engine, output)) |index| {
        const item = try scope.item(output, index);
        if (try is(scope, try scope.get(item, "type"), "text") and !truth(engine, try scope.get(item, "console"))) total += 1;
    }
    const items = try scope.own(try vm.array(engine));
    const console_lines = try scope.own(try vm.array(engine));
    var position: usize = 0;
    for (0..try vm.length(engine, output)) |index| {
        const item = try scope.item(output, index);
        if (try is(scope, try scope.get(item, "type"), "image")) try js.push(engine, items, item) else if (truth(engine, try scope.get(item, "console"))) {
            try js.push(engine, console_lines, try scope.get(item, "text"));
        } else {
            position += 1;
            const original = try scope.get(item, "text");
            const text = if (total > 1) try scope.concat(&.{ try scope.text("==> text "), c.JS_NewFloat64(engine.context, @floatFromInt(position)), try scope.text("/"), c.JS_NewFloat64(engine.context, @floatFromInt(total)), try scope.text(" <==\n"), original }) else original;
            try js.push(engine, items, try textItem(scope, text));
        }
    }
    if (try vm.length(engine, console_lines) > 0) {
        const text = try scope.concat(&.{ try scope.text("<console_output>\n"), try scope.invoke(console_lines, "join", &.{try scope.text("\n")}), try scope.text("\n</console_output>") });
        try js.push(engine, items, try textItem(scope, text));
    }
    return items;
}
fn joinAdjacent(scope: *Scope, items: c.JSValue) !c.JSValue {
    const engine = scope.engine;
    const joined = try scope.own(try vm.array(engine));
    var parts = try scope.own(try vm.array(engine));
    var last_part = try scope.text("");
    for (0..try vm.length(engine, items)) |index| {
        const item = try scope.item(items, index);
        if (!try is(scope, try scope.get(item, "type"), "text")) {
            try flushParts(scope, joined, parts);
            parts = try scope.own(try vm.array(engine));
            last_part = try scope.text("");
            try js.push(engine, joined, item);
            continue;
        }
        // Read only the last nonempty part. Rebuilding and then inspecting
        // the growing string for every item makes adjacent output quadratic.
        if (!try is(scope, last_part, "") and !truth(engine, try scope.invoke(last_part, "endsWith", &.{try scope.text("\n")}))) {
            last_part = try scope.text("\n");
            try js.push(engine, parts, last_part);
        }
        const text = try scope.get(item, "text");
        try js.push(engine, parts, text);
        if (!try is(scope, text, "")) last_part = text;
    }
    try flushParts(scope, joined, parts);
    return joined;
}
fn flushParts(scope: *Scope, joined: c.JSValue, parts: c.JSValue) !void {
    if (try vm.length(scope.engine, parts) > 0) try js.push(scope.engine, joined, try textItem(scope, try scope.invoke(parts, "join", &.{try scope.text("")})));
}
fn hasImages(scope: *Scope, items: c.JSValue) !bool {
    for (0..try vm.length(scope.engine, items)) |index| if (try is(scope, try scope.get(try scope.item(items, index), "type"), "image")) return true;
    return false;
}
fn errorText(scope: *Scope, result: c.JSValue, calls: c.JSValue) !c.JSValue {
    const error_value = try scope.get(result, "error");
    const kind = try scope.get(error_value, "kind");
    const message = try scope.get(error_value, "message");
    var head: c.JSValue = undefined;
    if (try is(scope, kind, "script")) {
        head = try scope.get(error_value, "stack");
        if (c.JS_IsUndefined(head) or c.JS_IsNull(head)) {
            const name = try scope.get(error_value, "name");
            head = try scope.concat(&.{ if (c.JS_IsUndefined(name) or c.JS_IsNull(name)) try scope.text("Error") else name, try scope.text(": "), message });
        }
    } else head = try scope.concat(&.{ try scope.text(if (try is(scope, kind, "timeout")) "Script timed out: " else if (try is(scope, kind, "aborted")) "Script aborted: " else "Script sandbox failed: "), message });
    const parts = try scope.own(try vm.array(scope.engine));
    for (0..try vm.length(scope.engine, calls)) |index| {
        const call = try scope.item(calls, index);
        try js.push(scope.engine, parts, try scope.concat(&.{ try scope.get(call, "name"), try scope.text(" ("), try scope.get(call, "status"), try scope.text(")") }));
    }
    const summary = if (try vm.length(scope.engine, parts) == 0) try scope.text("No tool calls were made.") else try scope.concat(&.{ try scope.text("Tool calls made before the failure (they are not undone): "), try scope.invoke(parts, "join", &.{try scope.text(", ")}) });
    return scope.concat(&.{ head, try scope.text("\n\n"), summary });
}
fn truncate(engine: *Engine, state: c.JSValue, items: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const texts = try scope.own(try vm.array(engine));
    for (0..try vm.length(engine, items)) |index| {
        const item = try scope.item(items, index);
        if (try is(&scope, try scope.get(item, "type"), "text")) try js.push(engine, texts, try scope.get(item, "text"));
    }
    const combined = try scope.invoke(texts, "join", &.{try scope.text("\n")});
    const options = try scope.get(state, "options");
    const max_tokens = try scope.get(options, "maxOutputTokens");
    const limits = try scope.get(options, "limits");
    const writer = try scope.get(options, "write");
    const math = try scope.own(try js.global(engine, "Math"));
    const byte_budget = try scope.invoke(math, "floor", &.{c.JS_NewFloat64(engine.context, try number(engine, try scope.get(limits, "maxBytes")) / 4)});
    const budget = try number(engine, try scope.invoke(math, "min", &.{ c.JS_NewFloat64(engine.context, try number(engine, max_tokens) * 4), byte_budget }));
    const line_budget = try number(engine, try scope.invoke(math, "floor", &.{c.JS_NewFloat64(engine.context, (try number(engine, try scope.get(limits, "maxLines")) - 100) / 2)}));
    const lines = try scope.invoke(combined, "split", &.{try scope.text("\n")});
    const length: f64 = @floatFromInt(try vm.length(engine, combined));
    if (try vm.length(engine, texts) == 0 or (length <= budget and @as(f64, @floatFromInt(try vm.length(engine, lines))) <= 2 * line_budget)) {
        try put(engine, state, "items", try copyArray(&scope, items));
        return saveImages(engine, state);
    }
    const head_chars = try number(engine, try scope.invoke(math, "floor", &.{c.JS_NewFloat64(engine.context, budget / 2)}));
    const tail_chars = budget - head_chars;
    const first = try scope.invoke(combined, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, head_chars) });
    const first_lines = try scope.invoke(first, "split", &.{try scope.text("\n")});
    const selected_head = try scope.invoke(first_lines, "slice", &.{ c.JS_NewInt32(engine.context, 0), c.JS_NewFloat64(engine.context, line_budget) });
    const head = try scope.invoke(selected_head, "join", &.{try scope.text("\n")});
    var tail = try scope.text("");
    if (tail_chars > 0) {
        const last = try scope.invoke(combined, "slice", &.{c.JS_NewFloat64(engine.context, -tail_chars)});
        const last_lines = try scope.invoke(last, "split", &.{try scope.text("\n")});
        const selected_tail = try scope.invoke(last_lines, "slice", &.{c.JS_NewFloat64(engine.context, -line_budget)});
        tail = try scope.invoke(selected_tail, "join", &.{try scope.text("\n")});
    }
    const original_tokens = try scope.invoke(math, "ceil", &.{c.JS_NewFloat64(engine.context, length / 4)});
    const removed = length - @as(f64, @floatFromInt(try vm.length(engine, head))) - @as(f64, @floatFromInt(try vm.length(engine, tail)));
    const removed_tokens = try scope.invoke(math, "ceil", &.{c.JS_NewFloat64(engine.context, removed / 4)});
    const text = try scope.concat(&.{ try scope.text("Warning: truncated output (original token count: "), original_tokens, try scope.text(")\nTotal output lines: "), c.JS_NewFloat64(engine.context, @floatFromInt(try vm.length(engine, lines))), try scope.text("\n\n"), head, try scope.text("…"), removed_tokens, try scope.text(" tokens truncated…"), tail });
    try put(engine, state, "truncatedText", text);
    try put(engine, state, "originalItems", items);
    const pending = try scope.own(try js.call(engine, writer, c.pi_js_undefined(), &.{ try scope.text("output.txt"), combined }));
    return wait(engine, state, pending, 1);
}
fn saveImages(engine: *Engine, state: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    try put(engine, state, "imageWriter", try scope.get(try scope.get(state, "options"), "write"));
    try put(engine, state, "labels", try scope.own(try js.builtin(engine, "Map", &.{})));
    const promise = try scope.own(try js.global(engine, "Promise"));
    const all = try scope.get(promise, "all");
    var data = [_]c.JSValue{state};
    const mapper = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, mapImage, "", 1, 0, data.len, &data)));
    const pending = try scope.invoke(try scope.get(state, "items"), "map", &.{mapper});
    const combined = try scope.own(try js.call(engine, all, promise, &.{pending}));
    return wait(engine, state, combined, 2);
}
fn mapImage(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, data: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return mapImageOwned(engine, data[0], if (argc > 0) argv[0] else c.pi_js_undefined()) catch |err| durable.rejectedPromise(engine, err);
}
fn mapImageOwned(engine: *Engine, state: c.JSValue, item: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try is(&scope, try scope.get(item, "type"), "image")) {
        const result = try scope.own(try vm.array(engine));
        try js.push(engine, result, item);
        const captured = try intrinsics(&scope, state);
        var args = [_]c.JSValue{result};
        return engine.checked(c.JS_Call(engine.context, captured.resolve, captured.constructor, 1, &args));
    }
    const labels = try scope.get(state, "labels");
    const key = try scope.get(item, "data");
    var pending = try scope.invoke(labels, "get", &.{key});
    if (c.JS_IsUndefined(pending)) {
        const index = try number(engine, try scope.get(labels, "size")) + 1;
        pending = try scope.own(label(engine, state, item, index) catch |err| durable.rejectedPromise(engine, err));
        _ = try scope.invoke(labels, "set", &.{ key, pending });
    }
    const child = try scope.own(try vm.object(engine));
    try put(engine, child, "root", state);
    try put(engine, child, "item", item);
    inline for (.{ "promiseConstructor", "promiseResolve", "promiseThen" }) |field| try put(engine, child, field, try scope.get(state, field));
    return wait(engine, child, pending, 3);
}
fn byteCode(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = Engine.fromContext(context.?);
    return vm.invoke(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), "charCodeAt", &.{c.JS_NewInt32(context, 0)}) catch |err| durable.reject(engine, err);
}
fn label(engine: *Engine, state: c.JSValue, item: c.JSValue, index: f64) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const bytes_constructor = try scope.own(try js.global(engine, "Uint8Array"));
    const from = try scope.get(bytes_constructor, "from");
    const atob = try scope.own(try js.global(engine, "atob"));
    const binary = try scope.own(try js.call(engine, atob, c.pi_js_undefined(), &.{try scope.get(item, "data")}));
    const mapper = try scope.own(try engine.checked(c.JS_NewCFunction(engine.context, byteCode, "", 1)));
    const bytes = try scope.own(try js.call(engine, from, bytes_constructor, &.{ binary, mapper }));
    const mime = try scope.get(item, "mimeType");
    const kind = try scope.concat(&.{ mime, try scope.text(", "), try scope.get(bytes, "length"), try scope.text(" bytes") });
    const extensions = try scope.own(try vm.object(engine));
    inline for (.{ .{ "image/png", ".png" }, .{ "image/jpeg", ".jpg" }, .{ "image/gif", ".gif" }, .{ "image/webp", ".webp" } }) |pair| {
        const key = try scope.text(pair[0]);
        try js.setKey(engine, extensions, key, try scope.text(pair[1]));
    }
    var suffix = try scope.own(try js.getKey(engine, extensions, mime));
    if (c.JS_IsUndefined(suffix) or c.JS_IsNull(suffix)) suffix = try scope.text(".bin");
    const name = try scope.concat(&.{ try scope.text("image-"), c.JS_NewFloat64(engine.context, index), suffix });
    const child = try scope.own(try vm.object(engine));
    try put(engine, child, "kind", kind);
    inline for (.{ "promiseConstructor", "promiseResolve", "promiseThen" }) |field| try put(engine, child, field, try scope.get(state, field));
    const writer = try scope.get(state, "imageWriter");
    const pending = try scope.own(try js.call(engine, writer, c.pi_js_undefined(), &.{ name, bytes }));
    return wait(engine, child, pending, 4);
}
fn advance(engine: *Engine, state: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !c.JSValue {
    if (rejected) return engine.checked(c.JS_Throw(engine.context, c.JS_DupValue(engine.context, value)));
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (stage == 1) {
        const has_path = try js.hasKey(engine, value, try scope.text("path"));
        const note = if (has_path) try scope.concat(&.{ try scope.text("\n\n[Full output: "), try scope.get(value, "path"), try scope.text(" (read with offset/limit)]") }) else try scope.concat(&.{ try scope.text("\n\n[Could not save the full output: "), try scope.get(value, "error"), try scope.text("]") });
        const items = try scope.own(try vm.array(engine));
        try js.push(engine, items, try textItem(&scope, try scope.concat(&.{ try scope.get(state, "truncatedText"), note })));
        const original = try scope.get(state, "originalItems");
        for (0..try vm.length(engine, original)) |index| {
            const item = try scope.item(original, index);
            if (try is(&scope, try scope.get(item, "type"), "image")) try js.push(engine, items, item);
        }
        if (has_path) try put(engine, state, "fullOutputPath", try scope.get(value, "path"));
        try put(engine, state, "items", items);
        return saveImages(engine, state);
    }
    if (stage == 2) {
        const flattened = try scope.invoke(value, "flat", &.{});
        const content = try joinAdjacent(&scope, flattened);
        const options = try scope.get(state, "options");
        const ok = truth(engine, try scope.get(try scope.get(state, "result"), "ok"));
        const seconds = c.JS_NewFloat64(engine.context, try number(engine, try scope.get(options, "wallMs")) / 1000);
        const wall = try scope.invoke(seconds, "toFixed", &.{c.JS_NewInt32(engine.context, 1)});
        const header = try scope.concat(&.{ try scope.text(if (ok) "Script completed\nWall time " else "Script failed\nWall time "), wall, try scope.text(" seconds\nOutput:\n") });
        const output = try scope.own(try vm.array(engine));
        try js.push(engine, output, try textItem(&scope, header));
        for (0..try vm.length(engine, content)) |index| try js.push(engine, output, try scope.item(content, index));
        const result = try vm.object(engine);
        errdefer engine.freeValue(result);
        try put(engine, result, "content", output);
        const path = try scope.get(state, "fullOutputPath");
        if (!c.JS_IsUndefined(path)) try put(engine, result, "fullOutputPath", path);
        return result;
    }
    if (stage == 3) {
        const result = try vm.array(engine);
        errdefer engine.freeValue(result);
        try js.push(engine, result, try textItem(&scope, value));
        try js.push(engine, result, try scope.get(state, "item"));
        return result;
    }
    if (stage == 4) {
        const kind = try scope.get(state, "kind");
        if (try js.hasKey(engine, value, try scope.text("path"))) return c.JS_DupValue(engine.context, try scope.concat(&.{ try scope.text("[Image saved to "), try scope.get(value, "path"), try scope.text(" ("), kind, try scope.text(")]") }));
        return c.JS_DupValue(engine.context, try scope.concat(&.{ try scope.text("[Image ("), kind, try scope.text(") could not be saved: "), try scope.get(value, "error"), try scope.text("]") }));
    }
    return error.InvalidCodemodeOutputContinuation;
}
