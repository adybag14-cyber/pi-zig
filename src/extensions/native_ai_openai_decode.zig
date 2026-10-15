//! Actual OpenAI-completions chunk decoder, shared by its real provider factories.
//! Owner-thread state is GC-visible JS values. HTTP, callbacks/retries and request
//! construction belong to the caller; this is not a complete provider binding.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_models_stream_scope.zig");
const Scope = temp.Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;
const Method = enum { start, push, finish };
fn eq(scope: *Scope, value: c.JSValue, text: []const u8) !bool {
    return scope.equal(value, try scope.text(text));
}
fn at(scope: *Scope, value: c.JSValue, index: u32) !c.JSValue {
    return scope.own(try scope.engine.checked(c.JS_GetPropertyUint32(scope.engine.context, value, index)));
}
fn optional(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !c.JSValue {
    return if (temp.nullish(value)) c.pi_js_undefined() else scope.get(value, name);
}
fn orZero(scope: *Scope, value: c.JSValue) c.JSValue {
    return if (scope.truthy(value)) value else c.JS_NewInt32(scope.engine.context, 0);
}
fn binary(scope: *Scope, operation: arithmetic.Operation, left: c.JSValue, right: c.JSValue) !c.JSValue {
    return scope.own(try arithmetic.binary(scope.engine, operation, left, right));
}
fn remove(scope: *Scope, value: c.JSValue, name: [*:0]const u8) !void {
    const atom = c.JS_NewAtom(scope.engine.context, name);
    if (atom == c.JS_ATOM_NULL) return js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    if (c.JS_DeleteProperty(scope.engine.context, value, atom, c.JS_PROP_THROW) < 0) return js.capture(scope.engine);
}
fn emit(scope: *Scope, owner: c.JSValue, kind: []const u8, block: ?c.JSValue, key: ?[*:0]const u8, value: c.JSValue) !void {
    const event = try scope.object();
    try scope.put(event, "type", try scope.text(kind));
    const output = try scope.get(owner, "output");
    if (block) |item| {
        const index = try scope.invoke(try scope.get(output, "content"), "indexOf", &.{item});
        try scope.put(event, "contentIndex", index);
    }
    if (key) |name| try scope.put(event, name, value);
    try scope.put(event, if (@import("std").mem.eql(u8, kind, "done")) "message" else if (@import("std").mem.eql(u8, kind, "error")) "error" else "partial", output);
    _ = try scope.invoke(try scope.get(owner, "stream"), "push", &.{event});
}
pub fn create(engine: *em.Engine, model: c.JSValue, compat: c.JSValue, stream: c.JSValue, json_api: c.JSValue, grammar_properties: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const owner = try scope.object();
    try scope.put(owner, "model", model);
    try scope.put(owner, "compat", compat);
    try scope.put(owner, "stream", stream);
    try scope.put(owner, "json", json_api);
    try scope.put(owner, "grammar", grammar_properties);
    inline for (.{ "byIndex", "byId" }) |name| try scope.put(owner, name, try scope.own(try js.builtin(engine, "Map", &.{})));
    inline for (.{ "text", "thinking", "details" }) |name| try scope.put(owner, name, c.pi_js_undefined());
    inline for (.{ "finished", "hasFinish" }) |name| try scope.put(owner, name, c.pi_js_bool(engine.context, 0));
    const output = try scope.object();
    try scope.put(output, "role", try scope.text("assistant"));
    try scope.put(output, "content", try scope.array());
    inline for (.{ "api", "provider" }) |name| try scope.put(output, name, try scope.get(model, name));
    try scope.put(output, "model", try scope.get(model, "id"));
    const usage = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "totalTokens" }) |name| try scope.put(usage, name, c.JS_NewInt32(engine.context, 0));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |name| try scope.put(cost, name, c.JS_NewInt32(engine.context, 0));
    try scope.put(usage, "cost", cost);
    try scope.put(output, "usage", usage);
    try scope.put(output, "stopReason", try scope.text("pending"));
    try scope.put(output, "timestamp", try scope.invoke(try scope.global("Date"), "now", &.{}));
    try scope.put(owner, "output", output);
    const exported = try scope.object();
    try scope.put(exported, "output", output);
    inline for (@typeInfo(Method).@"enum".fields) |field| {
        const Adapter = struct {
            fn call(host: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = host };
                defer row.deinit();
                if (row.truthy(try row.get(roots[0], "finished"))) return error.OpenAIDecoderAlreadyFinished;
                switch (@as(Method, @enumFromInt(field.value))) {
                    .start => try emit(&row, roots[0], "start", null, null, c.pi_js_undefined()),
                    .push => try chunk(&row, roots[0], if (args.len > 0) args[0] else c.pi_js_undefined()),
                    .finish => try finish(&row, roots[0], args.len > 0 and row.truthy(args[0])),
                }
                return c.pi_js_undefined();
            }
        };
        try scope.put(exported, field.name, try scope.own(try @import("native_node_function.zig").create(engine, field.name, if (field.value == 0) 0 else 1, Adapter.call, &.{owner})));
    }
    return c.JS_DupValue(engine.context, exported);
}
fn ensure(scope: *Scope, owner: c.JSValue, thinking: bool, signature: c.JSValue) !c.JSValue {
    const key: [*:0]const u8 = if (thinking) "thinking" else "text";
    var block = try scope.get(owner, key);
    if (!scope.truthy(block)) {
        block = try scope.object();
        try scope.put(block, "type", try scope.text(@import("std").mem.span(key)));
        try scope.put(block, key, try scope.text(""));
        if (thinking) try scope.put(block, "thinkingSignature", signature);
        try scope.put(owner, key, block);
        _ = try scope.invoke(try scope.get(try scope.get(owner, "output"), "content"), "push", &.{block});
        try emit(scope, owner, if (thinking) "thinking_start" else "text_start", block, null, c.pi_js_undefined());
    }
    return block;
}
fn parseUsage(scope: *Scope, owner: c.JSValue, raw: c.JSValue) !void {
    const result = try scope.object();
    const prompt = orZero(scope, try scope.get(raw, "prompt_tokens"));
    var read = try optional(scope, try scope.get(raw, "prompt_tokens_details"), "cached_tokens");
    if (temp.nullish(read)) read = try scope.get(raw, "prompt_cache_hit_tokens");
    if (temp.nullish(read)) read = try scope.get(raw, "cached_tokens");
    if (temp.nullish(read)) read = c.JS_NewInt32(scope.engine.context, 0);
    const write = orZero(scope, try optional(scope, try scope.get(raw, "prompt_tokens_details"), "cache_write_tokens"));
    const difference = try binary(scope, .subtract, try binary(scope, .subtract, prompt, read), write);
    const input = try scope.invoke(try scope.global("Math"), "max", &.{ c.JS_NewInt32(scope.engine.context, 0), difference });
    const output = orZero(scope, try scope.get(raw, "completion_tokens"));
    try scope.put(result, "input", input);
    try scope.put(result, "output", output);
    try scope.put(result, "cacheRead", read);
    try scope.put(result, "cacheWrite", write);
    try scope.put(result, "reasoning", orZero(scope, try optional(scope, try scope.get(raw, "completion_tokens_details"), "reasoning_tokens")));
    try scope.put(result, "totalTokens", try binary(scope, .add, try binary(scope, .add, try binary(scope, .add, input, output), read), write));
    const cost = try scope.object();
    inline for (.{ "input", "output", "cacheRead", "cacheWrite", "total" }) |name| try scope.put(cost, name, c.JS_NewInt32(scope.engine.context, 0));
    try scope.put(result, "cost", cost);
    _ = try scope.own(try @import("native_ai_cost.zig").calculate(scope.engine, try scope.get(owner, "model"), result));
    try scope.put(try scope.get(owner, "output"), "usage", result);
}
fn stop(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !void {
    const output = try scope.get(owner, "output");
    try scope.put(output, "rawStopReason", reason);
    const mapped: []const u8 = if (try eq(scope, reason, "stop") or try eq(scope, reason, "end")) "stop" else if (try eq(scope, reason, "length")) "length" else if (try eq(scope, reason, "function_call") or try eq(scope, reason, "tool_calls")) "toolUse" else "error";
    try scope.put(output, "stopReason", try scope.text(mapped));
    if (@import("std").mem.eql(u8, mapped, "error")) try scope.put(output, "errorMessage", try scope.concat(try scope.text("Provider finish_reason: "), try scope.stringify(reason)));
    try scope.put(owner, "hasFinish", c.pi_js_bool(scope.engine.context, 1));
}
fn chunk(scope: *Scope, owner: c.JSValue, value: c.JSValue) !void {
    if (!scope.truthy(value) or !c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) return;
    const output = try scope.get(owner, "output");
    if (!scope.truthy(try scope.get(output, "responseId"))) try scope.put(output, "responseId", try scope.get(value, "id"));
    const response_model = try scope.get(value, "model");
    if (c.JS_IsString(response_model) and scope.truthy(try scope.get(response_model, "length")) and !scope.equal(response_model, try scope.get(try scope.get(owner, "model"), "id")) and !scope.truthy(try scope.get(output, "responseModel"))) try scope.put(output, "responseModel", response_model);
    const raw_usage = try scope.get(value, "usage");
    if (scope.truthy(raw_usage)) try parseUsage(scope, owner, raw_usage);
    const choices = try scope.get(value, "choices");
    const choice = if (scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{choices}))) try at(scope, choices, 0) else c.pi_js_undefined();
    if (!scope.truthy(choice)) return;
    if (!scope.truthy(raw_usage) and scope.truthy(try scope.get(choice, "usage"))) try parseUsage(scope, owner, try scope.get(choice, "usage"));
    if (scope.truthy(try scope.get(choice, "finish_reason"))) try stop(scope, owner, try scope.get(choice, "finish_reason"));
    const delta = try scope.get(choice, "delta");
    if (!scope.truthy(delta)) return;
    for ([_][*:0]const u8{ "reasoning_content", "reasoning", "reasoning_text" }) |field| {
        const text = try scope.get(delta, field);
        if (c.JS_IsString(text) and scope.truthy(try scope.get(text, "length"))) {
            const signature = if (try eq(scope, try scope.get(try scope.get(owner, "model"), "provider"), "opencode-go") and @import("std").mem.eql(u8, @import("std").mem.span(field), "reasoning")) try scope.text("reasoning_content") else try scope.text(@import("std").mem.span(field));
            const block = try ensure(scope, owner, true, signature);
            try scope.put(block, "thinking", try scope.concat(try scope.get(block, "thinking"), text));
            try emit(scope, owner, "thinking_delta", block, "delta", text);
            break;
        }
    }
    const details = try scope.get(delta, "reasoning_details");
    if (scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{details}))) {
        var index: u32 = 0;
        while (try arithmetic.compare(scope.engine, .less, c.JS_NewUint32(scope.engine.context, index), try scope.get(details, "length"))) : (index += 1) {
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            const detail = try at(&row, details, index);
            if (!try validDetail(&row, detail)) continue;
            _ = try ensure(&row, owner, true, try row.text(""));
            var stored = try row.get(owner, "details");
            if (temp.nullish(stored)) {
                stored = try row.array();
                try row.put(owner, "details", stored);
            }
            try appendDetail(&row, stored, detail);
        }
    }
    const text = try scope.get(delta, "content");
    if (!temp.nullish(text) and try arithmetic.compare(scope.engine, .greater, try scope.get(text, "length"), c.JS_NewInt32(scope.engine.context, 0))) {
        const block = try ensure(scope, owner, false, c.pi_js_undefined());
        try scope.put(block, "text", try scope.concat(try scope.get(block, "text"), text));
        try emit(scope, owner, "text_delta", block, "delta", text);
    }
    const calls = try scope.get(delta, "tool_calls");
    if (scope.truthy(calls)) {
        var iterator = try js.Iterator.init(scope.engine, calls, try scope.own(try scope.engine.checked(c.JS_GetIteratorSymbol(scope.engine.context))));
        defer iterator.deinit();
        errdefer iterator.closePreserving();
        while (try iterator.next()) |item| {
            defer scope.engine.freeValue(item);
            var row: Scope = .{ .engine = scope.engine };
            defer row.deinit();
            try tool(&row, owner, item);
        }
    }
}
fn validDetail(scope: *Scope, value: c.JSValue) !bool {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value) or scope.truthy(try scope.invoke(try scope.global("Array"), "isArray", &.{value}))) return false;
    const id = try scope.get(value, "id");
    if (!temp.nullish(id) and !c.JS_IsString(id)) return false;
    const format = try scope.get(value, "format");
    if (!c.JS_IsUndefined(format) and !c.JS_IsString(format)) return false;
    const index = try scope.get(value, "index");
    if (!c.JS_IsUndefined(index) and !c.JS_IsNumber(index)) return false;
    const kind = try scope.get(value, "type");
    if (try eq(scope, kind, "reasoning.summary")) return c.JS_IsString(try scope.get(value, "summary"));
    if (try eq(scope, kind, "reasoning.encrypted")) return c.JS_IsString(try scope.get(value, "data"));
    if (try eq(scope, kind, "reasoning.text")) {
        const signature = try scope.get(value, "signature");
        return c.JS_IsString(try scope.get(value, "text")) and (temp.nullish(signature) or c.JS_IsString(signature));
    }
    return false;
}
fn appendDetail(scope: *Scope, stored: c.JSValue, detail: c.JSValue) !void {
    const last = try scope.invoke(stored, "at", &.{c.JS_NewInt32(scope.engine.context, -1)});
    const kind = try scope.get(detail, "type");
    if (!temp.nullish(last) and scope.equal(kind, try scope.get(last, "type")) and (try eq(scope, kind, "reasoning.text") or try eq(scope, kind, "reasoning.summary"))) {
        const key: [*:0]const u8 = if (try eq(scope, kind, "reasoning.text")) "text" else "summary";
        try scope.put(last, key, try scope.concat(try scope.get(last, key), try scope.get(detail, key)));
        if (try eq(scope, kind, "reasoning.text") and !scope.truthy(try scope.get(last, "signature"))) try scope.put(last, "signature", try scope.get(detail, "signature"));
        inline for (.{ "id", "index" }) |name| if (temp.nullish(try scope.get(last, name))) {
            try scope.put(last, name, try scope.get(detail, name));
        };
        if (!scope.truthy(try scope.get(last, "format"))) try scope.put(last, "format", try scope.get(detail, "format"));
    } else _ = try scope.invoke(stored, "push", &.{try scope.own(try js.spread(scope.engine, detail))});
}
fn tool(scope: *Scope, owner: c.JSValue, item: c.JSValue) !void {
    const index = try scope.get(item, "index");
    const id = try scope.get(item, "id");
    const function = try scope.get(item, "function");
    const custom = try scope.get(item, "custom");
    var name = try optional(scope, function, "name");
    if (temp.nullish(name)) name = try optional(scope, custom, "name");
    if (temp.nullish(name)) name = try scope.text("");
    const by_index = try scope.get(owner, "byIndex");
    const by_id = try scope.get(owner, "byId");
    var block = if (c.JS_IsNumber(index)) try scope.invoke(by_index, "get", &.{index}) else c.pi_js_undefined();
    if (!scope.truthy(block) and scope.truthy(id)) block = try scope.invoke(by_id, "get", &.{id});
    if (!scope.truthy(block)) {
        block = try scope.object();
        try scope.put(block, "type", try scope.text("toolCall"));
        try scope.put(block, "id", if (scope.truthy(id)) id else try scope.text(""));
        try scope.put(block, "name", name);
        try scope.put(block, "arguments", try scope.object());
        try scope.put(block, "partialArgs", try scope.text(""));
        try scope.put(block, "customInput", c.pi_js_undefined());
        try scope.put(block, "streamIndex", if (c.JS_IsNumber(index)) index else c.pi_js_undefined());
        if (scope.truthy(custom) and !scope.truthy(function)) try customInit(scope, owner, block, name);
        if (c.JS_IsNumber(index)) _ = try scope.invoke(by_index, "set", &.{ index, block });
        if (scope.truthy(id)) _ = try scope.invoke(by_id, "set", &.{ id, block });
        _ = try scope.invoke(try scope.get(try scope.get(owner, "output"), "content"), "push", &.{block});
        try emit(scope, owner, "toolcall_start", block, null, c.pi_js_undefined());
    }
    if (c.JS_IsNumber(index) and c.JS_IsUndefined(try scope.get(block, "streamIndex"))) {
        try scope.put(block, "streamIndex", index);
        _ = try scope.invoke(by_index, "set", &.{ index, block });
    }
    if (scope.truthy(id)) _ = try scope.invoke(by_id, "set", &.{ id, block });
    if (!scope.truthy(try scope.get(block, "name")) and scope.truthy(name)) try scope.put(block, "name", name);
    if (scope.truthy(custom) and !scope.truthy(function) and !scope.truthy(try scope.get(block, "customInput"))) {
        try customInit(scope, owner, block, try scope.get(block, "name"));
        try remove(scope, block, "partialArgs");
    }
    if (!scope.truthy(try scope.get(block, "id")) and scope.truthy(id)) {
        try scope.put(block, "id", id);
        _ = try scope.invoke(by_id, "set", &.{ id, block });
    }
    var delta = try scope.text("");
    const args = try optional(scope, function, "arguments");
    const custom_text = try optional(scope, custom, "input");
    if (scope.truthy(args)) {
        delta = args;
        const previous = try scope.get(block, "partialArgs");
        const partial = try scope.concat(if (temp.nullish(previous)) try scope.text("") else previous, args);
        try scope.put(block, "partialArgs", partial);
        try scope.put(block, "arguments", try scope.invoke(try scope.get(owner, "json"), "parseStreamingJson", &.{partial}));
    } else if (scope.truthy(custom_text)) {
        const property = try optional(scope, try scope.get(block, "customInput"), "property");
        const prior = if (c.JS_IsUndefined(property)) c.pi_js_undefined() else try scope.own(try js.getKey(scope.engine, try scope.get(block, "arguments"), property));
        delta = try customAppend(scope, block, try scope.concat(if (c.JS_IsString(prior)) prior else try scope.text(""), custom_text), false);
        if (c.JS_IsUndefined(delta)) delta = try scope.text("");
    }
    try emit(scope, owner, "toolcall_delta", block, "delta", delta);
}
fn customInit(scope: *Scope, owner: c.JSValue, block: c.JSValue, name: c.JSValue) !void {
    var property = try scope.invoke(try scope.get(owner, "grammar"), "get", &.{name});
    if (temp.nullish(property)) property = try scope.text("input");
    const args = try scope.object();
    try js.setKey(scope.engine, args, property, try scope.text(""));
    try scope.put(block, "arguments", args);
    const custom = try scope.object();
    try scope.put(custom, "property", property);
    const buffer = try scope.object();
    try scope.put(buffer, "input", try scope.text(""));
    inline for (.{ "started", "closed" }) |key| try scope.put(buffer, key, c.pi_js_bool(scope.engine.context, 0));
    try scope.put(custom, "jsonBuffer", buffer);
    try scope.put(block, "customInput", custom);
    try scope.put(block, "partialArgs", c.pi_js_undefined());
}
fn customAppend(scope: *Scope, block: c.JSValue, next: c.JSValue, close: bool) !c.JSValue {
    const custom = try scope.get(block, "customInput");
    if (!scope.truthy(custom)) return c.pi_js_undefined();
    const buffer = try scope.get(custom, "jsonBuffer");
    const property = try scope.get(custom, "property");
    const previous = try scope.get(buffer, "input");
    if (scope.truthy(try scope.get(buffer, "closed"))) {
        if (close and scope.equal(next, previous)) return c.pi_js_undefined();
        return error.GrammarInputChangedAfterClose;
    }
    if (!scope.truthy(try scope.invoke(next, "startsWith", &.{previous}))) return error.GrammarInputChangedNonMonotonically;
    const added = try scope.invoke(next, "slice", &.{try scope.get(previous, "length")});
    if (!close and !scope.truthy(try scope.get(added, "length"))) return c.pi_js_undefined();
    var delta = try scope.text("");
    const json = try scope.global("JSON");
    if (!scope.truthy(try scope.get(buffer, "started"))) {
        delta = try scope.concat(try scope.concat(try scope.text("{"), try scope.invoke(json, "stringify", &.{property})), try scope.text(":\""));
        try scope.put(buffer, "started", c.pi_js_bool(scope.engine.context, 1));
    }
    delta = try scope.concat(delta, try scope.invoke(try scope.invoke(json, "stringify", &.{added}), "slice", &.{ c.JS_NewInt32(scope.engine.context, 1), c.JS_NewInt32(scope.engine.context, -1) }));
    try scope.put(buffer, "input", next);
    if (close) {
        delta = try scope.concat(delta, try scope.text("\"}"));
        try scope.put(buffer, "closed", c.pi_js_bool(scope.engine.context, 1));
    }
    const args = try scope.object();
    try js.setKey(scope.engine, args, property, next);
    try scope.put(block, "arguments", args);
    return delta;
}
fn finish(scope: *Scope, owner: c.JSValue, aborted: bool) !void {
    const output = try scope.get(owner, "output");
    const blocks = try scope.get(output, "content");
    var has_tools = false;
    var index: u32 = 0;
    while (try arithmetic.compare(scope.engine, .less, c.JS_NewUint32(scope.engine.context, index), try scope.get(blocks, "length"))) : (index += 1) {
        var row: Scope = .{ .engine = scope.engine };
        defer row.deinit();
        const block = try at(&row, blocks, index);
        const kind = try row.get(block, "type");
        if (try eq(&row, kind, "text")) try emit(&row, owner, "text_end", block, "content", try row.get(block, "text")) else if (try eq(&row, kind, "thinking")) {
            const details = try row.get(owner, "details");
            if (!c.JS_IsUndefined(details)) try row.put(block, "thinkingSignature", try row.invoke(try row.global("JSON"), "stringify", &.{details}));
            try emit(&row, owner, "thinking_end", block, "content", try row.get(block, "thinking"));
        } else if (try eq(&row, kind, "toolCall")) {
            has_tools = true;
            const custom = try row.get(block, "customInput");
            if (row.truthy(custom)) {
                const property = try row.get(custom, "property");
                const input = try row.own(try js.getKey(row.engine, try row.get(block, "arguments"), property));
                const delta = try customAppend(&row, block, if (c.JS_IsString(input)) input else try row.text(""), true);
                if (!c.JS_IsUndefined(delta)) try emit(&row, owner, "toolcall_delta", block, "delta", delta);
            } else {
                const parsed = try row.invoke(try row.get(owner, "json"), "parseToolCallArguments", &.{try row.get(block, "partialArgs")});
                _ = try row.invoke(try row.global("Object"), "assign", &.{ block, parsed });
            }
            inline for (.{ "partialArgs", "customInput", "streamIndex" }) |key| try remove(&row, block, key);
            try emit(&row, owner, "toolcall_end", block, "toolCall", block);
        }
    }
    const has_finish = scope.truthy(try scope.get(owner, "hasFinish"));
    const supports = scope.truthy(try scope.get(try scope.get(owner, "compat"), "supportsFinishReason"));
    var reason = try scope.get(output, "stopReason");
    if (!has_finish and !supports) {
        reason = try scope.text(if (has_tools) "toolUse" else "stop");
        try scope.put(output, "stopReason", reason);
    }
    var message: ?c.JSValue = null;
    if (aborted) message = try scope.text("Request was aborted") else if (try eq(scope, reason, "error")) {
        const text = try scope.get(output, "errorMessage");
        message = if (scope.truthy(text)) text else try scope.text("Provider returned an error stop reason");
    } else if ((supports and !has_finish) or try eq(scope, reason, "pending")) message = try scope.text("Stream ended without finish_reason");
    if (message) |text| {
        reason = try scope.text(if (aborted) "aborted" else "error");
        try scope.put(output, "stopReason", reason);
        try scope.put(output, "errorMessage", text);
    }
    try emit(scope, owner, if (message != null) "error" else "done", null, "reason", reason);
    _ = try scope.invoke(try scope.get(owner, "stream"), "end", &.{});
    try scope.put(owner, "finished", c.pi_js_bool(scope.engine.context, 1));
}
