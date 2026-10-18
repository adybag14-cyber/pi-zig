//! c268 provider-env.ts: ordinary lookup, live bindings and actual empty catch.
const x = @import("native_ai_auth_helper_values.zig");
const p = @import("native_public_values.zig");
const c = x.c;
fn expression(engine: *x.em.Engine, comptime body: anytype, args: anytype) !c.JSValue {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishValue(&scope, @call(.auto, body, .{&o} ++ args));
}
fn statement(engine: *x.em.Engine, comptime body: anytype, args: anytype) !void {
    var scope: x.Scope = .{ .engine = engine };
    var o: x.Ops = .{ .s = &scope };
    return x.owned.finishVoid(&scope, @call(.auto, body, .{&o} ++ args));
}
fn value(o: *x.Ops, comptime body: anytype, args: anytype) !c.JSValue { return o.own(try expression(o.s.engine, body, args)); }
fn truth(o: *x.Ops, comptime body: anytype, args: anytype) !bool { return o.truthy(try value(o, body, args)); }
fn duplicate(o: *x.Ops, input: c.JSValue) c.JSValue { return c.JS_DupValue(o.s.engine.context, input); }
fn integer(o: *x.Ops, input: i32) c.JSValue { return c.JS_NewInt32(o.s.engine.context, input); }
fn boolean(o: *x.Ops, input: bool) c.JSValue { return c.pi_js_bool(o.s.engine.context, @intFromBool(input)); }

pub fn create(engine: *x.em.Engine) !c.JSValue {
    try engine.checkNativeEntry();
    if (engine.native_provider_env_lookup) |cached| return c.JS_DupValue(engine.context, cached);
    var frame: x.em.Engine.NativeInvocation = .{};
    engine.enterNativeInvocation(&frame);
    const result = try x.finishInvocation(engine, &frame, expression(engine, createBody, .{}));
    // Publication occurs after all factory temporaries and the invocation
    // retire. A reentrant completed factory owns the first published value.
    if (engine.native_provider_env_lookup) |cached| {
        var completion = x.owned.Completion.initValue(engine, c.JS_DupValue(engine.context, cached));
        completion.release(result);
        return completion.finishValue();
    }
    engine.native_provider_env_lookup = c.JS_DupValue(engine.context, result);
    return result;
}
fn createBody(o: *x.Ops) !c.JSValue {
    const cache = try o.cell();
    try o.put(cache, "value", c.pi_js_null());
    return @import("native_node_function.zig").create(o.s.engine, "getProviderEnvValue", 2, lookup, &.{cache});
}
fn lookup(engine: *x.em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    return expression(engine, lookupBody, .{x.arg(args, 0), x.arg(args, 1), roots[0]});
}
fn scoped(o: *x.Ops, env: c.JSValue, name: c.JSValue) !c.JSValue {
    return if (x.nullish(env)) c.pi_js_undefined() else duplicate(o, try o.getKey(env, name));
}
fn processMissing(o: *x.Ops) !c.JSValue { return boolean(o, c.JS_IsUndefined(try o.global("process"))); }
fn processValue(o: *x.Ops, name: c.JSValue) !c.JSValue {
    // The Source's typeof test and its property read resolve process separately.
    return if (try truth(o, processMissing, .{})) c.pi_js_undefined()
    else duplicate(o, try o.getKey(try value(o, processEnv, .{}), name));
}
fn processEnv(o: *x.Ops) !c.JSValue { return duplicate(o, try o.get(try o.global("process"), "env")); }
fn processVersions(o: *x.Ops) !c.JSValue { return duplicate(o, try o.get(try o.global("process"), "versions")); }
fn lookupBody(o: *x.Ops, name: c.JSValue, env: c.JSValue, cache: c.JSValue) !c.JSValue {
    const override = try value(o, scoped, .{env, name});
    if (o.truthy(override)) return duplicate(o, override);
    const normal = try value(o, processValue, .{name});
    if (o.truthy(normal)) return duplicate(o, normal);
    const recovered = try value(o, fallback, .{cache, name});
    return if (o.truthy(recovered)) duplicate(o, recovered) else c.pi_js_undefined();
}
fn processBun(o: *x.Ops) !c.JSValue {
    const versions = try value(o, processVersions, .{});
    return boolean(o, if (x.nullish(versions)) false else o.truthy(try o.get(versions, "bun")));
}
fn normalKeyNames(o: *x.Ops) !c.JSValue {
    const object = try o.global("Object");
    const keys = try o.get(object, "keys");
    const env = try value(o, processEnv, .{});
    return duplicate(o, try o.call(keys, object, &.{env}));
}
fn normalKeyCount(o: *x.Ops) !c.JSValue {
    const names = try value(o, normalKeyNames, .{});
    return duplicate(o, try o.get(names, "length"));
}
fn normalKeys(o: *x.Ops) !c.JSValue {
    return duplicate(o, try o.binary(6, try value(o, normalKeyCount, .{}), integer(o, 0)));
}
fn newMap(o: *x.Ops, cache: c.JSValue) !void {
    const map = try x.guest.construct(o.s, try o.global("Map"), &.{});
    try o.put(cache, "value", map);
}
fn fallback(o: *x.Ops, cache: c.JSValue, name: c.JSValue) !c.JSValue {
    if (try truth(o, processMissing, .{}) or !try truth(o, processBun, .{}) or try truth(o, normalKeys, .{})) return c.pi_js_undefined();
    if (c.JS_IsNull(try o.get(cache, "value"))) {
        try statement(o.s.engine, newMap, .{cache});
        const locals = try o.cell();
        try o.put(locals, "readFileSync", c.pi_js_undefined());
        try o.put(locals, "data", c.pi_js_undefined());
        try o.put(locals, "entry", c.pi_js_undefined());
        try o.put(locals, "idx", c.pi_js_undefined());
        var scope: x.Scope = .{ .engine = o.s.engine };
        var inner: x.Ops = .{ .s = &scope };
        var completion = x.owned.Completion.initVoid(o.s.engine, populate(&inner, cache, locals));
        completion.releaseScope(&scope);
        const outcome = try completion.finishAction();
        switch (outcome) {
            .returned => |unused| {
                var retired = x.owned.Completion.initVoid(o.s.engine, {});
                retired.release(unused); try retired.finishVoid();
            },
            .thrown => |reason| {
                // Source's empty catch handles ordinary DATA only. Actual
                // producer failures already escaped finishAction above.
                var retired = x.owned.Completion.initVoid(o.s.engine, {});
                retired.release(reason); try retired.finishVoid();
            },
            .awaited => unreachable,
        }
        // The locals remain in this invocation until the final cache.get call.
    }
    return duplicate(o, try o.invoke(try o.get(cache, "value"), "get", &.{name}));
}
fn fsBinding(o: *x.Ops) !c.JSValue {
    const fs = try o.call(try o.global("require"), c.pi_js_undefined(), &.{try o.text("node:fs")});
    return duplicate(o, try o.get(fs, "readFileSync"));
}
fn readProc(o: *x.Ops, callable: c.JSValue) !c.JSValue { return duplicate(o, try o.call(callable, c.pi_js_undefined(), &.{try o.text("/proc/self/environ"), try o.text("utf-8")})); }
fn splitEntries(o: *x.Ops, data: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(data, "split", &.{try o.text("\x00")})); }
fn populate(o: *x.Ops, cache: c.JSValue, locals: c.JSValue) !void {
    try o.put(locals, "readFileSync", try value(o, fsBinding, .{}));
    try o.put(locals, "data", try value(o, readProc, .{try o.get(locals, "readFileSync")}));
    const data = try o.get(locals, "data");
    var iterator = try p.Iterator.initOwned(o.s.engine, try expression(o.s.engine, splitEntries, .{data}));
    return iterator.finish(populateLoop(o.s.engine, &iterator, cache, locals));
}
fn populateLoop(engine: *x.em.Engine, iterator: *p.Iterator, cache: c.JSValue, locals: c.JSValue) !void {
    while (try iterator.next()) |incoming| {
        try statement(engine, populateEntry, .{cache, locals, incoming});
    }
}
fn indexOf(o: *x.Ops, entry: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(entry, "indexOf", &.{try o.text("=")})); }
fn positiveIndex(o: *x.Ops, input: c.JSValue) !c.JSValue { return duplicate(o, try o.binary(6, input, integer(o, 0))); }
fn populateEntry(o: *x.Ops, cache: c.JSValue, locals: c.JSValue, incoming: c.JSValue) !void {
    const entry = try o.own(incoming);
    try o.put(locals, "entry", entry);
    try o.put(locals, "idx", c.pi_js_undefined());
    try o.put(locals, "idx", try value(o, indexOf, .{entry}));
    const position = try o.get(locals, "idx");
    if (try truth(o, positiveIndex, .{position})) try statement(o.s.engine, setEntry, .{cache, entry, position});
}
fn setEntry(o: *x.Ops, cache: c.JSValue, entry: c.JSValue, position: c.JSValue) !void {
    const map = try o.get(cache, "value");
    const set = try o.get(map, "set");
    const key = try value(o, sliceKey, .{entry, position});
    const data = try value(o, sliceData, .{entry, position});
    _ = try o.call(set, map, &.{key, data});
}
fn sliceKey(o: *x.Ops, entry: c.JSValue, position: c.JSValue) !c.JSValue { return duplicate(o, try o.invoke(entry, "slice", &.{integer(o, 0), position})); }
fn sliceData(o: *x.Ops, entry: c.JSValue, position: c.JSValue) !c.JSValue {
    const callable = try o.get(entry, "slice");
    return duplicate(o, try o.call(callable, entry, &.{try o.binary(0, position, integer(o, 1))}));
}
