//! Accessed OpenAI6.40 logger semantics for createClient and SDK streaming.
//! Private native state only; no public OpenAI client/class is synthesized.
const v = @import("native_ai_provider_values.zig");
const Scope = v.Scope;
const c = v.c;
const key = "\x00native-openai-client-log-context";
pub fn initialize(engine: *v.em.Engine) !void {
    if (engine.native_module_values.contains(key)) return;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const state = try scope.object();
    const levels = try scope.object();
    inline for (.{ .{ "off", 0 }, .{ "error", 200 }, .{ "warn", 300 }, .{ "info", 400 }, .{ "debug", 500 } }) |entry| try scope.put(levels, entry[0], c.JS_NewInt32(engine.context, entry[1]));
    try scope.put(state, "levels", levels);
    try scope.put(state, "loggers", try scope.own(try v.js.builtin(engine, "WeakMap", &.{})));
    const Noop = struct {
        fn call(_: *v.em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
            return c.pi_js_undefined();
        }
    };
    const noop = try scope.own(try @import("native_node_function.zig").create(engine, "noop", 0, Noop.call, &.{}));
    try scope.put(state, "noop", noop);
    const no_logger = try scope.object();
    inline for (.{ "error", "warn", "info", "debug" }) |name| try scope.put(no_logger, name, noop);
    try scope.put(state, "noopLogger", no_logger);
    const retained = c.JS_DupValue(engine.context, state);
    engine.native_module_values.put(engine.gpa, key, retained) catch |err| {
        engine.freeValue(retained);
        return err;
    };
}
fn context(scope: *Scope) !c.JSValue {
    try initialize(scope.engine);
    return scope.engine.native_module_values.get(key).?;
}
pub fn loggerFor(scope: *Scope, client: c.JSValue) !c.JSValue {
    const state = try context(scope);
    const logger = try scope.get(client, "logger");
    const configured = try scope.get(client, "logLevel");
    const level = if (v.nullish(configured)) try scope.text("off") else configured;
    if (!scope.truthy(logger)) return scope.get(state, "noopLogger");
    const cache = try scope.get(state, "loggers");
    const previous = try scope.invoke(cache, "get", &.{logger});
    if (scope.truthy(previous) and scope.equal(try v.at(scope, previous, 0), level)) return v.at(scope, previous, 1);
    const output = try scope.object();
    inline for (.{ "error", "warn", "info", "debug" }) |name| {
        const levels = try scope.get(state, "levels");
        const threshold = try scope.get(levels, name);
        const current = try scope.own(try v.js.getKey(scope.engine, levels, level));
        const function = if (try @import("native_image_arithmetic.zig").compare(scope.engine, .greater, threshold, current)) try scope.get(state, "noop") else try scope.invoke(try scope.get(logger, name), "bind", &.{logger});
        try scope.put(output, name, function);
    }
    const entry = try scope.array();
    try scope.index(entry, 0, level);
    try scope.index(entry, 1, output);
    _ = try scope.invoke(cache, "set", &.{ logger, entry });
    return output;
}
pub fn parse(scope: *Scope, value: c.JSValue, source_name: []const u8, client: c.JSValue) !c.JSValue {
    if (!scope.truthy(value)) return c.pi_js_undefined();
    const levels = try scope.get(try context(scope), "levels");
    const has_own = try scope.get(try scope.get(try scope.global("Object"), "prototype"), "hasOwnProperty");
    if (scope.truthy(try scope.invoke(has_own, "call", &.{ levels, value }))) return value;
    // Source obtains/caches bound logger functions before formatting the value.
    const logger = try loggerFor(scope, client);
    const warn = try scope.get(logger, "warn");
    const json = try scope.global("JSON");
    var message = try scope.concat(try scope.text(source_name), try scope.text(" was set to "));
    message = try scope.concat(message, try scope.invoke(json, "stringify", &.{value}));
    message = try scope.concat(message, try scope.text(", expected one of "));
    message = try scope.concat(message, try scope.invoke(json, "stringify", &.{try scope.invoke(try scope.global("Object"), "keys", &.{levels})}));
    _ = try scope.call(warn, logger, &.{message});
    return c.pi_js_undefined();
}
fn spreadHeaders(scope: *Scope, value: c.JSValue) !c.JSValue {
    const result = try scope.array();
    var iterator = try v.iterator(scope, value);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |item| {
        defer scope.engine.freeValue(item);
        if (index == 0xffff_ffff) return scope.engine.checked(c.JS_ThrowRangeError(scope.engine.context, "Invalid array length"));
        if (c.JS_DefinePropertyValueUint32(scope.engine.context, result, index, c.JS_DupValue(scope.engine.context, item), c.JS_PROP_C_W_E) < 0) return v.js.capture(scope.engine);
        index += 1;
    }
    return result;
}
pub fn formatDetails(scope: *Scope, details: c.JSValue) !c.JSValue {
    if (scope.truthy(try scope.get(details, "options"))) {
        try scope.put(details, "options", try v.spread(scope, try scope.get(details, "options")));
        try v.remove(scope, try scope.get(details, "options"), "headers");
    }
    if (scope.truthy(try scope.get(details, "headers"))) {
        // The outer call's callee precedes its entire conditional/map argument.
        const object = try scope.global("Object");
        const from = try scope.get(object, "fromEntries");
        const instance = c.JS_IsInstanceOf(scope.engine.context, try scope.get(details, "headers"), try scope.global("Headers"));
        if (instance < 0) return v.js.capture(scope.engine);
        const entries = if (instance != 0) try spreadHeaders(scope, try scope.get(details, "headers")) else entries: {
            const constructor = try scope.global("Object");
            const function = try scope.get(constructor, "entries");
            break :entries try scope.call(function, constructor, &.{try scope.get(details, "headers")});
        };
        const Redact = struct {
            fn call(engine: *v.em.Engine, _: c.JSValue, args: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
                var row: Scope = .{ .engine = engine };
                defer row.deinit();
                const fields = try v.js.pair(engine, args[0], try row.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context))));
                defer for (fields) |value| engine.freeValue(value);
                var secret = false;
                inline for (.{ "authorization", "api-key", "x-api-key", "cookie", "set-cookie" }) |name| {
                    if (!secret) secret = try v.eq(&row, try row.invoke(fields[0], "toLowerCase", &.{}), name);
                }
                const result = try row.array();
                if (c.JS_DefinePropertyValueUint32(engine.context, result, 0, c.JS_DupValue(engine.context, fields[0]), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
                if (c.JS_DefinePropertyValueUint32(engine.context, result, 1, c.JS_DupValue(engine.context, if (secret) try row.text("***") else fields[1]), c.JS_PROP_C_W_E) < 0) return v.js.capture(engine);
                return c.JS_DupValue(engine.context, result);
            }
        };
        const mapped = try scope.invoke(entries, "map", &.{try scope.own(try @import("native_node_function.zig").createArrow(scope.engine, "", 1, Redact.call, &.{}))});
        try scope.put(details, "headers", try scope.call(from, object, &.{mapped}));
    }
    const atom = c.JS_NewAtom(scope.engine.context, "retryOfRequestLogID");
    if (atom == c.JS_ATOM_NULL) return v.js.capture(scope.engine);
    defer c.JS_FreeAtom(scope.engine.context, atom);
    const exists = c.JS_HasProperty(scope.engine.context, details, atom);
    if (exists < 0) return v.js.capture(scope.engine);
    if (exists != 0) {
        if (scope.truthy(try scope.get(details, "retryOfRequestLogID"))) try scope.put(details, "retryOf", try scope.get(details, "retryOfRequestLogID"));
        try v.remove(scope, details, "retryOfRequestLogID");
    }
    return details;
}
