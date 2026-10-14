//! Actual highlight.js10.7.3 MultiRegex bodies; private grammar compiler support.
const em = @import("engine.zig");
const sdk = @import("native_sdk.zig");
const js = @import("native_js_values.zig");
const regex = @import("native_highlight_regex.zig");
const Scope = @import("native_sdk_prompt_scope.zig").Scope;
const c = em.c;

pub const MultiRegex = struct {
    engine: *em.Engine,
    owner: c.JSValue,
    language: c.JSValue,
    empty_exec: bool = false,

    pub fn init(engine: *em.Engine, language: c.JSValue) !MultiRegex {
        var scope: Scope = .{ .engine = engine };
        defer scope.deinit();
        const owner = try scope.object();
        try scope.put(owner, "matchIndexes", try scope.object());
        try scope.put(owner, "regexes", try scope.array());
        try scope.put(owner, "matchAt", c.JS_NewInt32(engine.context, 1));
        try scope.put(owner, "position", c.JS_NewInt32(engine.context, 0));
        return .{ .engine = engine, .owner = c.JS_DupValue(engine.context, owner), .language = c.JS_DupValue(engine.context, language) };
    }
    pub fn deinit(self: *MultiRegex) void {
        self.engine.freeValue(self.owner);
        self.engine.freeValue(self.language);
    }
    pub fn addRule(self: *MultiRegex, expression: c.JSValue, options: c.JSValue) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const previous = try scope.get(self.owner, "position");
        const numeric_previous = try scope.own(try self.engine.checked(c.JS_PiToNumeric(self.engine.context, previous)));
        const next = try scope.own(try self.engine.checked(c.JS_PiIncrement(self.engine.context, numeric_previous)));
        try scope.set(self.owner, "position", next);
        try scope.set(options, "position", numeric_previous);
        const indices = try scope.get(self.owner, "matchIndexes");
        const at = try scope.get(self.owner, "matchAt");
        try js.setKey(self.engine, indices, at, options);
        const expressions = try scope.get(self.owner, "regexes");
        const push = try scope.get(expressions, "push");
        const pair = try scope.array();
        try scope.index(pair, 0, options);
        try scope.index(pair, 1, expression);
        _ = try scope.call(push, expressions, &.{pair});
        const current = try scope.get(self.owner, "matchAt");
        const groups = try scope.own(try regex.countMatchGroups(self.engine, expression));
        const added = try scope.concat(groups, c.JS_NewInt32(self.engine.context, 1));
        try scope.set(self.owner, "matchAt", try scope.concat(current, added));
    }
    pub fn compile(self: *MultiRegex) !void {
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        const expressions = try scope.get(self.owner, "regexes");
        if (scope.equal(try scope.get(expressions, "length"), c.JS_NewInt32(self.engine.context, 0))) self.empty_exec = true;
        const map = try scope.get(expressions, "map");
        const callback = try scope.own(try self.engine.checked(c.JS_NewCFunction(self.engine.context, second, "", 1)));
        const terminators = try scope.call(map, expressions, &.{callback});
        const joined = try scope.own(try regex.join(self.engine, terminators, c.pi_js_undefined()));
        const constructor = try scope.global("RegExp");
        const text = try scope.own(try regex.source(self.engine, joined));
        const insensitive = try scope.get(self.language, "case_insensitive");
        const flags = try scope.text(if (scope.truthy(insensitive)) "mig" else "mg");
        var args = [_]c.JSValue{ text, flags };
        const compiled = try scope.own(try self.engine.checked(c.JS_CallConstructor(self.engine.context, constructor, args.len, &args)));
        try scope.set(self.owner, "matcherRe", compiled);
        try scope.set(self.owner, "lastIndex", c.JS_NewInt32(self.engine.context, 0));
    }
    pub fn exec(self: *MultiRegex, text: c.JSValue) !c.JSValue {
        if (self.empty_exec) return c.pi_js_null();
        var scope: Scope = .{ .engine = self.engine };
        defer scope.deinit();
        try scope.set(try scope.get(self.owner, "matcherRe"), "lastIndex", try scope.get(self.owner, "lastIndex"));
        const matched = try scope.invoke(try scope.get(self.owner, "matcherRe"), "exec", &.{text});
        if (!scope.truthy(matched)) return c.pi_js_null();
        const find = try scope.get(matched, "findIndex");
        const predicate = try scope.own(try self.engine.checked(c.JS_NewCFunction(self.engine.context, presentCapture, "", 2)));
        const index = try scope.call(find, matched, &.{predicate});
        const data = try scope.own(try js.getKey(self.engine, try scope.get(self.owner, "matchIndexes"), index));
        _ = try scope.invoke(matched, "splice", &.{ c.JS_NewInt32(self.engine.context, 0), index });
        const result = try scope.invoke(try scope.global("Object"), "assign", &.{ matched, data });
        return c.JS_DupValue(self.engine.context, result);
    }
};

fn second(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    return js.getKey(engine, if (argc > 0) argv[0] else c.pi_js_undefined(), c.JS_NewInt32(engine.context, 1)) catch |err| sdk.fail(engine, err);
}
fn presentCapture(context: ?*c.JSContext, _: c.JSValue, argc: c_int, argv: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = em.Engine.fromContext(context.?);
    const index = if (argc > 1) argv[1] else c.pi_js_undefined();
    const positive = engine.checked(c.JS_PiBinaryOperator(engine.context, 6, index, c.JS_NewInt32(engine.context, 0))) catch |err| return sdk.fail(engine, err);
    defer engine.freeValue(positive);
    return c.pi_js_bool(engine.context, @intFromBool(c.JS_ToBool(engine.context, positive) == 1 and argc > 0 and !c.JS_IsUndefined(argv[0])));
}
