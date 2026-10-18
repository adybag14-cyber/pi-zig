//! Actual c268154c model-resolver.ts findInitialModel. Zero Source Await;
//! QuickJS owns the genuine AsyncFunction Promise and return adoption.
const x = @import("native_sdk_initial_model_values.zig");
const c = x.c;
pub fn create(engine: *x.em.Engine, defaults: c.JSValue) !c.JSValue {
    return x.af.createResumable(engine, "findInitialModel", 1, initial, &.{defaults});
}
fn initial(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, _: *c.JSValue, completion: x.af.Completion, _: c.JSValue) !x.af.Action {
    try engine.checkNativeEntry();
    if (completion != .start) return error.InitialModelHasNoSourceAwait;
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    return x.owned.finishAction(&s, source(&o, if (args.len > 0) args[0] else c.pi_js_undefined(), roots[0]));
}
fn result(o: *x.Ops, model: c.JSValue, thinking: c.JSValue) !c.JSValue {
    const value = try o.object();
    try o.put(value, "model", model); try o.put(value, "thinkingLevel", thinking); try o.put(value, "fallbackMessage", c.pi_js_undefined());
    return value;
}
fn returned(o: *x.Ops, value: c.JSValue) x.af.Action { return .{ .returned = c.JS_DupValue(o.s.engine.context, value) }; }
fn perModel(o: *x.Ops, levels: c.JSValue, provider: c.JSValue, id: c.JSValue) !c.JSValue {
    // Template substitutions ToString one at a time, before the next expression.
    const prefix = try o.binary(0, try o.stringify(provider), try o.text("/"));
    return o.key(levels, try o.binary(0, prefix, try o.stringify(id)));
}
fn source(o: *x.Ops, options: c.JSValue, defaults: c.JSValue) !x.af.Action {
    const scoped = try o.get(options, "scopedModels");
    const continuing = try o.get(options, "isContinuing");
    const provider = try o.get(options, "defaultProvider");
    const model_id = try o.get(options, "defaultModelId");
    const thinking = try o.get(options, "defaultThinkingLevel");
    const levels = try o.get(options, "modelThinkingLevels");
    const runtime = try o.get(options, "modelRuntime");
    const medium = try o.text("medium");
    if (o.truthy(try o.binary(6, try o.get(scoped, "length"), c.JS_NewInt32(o.s.engine.context, 0))) and !o.truthy(continuing)) {
        const row = try o.at(scoped, 0);
        var per_model = c.pi_js_undefined();
        if (!x.nullish(levels)) {
            // Source evaluates/coerces the provider substitution before looking
            // up scopedModel.model again for the id substitution.
            const prefix = try o.binary(0, try o.stringify(try o.get(try o.get(row, "model"), "provider")), try o.text("/"));
            const key = try o.binary(0, prefix, try o.stringify(try o.get(try o.get(row, "model"), "id")));
            per_model = try o.key(levels, key);
        }
        const value = try o.object();
        try o.put(value, "model", try o.get(row, "model"));
        var chosen = try o.get(row, "thinkingLevel");
        if (x.nullish(chosen)) chosen = per_model;
        if (x.nullish(chosen)) chosen = thinking;
        if (x.nullish(chosen)) chosen = medium;
        try o.put(value, "thinkingLevel", chosen); try o.put(value, "fallbackMessage", c.pi_js_undefined());
        return returned(o, value);
    }
    if (o.truthy(provider) and o.truthy(model_id)) {
        const found = try o.invoke(runtime, "getModel", &.{ provider, model_id });
        if (o.truthy(found)) {
            // Receiver/callee lookup precedes the found.provider argument getter.
            const check = try o.get(runtime, "hasConfiguredAuth");
            if (o.truthy(try o.call(check, runtime, &.{try o.get(found, "provider")}))) {
                const per_model = if (x.nullish(levels)) c.pi_js_undefined() else try perModel(o, levels, provider, model_id);
                return returned(o, try result(o, found, if (o.truthy(per_model)) per_model else if (o.truthy(thinking)) thinking else medium));
            }
        }
    }
    const available = try o.array();
    try spread(o, available, try o.invoke(runtime, "getAvailableSnapshot", &.{}));
    if (o.truthy(try o.binary(6, try o.get(available, "length"), c.JS_NewInt32(o.s.engine.context, 0)))) {
        const keys = try o.invoke(try o.global("Object"), "keys", &.{defaults});
        var iterator = try Iterator.init(o, keys);
        const value = selectDefaults(o, &iterator, available, defaults, medium) catch |err| {
            // Source for-of closes only after a BODY abrupt completion. A
            // next/done/value failure marks the iterator closed before return.
            var original = x.owned.Completion.initAction(o.s.engine, @as(anyerror!x.af.Action, err));
            var closing = x.owned.Completion.initVoid(o.s.engine, iterator.close(o));
            const action = closing.finishAction() catch return original.finishAction();
            switch (action) {
                // Original Throw wins over ordinary IteratorClose Throw DATA;
                // actual current fatal events still win in owned completion.
                .thrown, .returned => |discard| original.release(discard),
                .awaited => unreachable,
            }
            return original.finishAction();
        };
        // Return expression has already been evaluated, then IteratorClose.
        try iterator.close(o);
        return returned(o, value);
    }
    return returned(o, try result(o, c.pi_js_undefined(), medium));
}
fn selectDefaults(o: *x.Ops, iterator: *Iterator, available: c.JSValue, defaults: c.JSValue, medium: c.JSValue) !c.JSValue {
    while (try iterator.next(o)) |key| {
        const id = try o.key(defaults, key);
        const find = try o.get(available, "find");
        const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
        var roots = [_]c.JSValue{ key, id };
        const predicate = try o.allocation(c.JS_NewCFunctionData2(e.context, matchesDefault, "", 1, 0, roots.len, &roots), generation);
        const match = try o.call(find, available, &.{predicate});
        if (o.truthy(match)) return result(o, match, medium);
    }
    return result(o, try o.at(available, 0), medium);
}
fn matchesDefault(context: ?*c.JSContext, _: c.JSValue, argc: c_int, args: [*c]c.JSValue, _: c_int, roots: [*c]c.JSValue) callconv(.c) c.JSValue {
    const engine = x.em.Engine.fromContext(context.?);
    engine.checkNativeEntry() catch return engine.throwCaptured();
    engine.native_exception_diagnostics_suppressed += 1;
    defer engine.native_exception_diagnostics_suppressed -= 1;
    var invocation: x.em.Engine.NativeInvocation = .{}; engine.enterNativeInvocation(&invocation);
    var s: x.Scope = .{ .engine = engine }; var o: x.Ops = .{ .s = &s };
    const value = x.owned.finishValue(&s, matches(&o, if (argc > 0) args[0] else c.pi_js_undefined(), roots[0..2])) catch |err| @import("native_sdk.zig").fail(engine, err);
    return engine.leaveNativeInvocation(&invocation, value);
}
fn matches(o: *x.Ops, row: c.JSValue, roots: []const c.JSValue) !c.JSValue {
    if (!o.equal(try o.get(row, "provider"), roots[0])) return c.pi_js_bool(o.s.engine.context, 0);
    return c.pi_js_bool(o.s.engine.context, @intFromBool(o.equal(try o.get(row, "id"), roots[1])));
}
const Iterator = struct {
    value: c.JSValue,
    next_function: c.JSValue,
    closed: bool = false,
    native_steps: usize = 0,
    fn init(o: *x.Ops, iterable: c.JSValue) !Iterator {
        const symbol = try o.iteratorSymbol();
        const method = try o.key(iterable, symbol);
        const value = try o.call(method, iterable, &.{});
        if (!c.JS_IsObject(value)) return o.typeError("Iterator is not an object");
        return .{ .value = value, .next_function = try o.get(value, "next") };
    }
    fn next(self: *Iterator, o: *x.Ops) !?c.JSValue {
        errdefer self.closed = true;
        const e = o.s.engine;
        self.native_steps +|= 1;
        if (e.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            e.interrupts +|= 1; break :blk e.interrupts > e.options.interrupt_budget;
        })) {
            _ = try e.checked(c.JS_ThrowInternalError(e.context, "interrupted")); unreachable;
        }
        const step = try o.call(self.next_function, self.value, &.{});
        if (!c.JS_IsObject(step)) return o.typeError("Iterator result is not an object");
        if (o.truthy(try o.get(step, "done"))) { self.closed = true; return null; }
        return o.get(step, "value");
    }
    fn close(self: *Iterator, o: *x.Ops) !void {
        if (self.closed) return;
        self.closed = true;
        const method = try o.get(self.value, "return");
        if (x.nullish(method)) return;
        const value = try o.call(method, self.value, &.{});
        if (!c.JS_IsObject(value)) return o.typeError("Iterator return result is not an object");
    }
};
fn spread(o: *x.Ops, value: c.JSValue, source_value: c.JSValue) !void {
    var iterator = try Iterator.init(o, source_value);
    var index: u32 = 0;
    // Array spread does not perform IteratorClose for next/done/value abrupts.
    // Array indices are native CreateDataProperty, never guest push/set hooks.
    while (try iterator.next(o)) |item| {
        try o.index(value, index, item);
        index += 1;
    }
}
