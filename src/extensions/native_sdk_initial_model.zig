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
fn source(o: *x.Ops, options: c.JSValue, defaults: c.JSValue) !x.af.Action {
    const scoped = try o.get(options, "scopedModels");
    const continuing = try o.get(options, "isContinuing");
    const provider = try o.get(options, "defaultProvider");
    const model_id = try o.get(options, "defaultModelId");
    const thinking = try o.get(options, "defaultThinkingLevel");
    const levels = try o.get(options, "modelThinkingLevels");
    const runtime = try o.get(options, "modelRuntime");
    const medium = try o.text("medium");
    if (try positiveLength(o, scoped) and !o.truthy(continuing)) {
        const row = try o.at(scoped, 0);
        const per_model = if (x.nullish(levels)) c.pi_js_undefined() else try scopedPerModel(o, levels, row);
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
        const saved_result = try savedDefault(o, runtime, provider, model_id, levels, thinking, medium);
        if (!c.JS_IsUndefined(saved_result)) return returned(o, try o.own(saved_result));
    }
    const available = try o.array();
    try spreadSnapshot(o, available, runtime);
    if (try positiveLength(o, available)) {
        const selected = try knownDefault(o, available, defaults, medium);
        switch (selected) {
            .thrown => return selected,
            .awaited => unreachable,
            .returned => |value| if (!c.JS_IsUndefined(value)) return selected,
        }
        // The exhausted for-of iterator and cached next root have retired.
        return returned(o, try result(o, try o.at(available, 0), medium));
    }
    return returned(o, try result(o, c.pi_js_undefined(), medium));
}
fn positiveLength(o: *x.Ops, value: c.JSValue) !bool {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    const boolean = try x.owned.finishValue(&s, lengthBody(&local, value));
    return o.truthy(boolean);
}
fn lengthBody(o: *x.Ops, value: c.JSValue) !c.JSValue {
    const positive = try o.binary(6, try o.get(value, "length"), c.JS_NewInt32(o.s.engine.context, 0));
    return c.pi_js_bool(o.s.engine.context, @intFromBool(o.truthy(positive)));
}
fn scopedPerModel(o: *x.Ops, levels: c.JSValue, row: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return o.own(try x.owned.finishValue(&s, scopedPerModelBody(&local, levels, row)));
}
fn scopedString(o: *x.Ops, row: c.JSValue, field: [*:0]const u8) !c.JSValue {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return o.own(try x.owned.finishValue(&s, scopedStringBody(&local, row, field)));
}
fn scopedStringBody(o: *x.Ops, row: c.JSValue, field: [*:0]const u8) !c.JSValue {
    const value = try o.stringify(try o.get(try o.get(row, "model"), field));
    return c.JS_DupValue(o.s.engine.context, value);
}
fn scopedPerModelBody(o: *x.Ops, levels: c.JSValue, row: c.JSValue) !c.JSValue {
    // Each substitution retires its temporary model/field roots before the
    // next scopedModel.model lookup, while const scopedModel itself stays live.
    const prefix = try o.binary(0, try scopedString(o, row, "provider"), try o.text("/"));
    const key = try o.binary(0, prefix, try scopedString(o, row, "id"));
    return c.JS_DupValue(o.s.engine.context, try o.key(levels, key));
}
fn savedDefault(o: *x.Ops, runtime: c.JSValue, provider: c.JSValue, id: c.JSValue, levels: c.JSValue, thinking: c.JSValue, medium: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, savedDefaultBody(&local, runtime, provider, id, levels, thinking, medium));
}
fn configuredAuth(o: *x.Ops, runtime: c.JSValue, found: c.JSValue) !bool {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    const boolean = try x.owned.finishValue(&s, configuredAuthBody(&local, runtime, found));
    return o.truthy(boolean);
}
fn configuredAuthBody(o: *x.Ops, runtime: c.JSValue, found: c.JSValue) !c.JSValue {
    const check = try o.get(runtime, "hasConfiguredAuth");
    const value = try o.call(check, runtime, &.{try o.get(found, "provider")});
    return c.pi_js_bool(o.s.engine.context, @intFromBool(o.truthy(value)));
}
fn savedDefaultBody(o: *x.Ops, runtime: c.JSValue, provider: c.JSValue, id: c.JSValue, levels: c.JSValue, thinking: c.JSValue, medium: c.JSValue) !c.JSValue {
    const found = try o.invoke(runtime, "getModel", &.{ provider, id });
    if (!o.truthy(found) or !(try configuredAuth(o, runtime, found))) return c.pi_js_undefined();
    var per_model = c.pi_js_undefined();
    if (!x.nullish(levels)) {
        const prefix = try o.binary(0, try o.stringify(provider), try o.text("/"));
        per_model = try o.key(levels, try o.binary(0, prefix, try o.stringify(id)));
    }
    return c.JS_DupValue(o.s.engine.context, try result(o, found, if (o.truthy(per_model)) per_model else if (o.truthy(thinking)) thinking else medium));
}
fn knownDefault(o: *x.Ops, available: c.JSValue, defaults: c.JSValue, medium: c.JSValue) !x.af.Action {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishAction(&s, knownDefaultBody(&local, available, defaults, medium));
}
fn keysOwned(o: *x.Ops, defaults: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, keysBody(&local, defaults));
}
fn keysBody(o: *x.Ops, defaults: c.JSValue) !c.JSValue { return o.invokeOwned(try o.global("Object"), "keys", &.{defaults}); }
fn knownDefaultBody(o: *x.Ops, available: c.JSValue, defaults: c.JSValue, medium: c.JSValue) !x.af.Action {
    var iterator = try Iterator.initOwned(o, try keysOwned(o, defaults));
    const value = selectDefaults(o, &iterator, available, defaults, medium) catch |err| {
        var original = x.owned.Completion.initAction(o.s.engine, @as(anyerror!x.af.Action, err));
        var closing = x.owned.Completion.initVoid(o.s.engine, iterator.close(o, true));
        const action = closing.finishAction() catch return original.finishAction();
        switch (action) {
            .thrown, .returned => |discard| original.release(discard),
            .awaited => unreachable,
        }
        return original.finishAction();
    };
    const selected = try o.own(value);
    try iterator.close(o, false);
    return returned(o, selected);
}
fn selectDefaults(o: *x.Ops, iterator: *Iterator, available: c.JSValue, defaults: c.JSValue, medium: c.JSValue) !c.JSValue {
    while (!iterator.closed) {
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        const value = try x.owned.finishValue(&s, defaultIteration(&local, iterator, available, defaults, medium));
        if (!c.JS_IsUndefined(value)) return value;
        // Retire key/id/find/predicate/false match before the next iteration.
    }
    return c.pi_js_undefined();
}
fn defaultIteration(o: *x.Ops, iterator: *Iterator, available: c.JSValue, defaults: c.JSValue, medium: c.JSValue) !c.JSValue {
    const key = (try iterator.next(o)) orelse return c.pi_js_undefined();
    const id = try o.key(defaults, key);
    const match = try o.own(try findMatch(o, available, key, id));
    return if (o.truthy(match)) c.JS_DupValue(o.s.engine.context, try result(o, match, medium)) else c.pi_js_undefined();
}
fn findMatch(o: *x.Ops, available: c.JSValue, key: c.JSValue, id: c.JSValue) !c.JSValue {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishValue(&s, findMatchBody(&local, available, key, id));
}
fn findMatchBody(o: *x.Ops, available: c.JSValue, key: c.JSValue, id: c.JSValue) !c.JSValue {
    const find = try o.get(available, "find");
    const e = o.s.engine; try e.checkNativeEntry(); const generation = e.native_allocation_generation;
    var roots = [_]c.JSValue{ key, id };
    const predicate = try o.allocation(c.JS_NewCFunctionData2(e.context, matchesDefault, "", 1, 0, roots.len, &roots), generation);
    const match = try o.call(find, available, &.{predicate});
    return c.JS_DupValue(e.context, match);
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
    /// Consumes the expression's owned iterable, retires @@iterator method
    /// first and then iterable BEFORE the cached next getter, as the linked
    /// Source js_for_of_start/JS_GetIterator do. Iterator/next lexical roots
    /// belong to the enclosing loop scope, never the function-wide scope.
    fn initOwned(o: *x.Ops, iterable: c.JSValue) !Iterator {
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        var outcome = x.owned.Completion.initValue(o.s.engine, acquire(&local, iterable));
        outcome.releaseScope(&s);
        outcome.release(iterable);
        const value = try o.own(try outcome.finishValue());
        return .{ .value = value, .next_function = try o.get(value, "next") };
    }
    fn acquire(o: *x.Ops, iterable: c.JSValue) !c.JSValue {
        const method = try methodOwned(o, iterable);
        if (!c.JS_IsFunction(o.s.engine.context, method)) {
            var retirement = x.owned.Completion.initValue(o.s.engine, c.pi_js_undefined());
            retirement.release(method);
            _ = try retirement.finishValue();
            return o.typeError("value is not iterable");
        }
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        var outcome = x.owned.Completion.initValue(o.s.engine, callIterator(&local, iterable, method));
        outcome.releaseScope(&s); outcome.release(method);
        return outcome.finishValue();
    }
    fn methodOwned(o: *x.Ops, iterable: c.JSValue) !c.JSValue {
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        return x.owned.finishValue(&s, methodBody(&local, iterable));
    }
    fn methodBody(o: *x.Ops, iterable: c.JSValue) !c.JSValue {
        return c.JS_DupValue(o.s.engine.context, try o.key(iterable, try o.iteratorSymbol()));
    }
    fn callIterator(o: *x.Ops, iterable: c.JSValue, method: c.JSValue) !c.JSValue {
        const value = try o.call(method, iterable, &.{});
        if (!c.JS_IsObject(value)) return o.typeError("not an object");
        return c.JS_DupValue(o.s.engine.context, value);
    }
    fn next(self: *Iterator, o: *x.Ops) !?c.JSValue {
        errdefer self.closed = true;
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        const value = try x.owned.finishValue(&s, self.nextBody(&local));
        // Per-step result/done roots have retired before body delivery.
        if (self.closed) return null;
        return o.own(value);
    }
    fn nextBody(self: *Iterator, o: *x.Ops) !c.JSValue {
        const e = o.s.engine;
        self.native_steps +|= 1;
        if (e.cancelled.load(.acquire) or (self.native_steps % 256 == 0 and blk: {
            e.interrupts +|= 1; break :blk e.interrupts > e.options.interrupt_budget;
        })) {
            // This is an actual NEW interruption producer, not borrowed DATA.
            _ = c.JS_ThrowInternalError(e.context, "interrupted");
            const reason = c.JS_GetException(e.context);
            c.JS_SetUncatchableError(e.context, reason);
            _ = try e.checked(c.JS_Throw(e.context, reason)); unreachable;
        }
        const step = try o.call(self.next_function, self.value, &.{});
        if (!c.JS_IsObject(step)) return o.typeError("iterator must return an object");
        if (try done(o, step)) { self.closed = true; return c.pi_js_undefined(); }
        return c.JS_DupValue(e.context, try o.get(step, "value"));
    }
    fn done(o: *x.Ops, step: c.JSValue) !bool {
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        const boolean = try x.owned.finishValue(&s, doneBody(&local, step));
        return o.truthy(boolean);
    }
    fn doneBody(o: *x.Ops, step: c.JSValue) !c.JSValue {
        return c.pi_js_bool(o.s.engine.context, @intFromBool(o.truthy(try o.get(step, "done"))));
    }
    fn close(self: *Iterator, o: *x.Ops, throwing: bool) !void {
        if (self.closed) return;
        self.closed = true;
        var called = false;
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        const value = try x.owned.finishValue(&s, self.closeCall(&local, &called));
        var result_scope: x.Scope = .{ .engine = o.s.engine }; var result_ops: x.Ops = .{ .s = &result_scope };
        return x.owned.finishVoid(&result_scope, closeValidate(&result_ops, value, called and !throwing));
    }
    fn closeCall(self: *Iterator, o: *x.Ops, called: *bool) !c.JSValue {
        const method = try o.get(self.value, "return");
        if (x.nullish(method)) return c.pi_js_undefined();
        called.* = true;
        return c.JS_DupValue(o.s.engine.context, try o.call(method, self.value, &.{}));
    }
    fn closeValidate(o: *x.Ops, owned_value: c.JSValue, validate: bool) !void {
        const value = try o.own(owned_value);
        if (validate and !c.JS_IsObject(value)) return o.typeError("not an object");
    }
};
fn spreadSnapshot(o: *x.Ops, value: c.JSValue, runtime: c.JSValue) !void {
    var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
    return x.owned.finishVoid(&s, spreadBody(&local, value, runtime));
}
fn spreadBody(o: *x.Ops, value: c.JSValue, runtime: c.JSValue) !void {
    var iterator = try Iterator.initOwned(o, try o.invokeOwned(runtime, "getAvailableSnapshot", &.{}));
    var index: u32 = 0;
    while (!iterator.closed) {
        var s: x.Scope = .{ .engine = o.s.engine }; var local: x.Ops = .{ .s = &s };
        try x.owned.finishVoid(&s, spreadStep(&local, &iterator, value, &index));
    }
}
fn spreadStep(o: *x.Ops, iterator: *Iterator, value: c.JSValue, index: *u32) !void {
    if (try iterator.next(o)) |item| { try o.index(value, index.*, item); index.* += 1; }
}
