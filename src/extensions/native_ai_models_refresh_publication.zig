//! Original ModelsImpl publication queues and provider refresh phases.
//! Receiver fields and provider/store methods remain live ordinary properties.
const em = @import("engine.zig");
const js = @import("native_js_values.zig");
const sdk = @import("native_sdk.zig");
const temp = @import("native_sdk_prompt_scope.zig");
const Scope = temp.Scope;
const flow = @import("native_agent_async.zig");
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
    const queued = try flow.create(engine, receiver);
    defer engine.freeValue(queued.owner);
    const promise = try scope.own(queued.promise);
    startPublication(engine, queued.owner, id, generation, signal, publication, previous) catch |err| try flow.rejectError(engine, queued.owner, err);
    const catcher = try scope.get(promise, "catch");
    const ignore = try scope.own(try functions.createArrow(engine, "", 0, noop, &.{}));
    const tail = try scope.call(catcher, promise, &.{ignore});
    _ = try scope.invoke(try scope.get(receiver, "publicationChains"), "set", &.{ id, tail });
    const then = try scope.get(tail, "then");
    const cleanup = try scope.own(try functions.createArrow(engine, "", 0, retireTail, &.{ receiver, id, tail }));
    _ = try scope.call(then, tail, &.{cleanup});
    return js.call(engine, try scope.get(imports, "raceWithAbortSignal"), c.pi_js_undefined(), &.{ promise, signal });
}
fn retireTail(engine: *em.Engine, _: c.JSValue, _: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const chains = try scope.get(roots[0], "publicationChains");
    if (scope.equal(try scope.invoke(chains, "get", &.{roots[1]}), roots[2])) _ = try scope.invoke(try scope.get(roots[0], "publicationChains"), "delete", &.{roots[1]});
    return c.pi_js_undefined();
}
fn startPublication(engine: *em.Engine, owner: c.JSValue, id: c.JSValue, generation: c.JSValue, signal: c.JSValue, publication: c.JSValue, previous: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ .{ "providerId", id }, .{ "generation", generation }, .{ "signal", signal }, .{ "publication", publication } }) |field| try scope.put(owner, field[0], field[1]);
    const catcher = try scope.get(previous, "catch");
    const ignore = try scope.own(try functions.createArrow(engine, "", 0, noop, &.{}));
    return flow.wait(continuePublication, engine, owner, try scope.call(catcher, previous, &.{ignore}), 0);
}
fn current(scope: *Scope, owner: c.JSValue) !bool {
    if (scope.truthy(try scope.get(try scope.get(owner, "signal"), "aborted"))) return false;
    const generations = try scope.get(try scope.get(owner, "agent"), "refreshGenerations");
    const get = try scope.get(generations, "get");
    return scope.equal(try scope.call(get, generations, &.{try scope.get(owner, "providerId")}), try scope.get(owner, "generation"));
}
fn continuePublication(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected) return flow.settle(engine, owner, true, value);
    publicationBody(engine, owner, stage) catch |err| try flow.rejectError(engine, owner, err);
}
fn publicationBody(engine: *em.Engine, owner: c.JSValue, stage: c_int) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    if (!try current(&scope, owner)) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    const publication = try scope.get(owner, "publication");
    if (stage == 0) {
        const persist = try scope.get(publication, "persist");
        if (c.JS_IsNull(persist)) {
            const store = try scope.get(try scope.get(owner, "agent"), "modelsStore");
            const remove = try scope.get(store, "delete");
            const id = try scope.get(owner, "providerId");
            const options = try scope.object();
            try scope.put(options, "signal", try scope.get(owner, "signal"));
            return flow.wait(continuePublication, engine, owner, try scope.call(remove, store, &.{ id, options }), 1);
        } else if (!c.JS_IsUndefined(try scope.get(publication, "persist"))) {
            const store = try scope.get(try scope.get(owner, "agent"), "modelsStore");
            const write = try scope.get(store, "write");
            const id = try scope.get(owner, "providerId");
            const clone = try scope.global("structuredClone");
            const entry = try scope.call(clone, c.pi_js_undefined(), &.{try scope.get(publication, "persist")});
            const options = try scope.object();
            try scope.put(options, "signal", try scope.get(owner, "signal"));
            return flow.wait(continuePublication, engine, owner, try scope.call(write, store, &.{ id, entry, options }), 1);
        }
        // Source performs its second generation/abort check even when no store
        // mutation was requested; getters can change the current generation.
        if (!try current(&scope, owner)) return flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 0));
    }
    const update = try scope.get(publication, "update");
    if (!temp.nullish(update)) _ = try scope.call(update, publication, &.{});
    try flow.settle(engine, owner, false, c.pi_js_bool(engine.context, 1));
}
pub fn phase(engine: *em.Engine, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !c.JSValue {
    const pending = try flow.create(engine, receiver);
    defer engine.freeValue(pending.owner);
    errdefer engine.freeValue(pending.promise);
    startPhase(engine, pending.owner, receiver, args, imports) catch |err| try flow.rejectError(engine, pending.owner, err);
    return pending.promise;
}
fn startPhase(engine: *em.Engine, owner: c.JSValue, receiver: c.JSValue, args: []const c.JSValue, imports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    inline for (.{ "provider", "credential", "allowNetwork", "force", "generation", "signal" }, 0..) |name, index| try scope.put(owner, name, arg(args, index));
    try scope.put(owner, "imports", imports);
    const store = try scope.get(receiver, "modelsStore");
    const read = try scope.get(store, "read");
    const id = try scope.get(arg(args, 0), "id");
    const options = try scope.object();
    try scope.put(options, "signal", arg(args, 5));
    return flow.wait(continuePhase, engine, owner, try scope.call(read, store, &.{ id, options }), 0);
}
fn continuePhase(engine: *em.Engine, owner: c.JSValue, value: c.JSValue, rejected: bool, stage: c_int) !void {
    if (rejected or stage == 1) return flow.settle(engine, owner, rejected, if (rejected) value else c.pi_js_undefined());
    phaseBody(engine, owner, value) catch |err| try flow.rejectError(engine, owner, err);
}
fn phaseBody(engine: *em.Engine, owner: c.JSValue, stored: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const provider = try scope.get(owner, "provider");
    const refresh = try scope.get(provider, "refreshModels");
    const context = try scope.object();
    try scope.put(context, "credential", try scope.get(owner, "credential"));
    var entry = c.pi_js_undefined();
    if (scope.truthy(stored)) {
        const clone = try scope.global("structuredClone");
        entry = try scope.call(clone, c.pi_js_undefined(), &.{stored});
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
    return flow.wait(continuePhase, engine, owner, try scope.call(refresh, provider, &.{context}), 1);
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
    const predicate = try scope.get(imports, "hasKnownModelType");
    try scope.put(result, "models", try scope.call(filter, models, &.{predicate}));
    return result;
}
pub fn prepareKnownTypes(engine: *em.Engine, imports: c.JSValue) !void {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const known = try scope.object();
    inline for (.{ "chat", "image", "classifier" }) |name| try scope.put(known, name, c.pi_js_bool(engine.context, 1));
    const predicate = try scope.own(try functions.create(engine, "hasKnownModelType", 1, hasKnownType, &.{ try scope.get(imports, "getModelType"), known }));
    try scope.put(imports, "hasKnownModelType", predicate);
}
fn hasKnownType(engine: *em.Engine, _: c.JSValue, args: []const c.JSValue, roots: []const c.JSValue) !c.JSValue {
    var scope: Scope = .{ .engine = engine };
    defer scope.deinit();
    const object = try scope.global("Object");
    const has = try scope.get(object, "hasOwn");
    return js.call(engine, has, object, &.{ roots[1], try scope.call(roots[0], c.pi_js_undefined(), &.{arg(args, 0)}) });
}
