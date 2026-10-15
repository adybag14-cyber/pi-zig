//! Native port of pinned @google/genai GenerateContentResponse callback values.
//! Actual callback metadata retained in genuine Source60; native gates pending.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const cache_key = "\x00native-google-response";
const Kind = enum(c_int) { text, data, functionCalls, executableCode, codeExecutionResult };
fn construct(engine: *v.em.Engine, target: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return @import("native_class.zig").object(engine, target);
}
fn getter(context: ?*c.JSContext, receiver: c.JSValue, _: c_int, _: [*c]c.JSValue, magic: c_int) callconv(.c) c.JSValue {
    const engine = v.em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return get(engine, receiver, @enumFromInt(magic)) catch |err| @import("native_sdk.zig").fail(engine, err);
}
pub fn create(engine: *v.em.Engine) !c.JSValue {
    if (engine.native_module_values.get(cache_key)) |value| return c.JS_DupValue(engine.context, value);
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const prototype = try scope.object();
    const constructor = try scope.own(try @import("native_class.zig").constructor(engine, "GenerateContentResponse", 0, prototype, construct, &.{}));
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const callback = try scope.own(try engine.checked(c.JS_NewCFunctionMagic(engine.context, getter, "get " ++ field.name, 0, c.JS_CFUNC_generic_magic, @intCast(field.value))));
        const descriptor = try scope.object();
        try scope.put(descriptor, "get", callback);
        try scope.put(descriptor, "configurable", c.pi_js_bool(engine.context, 1));
        _ = try scope.invoke(try scope.global("Object"), "defineProperty", &.{ prototype, try scope.text(field.name), descriptor });
    }
    try engine.native_module_values.ensureUnusedCapacity(engine.gpa, 1);
    engine.native_module_values.putAssumeCapacity(cache_key, c.JS_DupValue(engine.context, constructor));
    return c.JS_DupValue(engine.context, constructor);
}
fn warn(scope: *Scope, text: c.JSValue) !void {
    _ = try scope.invoke(try scope.global("console"), "warn", &.{text});
}
fn firstParts(scope: *Scope, receiver: c.JSValue) !c.JSValue {
    const candidates = try scope.get(receiver, "candidates");
    const first = if (v.nullish(candidates)) c.pi_js_undefined() else try v.at(scope, candidates, 0);
    return v.optional(scope, try v.optional(scope, first, "content"), "parts");
}
fn select(scope: *Scope, parts: c.JSValue, comptime kind: Kind) !c.JSValue {
    const key: [*:0]const u8 = if (kind == .functionCalls) "functionCall" else if (kind == .executableCode) "executableCode" else "codeExecutionResult";
    const Predicate = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            // Source's filter arrow returns the field itself. A caller may
            // replace Array.prototype.filter and inspect that return value.
            return v.js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), key);
        }
    };
    const Mapper = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            engine.native_exception_diagnostics_suppressed += 1;
            defer engine.native_exception_diagnostics_suppressed -= 1;
            return v.js.get(engine, if (args.len > 0) args[0] else c.pi_js_undefined(), key);
        }
    };
    const Defined = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.pi_js_bool(engine.context, @intFromBool(args.len > 0 and !c.JS_IsUndefined(args[0])));
        }
    };
    const selected = try scope.invoke(parts, "filter", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Predicate.call, &.{}))});
    const mapped = try scope.invoke(selected, "map", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Mapper.call, &.{}))});
    return scope.invoke(mapped, "filter", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Defined.call, &.{}))});
}
fn get(engine: *v.em.Engine, receiver: c.JSValue, kind: Kind) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const initial_parts = try firstParts(&scope, receiver);
    if (!v.nullish(initial_parts) and scope.equal(try scope.get(initial_parts, "length"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
    if (scope.truthy(try scope.get(receiver, "candidates")) and try @import("native_image_arithmetic.zig").compare(engine, .greater, try scope.get(try scope.get(receiver, "candidates"), "length"), c.JS_NewInt32(engine.context, 1))) try warn(&scope, try scope.text(switch (kind) {
        .text => "there are multiple candidates in the response, returning text from the first one.",
        .data => "there are multiple candidates in the response, returning data from the first one.",
        .functionCalls => "there are multiple candidates in the response, returning function calls from the first one.",
        .executableCode => "there are multiple candidates in the response, returning executable code from the first one.",
        .codeExecutionResult => "there are multiple candidates in the response, returning code execution result from the first one.",
    }));
    const parts = try firstParts(&scope, receiver);
    if ((kind == .functionCalls or kind == .executableCode or kind == .codeExecutionResult) and v.nullish(parts)) return c.pi_js_undefined();
    if (kind == .functionCalls or kind == .executableCode or kind == .codeExecutionResult) {
        const selected = switch (kind) {
            .functionCalls => try select(&scope, parts, .functionCalls),
            .executableCode => try select(&scope, parts, .executableCode),
            .codeExecutionResult => try select(&scope, parts, .codeExecutionResult),
            else => unreachable,
        };
        if (scope.equal(try v.optional(&scope, selected, "length"), c.JS_NewInt32(engine.context, 0))) return c.pi_js_undefined();
        if (kind == .functionCalls) return c.JS_DupValue(engine.context, selected);
        return c.JS_DupValue(engine.context, try v.optional(&scope, if (v.nullish(selected)) c.pi_js_undefined() else try v.at(&scope, selected, 0), if (kind == .executableCode) "code" else "output"));
    }
    const non_parts = try scope.array();
    var combined = try scope.text("");
    var found = false;
    var rows = try v.iterator(&scope, if (v.nullish(parts)) try scope.array() else parts);
    defer rows.deinit();
    errdefer rows.closePreserving();
    while (try rows.next()) |part| {
        defer engine.freeValue(part);
        var row: Scope = .{ .engine = engine };
        defer row.deinit();
        if (kind == .text or kind == .data) {
            var fields = try v.iterator(&row, try row.invoke(try row.global("Object"), "entries", &.{part}));
            defer fields.deinit();
            errdefer fields.closePreserving();
            while (try fields.next()) |entry| {
                defer engine.freeValue(entry);
                const name = try v.at(&row, entry, 0);
                const exempt = if (kind == .text) try v.eq(&row, name, "text") or try v.eq(&row, name, "thought") or try v.eq(&row, name, "thoughtSignature") else try v.eq(&row, name, "inlineData");
                // Preserve the SDK's OR predicate: even null/undefined fields warn.
                if (!exempt) _ = try row.invoke(non_parts, "push", &.{name});
            }
        }
        if (kind == .text) {
            if (c.JS_IsString(try row.get(part, "text"))) {
                const thought = try row.get(part, "thought");
                if (c.JS_IsBool(thought) and row.truthy(try row.get(part, "thought"))) continue;
                found = true;
                combined = try scope.concat(combined, try row.get(part, "text"));
            }
        } else if (kind == .data) {
            if (row.truthy(try row.get(part, "inlineData")) and c.JS_IsString(try row.get(try row.get(part, "inlineData"), "data"))) combined = try scope.concat(combined, try row.call(try row.global("atob"), c.pi_js_undefined(), &.{try row.get(try row.get(part, "inlineData"), "data")}));
        }
    }
    if ((kind == .text or kind == .data) and try v.length(&scope, non_parts) > 0) {
        var message = try scope.concat(try scope.text(if (kind == .text) "there are non-text parts " else "there are non-data parts "), try scope.stringify(non_parts));
        message = try scope.concat(message, try scope.text(if (kind == .text) " in the response, returning concatenation of all text parts. Please refer to the non text parts for a full response from model." else " in the response, returning concatenation of all data parts. Please refer to the non data parts for a full response from model."));
        try warn(&scope, message);
    }
    return c.JS_DupValue(engine.context, switch (kind) {
        .text => if (found) combined else c.pi_js_undefined(),
        .data => if (try v.length(&scope, combined) > 0) try scope.call(try scope.global("btoa"), c.pi_js_undefined(), &.{combined}) else c.pi_js_undefined(),
        else => unreachable,
    });
}
fn copyList(scope: *Scope, value: c.JSValue) !c.JSValue {
    if (!try v.array(scope, value)) return value;
    const Identity = struct {
        fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.JS_DupValue(engine.context, if (args.len > 0) args[0] else c.pi_js_undefined());
        }
    };
    return scope.invoke(value, "map", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Identity.call, &.{}))});
}
// Pinned SDK getValueByPath ignores non-object sources and catches TypeError
// from a field getter. Other thrown values and native allocation failures escape.
fn sdkField(scope: *Scope, value: c.JSValue, key: [*:0]const u8) !c.JSValue {
    if (!c.JS_IsObject(value) or c.JS_IsFunction(scope.engine.context, value)) return c.pi_js_undefined();
    const generation = scope.engine.native_allocation_generation;
    return scope.get(value, key) catch |err| {
        if (err != error.JavaScriptException or scope.engine.native_allocation_generation != generation) return err;
        const reason = @import("native_agent_async.zig").reason(scope.engine, err);
        defer scope.engine.freeValue(reason);
        const matches = c.JS_IsInstanceOf(scope.engine.context, reason, try scope.global("TypeError"));
        if (matches < 0) return v.js.capture(scope.engine);
        if (matches == 0) return err;
        try @import("native_ai_partial_json.zig").discard(scope.engine, err, generation);
        return c.pi_js_undefined();
    };
}
fn candidate(scope: *Scope, value: c.JSValue) !c.JSValue {
    const output = try scope.object();
    inline for (.{ "content", "citationMetadata", "tokenCount", "finishReason", "groundingMetadata", "avgLogprobs", "index", "logprobsResult", "safetyRatings", "urlContextMetadata" }) |key| {
        const field = try sdkField(scope, value, key);
        if (!v.nullish(field)) {
            if (@import("std").mem.eql(u8, key, "citationMetadata")) {
                const citations = try scope.object();
                const sources = try sdkField(scope, field, "citationSources");
                if (!v.nullish(sources)) try scope.put(citations, "citations", try copyList(scope, sources));
                try scope.put(output, key, citations);
            } else if (@import("std").mem.eql(u8, key, "safetyRatings")) {
                try scope.put(output, key, try copyList(scope, field));
            } else try scope.put(output, key, field);
        }
    }
    return output;
}
pub fn wrap(scope: *Scope, constructor: c.JSValue, raw: c.JSValue, response_headers: c.JSValue, vertex: bool) !c.JSValue {
    const result = try scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, constructor, 0, null)));
    const candidates = try sdkField(scope, raw, "candidates");
    if (!v.nullish(candidates)) {
        var converted = candidates;
        if (vertex) {
            converted = try copyList(scope, candidates);
        } else if (try v.array(scope, candidates)) {
            const Convert = struct {
                fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                    engine.native_exception_diagnostics_suppressed += 1;
                    defer engine.native_exception_diagnostics_suppressed -= 1;
                    var row: Scope = .{ .engine = engine };
                    defer row.deinit();
                    return c.JS_DupValue(engine.context, try candidate(&row, if (args.len > 0) args[0] else c.pi_js_undefined()));
                }
            };
            converted = try scope.invoke(candidates, "map", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Convert.call, &.{}))});
        }
        try scope.put(result, "candidates", converted);
    }
    if (vertex) {
        const create_time = try sdkField(scope, raw, "createTime");
        if (!v.nullish(create_time)) try scope.put(result, "createTime", create_time);
    }
    inline for (.{ "modelVersion", "promptFeedback", "responseId", "usageMetadata" }) |key| {
        const value = try sdkField(scope, raw, key);
        if (!v.nullish(value)) try scope.put(result, key, value);
    }
    if (!vertex) {
        const status = try sdkField(scope, raw, "modelStatus");
        if (!v.nullish(status)) try scope.put(result, "modelStatus", status);
    }
    const http = try scope.object();
    const headers = try scope.object();
    const normalized = try scope.own(try @import("native_headers.zig").fromRecord(scope.engine, response_headers));
    var entries = try v.iterator(scope, try scope.invoke(normalized, "entries", &.{}));
    defer entries.deinit();
    errdefer entries.closePreserving();
    while (try entries.next()) |entry| {
        defer scope.engine.freeValue(entry);
        try v.js.setKey(scope.engine, headers, try v.at(scope, entry, 0), try v.at(scope, entry, 1));
    }
    try scope.put(http, "headers", headers);
    try scope.put(result, "sdkHttpResponse", http);
    return result;
}
