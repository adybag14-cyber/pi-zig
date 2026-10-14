//! Original Pi provider classification with shared module-lifetime RegExp values.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const arithmetic = @import("native_image_arithmetic.zig");
const c = em.c;

fn regexp(scope: *Scope, pattern: c.JSValue) !c.JSValue {
    const flags = try scope.text("i");
    var args = [_]c.JSValue{ pattern, flags };
    return scope.own(try scope.engine.checked(c.JS_CallConstructor(scope.engine.context, scope.engine.intrinsic_regexp_constructor, 2, &args)));
}
pub fn initialize(engine: *em.Engine) !c.JSValue {
    if (engine.native_ai_retry_patterns) |value| return value;
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const result = try scope.object();
    const source = @embedFile("overflow-provider-patterns.json");
    const patterns = try scope.own(try engine.checked(c.JS_ParseJSON(engine.context, source.ptr, source.len, "overflow-provider-patterns.json")));
    inline for (.{ "overflow", "nonoverflow" }) |name| {
        const inputs = try scope.get(patterns, name);
        const outputs = try scope.array();
        var length: u32 = 0;
        if (c.JS_ToUint32(engine.context, &length, try scope.get(inputs, "length")) < 0) return js.capture(engine);
        for (0..length) |index| {
            const pattern = try scope.own(try engine.checked(c.JS_GetPropertyUint32(engine.context, inputs, @intCast(index))));
            try scope.index(outputs, @intCast(index), try regexp(&scope, pattern));
        }
        try scope.put(result, name, outputs);
    }
    try scope.put(result, "cerebras", try regexp(&scope, try scope.get(patterns, "cerebras")));
    try scope.put(result, "retryable", try regexp(&scope, try scope.text(@embedFile("retryable-provider-pattern.txt"))));
    try scope.put(result, "nonretryable", try regexp(&scope, try scope.text(@embedFile("nonretryable-provider-pattern.txt"))));
    engine.native_ai_retry_patterns = c.JS_DupValue(engine.context, result);
    return engine.native_ai_retry_patterns.?;
}
fn some(engine: *em.Engine, patterns: c.JSValue, message: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    var roots = [_]c.JSValue{message};
    const callback = try scope.own(try engine.checked(c.JS_NewCFunctionData2(engine.context, testPattern, "", 1, 0, roots.len, &roots)));
    return scope.truthy(try scope.invoke(patterns, "some", &.{callback}));
}
fn testPattern(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    return testPatternValue(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), roots[0]) catch |err| sdk.fail(engine, err);
}
fn testPatternValue(engine: *em.Engine, pattern: c.JSValue, message: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const function = try scope.get(pattern, "test");
    return js.call(engine, function, pattern, &.{try scope.get(message, "errorMessage")});
}
pub fn retryable(engine: *em.Engine, message: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const patterns = try initialize(engine);
    if (!scope.equal(try scope.get(message, "stopReason"), try scope.text("error")) or !scope.truthy(try scope.get(message, "errorMessage"))) return false;
    const error_message = try scope.get(message, "errorMessage");
    if (scope.truthy(try scope.invoke(try scope.get(patterns, "nonretryable"), "test", &.{error_message}))) return false;
    return scope.truthy(try scope.invoke(try scope.get(patterns, "retryable"), "test", &.{error_message}));
}
pub fn overflow(engine: *em.Engine, message: c.JSValue, context_window: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const patterns = try initialize(engine);
    if (scope.equal(try scope.get(message, "stopReason"), try scope.text("error")) and scope.truthy(try scope.get(message, "errorMessage"))) {
        if (!try some(engine, try scope.get(patterns, "nonoverflow"), message)) {
            if (try some(engine, try scope.get(patterns, "overflow"), message)) return true;
            if (scope.equal(try scope.get(message, "provider"), try scope.text("cerebras"))) {
                const pattern = try scope.get(patterns, "cerebras");
                const function = try scope.get(pattern, "test");
                if (scope.truthy(try scope.call(function, pattern, &.{try scope.get(message, "errorMessage")}))) return true;
            }
        }
    }
    if (scope.truthy(context_window) and scope.equal(try scope.get(message, "stopReason"), try scope.text("stop"))) {
        const input = try scope.get(try scope.get(message, "usage"), "input");
        const cache = try scope.get(try scope.get(message, "usage"), "cacheRead");
        const tokens = try scope.concat(input, cache);
        if (try arithmetic.compare(engine, .greater, tokens, context_window)) return true;
    }
    if (scope.truthy(context_window) and scope.equal(try scope.get(message, "stopReason"), try scope.text("length")) and scope.equal(try scope.get(try scope.get(message, "usage"), "output"), c.JS_NewInt32(engine.context, 0))) {
        const input = try scope.get(try scope.get(message, "usage"), "input");
        const cache = try scope.get(try scope.get(message, "usage"), "cacheRead");
        const tokens = try scope.concat(input, cache);
        const threshold = try scope.own(try arithmetic.binary(engine, .multiply, context_window, c.JS_NewFloat64(engine.context, 0.99)));
        if (try arithmetic.compare(engine, .greater_equal, tokens, threshold)) return true;
    }
    return false;
}
pub fn recoverableLength(engine: *em.Engine, message: c.JSValue, desired_max_output: c.JSValue) !bool {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    return scope.equal(try scope.get(message, "stopReason"), try scope.text("length")) and
        try arithmetic.compare(engine, .greater, desired_max_output, c.JS_NewInt32(engine.context, 0)) and
        try arithmetic.compare(engine, .less, try scope.get(try scope.get(message, "usage"), "output"), desired_max_output);
}
pub fn getOverflowPatterns(engine: *em.Engine) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const patterns = try scope.get(try initialize(engine), "overflow");
    const output = try scope.array();
    const symbol = try scope.own(try engine.checked(c.JS_GetIteratorSymbol(engine.context)));
    var iterator = try js.Iterator.init(engine, patterns, symbol);
    defer iterator.deinit();
    errdefer iterator.closePreserving();
    var index: u32 = 0;
    while (try iterator.next()) |value| {
        defer engine.freeValue(value);
        try scope.index(output, index, value);
        index += 1;
    }
    return c.JS_DupValue(engine.context, output);
}
