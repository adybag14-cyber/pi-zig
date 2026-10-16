//! Source publication queues and refresh phases using one true async frame.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const af = @import("native_async_function.zig");
const functions = @import("native_node_function.zig");
const c = em.c;
pub fn rememberNativeGeneration(scope: *Scope, owner: c.JSValue) !void {
    try scope.put(owner, "nativeGeneration", try scope.own(try scope.engine.checked(c.JS_NewBigUint64(scope.engine.context, scope.engine.native_allocation_generation))));
}
pub fn nativeReason(scope: *Scope, owner: c.JSValue, reason: c.JSValue) !bool {
    const tagged = c.pi_js_native_allocation_error_generation(reason);
    if (tagged == 0) return false;
    var generation: u64 = 0;
    if (c.JS_ToBigUint64(scope.engine.context, &generation, try scope.get(owner, "nativeGeneration")) < 0) return js.capture(scope.engine);
    const distance = tagged -% generation;
    return distance != 0 and distance <= scope.engine.native_allocation_generation -% generation;
}
pub fn initialize(scope: *Scope, slot: *c.JSValue, receiver: c.JSValue) !c.JSValue {
    const owner = try scope.object();
    try scope.put(owner, "agent", receiver);
    try rememberNativeGeneration(scope, owner);
    af.replaceState(scope.engine, slot, c.JS_DupValue(scope.engine.context, owner));
    return owner;
}
pub fn stage(scope: *Scope, owner: c.JSValue) !c_int {
    var result: c_int = 0;
    if (c.JS_ToInt32(scope.engine.context, &result, try scope.get(owner, "stage")) < 0) return js.capture(scope.engine);
    return result;
}
pub fn awaitAt(scope: *Scope, owner: c.JSValue, value: c.JSValue, next: c_int) !af.Action {
    try scope.put(owner, "stage", c.JS_NewInt32(scope.engine.context, next));
    return .{ .awaited = c.JS_DupValue(scope.engine.context, value) };
}
pub fn returned(engine: *em.Engine, value: c.JSValue) af.Action {
    return .{ .returned = c.JS_DupValue(engine.context, value) };
}
pub fn thrown(engine: *em.Engine, value: c.JSValue) af.Action {
    return .{ .thrown = c.JS_DupValue(engine.context, value) };
}
fn arg(args: []const c.JSValue, index: usize) c.JSValue {
    return if (index < args.len) args[index] else c.pi_js_undefined();
}
fn noop(_: *em.Engine, _: c.JSValue, _: []const c.JSValue, _: []const c.JSValue) !c.JSValue {
    return c.pi_js_undefined();
}
pub fn publish(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const id = arg(args, 0);
    const generation = arg(args, 1);
    const signal = arg(args, 2);
    const publication = arg(args, 3);
    var previous = try scope.invoke(try scope.get(receiver, "publicationChains"), "get", &.{id});
    if (temp.nullish(previous)) previous = try scope.invoke(try scope.global("Promise"), "resolve", &.{});
    const queued_body = try scope.own(try af.createResumableArrow(engine, "", 0, publicationBody, &.{ receiver, id, generation, signal, publication, previous }, receiver));
    const queued = try scope.call(queued_body, c.pi_js_undefined(), &.{});
    const catcher = try scope.get(queued, "catch");
    const ignore = try scope.own(try functions.createArrow(engine, "", 0, noop, &.{}));
    const tail = try scope.call(catcher, queued, &.{ignore});
    _ = try scope.invoke(try scope.get(receiver, "publicationChains"), "set", &.{ id, tail });
    const then = try scope.get(tail, "then");
    const cleanup = try scope.own(try functions.createArrow(engine, "", 0, retireTail, &.{ receiver, id, tail }));
    _ = try scope.call(then, tail, &.{cleanup});
    return js.call(engine, try scope.get(imports, "raceWithAbortSignal"), c.pi_js_undefined(), &.{ queued, signal });
}
fn retireTail(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const chains = try scope.get(roots[0], "publicationChains");
    if (scope.equal(try scope.invoke(chains, "get", &.{roots[1]}), roots[2])) _ = try scope.invoke(try scope.get(roots[0], "publicationChains"), "delete", &.{roots[1]});
    return c.pi_js_undefined();
}
fn current(scope: *Scope, owner: c.JSValue) !bool {
    if (scope.truthy(try scope.get(try scope.get(owner, "signal"), "aborted"))) return false;
    const generations = try scope.get(try scope.get(owner, "agent"), "refreshGenerations");
    const get = try scope.get(generations, "get");
    return scope.equal(try scope.call(get, generations, &.{try scope.get(owner, "providerId")}), try scope.get(owner, "generation"));
}
fn publicationBody(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const owner = try initialize(&scope, slot, roots[0]);
        inline for (.{ "providerId", "generation", "signal", "publication" }, 1..) |name, index| try scope.put(owner, name, roots[index]);
        const catcher = try scope.get(roots[5], "catch");
        const ignore = try scope.own(try functions.createArrow(engine, "", 0, noop, &.{}));
        return awaitAt(&scope, owner, try scope.call(catcher, roots[5], &.{ignore}), 0);
    }
    if (completion == .rejected) return thrown(engine, input);
    const owner = slot.*;
    if (!try current(&scope, owner)) return returned(engine, c.pi_js_bool(engine.context, 0));
    const publication = try scope.get(owner, "publication");
    if (try stage(&scope, owner) == 0) {
        const persist = try scope.get(publication, "persist");
        if (c.JS_IsNull(persist)) {
            const store = try scope.get(try scope.get(owner, "agent"), "modelsStore");
            const remove = try scope.get(store, "delete");
            const id = try scope.get(owner, "providerId");
            const options = try scope.object();
            try scope.put(options, "signal", try scope.get(owner, "signal"));
            return awaitAt(&scope, owner, try scope.call(remove, store, &.{ id, options }), 1);
        } else if (!c.JS_IsUndefined(try scope.get(publication, "persist"))) {
            const store = try scope.get(try scope.get(owner, "agent"), "modelsStore");
            const write = try scope.get(store, "write");
            const id = try scope.get(owner, "providerId");
            const clone = try scope.global("structuredClone");
            const entry = try scope.call(clone, c.pi_js_undefined(), &.{try scope.get(publication, "persist")});
            const options = try scope.object();
            try scope.put(options, "signal", try scope.get(owner, "signal"));
            return awaitAt(&scope, owner, try scope.call(write, store, &.{ id, entry, options }), 1);
        }
        if (!try current(&scope, owner)) return returned(engine, c.pi_js_bool(engine.context, 0));
    }
    const update = try scope.get(publication, "update");
    if (!temp.nullish(update)) _ = try scope.call(update, publication, &.{});
    return returned(engine, c.pi_js_bool(engine.context, 1));
}
pub fn phaseBody(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue, slot: *c.JSValue, completion: af.Completion, input: c.JSValue) !af.Action {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (completion == .start) {
        const owner = try initialize(&scope, slot, receiver);
        inline for (.{ "provider", "credential", "allowNetwork", "force", "generation", "signal" }, 0..) |name, index| try scope.put(owner, name, arg(args, index));
        try scope.put(owner, "imports", roots[0]);
        const store = try scope.get(receiver, "modelsStore");
        const read = try scope.get(store, "read");
        const id = try scope.get(arg(args, 0), "id");
        const options = try scope.object();
        try scope.put(options, "signal", arg(args, 5));
        return awaitAt(&scope, owner, try scope.call(read, store, &.{ id, options }), 0);
    }
    if (completion == .rejected) return thrown(engine, input);
    const owner = slot.*;
    if (try stage(&scope, owner) == 1) return returned(engine, c.pi_js_undefined());
    const provider = try scope.get(owner, "provider");
    const refresh = try scope.get(provider, "refreshModels");
    const context = try scope.object();
    try scope.put(context, "credential", try scope.get(owner, "credential"));
    var entry = c.pi_js_undefined();
    if (scope.truthy(input)) {
        const clone = try scope.global("structuredClone");
        entry = try scope.call(clone, c.pi_js_undefined(), &.{input});
        entry = try knownTypes(&scope, entry, try scope.get(owner, "imports"));
    }
    try scope.put(context, "stored", entry);
    const publish_callback = try scope.own(try functions.createArrow(engine, "publish", 1, phasePublication, &.{ try scope.get(owner, "agent"), provider, try scope.get(owner, "generation"), try scope.get(owner, "signal") }));
    try scope.put(context, "publish", publish_callback);
    const network = try scope.get(owner, "allowNetwork");
    try scope.put(context, "allowNetwork", network);
    try scope.put(context, "force", if (scope.truthy(network)) try scope.get(owner, "force") else c.pi_js_undefined());
    try scope.put(context, "signal", try scope.get(owner, "signal"));
    try scope.put(context, "baseUrl", try scope.get(provider, "baseUrl"));
    return awaitAt(&scope, owner, try scope.call(refresh, provider, &.{context}), 1);
}
fn phasePublication(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const publish_method = try scope.get(roots[0], "publishProviderModels");
    return js.call(engine, publish_method, roots[0], &.{ try scope.get(roots[1], "id"), roots[2], roots[3], arg(args, 0) });
}
fn knownTypes(scope: *Scope, entry: c.JSValue, imports: c.JSValue) !c.JSValue {
    const result = try scope.own(try js.spread(scope.engine, entry));
    const models = try scope.get(entry, "models");
    const filter = try scope.get(models, "filter");
    try scope.put(result, "models", try scope.call(filter, models, &.{try scope.get(imports, "hasKnownModelType")}));
    return result;
}
